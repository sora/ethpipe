module gmii2fifo18 # (
	parameter Gap = 4'h2
) (
	input         sys_rst,
	input         gmii_rx_clk,
	input         gmii_rx_dv,
	input  [7:0]  gmii_rxd,
	// FIFO
	output [17:0]  din,
	input         full,
        output reg    wr_en,
	output        wr_clk,
	output reg [7:0] wr_count
);

assign wr_clk = gmii_rx_clk;

parameter STATE_IDLE  = 2'h0;
parameter STATE_DATAH = 2'h1;
parameter STATE_DATAL = 2'h2;
reg [1:0] state;

//-----------------------------------
// logic
//-----------------------------------
reg [17:0] rxd = 18'h000;
reg rxc = 1'b0;
reg [3:0] gap_count = 4'h0;
always @(posedge gmii_rx_clk) begin
	if (sys_rst) begin
		gap_count <= Gap;
		rxd <= 18'h000;
		wr_en <= 1'b0;
		wr_count <= 8'h0;
		state <= STATE_IDLE;
	end else begin
                wr_en <= 1'b0;
		if (gmii_rx_dv == 1'b1) begin
			case (state)
				STATE_IDLE: begin
					gap_count <= Gap;
					if (gmii_rxd[7:0] == 8'hd5)
						state <= STATE_DATAH;
				end
				STATE_DATAH: begin
					rxd[17:0] <= {2'b10, gmii_rxd[7:0], 8'h00};
					state <= STATE_DATAL;
				end
				STATE_DATAL: begin
					rxd[16] <= 1'b1;
					rxd[7:0] <= gmii_rxd[7:0];
               			 	wr_en <= 1'b1;
					state <= STATE_DATAH;
				end
			endcase
		end else begin
			state <= STATE_IDLE;
			if (state != STATE_IDLE)
				wr_count <= wr_count + 8'h1;
			if (state != STATE_DATAL) begin
				rxd <= 18'h000;
			end
			if (gap_count != 4'h0) begin
                		wr_en <= 1'b1;
				gap_count <= gap_count - 4'h1;
			end
		end
	end
end

assign din[17:0] = rxd[17:0];

endmodule
