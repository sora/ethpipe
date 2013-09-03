SOURCES=$(wildcard *.v) \
	$(wildcard ../../../cores/ethpipe/rtl/*.v) \
	$(wildcard ../../../cores/clk_sync/rtl/*.v) \
	$(wildcard ../../../cores/crc/rtl/*.v) \
	$(wildcard ../../../cores/gmii2fifo18/rtl/*.v) \
	$(wildcard ../rtl/ecp3/ethpipe_mid.v) \
	$(wildcard ../rtl/ecp3/receiver.v) \
	$(wildcard ../rtl/ecp3/sender.v) \
	$(wildcard ../rtl/ecp3/pcie_tlp.v)

#all: cversim
all: tlp_data.hex phy_data.hex isim

gtk: all
	gtkwave test.vcd

wave: all
	gtkwave wave_files/send_phy1.gtkw

isim: tb_system
	./tb_system

lint: $(SOURCES) lint.vh
	verilator --lint-only --top-module ethpipe_mid lint.vh $(SOURCES)

lint-all: $(SOURCES) lint.vh
	verilator --lint-only -Wall --top-module ethpipe_mid lint.vh $(SOURCES)

cversim: $(SOURCES)
	cver $(SOURCES)

clean:
	rm -f tb_system verilog.log test.vcd

tb_system: $(SOURCES)
	iverilog -o tb_system $(SOURCES)

.PHONY: clean isim cversim gtk
