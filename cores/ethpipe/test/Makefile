SIM_SRC=tb_ethpipe.v ../../crc/rtl/crc.v ../../clk_sync/rtl/clk_sync.v ../rtl/ethpipe.v

test: request.hex isim

tb_system: $(SIM_SRC)
	iverilog -o tb_system $(SIM_SRC)

isim: tb_system
	./tb_system

wave: test
	gtkwave test.vcd

clean:
	rm -f tb_system verilog.log test.vcd

.PHONY: clean isim wave
