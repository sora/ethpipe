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
#define DRV_NAME	"ethpipe"
#endif
#ifndef RX_ADDR
#define RX_ADDR	 0x8000
#endif
#ifndef TX_ADDR
#define TX_ADDR	 0x9000
#endif

#define	DRV_VERSION	"0.1.0"
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

static unsigned char *mmio0_ptr = 0L, *mmio1_ptr = 0L, *dma1_virt_ptr = 0L, *dma2_virt_ptr = 0L;
static dma_addr_t dma1_phys_ptr = 0L, dma2_phys_ptr;
static unsigned long mmio0_start, mmio0_end, mmio0_flags, mmio0_len;
static unsigned long mmio1_start, mmio1_end, mmio1_flags, mmio1_len;
static struct pci_dev *pcidev = NULL;
static wait_queue_head_t write_q;
static wait_queue_head_t read_q;


static irqreturn_t ethpipe_interrupt(int irq, void *pdev)
{
	int status;
	long dma1_addr_cur, dma2_addr_cur;

	status = *(mmio0_ptr + 0x10);
	// not ethpipe interrupt
	if ((status & 4) == 0 ) {
		return IRQ_NONE;
	}

	dma1_addr_cur = *(long *)(mmio0_ptr + 0x24);
	dma2_addr_cur = *(long *)(mmio0_ptr + 0x2c);

//#ifdef DEBUG
	printk("%s\n", __func__);
	printk( "dma1_addr_cur=%x\n", dma1_addr_cur );
	printk( "dma2_addr_cur=%x\n", dma1_addr_cur );
//#endif

#ifdef NO
	wake_up_interruptible( &read_q );
#endif
	// clear interrupt flag
	*(mmio0_ptr + 0x10) = status & 0xfb; 

	return IRQ_HANDLED;
}

static int ethpipe_open(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	/* enanble DMA1 and DMA2 */
	*(mmio0_ptr + 0x10)  = 0x3;

	return 0;
}

static ssize_t ethpipe_read(struct file *filp, char __user *buf,
			   size_t count, loff_t *ppos)
{
	int copy_len;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

#ifdef	NO
	if ( wait_event_interruptible( read_q, ( pbuf0.rx_read_ptr != pbuf0.rx_write_ptr ) ) )
		return -ERESTARTSYS;


	if ( copy_to_user( buf, pbuf0.rx_read_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}
#endif

	copy_len = count;

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

	if ( copy_from_user( mmio1_ptr, buf, copy_len ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	return copy_len;
}

static int ethpipe_release(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	/* disable DMA1 and DMA2 */
	*(mmio0_ptr + 0x10)  = 0x0;

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
	.name = DRV_NAME,
	.fops = &ethpipe_fops,
};


static int __devinit ethpipe_init_one (struct pci_dev *pdev,
				       const struct pci_device_id *ent)
{
	int rc;

	mmio0_ptr = 0L;
	mmio1_ptr = 0L;
	dma1_virt_ptr = 0L;
	dma1_phys_ptr = 0L;
	dma2_virt_ptr = 0L;
	dma2_phys_ptr = 0L;

	rc = pci_enable_device (pdev);
	if (rc)
		goto err_out;

	rc = pci_request_regions (pdev, DRV_NAME);
	if (rc)
		goto err_out;

	pci_set_master (pdev);		/* set BUS Master Mode */

	mmio0_start = pci_resource_start (pdev, 0);
	mmio0_end   = pci_resource_end   (pdev, 0);
	mmio0_flags = pci_resource_flags (pdev, 0);
	mmio0_len   = pci_resource_len   (pdev, 0);

	printk( KERN_INFO "mmio0_start: %X\n", mmio0_start );
	printk( KERN_INFO "mmio0_end  : %X\n", mmio0_end   );
	printk( KERN_INFO "mmio0_flags: %X\n", mmio0_flags );
	printk( KERN_INFO "mmio0_len  : %X\n", mmio0_len   );

	mmio0_ptr = ioremap(mmio0_start, mmio0_len);
	if (!mmio0_ptr) {
		printk(KERN_ERR "cannot ioremap MMIO0 base\n");
		goto err_out;
	}

	mmio1_start = pci_resource_start (pdev, 2);
	mmio1_end   = pci_resource_end   (pdev, 2);
	mmio1_flags = pci_resource_flags (pdev, 2);
	mmio1_len   = pci_resource_len   (pdev, 2);

	printk( KERN_INFO "mmio1_start: %X\n", mmio1_start );
	printk( KERN_INFO "mmio1_end  : %X\n", mmio1_end   );
	printk( KERN_INFO "mmio1_flags: %X\n", mmio1_flags );
	printk( KERN_INFO "mmio1_len  : %X\n", mmio1_len   );

	mmio1_ptr = ioremap_wc(mmio1_start, mmio1_len);
	if (!mmio1_ptr) {
		printk(KERN_ERR "cannot ioremap MMIO1 base\n");
		goto err_out;
	}

	dma1_virt_ptr = dma_alloc_coherent( &pdev->dev, PACKET_BUF_MAX, &dma1_phys_ptr, GFP_KERNEL);
	if (!dma1_virt_ptr) {
		printk(KERN_ERR "cannot dma1_alloc_coherent\n");
		goto err_out;
	}
	printk( KERN_INFO "dma1_virt_ptr  : %X\n", dma1_virt_ptr );
	printk( KERN_INFO "dma1_phys_ptr  : %X\n", dma1_phys_ptr );

	dma2_virt_ptr = dma_alloc_coherent( &pdev->dev, PACKET_BUF_MAX, &dma2_phys_ptr, GFP_KERNEL);
	if (!dma2_virt_ptr) {
		printk(KERN_ERR "cannot dma2_alloc_coherent\n");
		goto err_out;
	}
	printk( KERN_INFO "dma2_virt_ptr  : %X\n", dma2_virt_ptr );
	printk( KERN_INFO "dma2_phys_ptr  : %X\n", dma2_phys_ptr );

	if (request_irq(pdev->irq, ethpipe_interrupt, IRQF_SHARED, DRV_NAME, pdev)) {
		printk(KERN_ERR "cannot request_irq\n");
	}
	
	pcidev = pdev;

	/* set DMA Buffer length */
	*(long *)(mmio0_ptr + 0x14)  = PACKET_BUF_MAX;

	/* set DMA1 start address */
	*(long *)(mmio0_ptr + 0x20)  = dma1_phys_ptr;

	/* set DMA2 start address */
	*(long *)(mmio0_ptr + 0x28)  = dma2_phys_ptr;

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

	if (mmio0_ptr) {
		iounmap(mmio0_ptr);
		mmio0_ptr = 0L;
	}
	if (mmio1_ptr) {
		iounmap(mmio1_ptr);
		mmio1_ptr = 0L;
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

	if ( dma1_virt_ptr )
		dma_free_coherent(&pcidev->dev, PACKET_BUF_MAX, dma1_virt_ptr, dma1_phys_ptr);

	if ( dma2_virt_ptr )
		dma_free_coherent(&pcidev->dev, PACKET_BUF_MAX, dma2_virt_ptr, dma2_phys_ptr);
}

MODULE_LICENSE("GPL");
module_init(ethpipe_init);
module_exit(ethpipe_cleanup);

