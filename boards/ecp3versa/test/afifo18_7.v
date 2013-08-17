`default_nettype none
module afifo18_7 (
	input wire [17:0] Data,
	input wire WrClock,
	input wire RdClock,
	input wire WrEn,
	input wire RdEn,
	input wire Reset,
	input wire RPReset,
	output wire [17:0] Q,
	output wire Empty,
	output wire Full
);

asfifo # (
	.DATA_WIDTH(18),
	.ADDRESS_WIDTH(7)
) asfifo_inst (
	.dout(Q), 
	.empty(Empty),
	.rd_en(RdEn),
	.rd_clk(RdClock),        
	.din(Data),  
	.full(Full),
	.wr_en(WrEn),
	.wr_clk(WrClock),
	.rst(Reset)
);

endmodule
`default_nettype wire
