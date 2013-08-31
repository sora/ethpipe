`default_nettype none
`include "setup.v"
module receiver (
	// System
	input sys_clk,
	input sys_rst,
	output reg sys_intr,
	// Phy FIFO
	input [17:0] phy_dout,
	input phy_empty,
	output reg phy_rd_en,
	// Length FIFO
	input [17:0] len_dout,
	input len_empty,
	output reg len_rd_en,
	// Master FIFO
	output reg [17:0] mst_din,
	input mst_full,
	output reg  mst_wr_en,
	input [17:0] mst_dout,
	input mst_empty,
	output reg mst_rd_en,
	// DMA regs
	input [7:0]  dma_status,
	input [21:2] dma_length,
	input [31:2] dma_addr_start,
	input dma_load,
	output reg [31:2] dma_addr_cur,
	// LED and Switches
	input [7:0] dipsw,
	output [7:0] led,
	output [13:0] segled,
	input btn
);

wire [31:2] dma_addr_end1 = (dma_addr_start + dma_length);
wire [31:2] dma_addr_end  = (dma_addr_end1 - 1);

parameter [3:0]
	REC_IDLE     = 4'h0,
	REC_SKIP     = 4'h1,
	REC_HEAD     = 4'h2,
	REC_HEAD0    = 4'h3,
	REC_HEAD1    = 4'h4,
	REC_HEAD2    = 4'h5,
	REC_LENGTHL  = 4'h6,
	REC_LENGTHH  = 4'h7,
	REC_TUPLEL   = 4'h8,
	REC_TUPLEH   = 4'h9,
	REC_DATA     = 4'ha,
	REC_FIN      = 4'he,
	REC_FIN2     = 4'hf;
reg [3:0] rec_status = REC_IDLE;

reg dma_load_req = 1'b0, dma_load_ack = 1'b0;

reg [31:2] dma_frame_ptr;	// current frame ptr
reg dma_frame_in;		// in frame ?
reg dma_enable;

always @(posedge sys_clk) begin
	if (sys_rst) begin
		dma_load_req <= 1'b0;
	end else begin
		if (dma_load) begin
			dma_load_req <= 1'b1;
		end else if (dma_load_ack)
			dma_load_req <= 1'b0;
	end
end
	
reg [10:0] frame_len;
reg [8:0] total_remain;
reg [9:0] tlp_remain;
always @(posedge sys_clk) begin
	if (sys_rst) begin
		sys_intr <= 1'b0;
		dma_load_ack <= 1'b0;
		dma_frame_ptr <= dma_addr_start;
		dma_addr_cur <= dma_addr_start;
		dma_frame_in <= 1'b0;
		dma_enable <= 1'b0;
		dma_addr_cur <= 30'h0;
		frame_len <= 11'h0;
		total_remain <= 9'h0;
		tlp_remain <= 10'h0;
		phy_rd_en <= 1'b0;
		len_rd_en <= 1'b0;
		mst_wr_en <= 1'b0;
		rec_status <= REC_IDLE;
	end else begin
		sys_intr <= 1'b0;
		dma_load_ack <= 1'b0;
		phy_rd_en <= 1'b0;
		len_rd_en <= 1'b0;
		mst_wr_en <= 1'b0;
		case ( rec_status )
			REC_IDLE: begin
				len_rd_en <= ~len_empty;
				if ( len_rd_en && len_dout[17] ) begin
					len_rd_en <= 1'b0;
`ifdef SIMULATION
					dma_enable <= 1'b1;
`else
					dma_enable <= dma_status[0];
`endif
					frame_len <= (len_dout[10:0] - 11'h8);  // subtract gcounter
					total_remain <= ((len_dout[10:0] + 11'hb) >> 2);
					dma_frame_in <= 1'b0;
					rec_status <= REC_SKIP;
				end else if ( dma_load_req ) begin
					dma_frame_ptr <= dma_addr_start;
					dma_addr_cur <= dma_addr_start;
					dma_load_ack <= 1'b1;
				end
			end
			REC_SKIP: begin
				phy_rd_en <= ~phy_empty;
				if (phy_rd_en && phy_dout[17]) begin
					phy_rd_en <= 1'b0;
					rec_status <= REC_HEAD;
				end
			end
			REC_HEAD: begin
				if (total_remain < `TLP_MAX>>2) begin
					mst_din[13:8] <= total_remain[5:0];
					tlp_remain <= {total_remain[8:0], 1'b0};
				end else begin
					mst_din[13:8] <= `TLP_MAX>>2;
					tlp_remain <= `TLP_MAX>>1;
				end
				rec_status <= REC_HEAD0;
			end
			REC_HEAD0: begin
				mst_din[17:14] <= 4'b10_10;	// Write command
				if ((dma_frame_ptr + tlp_remain[9:1]) >= dma_addr_end1) begin
					mst_din[13:8] <= (dma_addr_end1 - dma_frame_ptr);
					tlp_remain <= {(dma_addr_end1 - dma_frame_ptr), 1'b0};
				end
				mst_din[7:0] <= 8'hff;
				mst_wr_en <= dma_enable;
				rec_status <= REC_HEAD1;
			end
			REC_HEAD1: begin
				mst_din[17:0] <= {2'b00, dma_frame_ptr[31:16]};
				mst_wr_en <= dma_enable;
				rec_status <= REC_HEAD2;
			end
			REC_HEAD2: begin
				mst_din[17:0] <= {2'b00, dma_frame_ptr[15:2], 2'b00};
				mst_wr_en <= dma_enable;
				if (dma_frame_in == 1'b0) begin
					rec_status <= REC_LENGTHL;
				end else begin
					phy_rd_en <= ~phy_empty;
					rec_status <= REC_DATA;
				end
			end
			REC_LENGTHL: begin
				dma_frame_in <= 1'b1;
				mst_din[17:0] <= {2'b00, frame_len[7:0], 5'b00000, frame_len[10:8]};
				mst_wr_en <= dma_enable;
				rec_status <= REC_LENGTHH;
			end
			REC_LENGTHH: begin
				mst_din[17:0] <= {2'b00, 16'h0000};
				mst_wr_en <= dma_enable;
				rec_status <= REC_TUPLEL;
			end
			REC_TUPLEL: begin
				mst_din[17:0] <= {2'b00, 16'h55_55};
				mst_wr_en <= dma_enable;
				rec_status <= REC_TUPLEH;
			end
			REC_TUPLEH: begin
				if (dma_enable)
					dma_frame_ptr <= dma_frame_ptr + 30'h2;
				total_remain <= total_remain - 9'h2;
				tlp_remain <= tlp_remain - 10'h4;
				mst_din[17:0] <= {2'b00, 16'h55_5d};
				mst_wr_en <= dma_enable;
				rec_status <= REC_DATA;
			end
			REC_DATA: begin
				mst_din[15:0] <= phy_dout[15:0];
				if (phy_dout[17:16] != 2'b11) begin
					dma_frame_in <= 1'b0;
					phy_rd_en <= 1'b0;
				end
				mst_wr_en <= dma_enable;
				mst_din[17] <= 1'b0;
				if (tlp_remain == 10'h00) begin
					phy_rd_en <= 1'b0;
					mst_din[16] <= 1'b1;
					if (total_remain != 10'h0)
						rec_status <=  REC_HEAD;
					else begin
						rec_status <=  REC_FIN;
					end
				end else begin
					mst_din[16] <= 1'b0;
					tlp_remain <= tlp_remain - 10'h1;
					if (!tlp_remain[0]) begin
						total_remain <= total_remain - 10'h1;
						if (dma_enable) begin
							if (dma_frame_ptr == dma_addr_end)
								dma_frame_ptr <= dma_addr_start;
							else
								dma_frame_ptr <= dma_frame_ptr + 30'h1;
						end
					end
					if (dma_frame_in && tlp_remain != 10'h1)
						phy_rd_en <= ~phy_empty;
					else
						phy_rd_en <= 1'b0;
				end
			end
			REC_FIN: begin
				if (dma_enable) begin
					if (dma_frame_ptr[3:2] != 2'b00) begin
						dma_frame_ptr[31:4] <= (dma_frame_ptr[31:4] + 28'h1);
					end
					dma_frame_ptr[3:2] <= 2'b00;
					sys_intr <= 1'b1;
				end
				rec_status <= REC_FIN2;
			end
			REC_FIN2: begin
				if (dma_frame_ptr == dma_addr_end1) begin
					dma_frame_ptr <= dma_addr_start;
					dma_addr_cur <= dma_addr_start;
				end else begin
					dma_addr_cur <= dma_frame_ptr;
				end
				rec_status <= REC_IDLE;
			end
		endcase
	end
end

//assign led[7:0] = ~eth_dest[7:0];

endmodule
`default_nettype wire
