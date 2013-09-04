module gmii2fifo18 # (
	parameter Gap = 4'h2
) (
	input sys_rst,
	input [63:0] global_counter,
	input gmii_rx_clk,
	input gmii_rx_dv,
	input [7:0] gmii_rxd,
	// DATA FIFO
	output [17:0] data_din,
	input data_full,
	output reg data_wr_en,
	// LENGTH FIFO
	output reg [17:0] len_din,
	input len_full,
	output reg len_wr_en,
	output wr_clk
);

assign wr_clk = gmii_rx_clk;

parameter STATE_SFD  = 1'h0;
parameter STATE_DATA = 1'h1;
reg state;

reg [63:0] global_counter_latch;
reg [2:0] sfd_count;
reg [15:0] frame_len;
reg data_odd;

//-----------------------------------
// logic
//-----------------------------------
reg [17:0] rxd = 18'h000;
reg rxc = 1'b0;
reg [3:0] gap_count = 4'h0;
always @(posedge gmii_rx_clk) begin
	if (sys_rst) begin
		gap_count <= 4'h0;
		sfd_count <= 3'h0;
		data_odd <= 1'b0;
		frame_len <= 16'h0;
		rxd <= 18'h000;
		data_wr_en <= 1'b0;
		len_wr_en <= 1'b0;
		state <= STATE_SFD;
	end else begin
		data_wr_en <= 1'b0;
		len_wr_en <= 1'b0;
		if (gmii_rx_dv == 1'b1) begin
			case (state)
				STATE_SFD: begin
					gap_count <= Gap;
					sfd_count <= sfd_count + 3'h1;
					data_odd <= 1'b0;
					frame_len <= 16'h8;
					rxd[17:16] <= 2'b11;
					case (sfd_count)
						3'h0: rxd[15:8] <= global_counter_latch[63:56];
						3'h1: rxd[ 7:0] <= global_counter_latch[55:48];
						3'h2: rxd[15:8] <= global_counter_latch[47:40];
						3'h3: rxd[ 7:0] <= global_counter_latch[39:32];
						3'h4: rxd[15:8] <= global_counter_latch[31:24];
						3'h5: rxd[ 7:0] <= global_counter_latch[23:16];
						3'h6: rxd[15:8] <= global_counter_latch[15: 8];
						3'h7: rxd[ 7:0] <= global_counter_latch[ 7: 0];
					endcase
	       	 			data_wr_en <= sfd_count[0];
					if (sfd_count == 3'h7)
						state <= STATE_DATA;
				end
				STATE_DATA: begin
					frame_len <= frame_len + 16'h1;
					data_odd <= ~data_odd;
	       		 		data_wr_en <= data_odd;
					if (data_odd == 1'b0) begin
						rxd[17:0] <= {2'b10, gmii_rxd[7:0], 8'h00};
					end else begin
						rxd[16] <= 1'b1;
						rxd[7:0] <= gmii_rxd[7:0];
					end
				end
			endcase
		end else begin
			global_counter_latch[63:0] <= global_counter[63:0];
			sfd_count <= 3'h0;
			state <= STATE_SFD;
			if (state == STATE_DATA) begin
				if (data_odd == 1'b1) begin
	       		 		data_wr_en <= 1'b1;
				end
				len_din[17:0] <= {2'b10, frame_len};
				len_wr_en <= 1'b1;
			end else begin
				rxd <= 18'h000;
				rxd[17:0] <= 18'h00;
				len_din <= 18'h0;
				if (gap_count != 4'h0) begin
					data_wr_en <= 1'b1;
					len_wr_en <= 1'b1;
					gap_count <= gap_count - 4'h1;
				end
			end
		end
	end
end

assign data_din[17:0] = rxd[17:0];

endmodule
