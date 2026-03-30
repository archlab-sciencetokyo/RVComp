// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2026 Archlab, Science Tokyo
// Linux netdev driver for RVCOMP on-chip Ethernet MAC (DT-driven)

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/log2.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/of_net.h>
#include <linux/of_irq.h>
#include <linux/platform_device.h>
#include <linux/delay.h>
#include <linux/jiffies.h>
#include <linux/workqueue.h>

/* CSR offsets (word addressing) */
#define REG_ADDR_START       0
#define REG_ADDR_END         1
#define REG_RX_READ_BYTE   2
#define REG_RX_ERR         3
#define REG_TX_BUSY        4
#define REG_TX_BUFFER_START 5
#define REG_TX_BUFFER_END   6

#define RVCOMP_MTU            1514
#define RVCOMP_WATCHDOG_MS    500    /* RX watchdog interval; tune for CPU speed */
#define RVCOMP_TX_POLL_MS     1
#define ETH_MIN_FRAME_SIZE   60     /* Minimum Ethernet frame size (excluding FCS) */
#define RVCOMP_TX_MIN_RECORD  (4 + ETH_MIN_FRAME_SIZE)

struct rvcomp_eth {
	void __iomem *csr;
	void __iomem *rxbuf;
	void __iomem *txbuf;
	int irq;
	/* debugging: last observed CSR pointers */
	u32 last_start;
	u32 last_end;
	struct delayed_work rx_watchdog;
	struct delayed_work tx_reclaim;
	struct napi_struct napi;
	struct net_device *ndev;
	spinlock_t tx_lock; /* serialize TX path */
	u32 rxbuf_size;
	u32 txbuf_size;
};

/* Helpers */
static inline u32 rvcomp_csr_read(struct rvcomp_eth *eth, u32 reg)
{
	return ioread32(eth->csr + reg * 4);
}

static inline void rvcomp_csr_write(struct rvcomp_eth *eth, u32 reg, u32 val)
{
	iowrite32(val, eth->csr + reg * 4);
}

static int rvcomp_validate_buf_size(struct device *dev, resource_size_t size,
				       const char *label, u32 *validated)
{
	if (size > U32_MAX) {
		dev_err(dev, "%s buffer size too large: %pa\n", label, &size);
		return -EINVAL;
	}

	if (size < 2048 || size > (64 * 1024 * 1024) || (size & 0x3) ||
	    !is_power_of_2(size)) {
		dev_err(dev, "%s buffer size must be power-of-2, >= 2048, <= 64 MiB, 4-byte aligned (got %pa)\n",
			label, &size);
		return -EINVAL;
	}

	*validated = (u32)size;
	return 0;
}

static u32 rvcomp_tx_enqueue_one(struct rvcomp_eth *eth, const u8 *data, u32 len, u32 end)
{
	u32 padded_len = (len < ETH_MIN_FRAME_SIZE) ? ETH_MIN_FRAME_SIZE : len;
	u32 payload_aligned = (padded_len + 3) & ~0x3;
	u32 payload_idx = 0;
	u32 pos = end;

	/* Header: frame length in bytes (little-endian u32). */
	iowrite32(padded_len, eth->txbuf + pos);
	pos = (pos + 4) % eth->txbuf_size;

	/* Payload + zero padding to 4-byte alignment. */
	while (payload_idx < payload_aligned) {
		u32 word = 0;
		int i;

		for (i = 0; i < 4; i++) {
			u8 b = 0;

			if (payload_idx < len)
				b = data[payload_idx];
			word |= ((u32)b) << (i * 8);
			payload_idx++;
		}

		iowrite32(word, eth->txbuf + pos);
		pos = (pos + 4) % eth->txbuf_size;
	}

	return pos;
}

static void rvcomp_tx_reclaim(struct work_struct *work)
{
	struct rvcomp_eth *eth = container_of(to_delayed_work(work),
					     struct rvcomp_eth, tx_reclaim);
	struct net_device *ndev = eth->ndev;
	unsigned long flags;
	u32 start, end, free_bytes;
	bool wake = false;
	bool resched = false;

	if (!netif_running(ndev))
		return;

	spin_lock_irqsave(&eth->tx_lock, flags);
	start = rvcomp_csr_read(eth, REG_TX_BUFFER_START);
	end   = rvcomp_csr_read(eth, REG_TX_BUFFER_END);
	start = (start & (eth->txbuf_size - 1)) & ~0x3;
	end   = (end & (eth->txbuf_size - 1)) & ~0x3;
	free_bytes = eth->txbuf_size - ((end - start + eth->txbuf_size) % eth->txbuf_size) - 4;

	if (netif_queue_stopped(ndev)) {
		if (free_bytes >= RVCOMP_TX_MIN_RECORD)
			wake = true;
		else
			resched = true;
	}
	spin_unlock_irqrestore(&eth->tx_lock, flags);

	if (wake)
		netif_wake_queue(ndev);
	else if (resched)
		schedule_delayed_work(&eth->tx_reclaim, msecs_to_jiffies(RVCOMP_TX_POLL_MS));
}

/* Opportunistically schedule NAPI if unread data exists (e.g. lost IRQ) */
static void rvcomp_kick_rx_if_pending(struct rvcomp_eth *eth)
{
	u32 start = rvcomp_csr_read(eth, REG_ADDR_START);
	u32 end   = rvcomp_csr_read(eth, REG_ADDR_END);
	u32 start_m = start & (eth->rxbuf_size - 1);
	u32 end_m   = end & (eth->rxbuf_size - 1);

	eth->last_start = start;
	eth->last_end   = end;

	if (start_m != end_m && napi_schedule_prep(&eth->napi)) {
		disable_irq_nosync(eth->irq);
		__napi_schedule(&eth->napi);
	}
}

/* Simple watchdog: poll for stuck pending RX every 100 ms */
static void rvcomp_rx_watchdog(struct work_struct *work)
{
	struct rvcomp_eth *eth = container_of(to_delayed_work(work),
					     struct rvcomp_eth, rx_watchdog);

	rvcomp_kick_rx_if_pending(eth);
	schedule_delayed_work(&eth->rx_watchdog, msecs_to_jiffies(RVCOMP_WATCHDOG_MS));
}

/* RX: pull one packet if available, return true if consumed */
static bool rvcomp_rx_one(struct rvcomp_eth *eth, int *work_done)
{
	u32 raw_start = rvcomp_csr_read(eth, REG_ADDR_START);
	u32 raw_end   = rvcomp_csr_read(eth, REG_ADDR_END);
	u32 start;
	u32 end;
	u32 len;
	struct sk_buff *skb;
	u32 buf_index;
	u32 eth_index;
	u32 new_start;

	if (raw_start == raw_end)
		return false;

	start = raw_start & (eth->rxbuf_size - 1);
	end   = raw_end & (eth->rxbuf_size - 1);

	/* Align start to 4 bytes as bootrom does */
	start = (start + 3) & ~0x3;
	if (start >= eth->rxbuf_size)
		start = 0;

	len = (end < start) ? (end + eth->rxbuf_size - start) : (end - start);
	if (len > RVCOMP_MTU)
		len = RVCOMP_MTU;

	/* Allocate skb */
	skb = netdev_alloc_skb_ip_align(eth->ndev, len);
	if (!skb) {
		eth->ndev->stats.rx_dropped++;
		/* still must advance pointers to drop frame */
		goto advance;
	}

	buf_index = 0;
	eth_index = start >> 2; /* word index */
	while (buf_index < len) {
		u32 word = ioread32(eth->rxbuf + (eth_index << 2));
		if (buf_index < len) skb->data[buf_index++] = word & 0xFF;
		if (buf_index < len) skb->data[buf_index++] = (word >> 8) & 0xFF;
		if (buf_index < len) skb->data[buf_index++] = (word >> 16) & 0xFF;
		if (buf_index < len) skb->data[buf_index++] = (word >> 24) & 0xFF;
		eth_index = (eth_index + 1) % (eth->rxbuf_size >> 2);
	}
	skb_put(skb, len);
	skb->protocol = eth_type_trans(skb, eth->ndev);
	netif_receive_skb(skb);
	eth->ndev->stats.rx_packets++;
	eth->ndev->stats.rx_bytes += len;

advance:
	/* Advance start and free capacity */
	new_start = (start + len) % eth->rxbuf_size;
	rvcomp_csr_write(eth, REG_ADDR_START, new_start);
	(*work_done)++;
	return true;
}

static int rvcomp_napi_poll(struct napi_struct *napi, int budget)
{
	struct rvcomp_eth *eth = container_of(napi, struct rvcomp_eth, napi);
	int work_done = 0;

	while (work_done < budget) {
		if (!rvcomp_rx_one(eth, &work_done))
			break;
	}

	if (work_done < budget) {
		napi_complete_done(napi, work_done);
		enable_irq(eth->irq);
	}
	return work_done;
}

static irqreturn_t rvcomp_irq_handler(int irq, void *dev_id)
{
	struct rvcomp_eth *eth = dev_id;

	/* Schedule NAPI to process received data.
	 * Interrupt will be cleared when rvcomp_rx_one() updates ADDR_START
	 * to equal ADDR_END after draining all packets.
	 */
	if (napi_schedule_prep(&eth->napi)) {
		disable_irq_nosync(irq);
		__napi_schedule(&eth->napi);
	}
	return IRQ_HANDLED;
}

static netdev_tx_t rvcomp_start_xmit(struct sk_buff *skb, struct net_device *ndev)
{
	struct rvcomp_eth *eth = netdev_priv(ndev);
	unsigned long flags;
	u32 len = skb->len;
	u32 padded_len = (len < ETH_MIN_FRAME_SIZE) ? ETH_MIN_FRAME_SIZE : len;
	u32 record_size = 4 + ((padded_len + 3) & ~0x3);
	u32 start, end, free_bytes, new_end;

	if (len == 0 || len > RVCOMP_MTU) {
		ndev->stats.tx_dropped++;
		dev_kfree_skb(skb);
		return NETDEV_TX_OK;
	}

	spin_lock_irqsave(&eth->tx_lock, flags);

	start = rvcomp_csr_read(eth, REG_TX_BUFFER_START);
	end   = rvcomp_csr_read(eth, REG_TX_BUFFER_END);
	start = (start & (eth->txbuf_size - 1)) & ~0x3;
	end   = (end & (eth->txbuf_size - 1)) & ~0x3;
	free_bytes = eth->txbuf_size - ((end - start + eth->txbuf_size) % eth->txbuf_size) - 4;
	if (free_bytes < record_size) {
		netif_stop_queue(ndev);
		spin_unlock_irqrestore(&eth->tx_lock, flags);
		schedule_delayed_work(&eth->tx_reclaim, msecs_to_jiffies(RVCOMP_TX_POLL_MS));
		return NETDEV_TX_BUSY;
	}

	new_end = rvcomp_tx_enqueue_one(eth, skb->data, len, end);
	wmb();
	rvcomp_csr_write(eth, REG_TX_BUFFER_END, new_end);

	spin_unlock_irqrestore(&eth->tx_lock, flags);

	ndev->stats.tx_packets++;
	ndev->stats.tx_bytes += len;

	/* If TX took interrupts down for a while, make sure pending RX is serviced */
	rvcomp_kick_rx_if_pending(eth);

	dev_kfree_skb(skb);
	return NETDEV_TX_OK;
}

static int rvcomp_open(struct net_device *ndev)
{
	struct rvcomp_eth *eth = netdev_priv(ndev);
	int ret;
	u32 tx_start;

	/* Clear any stale pending IRQ/data by syncing start to end */
	eth->last_end = rvcomp_csr_read(eth, REG_ADDR_END);
	eth->last_end &= (eth->rxbuf_size - 1);
	rvcomp_csr_write(eth, REG_ADDR_START, eth->last_end);
	tx_start = rvcomp_csr_read(eth, REG_TX_BUFFER_START);
	tx_start = (tx_start & (eth->txbuf_size - 1)) & ~0x3;
	rvcomp_csr_write(eth, REG_TX_BUFFER_END, tx_start);

	napi_enable(&eth->napi);

	ret = request_irq(eth->irq, rvcomp_irq_handler, 0, ndev->name, eth);
	if (ret) {
		netdev_err(ndev, "request_irq failed %d\n", ret);
		napi_disable(&eth->napi);
		return ret;
	}

	netif_start_queue(ndev);
	schedule_delayed_work(&eth->rx_watchdog, msecs_to_jiffies(RVCOMP_WATCHDOG_MS));
	return 0;
}

static int rvcomp_stop(struct net_device *ndev)
{
	struct rvcomp_eth *eth = netdev_priv(ndev);

	netif_stop_queue(ndev);
	cancel_delayed_work_sync(&eth->rx_watchdog);
	cancel_delayed_work_sync(&eth->tx_reclaim);
	free_irq(eth->irq, eth);
	napi_disable(&eth->napi);
	return 0;
}

static const struct net_device_ops rvcomp_netdev_ops = {
	.ndo_open       = rvcomp_open,
	.ndo_stop       = rvcomp_stop,
	.ndo_start_xmit = rvcomp_start_xmit,
};

/* Platform driver glue */
static int rvcomp_probe(struct platform_device *pdev)
{
	struct net_device *ndev;
	struct rvcomp_eth *eth;
	struct resource *res_csr, *res_rx, *res_tx;
	u8 mac[ETH_ALEN];
	int ret;

	ndev = alloc_etherdev(sizeof(struct rvcomp_eth));
	if (!ndev)
		return -ENOMEM;

	eth = netdev_priv(ndev);
	eth->ndev = ndev;
	spin_lock_init(&eth->tx_lock);

	res_csr = platform_get_resource_byname(pdev, IORESOURCE_MEM, "csr");
	res_rx  = platform_get_resource_byname(pdev, IORESOURCE_MEM, "rxbuf");
	res_tx  = platform_get_resource_byname(pdev, IORESOURCE_MEM, "txbuf");
	if (!res_csr || !res_rx || !res_tx) {
		res_csr = platform_get_resource(pdev, IORESOURCE_MEM, 0);
		res_rx  = platform_get_resource(pdev, IORESOURCE_MEM, 1);
		res_tx  = platform_get_resource(pdev, IORESOURCE_MEM, 2);
	}
	if (!res_csr || !res_rx || !res_tx) {
		ret = -ENODEV;
		goto err_free;
	}

	ret = rvcomp_validate_buf_size(&pdev->dev, resource_size(res_rx), "rx", &eth->rxbuf_size);
	if (ret)
		goto err_free;
	ret = rvcomp_validate_buf_size(&pdev->dev, resource_size(res_tx), "tx", &eth->txbuf_size);
	if (ret)
		goto err_free;

	eth->csr   = devm_ioremap_resource(&pdev->dev, res_csr);
	eth->rxbuf = devm_ioremap_resource(&pdev->dev, res_rx);
	eth->txbuf = devm_ioremap_resource(&pdev->dev, res_tx);
	if (IS_ERR(eth->csr) || IS_ERR(eth->rxbuf) || IS_ERR(eth->txbuf)) {
		ret = PTR_ERR(IS_ERR(eth->csr) ? eth->csr :
			      IS_ERR(eth->rxbuf) ? eth->rxbuf : eth->txbuf);
		goto err_free;
	}

	/* Prefer named IRQ "ethernet"; fall back to hwirq=2 direct map if needed */
	eth->irq = platform_get_irq_byname_optional(pdev, "ethernet");
	if (eth->irq < 0) {
		int virq = irq_of_parse_and_map(pdev->dev.of_node, 0);
		eth->irq = (virq > 0) ? virq : -ENODEV;
	}
	if (eth->irq < 0) {
		ret = eth->irq;
		goto err_free;
	}

	ndev->netdev_ops = &rvcomp_netdev_ops;
	ndev->min_mtu = 68;
	ndev->max_mtu = RVCOMP_MTU;
	ndev->dev.parent = &pdev->dev;

	ret = of_get_mac_address(pdev->dev.of_node, mac);
	if (!ret && is_valid_ether_addr(mac))
		eth_hw_addr_set(ndev, mac);
	else
		eth_hw_addr_random(ndev);

	netif_napi_add(ndev, &eth->napi, rvcomp_napi_poll);
	INIT_DELAYED_WORK(&eth->rx_watchdog, rvcomp_rx_watchdog);
	INIT_DELAYED_WORK(&eth->tx_reclaim, rvcomp_tx_reclaim);
	memset(&ndev->stats, 0, sizeof(ndev->stats));

	/* Simple CSR r/w self-test to confirm bus mapping */
	rvcomp_csr_write(eth, REG_ADDR_START, 0);
	if (rvcomp_csr_read(eth, REG_ADDR_START) != 0)
		dev_warn(&pdev->dev, "CSR self-test failed: start reg not writable\n");

	ret = register_netdev(ndev);
	if (ret) {
		dev_err(&pdev->dev, "register_netdev failed %d\n", ret);
		goto err_napi;
	}

	platform_set_drvdata(pdev, ndev);
	dev_info(&pdev->dev,
		 "rvcomp ethernet probed: irq=%d csr=[%pa-%pa] rx=[%pa-%pa]/%#x tx=[%pa-%pa]/%#x\n",
		 eth->irq,
		 &res_csr->start, &res_csr->end,
		 &res_rx->start, &res_rx->end, eth->rxbuf_size,
		 &res_tx->start, &res_tx->end, eth->txbuf_size);
	return 0;

err_napi:
	netif_napi_del(&eth->napi);
err_free:
	free_netdev(ndev);
	return ret;
}

static void rvcomp_remove(struct platform_device *pdev)
{
	struct net_device *ndev = platform_get_drvdata(pdev);
	struct rvcomp_eth *eth;

	if (!ndev)
		return;

	eth = netdev_priv(ndev);
	unregister_netdev(ndev);
	netif_napi_del(&eth->napi);
	free_netdev(ndev);
}

static const struct of_device_id rvcomp_of_match[] = {
	{ .compatible = "isct,rvcomp-ethernet" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, rvcomp_of_match);

static struct platform_driver rvcomp_driver = {
	.probe  = rvcomp_probe,
	.remove = rvcomp_remove,
	.driver = {
		.name           = "rvcomp-ethernet",
		.of_match_table = rvcomp_of_match,
	},
};

module_platform_driver(rvcomp_driver);

MODULE_AUTHOR("Archlab / Science Tokyo");
MODULE_DESCRIPTION("RVCOMP on-chip Ethernet driver");
MODULE_LICENSE("GPL");
