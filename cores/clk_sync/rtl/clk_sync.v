module clk_sync_ashot (
    input clk1
  , input i
  , input clk2
  , output o
);

reg buf0, buf1, buf2, buf3;
reg i0;

always @(posedge clk1) begin
    i0 <= i;
    if (i & ~i0)
        buf0 <= ~buf0;
end

always @(posedge clk2) begin
    buf1 <= buf0;
    buf2 <= buf1;
    buf3 <= buf2;
end

assign o = buf2 ^ buf3;

endmodule

module clk_sync (
    input clk1
  , input i
  , input clk2
  , output o
);

reg buf0, buf1, buf2, buf3;

always @(posedge clk1)
    if (i)
        buf0 <= ~buf0;

always @(posedge clk2) begin
    buf1 <= buf0;
    buf2 <= buf1;
    buf3 <= buf2;
end

assign o = buf2 ^ buf3;

endmodule

