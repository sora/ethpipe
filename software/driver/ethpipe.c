#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/string.h>
#include <linux/pci.h>
#include <linux/wait.h>		/* wait_queue_head_t */
#include <linux/sched.h>	/* wait_event_interruptible, wake_up_interruptible */
#include <linux/interrupt.h>
#include <linux/version.h>

#ifndef DRV_NAME
#define DRV_NAME        "ethpipe"
#endif
#ifndef RX_ADDR
#define RX_ADDR         0x8000
#endif
#ifndef TX_ADDR
#define TX_ADDR         0x9000
#endif

#define	DRV_VERSION	"0.0.2"
#define	ethpipe_DRIVER_NAME	DRV_NAME " Etherpipe driver " DRV_VERSION
#define	PACKET_BUF_MAX	(1024*1024)
#define	TEMP_BUF_MAX	2000

#define HEADER_LEN	16

#if LINUX_VERSION_CODE > KERNEL_VERSION(3,8,0)
#define	__devinit
#define	__devexit
#define	__devexit_p
#endif

static DEFINE_PCI_DEVICE_TABLE(ethpipe_pci_tbl) = {
	{0x3776, 0x8001, PCI_ANY_ID, PCI_ANY_ID, 0, 0, 0 },
	{0,}
};
MODULE_DEVICE_TABLE(pci, ethpipe_pci_tbl);

static unsigned char *mmio_ptr = 0L;
static unsigned long mmio_start, mmio_end, mmio_flags, mmio_len;
static struct pci_dev *pcidev = NULL;
static wait_queue_head_t write_q;
static wait_queue_head_t read_q;

/* receive and transmitte buffer */
struct _pbuf_dma {
	unsigned char	*rx_start_ptr;		/* buf start */
	unsigned char 	*rx_end_ptr;		/* buf end */
	unsigned char	*rx_write_ptr;		/* write ptr */
	unsigned char	*rx_read_ptr;		/* read ptr */
} static pbuf0={0,0,0,0,0}, pbuf1={0,0,0,0,0};


static irqreturn_t ethpipe_interrupt(int irq, struct pci_dev *pdev)
{
	unsigned int frame_len;

	frame_len = *(short *)(mmio_ptr + RX_ADDR + 0x0c);
#ifdef DEBUG
	printk("%s\n", __func__);
	printk( "frame_len=%d\n", frame_len);
#endif

	if (frame_len < 64)
		frame_len = 64;

	if (frame_len > 1518)
		frame_len = 1518;

	if ( (pbuf0.rx_write_ptr +  frame_len + 0x10) > pbuf0.rx_end_ptr ) {
		memcpy( pbuf0.rx_start_ptr, pbuf0.rx_write_ptr, (pbuf0.rx_write_ptr - pbuf0.rx_start_ptr ));
		pbuf0.rx_read_ptr -= (pbuf0.rx_write_ptr - pbuf0.rx_start_ptr );
		if ( pbuf0.rx_read_ptr < pbuf0.rx_start_ptr )
			pbuf0.rx_read_ptr = pbuf0.rx_start_ptr;
		pbuf0.rx_write_ptr = pbuf0.rx_start_ptr;
	}

	memcpy(pbuf0.rx_write_ptr+0x04, mmio_ptr+RX_ADDR, 0x0c);
	memcpy(pbuf0.rx_write_ptr+0x10, mmio_ptr+RX_ADDR+0x10, frame_len);
	
	pbuf0.rx_write_ptr[0x00] = 0x55;			/* magic code 0x55d5 */
	pbuf0.rx_write_ptr[0x01] = 0xd5;
	*(short *)(pbuf0.rx_write_ptr + 2) = frame_len;
//	pbuf0.rx_write_ptr[0x02] = *(mmio_ptr + 0x800c);	/* frame_len[00:07] */
//	pbuf0.rx_write_ptr[0x03] = *(mmio_ptr + 0x800d);	/* frame_len[15:08] */
//	pbuf0.rx_write_ptr[0x04] = *(mmio_ptr + 0x8000);	/* counter[00:07] */
//	pbuf0.rx_write_ptr[0x05] = *(mmio_ptr + 0x8001);	/* counter[15:08] */
//	pbuf0.rx_write_ptr[0x06] = *(mmio_ptr + 0x8002);	/* counter[23:16] */
//	pbuf0.rx_write_ptr[0x07] = *(mmio_ptr + 0x8003);	/* counter[31:24] */
//	pbuf0.rx_write_ptr[0x08] = *(mmio_ptr + 0x8004);	/* counter[39:32] */
//	pbuf0.rx_write_ptr[0x09] = *(mmio_ptr + 0x8005);	/* counter[47:40] */
//	pbuf0.rx_write_ptr[0x0a] = *(mmio_ptr + 0x8006);	/* counter[55:48] */
//	pbuf0.rx_write_ptr[0x0b] = *(mmio_ptr + 0x8007);	/* counter[63:56] */
//	pbuf0.rx_write_ptr[0x0c] = *(mmio_ptr + 0x8008);	/* hash   [00:07] */
//	pbuf0.rx_write_ptr[0x0d] = *(mmio_ptr + 0x8009);	/* hash   [00:07] */
//	pbuf0.rx_write_ptr[0x0e] = *(mmio_ptr + 0x800a);	/* hash   [00:07] */
//	pbuf0.rx_write_ptr[0x0f] = *(mmio_ptr + 0x800b);	/* hash   [00:07] */

	pbuf0.rx_write_ptr += (frame_len + 0x10);

	*mmio_ptr = 0x02;		/* IRQ clear and Request receiving PHY#0 */

	wake_up_interruptible( &read_q );

	return IRQ_HANDLED;
}

static int ethpipe_open(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	*mmio_ptr = 0x02;		/* IRQ clear and Request receiving PHY#0 */

	return 0;
}

static ssize_t ethpipe_read(struct file *filp, char __user *buf,
			   size_t count, loff_t *ppos)
{
	int copy_len, available_read_len;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	if ( wait_event_interruptible( read_q, ( pbuf0.rx_read_ptr != pbuf0.rx_write_ptr ) ) )
		return -ERESTARTSYS;

	available_read_len = (pbuf0.rx_write_ptr - pbuf0.rx_read_ptr);

	if ( count > available_read_len )
		copy_len = available_read_len;
	else
		copy_len = count;


	if ( copy_to_user( buf, pbuf0.rx_read_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}

	pbuf0.rx_read_ptr += copy_len;

	return copy_len;
}

static ssize_t ethpipe_write(struct file *filp, const char __user *buf,
			    size_t count, loff_t *ppos)

{
	int copy_len;
	if ( count > 256 )
		copy_len = 256;
	else
		copy_len = count;
#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	if ( copy_from_user( mmio_ptr, buf, copy_len ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	return copy_len;
}

static int ethpipe_release(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	*mmio_ptr = 0x00;		/* IRQ clear and not Request receiving PHY#0 */

	return 0;
}

static unsigned int ethpipe_poll(struct file *filp, poll_table *wait)
{
	printk("%s\n", __func__);
	return 0;
}


static int ethpipe_ioctl(struct inode *inode, struct file *filp,
			unsigned int cmd, unsigned long arg)
{
	printk("%s\n", __func__);
	return  -ENOTTY;
}

static struct file_operations ethpipe_fops = {
	.owner		= THIS_MODULE,
	.read		= ethpipe_read,
	.write		= ethpipe_write,
	.poll		= ethpipe_poll,
	.compat_ioctl	= ethpipe_ioctl,
	.open		= ethpipe_open,
	.release	= ethpipe_release,
};

static struct miscdevice ethpipe_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "ethpipe",
	.fops = &ethpipe_fops,
};


static int __devinit ethpipe_init_one (struct pci_dev *pdev,
				       const struct pci_device_id *ent)
{
	int rc;

	mmio_ptr = 0L;

	rc = pci_enable_device (pdev);
	if (rc)
		goto err_out;

	rc = pci_request_regions (pdev, DRV_NAME);
	if (rc)
		goto err_out;

#if 0
	pci_set_master (pdev);		/* set BUS Master Mode */
#endif

	mmio_start = pci_resource_start (pdev, 0);
	mmio_end   = pci_resource_end   (pdev, 0);
	mmio_flags = pci_resource_flags (pdev, 0);
	mmio_len   = pci_resource_len   (pdev, 0);

	printk( KERN_INFO "mmio_start: %X\n", mmio_start );
	printk( KERN_INFO "mmio_end  : %X\n", mmio_end   );
	printk( KERN_INFO "mmio_flags: %X\n", mmio_flags );
	printk( KERN_INFO "mmio_len  : %X\n", mmio_len   );

	mmio_ptr = ioremap(mmio_start, mmio_len);
	if (!mmio_ptr) {
		printk(KERN_ERR "cannot ioremap MMIO base\n");
		goto err_out;
	}

	if (request_irq(pdev->irq, ethpipe_interrupt, IRQF_SHARED, DRV_NAME, pdev)) {
		printk(KERN_ERR "cannot request_irq\n");
	}
	
	/* reset board */
	pcidev = pdev;
	*mmio_ptr = 0x02;	/* Request receiving PHY#1 */

	return 0;

err_out:
	pci_release_regions (pdev);
	pci_disable_device (pdev);
	return -1;
}


static void __devexit ethpipe_remove_one (struct pci_dev *pdev)
{
	disable_irq(pdev->irq);
	free_irq(pdev->irq, pdev);

	if (mmio_ptr) {
		iounmap(mmio_ptr);
		mmio_ptr = 0L;
	}
	pci_release_regions (pdev);
	pci_disable_device (pdev);
	printk("%s\n", __func__);
}


static struct pci_driver ethpipe_pci_driver = {
	.name		= DRV_NAME,
	.id_table	= ethpipe_pci_tbl,
	.probe		= ethpipe_init_one,
	.remove		= __devexit_p(ethpipe_remove_one),
#ifdef CONFIG_PM
//	.suspend	= ethpipe_suspend,
//	.resume		= ethpipe_resume,
#endif /* CONFIG_PM */
};


static int __init ethpipe_init(void)
{
	int ret;

#ifdef MODULE
	pr_info(ethpipe_DRIVER_NAME "\n");
#endif

	ret = misc_register(&ethpipe_dev);
	if (ret) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		return ret;
	}

	if ( ( pbuf0.rx_start_ptr = kmalloc( PACKET_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		return -1;
	}
	pbuf0.rx_end_ptr = (pbuf0.rx_start_ptr + PACKET_BUF_MAX - 1);
	pbuf0.rx_write_ptr = pbuf0.rx_start_ptr;
	pbuf0.rx_read_ptr  = pbuf0.rx_start_ptr;

	init_waitqueue_head( &write_q );
	init_waitqueue_head( &read_q );
	
	printk("%s\n", __func__);
	return pci_register_driver(&ethpipe_pci_driver);
}

static void __exit ethpipe_cleanup(void)
{
	printk("%s\n", __func__);
	misc_deregister(&ethpipe_dev);
	pci_unregister_driver(&ethpipe_pci_driver);
	if ( pbuf0.rx_start_ptr )
		kfree( pbuf0.rx_start_ptr );
}

MODULE_LICENSE("GPL");
module_init(ethpipe_init);
module_exit(ethpipe_cleanup);

