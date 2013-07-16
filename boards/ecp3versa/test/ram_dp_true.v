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
  , output [15:0] QA
  , output [15:0] QB
);

endmodule
