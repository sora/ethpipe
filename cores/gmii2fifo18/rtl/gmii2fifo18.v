module gmii2fifo18 # (
	parameter Gap = 4'h2
) (
	input         sys_rst,
	input [63:0]  global_counter,
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

parameter STATE_SFD0  = 4'h1;
parameter STATE_SFD1  = 4'h2;
parameter STATE_SFD2  = 4'h3;
parameter STATE_SFD3  = 4'h4;
parameter STATE_SFD4  = 4'h5;
parameter STATE_SFD5  = 4'h6;
parameter STATE_SFD6  = 4'h7;
parameter STATE_SFD7  = 4'h8;
parameter STATE_DATAH = 4'h9;
parameter STATE_DATAL = 4'ha;
reg [3:0] state;

reg [63:8] global_counter_latch;

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
		state <= STATE_SFD0;
	end else begin
                wr_en <= 1'b0;
		if (gmii_rx_dv == 1'b1) begin
			case (state)
				STATE_SFD0: begin
					gap_count <= Gap;
					global_counter_latch[63:8] <= global_counter[63:8];
					rxd[17:8] <= {2'b11, global_counter[ 7: 0]};
					state <= STATE_SFD1;
				end
				STATE_SFD1: begin
					rxd[ 7:0] <= global_counter_latch[15: 8];
               	 			wr_en <= 1'b1;
					state <= STATE_SFD2;
				end
				STATE_SFD2: begin
					rxd[17:8] <= {2'b11, global_counter[23:16]};
					state <= STATE_SFD3;
				end
				STATE_SFD3: begin
					rxd[ 7:0] <= global_counter_latch[31:24];
               	 			wr_en <= 1'b1;
					state <= STATE_SFD4;
				end
				STATE_SFD4: begin
					rxd[17:8] <= {2'b11, global_counter[39:32]};
					state <= STATE_SFD5;
				end
				STATE_SFD5: begin
					rxd[ 7:0] <= global_counter_latch[47:40];
               	 			wr_en <= 1'b1;
					state <= STATE_SFD6;
				end
				STATE_SFD6: begin
					rxd[17:8] <= {2'b11, global_counter[55:48]};
					state <= STATE_SFD7;
				end
				STATE_SFD7: begin
					rxd[ 7:0] <= global_counter_latch[63:56];
               	 			wr_en <= 1'b1;
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
			state <= STATE_SFD0;
			if (state != STATE_SFD0)
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
