`timescale 1ps / 1ps
`define SIMULATION
//`include "../rtl/setup.v"
module tb_system();

`ifndef VERILATOR
/* 125MHz system clock */
reg sys_clk;
initial sys_clk = 1'b0;
initial gmii_tx_clk = 1'b0;
initial gmii_rx_clk = 1'b0;
always #8 sys_clk = ~sys_clk;
always #8 gmii_tx_clk = ~gmii_tx_clk;
always #8 gmii_rx_clk = ~gmii_rx_clk;

// System
reg sys_rst;
// Management
reg [6:0] rx_bar_hit = 6'b000011;
reg [7:0] bus_num = 8'h12;
reg [4:0] dev_num = 5'h1;
reg [2:0] func_num = 3'h1;
// Receive
reg rx_st;
reg rx_end;
reg [15:0] rx_data;
// Transmit
wire tx_req;
reg tx_rdy=1'b1;
wire tx_st;
wire tx_end;
wire [15:0] tx_data;
// Receive credits
wire [7:0] pd_num;
wire ph_cr;
wire pd_cr;
wire nph_cr;
wire npd_cr;
// Phy
reg gmii_tx_clk;
wire [7:0] gmii_txd;
wire gmii_tx_en;
reg [7:0] gmii_rxd;
reg gmii_rx_dv;
reg gmii_rx_clk;
// LED and Switches
reg [7:0] dipsw;
wire [7:0] led;
wire [13:0] segled;

ethpipe_mid ethpipe_mid_inst (
	.clk_125(sys_clk),
	.sys_rst(sys_rst),
	// Management
	.rx_bar_hit(rx_bar_hit),
	.bus_num(bus_num),
	.dev_num(dev_num),
	.func_num(func_num),
	// Receive
	.rx_st(rx_st),
	.rx_end(rx_end),
	.rx_data(rx_data),
	// Transmit
	.tx_req(tx_req),
	.tx_rdy(tx_rdy),
	.tx_st(tx_st),
	.tx_end(tx_end),
	.tx_data(tx_data),
	// Receive credits
	.pd_num(),
	.ph_cr(),
	.pd_cr(),
	.nph_cr(),
	.npd_cr(),
	// Phy
	.phy1_125M_clk(gmii_tx_clk),
	.phy1_tx_data(gmii_txd),
	.phy1_tx_en(gmii_tx_en),
	.phy1_rx_data(gmii_rxd),
	.phy1_rx_dv(gmii_rx_dv),
	.phy1_rx_clk(gmii_rx_clk),
	// Phy
	.phy2_125M_clk(gmii_tx_clk),
	.phy2_tx_data(gmii_txd),
	.phy2_tx_en(gmii_tx_en),
	.phy2_rx_data(8'h00),
	.phy2_rx_dv(1'b0),
	.phy2_rx_clk(gmii_rx_clk),
	// LED and Switches
	.dipsw(),
	.led(),
	.segled()
);

task waitclock;
begin
	@(posedge sys_clk);
	#1;
end
endtask

/*
always @(posedge Wclk) begin
	if (WriteEn_in == 1'b1)
		$display("Data_in: %x", Data_in);
end
*/

reg [23:0] tlp_rom [0:4095];
reg [11:0] phy_rom [0:4095];
reg [11:0] tlp_counter, phy_counter;
wire [23:0] tlp_cur;
wire [11:0] phy_cur;
assign tlp_cur = tlp_rom[ tlp_counter ];
assign phy_cur = phy_rom[ phy_counter ];

always @(posedge sys_clk) begin
	rx_st   <= tlp_cur[20];
	rx_end  <= tlp_cur[16];
	rx_data <= tlp_cur[15:0];
	tlp_counter <= tlp_counter + 1;
end

always @(posedge sys_clk) begin
	gmii_rx_dv  <= phy_cur[8];
	gmii_rxd    <= phy_cur[7:0];
	phy_counter <= phy_counter + 1;
end

initial begin
	$dumpfile("./test.vcd");
	$dumpvars(0, tb_system); 
	$readmemh("./tlp_data.hex", tlp_rom);
	$readmemh("./phy_data.hex", phy_rom);
	/* Reset / Initialize our logic */
	sys_rst = 1'b1;
	tlp_counter = 0;
	phy_counter = 0;

	waitclock;
	waitclock;

	sys_rst = 1'b0;

	waitclock;

//	#(1*16) ethpipe_mid_inst.global_counter[47:0] = 64'h0123456789ab;
	#(1*16) ethpipe_mid_inst.global_counter[47:0] = 64'h2000;
//	#(60*16) ethpipe_mid_inst.tx0mem_wr_ptr = 12'h26;
	#(60*16) ethpipe_mid_inst.tx0mem_wr_ptr = 12'h4c;
	#(180*16) ethpipe_mid_inst.tx0mem_wr_ptr = 12'h72;
	#(240*16) ethpipe_mid_inst.tx0mem_wr_ptr = 12'hd8;

//	#(8*2) mst_req_o = 1'b0;

	#10000;

	$finish;
end
`endif

endmodule

