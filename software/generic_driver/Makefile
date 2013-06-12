ifneq ($(KERNELRELEASE),)
obj-m		:= genpipe0.o genpipe1.o
else
KDIR		:= /lib/modules/$(shell uname -r)/build/
KDIR2		:= /lib/modules/$(shell uname -r)/kernel/
PWD		:= $(shell pwd)

all:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) V=1 modules

clean:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) clean 

install:
	cp -p $(PWD)/*.ko $(KDIR2)/drivers/misc/
	depmod -a
endif
