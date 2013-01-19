#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/pci.h>

#define	DRV_NAME	"ethpipe"
#define	DRV_VERSION	"0.0.1"
#define	ethpipe_DRIVER_NAME	DRV_NAME " Etherpipe driver " DRV_VERSION

static DEFINE_PCI_DEVICE_TABLE(ethpipe_pci_tbl) = {
	{0x3776, 0x8001, PCI_ANY_ID, PCI_ANY_ID, 0, 0, 0 },
	{0,}
};
MODULE_DEVICE_TABLE(pci, ethpipe_pci_tbl);

static unsigned long *mmio_ptr, mmio_start = 0L, mmio_end, mmio_flags, mmio_len;
static struct pci_dev *pcidev = NULL;

static int ethpipe_open(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);
	/* */
	return 0;
}

static ssize_t ethpipe_read(struct file *filp, char __user *buf,
			   size_t count, loff_t *ppos)
{
	int copy_len;

	printk("%s\n", __func__);

	if ( count > 2048 )
		copy_len = 2048;
	else
		copy_len = count;

	if ( copy_to_user( buf, ((char *)mmio_ptr + 0x8000), copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}

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
	printk("%s\n", __func__);

	if ( copy_from_user( mmio_ptr, buf, copy_len ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	return copy_len;
}

static int ethpipe_release(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);
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

	/* reset board */
	pcidev = pdev;

	return 0;

err_out:
	pci_release_regions (pdev);
	pci_disable_device (pdev);
	return -1;
}


static void __devexit ethpipe_remove_one (struct pci_dev *pdev)
{
	if (mmio_start) {
		iounmap(mmio_start);
		mmio_start = 0L;
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
	
	printk("%s\n", __func__);
	return pci_register_driver(&ethpipe_pci_driver);
}

static void __exit ethpipe_cleanup(void)
{
	if (pcidev)
		ethpipe_remove_one (pcidev);
	misc_deregister(&ethpipe_dev);
	pci_unregister_driver(&ethpipe_pci_driver);
	printk("%s\n", __func__);
}

MODULE_LICENSE("GPL");
module_init(ethpipe_init);
module_exit(ethpipe_cleanup);
