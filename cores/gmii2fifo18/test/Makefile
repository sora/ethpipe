SOURCES=tb_gmii2fifo18.v $(wildcard ../rtl/*.v)

#all: cversim
all: isim

gtk: all
	gtkwave test.vcd

isim: tb_gmii2fifo18
	./tb_gmii2fifo18

cversim: $(SOURCES)
	cver $(SOURCES)

clean:
	rm -f tb_gmii2fifo18 verilog.log test.vcd

tb_gmii2fifo18: $(SOURCES)
	iverilog -o tb_gmii2fifo18 $(SOURCES)

.PHONY: clean isim cversim gtk
