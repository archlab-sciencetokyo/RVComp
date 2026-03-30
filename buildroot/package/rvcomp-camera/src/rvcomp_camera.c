// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2026 Archlab, Science Tokyo
// Linux misc driver for RVComp camera MMIO (polling only, no IRQ)

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/io.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/poll.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/workqueue.h>
#include <linux/jiffies.h>
#include <linux/spinlock.h>
#include <linux/ioctl.h>
#include <linux/types.h>

#define DRIVER_NAME "rvcomp-camera"

/* CSR byte offsets */
#define CAM_REG_ID          0x00
#define CAM_REG_CTRL        0x04
#define CAM_REG_STATUS      0x08
#define CAM_REG_WIDTH       0x0c
#define CAM_REG_HEIGHT      0x10
#define CAM_REG_STRIDE      0x14
#define CAM_REG_FRAME_BYTES 0x18
#define CAM_REG_SEQ         0x1c
#define CAM_REG_READY_BANK  0x20
#define CAM_REG_READ_BANK   0x24
#define CAM_REG_DROP_COUNT  0x28
#define CAM_REG_GAIN        0x2c

#define CAM_CTRL_ENABLE_BIT 0
#define CAM_FRAME_APERTURE_BYTES 0x20000u
#define CAM_POLL_INTERVAL_MS 5u

#define RVCOMP_CAM_PIXFMT_GRAY8 0x59455247u /* "GREY" */

struct rvcomp_cam_info {
	__u32 width;
	__u32 height;
	__u32 stride;
	__u32 frame_bytes;
	__u32 pixfmt;
};

struct rvcomp_cam_meta {
	__u32 seq;
	__u32 ready_bank;
	__u32 read_bank;
	__u32 drop_count;
	__u32 status;
};

#define RVCOMP_CAM_IOC_MAGIC  'P'
#define RVCOMP_CAM_IOC_G_INFO _IOR(RVCOMP_CAM_IOC_MAGIC, 0x00, struct rvcomp_cam_info)
#define RVCOMP_CAM_IOC_G_META _IOR(RVCOMP_CAM_IOC_MAGIC, 0x01, struct rvcomp_cam_meta)

struct rvcomp_camera {
	struct device *dev;
	void __iomem *csr;
	void __iomem *frame;

	u32 width;
	u32 height;
	u32 stride;
	u32 frame_bytes;

	u8 *read_buf;
	struct mutex io_lock;

	wait_queue_head_t wq;
	struct delayed_work poll_work;
	spinlock_t seq_lock;
	u32 latest_seq;

	struct miscdevice miscdev;
};

struct rvcomp_cam_file_ctx {
	struct rvcomp_camera *cam;
	u32 seen_seq;
};

static inline u32 cam_readl(struct rvcomp_camera *cam, u32 reg)
{
	return ioread32(cam->csr + reg);
}

static inline void cam_writel(struct rvcomp_camera *cam, u32 reg, u32 val)
{
	iowrite32(val, cam->csr + reg);
}

static u32 rvcomp_cam_get_latest_seq(struct rvcomp_camera *cam)
{
	unsigned long flags;
	u32 seq;

	spin_lock_irqsave(&cam->seq_lock, flags);
	seq = cam->latest_seq;
	spin_unlock_irqrestore(&cam->seq_lock, flags);

	return seq;
}

static void rvcomp_cam_update_latest_seq(struct rvcomp_camera *cam, u32 seq)
{
	unsigned long flags;
	bool changed = false;

	spin_lock_irqsave(&cam->seq_lock, flags);
	if (cam->latest_seq != seq) {
		cam->latest_seq = seq;
		changed = true;
	}
	spin_unlock_irqrestore(&cam->seq_lock, flags);

	if (changed)
		wake_up_interruptible(&cam->wq);
}

static void rvcomp_cam_poll_workfn(struct work_struct *work)
{
	struct rvcomp_camera *cam;
	u32 seq;

	cam = container_of(to_delayed_work(work), struct rvcomp_camera, poll_work);
	seq = cam_readl(cam, CAM_REG_SEQ);
	rvcomp_cam_update_latest_seq(cam, seq);

	schedule_delayed_work(&cam->poll_work, msecs_to_jiffies(CAM_POLL_INTERVAL_MS));
}

static int rvcomp_cam_open(struct inode *inode, struct file *file)
{
	struct miscdevice *mdev;
	struct rvcomp_camera *cam;
	struct rvcomp_cam_file_ctx *ctx;
	u32 seq;

	mdev = file->private_data;
	cam = container_of(mdev, struct rvcomp_camera, miscdev);

	ctx = kzalloc(sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	seq = cam_readl(cam, CAM_REG_SEQ);
	rvcomp_cam_update_latest_seq(cam, seq);

	ctx->cam = cam;
	ctx->seen_seq = seq;
	file->private_data = ctx;

	return 0;
}

static int rvcomp_cam_release(struct inode *inode, struct file *file)
{
	struct rvcomp_cam_file_ctx *ctx = file->private_data;

	kfree(ctx);
	return 0;
}

static int rvcomp_cam_wait_next_seq(struct rvcomp_camera *cam, struct rvcomp_cam_file_ctx *ctx,
			       bool nonblock, u32 *out_seq)
{
	int ret;
	u32 seq;

	for (;;) {
		seq = rvcomp_cam_get_latest_seq(cam);
		if (seq != ctx->seen_seq) {
			*out_seq = seq;
			return 0;
		}

		seq = cam_readl(cam, CAM_REG_SEQ);
		rvcomp_cam_update_latest_seq(cam, seq);
		if (seq != ctx->seen_seq) {
			*out_seq = seq;
			return 0;
		}

		if (nonblock)
			return -EAGAIN;

		ret = wait_event_interruptible_timeout(
			cam->wq,
			READ_ONCE(cam->latest_seq) != ctx->seen_seq,
			msecs_to_jiffies(CAM_POLL_INTERVAL_MS * 2));
		if (ret < 0)
			return ret;
	}
}

static ssize_t rvcomp_cam_read(struct file *file, char __user *buf,
			  size_t count, loff_t *ppos)
{
	struct rvcomp_cam_file_ctx *ctx = file->private_data;
	struct rvcomp_camera *cam;
	bool nonblock;
	u32 seq;
	u32 ready_bank;
	ssize_t ret;

	if (!ctx || !ctx->cam)
		return -EIO;

	cam = ctx->cam;
	if (count < cam->frame_bytes)
		return -EINVAL;

	nonblock = (file->f_flags & O_NONBLOCK) != 0;

	ret = mutex_lock_interruptible(&cam->io_lock);
	if (ret)
		return ret;

	ret = rvcomp_cam_wait_next_seq(cam, ctx, nonblock, &seq);
	if (ret)
		goto out_unlock;

	ready_bank = cam_readl(cam, CAM_REG_READY_BANK) & 0x1;
	cam_writel(cam, CAM_REG_READ_BANK, ready_bank);

	memcpy_fromio(cam->read_buf, cam->frame, cam->frame_bytes);
	if (copy_to_user(buf, cam->read_buf, cam->frame_bytes)) {
		ret = -EFAULT;
		goto out_unlock;
	}

	ctx->seen_seq = seq;
	ret = cam->frame_bytes;

out_unlock:
	mutex_unlock(&cam->io_lock);
	return ret;
}

static __poll_t rvcomp_cam_poll(struct file *file, poll_table *wait)
{
	struct rvcomp_cam_file_ctx *ctx = file->private_data;
	struct rvcomp_camera *cam;
	u32 latest;
	u32 seq;

	if (!ctx || !ctx->cam)
		return EPOLLERR;

	cam = ctx->cam;
	poll_wait(file, &cam->wq, wait);

	latest = rvcomp_cam_get_latest_seq(cam);
	if (latest != ctx->seen_seq)
		return EPOLLIN | EPOLLRDNORM;

	seq = cam_readl(cam, CAM_REG_SEQ);
	rvcomp_cam_update_latest_seq(cam, seq);
	if (seq != ctx->seen_seq)
		return EPOLLIN | EPOLLRDNORM;

	return 0;
}

static long rvcomp_cam_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	struct rvcomp_cam_file_ctx *ctx = file->private_data;
	struct rvcomp_camera *cam;

	if (!ctx || !ctx->cam)
		return -EIO;

	cam = ctx->cam;

	switch (cmd) {
	case RVCOMP_CAM_IOC_G_INFO: {
		struct rvcomp_cam_info info;

		info.width = cam->width;
		info.height = cam->height;
		info.stride = cam->stride;
		info.frame_bytes = cam->frame_bytes;
		info.pixfmt = RVCOMP_CAM_PIXFMT_GRAY8;

		if (copy_to_user((void __user *)arg, &info, sizeof(info)))
			return -EFAULT;
		return 0;
	}
	case RVCOMP_CAM_IOC_G_META: {
		struct rvcomp_cam_meta meta;

		meta.seq = cam_readl(cam, CAM_REG_SEQ);
		meta.ready_bank = cam_readl(cam, CAM_REG_READY_BANK);
		meta.read_bank = cam_readl(cam, CAM_REG_READ_BANK);
		meta.drop_count = cam_readl(cam, CAM_REG_DROP_COUNT);
		meta.status = cam_readl(cam, CAM_REG_STATUS);

		if (copy_to_user((void __user *)arg, &meta, sizeof(meta)))
			return -EFAULT;
		return 0;
	}
	default:
		return -ENOTTY;
	}
}

static const struct file_operations rvcomp_cam_fops = {
	.owner = THIS_MODULE,
	.open = rvcomp_cam_open,
	.release = rvcomp_cam_release,
	.read = rvcomp_cam_read,
	.poll = rvcomp_cam_poll,
	.unlocked_ioctl = rvcomp_cam_ioctl,
	.llseek = noop_llseek,
};

static int rvcomp_camera_probe(struct platform_device *pdev)
{
	struct rvcomp_camera *cam;
	struct resource *res;
	u32 ctrl;
	u32 seq;
	int ret;

	cam = devm_kzalloc(&pdev->dev, sizeof(*cam), GFP_KERNEL);
	if (!cam)
		return -ENOMEM;

	cam->dev = &pdev->dev;

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res)
		return -ENODEV;
	cam->csr = devm_ioremap_resource(&pdev->dev, res);
	if (IS_ERR(cam->csr))
		return PTR_ERR(cam->csr);

	res = platform_get_resource(pdev, IORESOURCE_MEM, 1);
	if (!res)
		return -ENODEV;
	cam->frame = devm_ioremap_resource(&pdev->dev, res);
	if (IS_ERR(cam->frame))
		return PTR_ERR(cam->frame);

	cam->width = cam_readl(cam, CAM_REG_WIDTH);
	cam->height = cam_readl(cam, CAM_REG_HEIGHT);
	cam->stride = cam_readl(cam, CAM_REG_STRIDE);
	cam->frame_bytes = cam_readl(cam, CAM_REG_FRAME_BYTES);
	if (!cam->width || !cam->height || !cam->stride || !cam->frame_bytes ||
	    cam->frame_bytes > CAM_FRAME_APERTURE_BYTES) {
		dev_err(&pdev->dev,
			"invalid camera geometry: w=%u h=%u stride=%u bytes=%u\n",
			cam->width, cam->height, cam->stride, cam->frame_bytes);
		return -EINVAL;
	}

	cam->read_buf = devm_kmalloc(&pdev->dev, cam->frame_bytes, GFP_KERNEL);
	if (!cam->read_buf)
		return -ENOMEM;

	mutex_init(&cam->io_lock);
	init_waitqueue_head(&cam->wq);
	spin_lock_init(&cam->seq_lock);

	/* Force camera capture enable bit on. */
	ctrl = cam_readl(cam, CAM_REG_CTRL);
	ctrl |= BIT(CAM_CTRL_ENABLE_BIT);
	cam_writel(cam, CAM_REG_CTRL, ctrl);

	seq = cam_readl(cam, CAM_REG_SEQ);
	cam->latest_seq = seq;

	cam->miscdev.minor = MISC_DYNAMIC_MINOR;
	cam->miscdev.name = "rvcomp_cam0";
	cam->miscdev.fops = &rvcomp_cam_fops;
	cam->miscdev.parent = &pdev->dev;

	ret = misc_register(&cam->miscdev);
	if (ret) {
		dev_err(&pdev->dev, "misc_register failed: %d\n", ret);
		return ret;
	}

	INIT_DELAYED_WORK(&cam->poll_work, rvcomp_cam_poll_workfn);
	schedule_delayed_work(&cam->poll_work, msecs_to_jiffies(CAM_POLL_INTERVAL_MS));

	platform_set_drvdata(pdev, cam);
	dev_info(&pdev->dev,
		 "rvcomp-camera probed: %ux%u stride=%u frame_bytes=%u\n",
		 cam->width, cam->height, cam->stride, cam->frame_bytes);
	return 0;
}

static void rvcomp_camera_remove(struct platform_device *pdev)
{
	struct rvcomp_camera *cam = platform_get_drvdata(pdev);

	if (!cam)
		return;

	cancel_delayed_work_sync(&cam->poll_work);
	misc_deregister(&cam->miscdev);
}

static const struct of_device_id rvcomp_camera_of_match[] = {
	{ .compatible = "rvcomp,camera" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, rvcomp_camera_of_match);

static struct platform_driver rvcomp_camera_driver = {
	.probe = rvcomp_camera_probe,
	.remove = rvcomp_camera_remove,
	.driver = {
		.name = DRIVER_NAME,
		.of_match_table = rvcomp_camera_of_match,
	},
};

module_platform_driver(rvcomp_camera_driver);

MODULE_AUTHOR("Archlab, Science Tokyo");
MODULE_DESCRIPTION("RVComp camera misc driver (MMIO polling)");
MODULE_LICENSE("GPL");
