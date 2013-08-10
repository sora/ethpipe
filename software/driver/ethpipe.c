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

#ifndef TX_WRITE_PTR_ADDRESS
#define TX_WRITE_PTR_ADDRESS	(0x30)
#endif

#ifndef TX_READ_PTR_ADDRESS
#define TX_READ_PTR_ADDRESS		(0x34)
#endif

#define	DRV_VERSION	"0.1.0"
#define	ethpipe_DRIVER_NAME	DRV_NAME " Etherpipe driver " DRV_VERSION
#define	PACKET_BUF_MAX	(1024*1024)
#define	TEMP_BUF_MAX	(2000)

#define ETHPIPE_HEADER_LEN		(14)
#define MAX_FRAME_LEN			(9014)

#if LINUX_VERSION_CODE > KERNEL_VERSION(3,8,0)
#define	__devinit
#define	__devexit
#define	__devexit_p
#endif

#define DEBUG

static DEFINE_PCI_DEVICE_TABLE(ethpipe_pci_tbl) = {
	{0x3776, 0x8001, PCI_ANY_ID, PCI_ANY_ID, 0, 0, 0 },
	{0,}
};
MODULE_DEVICE_TABLE(pci, ethpipe_pci_tbl);

static unsigned char *mmio0_ptr = 0L, *mmio1_ptr = 0L, *dma1_virt_ptr = 0L, *dma2_virt_ptr = 0L;
static unsigned long long mmio0_start, mmio0_end, mmio0_flags, mmio0_len;
static unsigned long long mmio1_start, mmio1_end, mmio1_flags, mmio1_len;

static dma_addr_t dma1_phys_ptr = 0L, dma2_phys_ptr;
static long *dma1_addr_start, *dma2_addr_start;
static long *dma1_addr_cur, *dma2_addr_cur;
static long dma1_addr_read, dma2_addr_read;

static unsigned short *tx_write_ptr;
static unsigned short *tx_read_ptr;

static struct pci_dev *pcidev = NULL;
static wait_queue_head_t write_q;
static wait_queue_head_t read_q;

/* receive and transmitte buffer */
struct _pbuf_dma {
	unsigned char   *rx_start_ptr;	/* rx buf start */
	unsigned char   *rx_end_ptr;	/* rx buf end */
	unsigned char   *rx_write_ptr;	/* rx write ptr */
	unsigned char   *rx_read_ptr;	/* rx read ptr */
	unsigned char   *tx_start_ptr;	/* tx buf start */
	unsigned char   *tx_end_ptr;	/* tx buf end */
	unsigned char   *tx_write_ptr;	/* tx write ptr */
	unsigned char   *tx_read_ptr;	/* tx read ptr */
} static pbuf0={0,0,0,0,0,0,0,0};


static irqreturn_t ethpipe_interrupt(int irq, void *pdev)
{
	int i, status;
	unsigned short frame_len;
	static unsigned short hex[257], initialized = 0;
	int handled = 0;

	status = *(mmio0_ptr + 0x10);
	// is ethpipe interrupt?
	if ((status & 8) == 0 ) {
		goto lend;
	}

	// clear interrupt flag
	*(mmio0_ptr + 0x10) = status & 0xf7; 

	handled = 1;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	if ( unlikely(initialized == 0) ) {
		for ( i = 0 ; i < 256 ; ++i ) {
			sprintf( (unsigned char *)&hex[i], "%02X", i);
		}
		initialized = 1;
	}

	if ( *dma1_addr_cur != dma1_addr_read ) {
		unsigned char *read_ptr, *p;

		read_ptr = dma1_virt_ptr;
		read_ptr += (int)(dma1_addr_read - dma1_phys_ptr);
		
		frame_len = *(unsigned short *)(read_ptr + 0);

#ifdef DEBUG
		printk( "frame_len=%4d\n", frame_len );
#endif
		if (frame_len>1518)
			frame_len = 1518;

		if ( (pbuf0.rx_write_ptr + frame_len + 0x10) > pbuf0.rx_end_ptr ) {
			if (pbuf0.rx_read_ptr == pbuf0.rx_start_ptr)
				pbuf0.rx_read_ptr = pbuf0.rx_write_ptr;
			memcpy( pbuf0.rx_start_ptr, pbuf0.rx_read_ptr, (pbuf0.rx_write_ptr - pbuf0.rx_read_ptr ));
			pbuf0.rx_write_ptr = pbuf0.rx_start_ptr + (pbuf0.rx_write_ptr - pbuf0.rx_read_ptr );
			pbuf0.rx_read_ptr = pbuf0.rx_start_ptr;
		}

		// L2 header
		p = (read_ptr + 0x10);

		for ( i = 0; i < 14; ++i ) {
			*(unsigned short *)pbuf0.rx_write_ptr = hex[ p[i] ];
			pbuf0.rx_write_ptr += 2;
			if ( pbuf0.rx_write_ptr > pbuf0.rx_end_ptr )
				pbuf0.rx_write_ptr -= (pbuf0.rx_end_ptr - pbuf0.rx_start_ptr + 1);
			if ( i == 5 || i== 11 || i == 13 ) {
				*pbuf0.rx_write_ptr++ = ' ';
			}
		}

		// L3 header
		p = (read_ptr + 0x24);
		for ( i = 0; i < (frame_len-14) ; ++i) {
			*(unsigned short *)pbuf0.rx_write_ptr = hex[ p[i] ];
			pbuf0.rx_write_ptr += 2;
			if ( pbuf0.rx_write_ptr > pbuf0.rx_end_ptr )
				pbuf0.rx_write_ptr -= (pbuf0.rx_end_ptr - pbuf0.rx_start_ptr + 1);
			if ( likely( i != (frame_len-14-1) ) ) {
				*pbuf0.rx_write_ptr++ = ' ';
			} else {
				*pbuf0.rx_write_ptr++ = '\n';
			}
			if ( pbuf0.rx_write_ptr > pbuf0.rx_end_ptr )
				pbuf0.rx_write_ptr -= (pbuf0.rx_end_ptr - pbuf0.rx_start_ptr + 1);
		}


		dma1_addr_read = (long)*dma1_addr_cur;

		wake_up_interruptible( &read_q );
	}

lend:
	return IRQ_RETVAL(handled);
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
	int copy_len, available_read_len;
#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	if ( wait_event_interruptible( read_q, ( pbuf0.rx_read_ptr != pbuf0.rx_write_ptr ) ) )
		return -ERESTARTSYS;

	available_read_len = (pbuf0.rx_write_ptr - pbuf0.rx_read_ptr);

	if ( (pbuf0.rx_read_ptr + available_read_len ) > pbuf0.rx_end_ptr )
		available_read_len = (pbuf0.rx_end_ptr - pbuf0.rx_read_ptr + 1);

	if ( count > available_read_len )
		copy_len = available_read_len;
	else
		copy_len = count;

	if ( copy_to_user( buf, pbuf0.rx_read_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}

	pbuf0.rx_read_ptr += copy_len;
	if (pbuf0.rx_read_ptr > pbuf0.rx_end_ptr)
		pbuf0.rx_read_ptr = pbuf0.rx_start_ptr;

	return copy_len;
}

static ssize_t ethpipe_write(struct file *filp, const char __user *buf,
			    size_t count, loff_t *ppos)
{
	static unsigned char tmp_pkt[14+MAX_FRAME_LEN] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0};
	unsigned int copy_len, pos, frame_len;
	unsigned short hw_slot_addr = 0u;
	unsigned char *cr;
	unsigned short *p1;
	int i;

	copy_len = 0;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	// copy from user inputs to kernel buffer
	if ( copy_from_user( pbuf0.tx_write_ptr, buf, count ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}
	pbuf0.tx_write_ptr += count;

	copy_len = count;

	hw_slot_addr = *tx_write_ptr;

ethpipe_write_loop:

	// check input number of words
	for ( cr = pbuf0.tx_read_ptr; cr < pbuf0.tx_write_ptr && *cr != '\n'; ++cr );
	if ( cr == pbuf0.tx_write_ptr )
		goto ethpipe_write_exit;

//#ifdef DEBUG
	printk("pbuf0.tx_write_ptr: %p\n", pbuf0.tx_write_ptr);
	printk("pbuf0.tx_read_ptr: %p\n", pbuf0.tx_read_ptr);
	printk("cr               : %p\n", cr);
	printk("count: %d\n", (int)count);
//#endif

	frame_len = 0;
	pos = 0;
	for ( ; pbuf0.tx_read_ptr < cr && frame_len < MAX_FRAME_LEN; ++pbuf0.tx_read_ptr ) {

		// skip blank char
		if (*pbuf0.tx_read_ptr == ' ')
			continue;

		// upper words
		if (*pbuf0.tx_read_ptr >= 'a' && *pbuf0.tx_read_ptr <= 'z')
			*pbuf0.tx_read_ptr -= 0x20;

		// ascii to number
		if (*pbuf0.tx_read_ptr >= '0' && *pbuf0.tx_read_ptr <= '9') {
			if (pos == 0) {
				tmp_pkt[frame_len+14] = (*pbuf0.tx_read_ptr - '0') << 4;
				pos = 1;
			} else {
				tmp_pkt[frame_len+14] |= (*pbuf0.tx_read_ptr - '0');
				pos = 0;
				++frame_len;
			}
		} else if (*pbuf0.tx_read_ptr >= 'A' && *pbuf0.tx_read_ptr <= 'F') {
			if (pos == 0) {
				tmp_pkt[frame_len+14] = (*pbuf0.tx_read_ptr - 'A' + 0xA) << 4;
				pos = 1;
			} else {
				tmp_pkt[frame_len+14] |= (*pbuf0.tx_read_ptr - 'A' + 0xA);
				pos = 0;
				++frame_len;
			}
		} else {
			printk("input data err: %c\n", *pbuf0.tx_read_ptr);
			goto ethpipe_write_exit;
		}
//		printk( "frame_len: %d, word: %c\n", frame_len, *pbuf0.tx_read_ptr );
	}

	// set frame length
	printk( "frame_len: %d\n", frame_len );
	tmp_pkt[0] = (frame_len >> 8) & 0xFF;
	tmp_pkt[1] = frame_len & 0xFF;
	printk( "tmp_pkt[0] = %02x, tmp_pkt[1] = %02x\n", tmp_pkt[0], tmp_pkt[1] );

#ifdef DEBUG
	printk( "%02x%02x%02x%02x%02x%02x %02x%02x%02x%02x%02x%02x %02x%02x %02x %02x\n",
		tmp_pkt[14], tmp_pkt[15], tmp_pkt[16], tmp_pkt[17], tmp_pkt[18], tmp_pkt[19],
		tmp_pkt[20], tmp_pkt[21], tmp_pkt[22], tmp_pkt[23], tmp_pkt[24], tmp_pkt[25],
		tmp_pkt[26], tmp_pkt[27],
		tmp_pkt[27], tmp_pkt[28]);
#endif

	// write send data to FPGA memory
	memcpy(mmio1_ptr + hw_slot_addr, tmp_pkt, frame_len+ETHPIPE_HEADER_LEN);

#ifdef DEBUG
	p1 = (unsigned short *)mmio1_ptr;
	for (i=0; i<200;i++)
		printk("%04X: %04X\n", i, *(p1++));
#endif

	if (frame_len % 2)
		hw_slot_addr = hw_slot_addr + ((frame_len + 1) / 2) + 7;
	else
		hw_slot_addr = hw_slot_addr + (frame_len / 2) + 7;

	printk( "hw_slot_addr: %d\n", hw_slot_addr );
	printk( "*tx_write_ptr: %d, *tx_read_ptr %d\n", *tx_write_ptr, *tx_read_ptr);

	pbuf0.tx_read_ptr = cr + 1;

	goto ethpipe_write_loop;


ethpipe_write_exit:

	printk( "ethpipe_write_exit\n" );

	// update tx_write_pointer
	*tx_write_ptr = hw_slot_addr;

	return copy_len;
}

static int ethpipe_release(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	/* disable DMA1 and DMA2 */
	*(mmio0_ptr + 0x10)  = 0x0;

	return 0;
}

static unsigned int ethpipe_poll( struct file* filp, poll_table* wait )
{
	unsigned int retmask = 0;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	poll_wait( filp, &read_q,  wait );
//      poll_wait( filp, &write_q, wait );

	if ( pbuf0.rx_read_ptr != pbuf0.rx_write_ptr ) {
		retmask |= ( POLLIN  | POLLRDNORM );
//		log_format( "POLLIN  | POLLRDNORM" );
	}
/*
   読み込みデバイスが EOF の場合は retmask に POLLHUP を設定
   デバイスがエラー状態である場合は POLLERR を設定
   out-of-band データが読み出せる場合は POLLPRI を設定
 */

	return retmask;
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
	static char name[16];
	static int board_idx = -1;

	mmio0_ptr = 0L;
	mmio1_ptr = 0L;
	dma1_virt_ptr = 0L;
	dma1_phys_ptr = 0L;
	dma2_virt_ptr = 0L;
	dma2_phys_ptr = 0L;

	rc = pci_enable_device (pdev);
	if (rc)
		goto error;

	rc = pci_request_regions (pdev, DRV_NAME);
	if (rc)
		goto error;

	++board_idx;

	printk( KERN_INFO "board_idx: %d\n", board_idx );

	pci_set_master (pdev);		/* set BUS Master Mode */

	mmio0_start = pci_resource_start (pdev, 0);
	mmio0_end   = pci_resource_end   (pdev, 0);
	mmio0_flags = pci_resource_flags (pdev, 0);
	mmio0_len   = pci_resource_len   (pdev, 0);

	printk( KERN_INFO "mmio0_start: %X\n", (unsigned int)mmio0_start );
	printk( KERN_INFO "mmio0_end  : %X\n", (unsigned int)mmio0_end   );
	printk( KERN_INFO "mmio0_flags: %X\n", (unsigned int)mmio0_flags );
	printk( KERN_INFO "mmio0_len  : %X\n", (unsigned int)mmio0_len   );

	mmio0_ptr = ioremap(mmio0_start, mmio0_len);
	if (!mmio0_ptr) {
		printk(KERN_ERR "cannot ioremap MMIO0 base\n");
		goto error;
	}

	mmio1_start = pci_resource_start (pdev, 2);
	mmio1_end   = pci_resource_end   (pdev, 2);
	mmio1_flags = pci_resource_flags (pdev, 2);
	mmio1_len   = pci_resource_len   (pdev, 2);

	printk( KERN_INFO "mmio1_start: %X\n", (unsigned int)mmio1_start );
	printk( KERN_INFO "mmio1_end  : %X\n", (unsigned int)mmio1_end   );
	printk( KERN_INFO "mmio1_flags: %X\n", (unsigned int)mmio1_flags );
	printk( KERN_INFO "mmio1_len  : %X\n", (unsigned int)mmio1_len   );

	mmio1_ptr = ioremap_wc(mmio1_start, mmio1_len);
	if (!mmio1_ptr) {
		printk(KERN_ERR "cannot ioremap MMIO1 base\n");
		goto error;
	}

	dma1_virt_ptr = dma_alloc_coherent( &pdev->dev, PACKET_BUF_MAX, &dma1_phys_ptr, GFP_KERNEL);
	if (!dma1_virt_ptr) {
		printk(KERN_ERR "cannot dma1_alloc_coherent\n");
		goto error;
	}
	printk( KERN_INFO "dma1_virt_ptr  : %llX\n", (long long)dma1_virt_ptr );
	printk( KERN_INFO "dma1_phys_ptr  : %llX\n", (long long)dma1_phys_ptr );

	dma2_virt_ptr = dma_alloc_coherent( &pdev->dev, PACKET_BUF_MAX, &dma2_phys_ptr, GFP_KERNEL);
	if (!dma2_virt_ptr) {
		printk(KERN_ERR "cannot dma2_alloc_coherent\n");
		goto error;
	}
	printk( KERN_INFO "dma2_virt_ptr  : %llX\n", (long long)dma2_virt_ptr );
	printk( KERN_INFO "dma2_phys_ptr  : %llX\n", (long long)dma2_phys_ptr );

	if (request_irq(pdev->irq, ethpipe_interrupt, IRQF_SHARED, DRV_NAME, pdev)) {
		printk(KERN_ERR "cannot request_irq\n");
	}
	
	pcidev = pdev;

	/* Set DMA Pointer */
	dma1_addr_start = (mmio0_ptr + 0x20);
	dma1_addr_cur   = (mmio0_ptr + 0x24);
	dma2_addr_start = (mmio0_ptr + 0x28);
	dma2_addr_cur   = (mmio0_ptr + 0x2c);

	/* set DMA Buffer length */
	*(long *)(mmio0_ptr + 0x14)  = PACKET_BUF_MAX;

	/* set DMA1 start address */
	*dma1_addr_start  = dma1_phys_ptr;

	/* set DMA2 start address */
	*dma2_addr_start  = dma2_phys_ptr;

	/* set DMA read pointer */
	dma1_addr_read = dma1_phys_ptr;
	dma2_addr_read = dma2_phys_ptr;

	/* set TX slot Pointer */
	tx_write_ptr = (mmio0_ptr + TX_WRITE_PTR_ADDRESS);
	tx_read_ptr  = (mmio0_ptr + TX_READ_PTR_ADDRESS);

	/* clear tx_write_ptr */
	*tx_write_ptr = *tx_read_ptr;

	/* Set receive buffer */
	if ( ( pbuf0.rx_start_ptr = kmalloc(PACKET_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		rc = -1;
		goto error;
	}
	pbuf0.rx_end_ptr = (pbuf0.rx_start_ptr + PACKET_BUF_MAX - 1);
	pbuf0.rx_write_ptr = pbuf0.rx_start_ptr;
	pbuf0.rx_read_ptr  = pbuf0.rx_start_ptr;

	/* Set transmitte buffer */
	if ( ( pbuf0.tx_start_ptr = kmalloc(PACKET_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		rc = -1;
		goto error;
	}
	pbuf0.tx_end_ptr = (pbuf0.tx_start_ptr + PACKET_BUF_MAX - 1);
	pbuf0.tx_write_ptr = pbuf0.tx_start_ptr;
	pbuf0.tx_read_ptr  = pbuf0.tx_start_ptr;


	/* register character device */
	sprintf( name, "%s/%d", DRV_NAME, board_idx );
	ethpipe_dev.name = name,
	rc = misc_register(&ethpipe_dev);
	if (rc) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		return rc;
	}

	return 0;

error:
	if ( pbuf0.rx_start_ptr ) {
		kfree( pbuf0.rx_start_ptr );
		pbuf0.rx_start_ptr = NULL;
	}

	if ( pbuf0.tx_start_ptr ) {
		kfree( pbuf0.tx_start_ptr );
		pbuf0.tx_start_ptr = NULL;
	}

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
	if ( pbuf0.rx_start_ptr ) {
		kfree( pbuf0.rx_start_ptr );
		pbuf0.rx_start_ptr = NULL;
	}

	if ( pbuf0.tx_start_ptr ) {
		kfree( pbuf0.tx_start_ptr );
		pbuf0.tx_start_ptr = NULL;
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
#ifdef MODULE
	pr_info(ethpipe_DRIVER_NAME "\n");
#endif

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

