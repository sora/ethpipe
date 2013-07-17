`default_nettype none
module receiver (
	// System
	input sys_clk,
	input sys_rst,
	// Phy FIFO
	input [17:0] phy1_dout,
	input phy1_empty,
	output reg phy1_rd_en,
	input [7:0] phy1_rx_count,
	input [17:0] phy2_dout,
	input phy2_empty,
	output reg phy2_rd_en,
	input [7:0] phy2_rx_count,
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
	input [31:2] dma1_addr_start,
	output [31:2] dma1_addr_cur,
	input [31:2] dma2_addr_start,
	output [31:2] dma2_addr_cur,
	// LED and Switches
	input [7:0] dipsw,
	output [7:0] led,
	output [13:0] segled,
	input btn
);

parameter [3:0]
	REC_IDLE     = 4'h0,
	REC_HEAD10   = 4'h1,
	REC_HEAD11   = 4'h2,
	REC_HEAD12   = 4'h3,
	REC_SKIP     = 4'h4,
	REC_DATA     = 4'h5,
	REC_HEAD20   = 4'h6,
	REC_HEAD21   = 4'h7,
	REC_HEAD22   = 4'h8,
	REC_LENGTH   = 4'h9,
	REC_TUPLE    = 4'ha,
	REC_FIN      = 4'hf;
reg [3:0] rec_status = REC_IDLE;

reg [31:2] dma1_frame_start, dma2_frame_start;	// current frame start addr
reg [31:2] dma1_frame_ptr, dma2_frame_ptr;	// current frame ptr
reg [11:0] dma1_frame_len, dma2_frame_len;	// current frame length (0-4095)
reg dma1_frame_in, dma2_frame_in;		// in frame ?
reg [7:0] dma1_rx_count, dma2_rx_count;		// frame received count
reg sel_phy;					// selected phy number (0-1)
	
reg [7:0] remain_word;
always @(posedge sys_clk) begin
	if (sys_rst) begin
		dma1_frame_start <= 30'h0;
		dma2_frame_start <= 30'h0;
		dma1_frame_ptr <= 30'h0;
		dma2_frame_ptr <= 30'h0;
		dma1_frame_len <= 12'h0;
		dma2_frame_len <= 12'h0;
		dma1_frame_in <= 1'b0;
		dma2_frame_in <= 1'b0;
		dma1_rx_count <= 8'h0;
		dma2_rx_count <= 8'h0;
		phy1_rd_en <= 1'b0;
		phy2_rd_en <= 1'b0;
		sel_phy <= 1'b0;
		mst_wr_en <= 1'b0;
		rec_status <= REC_IDLE;
	end else begin
		phy1_rd_en <= 1'b0;
		phy2_rd_en <= 1'b0;
		mst_wr_en <= 1'b0;
		case ( rec_status )
			REC_IDLE: begin
				if ( dma1_frame_ptr == 30'h0 )
					dma1_frame_ptr <= dma1_addr_start;
				if ( dma2_frame_ptr == 30'h0 )
					dma2_frame_ptr <= dma2_addr_start;
				if ( dma1_frame_in  & ~phy1_empty ) begin
					sel_phy <= 1'b0;
//					phy1_rd_en <= 1'b1;
					remain_word <= (8'd64 >> 1);
					rec_status <= REC_HEAD10;
				end else if ( dma2_frame_in & ~phy2_empty ) begin
					sel_phy <= 1'b1;
//					phy2_rd_en <= 1'b1;
					remain_word <= (8'd64 >> 1);
					rec_status <= REC_HEAD10;
				end else begin
					if ( phy1_rx_count != dma1_rx_count ) begin
						sel_phy <= 1'b0;
						dma1_frame_len <= 12'h0;
						dma1_frame_start <= dma1_frame_ptr;
						dma1_frame_ptr   <= dma1_frame_ptr + 30'd2; 	// GCounter = Start + 0x8
						remain_word <= ((8'd64-8'd8) >> 1);
						rec_status <= REC_HEAD10;
					end else if ( phy2_rx_count != dma2_rx_count ) begin
						sel_phy <= 1'b1;
						dma2_frame_len <= 12'h0;
						dma2_frame_start <= dma2_frame_ptr;
						dma2_frame_ptr   <= dma2_frame_ptr + 30'd2; 	// Gcounter = Start + 0x8
						remain_word <= ((8'd64-8'd8) >> 1);
						rec_status <= REC_HEAD10;
					end
				end
			end
			REC_HEAD10: begin
				mst_din[17:0] <= {2'b10, 16'h90ff};	// Write 64 byte command
				mst_wr_en <= 1'b1;
				rec_status <= REC_HEAD11;
			end
			REC_HEAD11: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_ptr[31:16]};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_ptr[31:16]};
				end
				mst_wr_en <= 1'b1;
				rec_status <= REC_HEAD12;
			end
			REC_HEAD12: begin
				phy1_rd_en <= (~phy1_empty) & (~sel_phy);
				phy2_rd_en <= (~phy2_empty) & sel_phy;
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_ptr[15:2], 2'b00};
					if (dma1_frame_in) begin
						rec_status <= REC_DATA;
					end else begin
						rec_status <= REC_SKIP;
					end
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_ptr[15:2], 2'b00};
					if (dma2_frame_in) begin
						rec_status <= REC_DATA;
					end else begin
						rec_status <= REC_SKIP;
					end
				end
				mst_wr_en <= 1'b1;
			end
			REC_SKIP: begin
				phy1_rd_en <= (~phy1_empty) & (~sel_phy);
				phy2_rd_en <= (~phy2_empty) & sel_phy;
				if (phy1_rd_en && phy1_dout[17]) begin
					dma1_frame_in <= 1'b1;
					mst_din[17:0] <= {2'b00, phy1_dout[15:0]};
					mst_wr_en <= 1'b1;
					rec_status <= REC_DATA;
				end
				if (phy2_rd_en && phy2_dout[17]) begin
					dma2_frame_in <= 1'b1;
					mst_din[17:0] <= {2'b00, phy2_dout[15:0]};
					mst_wr_en <= 1'b1;
					rec_status <= REC_DATA;
				end
			end
			REC_DATA: begin
				remain_word <= remain_word - 8'd1;
				if (~sel_phy) begin
					if (remain_word[0])
						dma1_frame_ptr <= dma1_frame_ptr + 30'h1;
					if (phy1_rd_en) begin
						mst_din[15:0] <= phy1_dout[15:0];
						dma1_frame_len <= dma1_frame_len + {10'h0, phy1_dout[16], phy1_dout[17] & (~phy1_dout[16])} ;
						if (phy1_dout[17:16] != 2'b11) begin
							dma1_frame_in <= 1'b0;
							dma1_rx_count <= dma1_rx_count + 8'h1;
						end
					end else begin
						mst_din[15:0] <= 16'h00;
					end
					if (dma1_frame_in)
						phy1_rd_en <= ~phy1_empty & (remain_word != 8'h00);
				end else begin
					if (remain_word[0])
						dma2_frame_ptr <= dma2_frame_ptr + 30'h1;
					mst_din[15:0] <= phy2_dout[15:0];
					if (phy2_rd_en) begin
						mst_din[15:0] <= phy2_dout[15:0];
						dma2_frame_len <= dma2_frame_len + {10'h0, phy2_dout[16], phy2_dout[17] & (~phy2_dout[16])} ;
						if (phy2_dout[17:16] != 2'b11) begin
							dma2_frame_in <= 1'b0;
							dma2_rx_count <= dma2_rx_count + 8'h1;
						end
					end else begin
						mst_din[15:0] <= 16'h00;
					end
					if (dma2_frame_in)
						phy2_rd_en <= ~phy2_empty & (remain_word != 8'h00);
				end
				mst_wr_en <= 1'b1;
				mst_din[17] <= 1'b0;
				if (remain_word == 8'h00) begin
					mst_din[16] <= 1'b1;
					rec_status <= ((dma1_frame_in & (~sel_phy)) || (dma2_frame_in & sel_phy)) ? REC_IDLE : REC_HEAD20;
				end else
					mst_din[16] <= 1'b0;
			end
			REC_HEAD20: begin
				if ( dma1_frame_ptr > ( dma1_addr_start + dma_length + 30'h10)  )
					dma1_frame_ptr <= dma1_frame_start;
				mst_din[17:0] <= {2'b10, 16'h82ff};	// Write 8 byte command
				mst_wr_en <= 1'b1;
				rec_status <= REC_HEAD21;
			end
			REC_HEAD21: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_start[31:16]};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_start[31:16]};
				end
				mst_wr_en <= 1'b1;
				rec_status <= REC_HEAD22;
			end
			REC_HEAD22: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_start[15:2], 2'b00};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_start[15:2], 2'b00};
				end
				mst_wr_en <= 1'b1;
				rec_status <= REC_LENGTH;
			end
			REC_LENGTH: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, 16'h00};
				end else begin
					mst_din[17:0] <= {2'b00, 16'h00};
				end
				rec_status <= REC_TUPLE;
			end
			REC_TUPLE: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {6'b00_0000, dma1_frame_len[11:0]};
				end else begin
					mst_din[17:0] <= {6'b00_0000, dma2_frame_len[11:0]};
				end
				mst_wr_en <= 1'b1;
				rec_status <= REC_FIN;
			end
			REC_FIN: begin
				rec_status <= REC_IDLE;
			end
		endcase
	end
end

//assign led[7:0] = ~eth_dest[7:0];

assign	dma1_addr_cur = dma1_frame_ptr;
assign	dma2_addr_cur = dma2_frame_ptr;

endmodule
`default_nettype wire
