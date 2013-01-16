//Verilog testbench template generated by SCUBA Diamond_1.4_Production (87)
`timescale 1 ns / 1 ps
module tb;
    reg [15:0] DataInA = 16'b0;
    reg [15:0] DataInB = 16'b0;
    reg [1:0] ByteEnA = 2'b0;
    reg [1:0] ByteEnB = 2'b0;
    reg [11:0] AddressA = 12'b0;
    reg [11:0] AddressB = 12'b0;
    reg ClockA = 0;
    reg ClockB = 0;
    reg ClockEnA = 0;
    reg ClockEnB = 0;
    reg WrA = 0;
    reg WrB = 0;
    reg ResetA = 0;
    reg ResetB = 0;
    wire [15:0] QA;
    wire [15:0] QB;

    integer i0 = 0, i1 = 0, i2 = 0, i3 = 0, i4 = 0, i5 = 0, i6 = 0, i7 = 0, i8 = 0, i9 = 0, i10 = 0, i11 = 0, i12 = 0, i13 = 0, i14 = 0, i15 = 0;

    GSR GSR_INST (.GSR(1'b1));
    PUR PUR_INST (.PUR(1'b1));

    ram_dp_true u1 (.DataInA(DataInA), .DataInB(DataInB), .ByteEnA(ByteEnA), 
        .ByteEnB(ByteEnB), .AddressA(AddressA), .AddressB(AddressB), .ClockA(ClockA), 
        .ClockB(ClockB), .ClockEnA(ClockEnA), .ClockEnB(ClockEnB), .WrA(WrA), 
        .WrB(WrB), .ResetA(ResetA), .ResetB(ResetB), .QA(QA), .QB(QB)
    );

    initial
    begin
       DataInA <= 0;
      #100;
      @(ResetA == 1'b0);
      for (i1 = 0; i1 < 4099; i1 = i1 + 1) begin
        @(posedge ClockA);
        #1  DataInA <= DataInA + 1'b1;
      end
    end
    initial
    begin
       DataInB <= 0;
      #100;
      @(ResetB == 1'b0);
      @(WrB == 1'b1);
      for (i2 = 0; i2 < 4099; i2 = i2 + 1) begin
        @(posedge ClockB);
        #1  DataInB <= DataInB + 1'b1;
      end
    end
    initial
    begin
       AddressA <= 0;
      #100;
      @(ResetA == 1'b0);
      for (i5 = 0; i5 < 8198; i5 = i5 + 1) begin
        @(posedge ClockA);
        #1  AddressA <= AddressA + 1'b1;
      end
    end
    initial
    begin
       AddressB <= 0;
      #100;
      @(ResetB == 1'b0);
      @(WrB == 1'b1);
      for (i6 = 0; i6 < 8198; i6 = i6 + 1) begin
        @(posedge ClockB);
        #1  AddressB <= AddressB + 1'b1;
      end
    end
    always
    #5.00 ClockA <= ~ ClockA;

    always
    #5.00 ClockB <= ~ ClockB;

    initial
    begin
       ClockEnA <= 1'b0;
      #100;
      @(ResetA == 1'b0);
       ClockEnA <= 1'b1;
    end
    initial
    begin
       ClockEnB <= 1'b0;
      #100;
      @(ResetB == 1'b0);
       ClockEnB <= 1'b1;
    end
    initial
    begin
       WrA <= 1'b0;
      @(ResetA == 1'b0);
      for (i11 = 0; i11 < 4099; i11 = i11 + 1) begin
        @(posedge ClockA);
        #1  WrA <= 1'b1;
      end
       WrA <= 1'b0;
    end
    initial
    begin
       WrB <= 1'b0;
      @(ResetB == 1'b0);
      @(WrA == 1'b1);
      @(WrA == 1'b0);
      for (i12 = 0; i12 < 4099; i12 = i12 + 1) begin
        @(posedge ClockA);
      end
      for (i12 = 0; i12 < 4099; i12 = i12 + 1) begin
        @(posedge ClockB);
        #1  WrB <= 1'b1;
      end
       WrB <= 1'b0;
    end
    initial
    begin
       ResetA <= 1'b1;
      #100;
       ResetA <= 1'b0;
    end
    initial
    begin
       ResetB <= 1'b1;
      #100;
       ResetB <= 1'b0;
    end
endmodule