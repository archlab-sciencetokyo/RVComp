// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2026 Archlab, Science Tokyo
// Linux block device driver for RVCOMP on-chip MMC controller (DT-driven)

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/io.h>
#include <linux/errno.h>
#include <linux/highmem.h>
#include <linux/mm.h>
#include <linux/blkdev.h>
#include <linux/blk-mq.h>

#define DRIVER_NAME "rvcomp-mmc"

/* CSR register byte offsets */
#define MMC_CSR_ADDR29        0x00
#define MMC_CSR_FLUSH         0x18
#define MMC_CSR_FLUSH_DONE    0x1C
#define MMC_CSR_FLUSH_DONE_CLR 0x20

/* 4 KiB window region */
#define MMC_WINDOW_BASE       0x1000
#define MMC_WINDOW_MASK       0x0FFF

/* Sector size */
#define MMC_SECTOR_SIZE   512

/* MMIO polling timeout (busy-wait loops, auto-updated by tools/setting.py). */
#define MMC_POLL_MAX_LOOPS 10000000U

static int rvcomp_mmc_major;

struct rvcomp_mmc {
	struct device *dev;
	void __iomem *csr;
	struct gendisk *disk;
	struct blk_mq_tag_set tag_set;
	u64 rootfs_offset;	/* byte offset on MMC */
	u64 disk_sectors;	/* number of sectors */
	u32 addr29_cached;
	bool addr29_valid;
	spinlock_t lock;
};

static inline int mmc_wait_flush_done(struct rvcomp_mmc *mmc)
{
	u32 i;

	for (i = 0; i < MMC_POLL_MAX_LOOPS; i++) {
		if (ioread32(mmc->csr + MMC_CSR_FLUSH_DONE) & 1)
			return 0;
		cpu_relax();
	}

	dev_err_ratelimited(mmc->dev, "timeout waiting for FLUSH_DONE\n");
	return -ETIMEDOUT;
}

static inline void mmc_select_addr29(struct rvcomp_mmc *mmc, u64 byte_addr)
{
	u32 addr29 = (byte_addr >> 12) & 0x1FFFFFFF;

	if (mmc->addr29_valid && mmc->addr29_cached == addr29)
		return;

	iowrite32(addr29, mmc->csr + MMC_CSR_ADDR29);
	mmc->addr29_cached = addr29;
	mmc->addr29_valid = true;
}

static inline void __iomem *mmc_window_ptr(struct rvcomp_mmc *mmc, u64 byte_addr)
{
	u32 off = (u32)(byte_addr & MMC_WINDOW_MASK);

	return mmc->csr + MMC_WINDOW_BASE + off;
}

static int mmc_flush(struct rvcomp_mmc *mmc)
{
	int ret;

	iowrite32(1, mmc->csr + MMC_CSR_FLUSH);

	ret = mmc_wait_flush_done(mmc);
	if (ret)
		return ret;

	/* W1C: explicitly clear flush-done latch. */
	iowrite32(1, mmc->csr + MMC_CSR_FLUSH_DONE_CLR);
	return 0;
}

static blk_status_t rvcomp_mmc_queue_rq(struct blk_mq_hw_ctx *hctx,
				       const struct blk_mq_queue_data *bd)
{
	struct request *rq = bd->rq;
	struct rvcomp_mmc *mmc = rq->q->queuedata;
	struct req_iterator iter;
	struct bio_vec bvec;
	u64 req_byte_pos = 0;
	u64 base_mmc_addr = mmc->rootfs_offset +
			   (u64)blk_rq_pos(rq) * MMC_SECTOR_SIZE;
	bool is_read = (rq_data_dir(rq) == READ);
	unsigned long flags;
	blk_status_t status = BLK_STS_OK;
	int ret = 0;

	blk_mq_start_request(rq);

	if (req_op(rq) == REQ_OP_FLUSH) {
		spin_lock_irqsave(&mmc->lock, flags);
		ret = mmc_flush(mmc);
		spin_unlock_irqrestore(&mmc->lock, flags);
		status = ret ? BLK_STS_IOERR : BLK_STS_OK;
		blk_mq_end_request(rq, status);
		return status;
	}

	if (blk_rq_is_passthrough(rq)) {
		blk_mq_end_request(rq, BLK_STS_IOERR);
		return BLK_STS_IOERR;
	}

	spin_lock_irqsave(&mmc->lock, flags);

	rq_for_each_segment(bvec, rq, iter) {
		unsigned int seg_pos = 0;

		if (bvec.bv_len % MMC_SECTOR_SIZE) {
			dev_err_ratelimited(mmc->dev,
					    "unaligned segment length: %u\n",
					    bvec.bv_len);
			status = BLK_STS_IOERR;
			goto out_unlock;
		}

		while (seg_pos < bvec.bv_len) {
			unsigned int off = bvec.bv_offset + seg_pos;
			struct page *page = bvec.bv_page + (off >> PAGE_SHIFT);
			unsigned int page_off = off & (PAGE_SIZE - 1);
			unsigned int seg_left = bvec.bv_len - seg_pos;
			u64 mmc_addr = base_mmc_addr + req_byte_pos;
			unsigned int win_off = (u32)(mmc_addr & MMC_WINDOW_MASK);
			unsigned int to_window_end =
				(MMC_WINDOW_MASK + 1u) - win_off;
			unsigned int to_page_end = PAGE_SIZE - page_off;
			unsigned int chunk = min(seg_left,
						 min(to_window_end, to_page_end));
			void __iomem *mmio;
			u8 *buf;
			void *kaddr;

			kaddr = kmap_local_page(page);
			buf = (u8 *)kaddr + page_off;

			mmc_select_addr29(mmc, mmc_addr);
			mmio = mmc_window_ptr(mmc, mmc_addr);
			if (is_read)
				memcpy_fromio(buf, mmio, chunk);
			else
				memcpy_toio(mmio, buf, chunk);
			kunmap_local(kaddr);

			seg_pos += chunk;
			req_byte_pos += chunk;
		}
	}

out_unlock:
	spin_unlock_irqrestore(&mmc->lock, flags);

	blk_mq_end_request(rq, status);
	return status;
}

static const struct blk_mq_ops rvcomp_mmc_mq_ops = {
	.queue_rq = rvcomp_mmc_queue_rq,
};

static const struct block_device_operations rvcomp_mmc_fops = {
	.owner = THIS_MODULE,
};

static int rvcomp_mmc_probe(struct platform_device *pdev)
{
	struct rvcomp_mmc *mmc;
	struct resource *res;
	u32 offset_val, size_mb;
	int ret;

	mmc = devm_kzalloc(&pdev->dev, sizeof(*mmc), GFP_KERNEL);
	if (!mmc)
		return -ENOMEM;

	mmc->dev = &pdev->dev;
	mmc->addr29_cached = 0;
	mmc->addr29_valid = false;
	spin_lock_init(&mmc->lock);

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res)
		return -ENODEV;

	mmc->csr = devm_ioremap_resource(&pdev->dev, res);
	if (IS_ERR(mmc->csr))
		return PTR_ERR(mmc->csr);

	ret = of_property_read_u32(pdev->dev.of_node, "rootfs-offset",
				   &offset_val);
	if (ret) {
		dev_err(&pdev->dev, "missing rootfs-offset property\n");
		return ret;
	}
	mmc->rootfs_offset = offset_val;

	ret = of_property_read_u32(pdev->dev.of_node, "disk-size-mb",
				   &size_mb);
	if (ret) {
		dev_err(&pdev->dev, "missing disk-size-mb property\n");
		return ret;
	}
	mmc->disk_sectors = (u64)size_mb * (1024 * 1024 / MMC_SECTOR_SIZE);

	/* Register block device major number */
	rvcomp_mmc_major = register_blkdev(0, "mmcblk0");
	if (rvcomp_mmc_major < 0) {
		dev_err(&pdev->dev, "register_blkdev failed: %d\n",
			rvcomp_mmc_major);
		return rvcomp_mmc_major;
	}

	/* Set up blk-mq tag set */
	mmc->tag_set.ops = &rvcomp_mmc_mq_ops;
	mmc->tag_set.nr_hw_queues = 1;
	mmc->tag_set.queue_depth = 16;
	mmc->tag_set.numa_node = NUMA_NO_NODE;
#ifdef BLK_MQ_F_SHOULD_MERGE
	mmc->tag_set.flags = BLK_MQ_F_SHOULD_MERGE;
#else
    mmc->tag_set.flags = 0;
#endif

	ret = blk_mq_alloc_tag_set(&mmc->tag_set);
	if (ret) {
		dev_err(&pdev->dev, "blk_mq_alloc_tag_set failed: %d\n", ret);
		goto err_blkdev;
	}

	struct queue_limits lim = {
		.logical_block_size = MMC_SECTOR_SIZE,
		.physical_block_size = MMC_WINDOW_MASK + 1u,
		.io_min = MMC_WINDOW_MASK + 1u,
		.io_opt = MMC_WINDOW_MASK + 1u,
		.features = BLK_FEAT_WRITE_CACHE,
	};

	mmc->disk = blk_mq_alloc_disk(&mmc->tag_set, &lim, mmc);
	if (IS_ERR(mmc->disk)) {
		ret = PTR_ERR(mmc->disk);
		dev_err(&pdev->dev, "blk_mq_alloc_disk failed: %d\n", ret);
		goto err_tag_set;
	}

	mmc->disk->major = rvcomp_mmc_major;
	mmc->disk->first_minor = 0;
	mmc->disk->minors = 1;
	mmc->disk->fops = &rvcomp_mmc_fops;
	mmc->disk->private_data = mmc;
	snprintf(mmc->disk->disk_name, DISK_NAME_LEN, "mmcblk0");
	set_capacity(mmc->disk, mmc->disk_sectors);

	ret = add_disk(mmc->disk);
	if (ret) {
		dev_err(&pdev->dev, "add_disk failed: %d\n", ret);
		goto err_disk;
	}

	platform_set_drvdata(pdev, mmc);
	dev_info(&pdev->dev,
		 "rvcomp-mmc probed: csr=%pa offset=0x%llx sectors=%llu\n",
		 &res->start, mmc->rootfs_offset, mmc->disk_sectors);
	return 0;

err_disk:
	put_disk(mmc->disk);
err_tag_set:
	blk_mq_free_tag_set(&mmc->tag_set);
err_blkdev:
	unregister_blkdev(rvcomp_mmc_major, "mmcblk0");
	return ret;
}

static void rvcomp_mmc_remove(struct platform_device *pdev)
{
	struct rvcomp_mmc *mmc = platform_get_drvdata(pdev);
	unsigned long flags;
	int ret;

	if (!mmc)
		return;

	del_gendisk(mmc->disk);

	spin_lock_irqsave(&mmc->lock, flags);
	ret = mmc_flush(mmc);
	spin_unlock_irqrestore(&mmc->lock, flags);
	if (ret)
		dev_warn(mmc->dev, "flush failed on remove: %d\n", ret);

	put_disk(mmc->disk);
	blk_mq_free_tag_set(&mmc->tag_set);
	unregister_blkdev(rvcomp_mmc_major, "mmcblk0");
}

static void rvcomp_mmc_shutdown(struct platform_device *pdev)
{
	struct rvcomp_mmc *mmc = platform_get_drvdata(pdev);
	unsigned long flags;
	int ret;

	if (!mmc)
		return;

	spin_lock_irqsave(&mmc->lock, flags);
	ret = mmc_flush(mmc);
	spin_unlock_irqrestore(&mmc->lock, flags);
	if (ret)
		dev_warn(mmc->dev, "flush failed on shutdown: %d\n", ret);
}

static const struct of_device_id rvcomp_mmc_of_match[] = {
	{ .compatible = "isct,rvcomp-mmc" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, rvcomp_mmc_of_match);

static struct platform_driver rvcomp_mmc_driver = {
	.probe  = rvcomp_mmc_probe,
	.remove = rvcomp_mmc_remove,
	.shutdown = rvcomp_mmc_shutdown,
	.driver = {
		.name           = DRIVER_NAME,
		.of_match_table = rvcomp_mmc_of_match,
	},
};

module_platform_driver(rvcomp_mmc_driver);

MODULE_AUTHOR("Archlab / Science Tokyo");
MODULE_DESCRIPTION("RVCOMP on-chip MMC block device driver");
MODULE_LICENSE("GPL");
