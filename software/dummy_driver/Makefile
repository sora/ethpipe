ifneq ($(KERNELRELEASE),)
obj-m		:= ethpipe.o ethpipe64.o ethpipe1518.o
else
KDIR		:= /lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) V=1 modules
clean:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) clean 
endif
