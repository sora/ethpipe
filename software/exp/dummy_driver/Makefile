ifneq ($(KERNELRELEASE),)
obj-m		:= ethpipe.o ethpipe64.o ethpipe1518.o
else
KDIR		:= /lib/modules/$(shell uname -r)/build/
PWD		:= $(shell pwd)

all:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) V=1 modules

clean:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) clean 

install:
	install -m 644 $(PWD)/*.ko /lib/modules/`uname -r`/kernel/drivers/misc
	depmod -a
endif
