`include "setup.v"

module ram_dp_true  (
    input  [15:0] DataInA
  , input  [15:0] DataInB
  , input  [1:0] ByteEnA
  , input  [1:0] ByteEnB
  , input  [13:0] AddressA
  , input  [13:0] AddressB
  , input  ClockA
  , input  ClockB
  , input  ClockEnA
  , input  ClockEnB
  , input  WrA
  , input  WrB
  , input  ResetA
  , input  ResetB
  , output reg [15:0] QA
  , output reg [15:0] QB
);

reg [15:0] mem [0:16383];

always @(posedge ClockA) begin
	if (WrA) begin
		if (ByteEnA[0])
			mem[AddressA][7:0] <= DataInA[7:0];
		if (ByteEnA[1])
			mem[AddressA][15:8] <= DataInA[15:8];
	end
	QA <= mem[AddressA];
end

always @(posedge ClockB) begin
	if (WrB) begin
		if (ByteEnB[0])
			mem[AddressB][7:0] <= DataInB[7:0];
		if (ByteEnB[1])
			mem[AddressB][15:8] <= DataInB[15:8];
	end
	QB <= mem[AddressB];
end

endmodule
