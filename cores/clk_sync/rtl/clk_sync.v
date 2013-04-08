module clk_sync_ashot (
    input clk1
  , input i
  , input clk2
  , output o
);

reg buf0, buf1, buf2, buf3;
reg i0;

always @(posedge clk1) begin
    buf0 <= i;
end

always @(posedge clk2) begin
    buf1 <= buf0;
    buf2 <= buf1;
    buf3 <= buf2;
end

assign o = buf3 & ~buf2;

endmodule

module clk_sync (
    input clk1
  , input i
  , input clk2
  , output o
);

reg buf0, buf1, buf2, buf3;

always @(posedge clk1)
        buf0 <= i;

always @(posedge clk2) begin
    buf1 <= buf0;
    buf2 <= buf1;
    buf3 <= buf2;
end

assign o = buf2 & buf3;

endmodule

