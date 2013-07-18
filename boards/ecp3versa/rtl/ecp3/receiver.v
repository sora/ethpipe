`default_nettype none
module receiver (
	// System
	input sys_clk,
	input sys_rst,
	output reg sys_intr,
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
	REC_LENGTHL  = 4'h9,
	REC_LENGTHH  = 4'ha,
	REC_TUPLEL   = 4'hb,
	REC_TUPLEH   = 4'hc,
	REC_FIN      = 4'hf;
reg [3:0] rec_status = REC_IDLE;

reg [31:2] dma1_frame_start, dma2_frame_start;	// current frame start addr
reg [31:2] dma1_frame_ptr, dma2_frame_ptr;	// current frame ptr
reg [11:0] dma1_frame_len, dma2_frame_len;	// current frame length (0-4095)
reg dma1_frame_in, dma2_frame_in;		// in frame ?
reg [7:0] dma1_rx_count, dma2_rx_count;		// frame received count
reg sel_phy;					// selected phy number (0-1)
reg dma1_enable, dma2_enable;
	
reg [7:0] remain_word;
always @(posedge sys_clk) begin
	if (sys_rst) begin
		sys_intr <= 1'b0;
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
		dma1_enable <= 1'b0;
		dma2_enable <= 1'b0;
		phy1_rd_en <= 1'b0;
		phy2_rd_en <= 1'b0;
		sel_phy <= 1'b0;
		mst_wr_en <= 1'b0;
		rec_status <= REC_IDLE;
	end else begin
		sys_intr <= 1'b0;
		phy1_rd_en <= 1'b0;
		phy2_rd_en <= 1'b0;
		mst_wr_en <= 1'b0;
		case ( rec_status )
			REC_IDLE: begin
				if ( dma1_frame_ptr < dma1_addr_start || ( dma1_addr_start + dma_length ) < dma1_frame_ptr )
					dma1_frame_ptr <= dma1_addr_start;
				if ( dma2_frame_ptr < dma2_addr_start || ( dma2_addr_start + dma_length ) < dma2_frame_ptr )
					dma2_frame_ptr <= dma2_addr_start;
				if ( dma1_frame_in  & ~phy1_empty ) begin
					sel_phy <= 1'b0;
					remain_word <= (8'd64 >> 1);
					rec_status <= REC_HEAD10;
				end else if ( dma2_frame_in & ~phy2_empty ) begin
					sel_phy <= 1'b1;
					remain_word <= (8'd64 >> 1);
					rec_status <= REC_HEAD10;
				end else begin
					if ( phy1_rx_count != dma1_rx_count ) begin
						sel_phy <= 1'b0;
						dma1_frame_len <= 12'h0;
						dma1_frame_start <= dma1_frame_ptr;
`ifdef SIMULATION
						dma1_frame_ptr   <= dma1_frame_ptr + 30'd2; 	// GCounter = Start + 0x8
						dma1_enable <= 1'b1;
`else
						if (dma_status[0])
							dma1_frame_ptr   <= dma1_frame_ptr + 30'd2; 	// GCounter = Start + 0x8
						dma1_enable <= dma_status[0];
`endif
						remain_word <= ((8'd64-8'd8) >> 1);
						rec_status <= REC_HEAD10;
					end else if ( phy2_rx_count != dma2_rx_count ) begin
						sel_phy <= 1'b1;
						dma2_frame_len <= 12'h0;
						dma2_frame_start <= dma2_frame_ptr;
`ifdef SIMULATION
						dma2_frame_ptr   <= dma2_frame_ptr + 30'd2; 	// Gcounter = Start + 0x8
						dma2_enable <= 1'b1;
`else
						if (dma_status[1])
							dma2_frame_ptr   <= dma2_frame_ptr + 30'd2; 	// GCounter = Start + 0x8
						dma2_enable <= dma_status[1];
`endif
						remain_word <= ((8'd64-8'd8) >> 1);
						rec_status <= REC_HEAD10;
					end
				end
			end
			REC_HEAD10: begin
				mst_din[17:0] <= {2'b10, 16'h90ff};	// Write 64 byte command
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
				rec_status <= REC_HEAD11;
			end
			REC_HEAD11: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_ptr[31:16]};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_ptr[31:16]};
				end
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
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
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
			end
			REC_SKIP: begin
				phy1_rd_en <= (~phy1_empty) & (~sel_phy);
				phy2_rd_en <= (~phy2_empty) & sel_phy;
				if (phy1_rd_en && phy1_dout[17]) begin
					dma1_frame_in <= 1'b1;
					mst_din[17:0] <= {2'b00, phy1_dout[15:0]};
					mst_wr_en <= dma1_enable;
					rec_status <= REC_DATA;
				end
				if (phy2_rd_en && phy2_dout[17]) begin
					dma2_frame_in <= 1'b1;
					mst_din[17:0] <= {2'b00, phy2_dout[15:0]};
					mst_wr_en <= dma2_enable;
					rec_status <= REC_DATA;
				end
			end
			REC_DATA: begin
				remain_word <= remain_word - 8'd1;
				if (~sel_phy) begin
					if (remain_word[0] & dma1_enable)
						dma1_frame_ptr <= dma1_frame_ptr + 30'h1;
					mst_din[15:0] <= {phy1_dout[15:8], phy1_dout[7:0]};
					if (phy1_rd_en) begin
						dma1_frame_len <= dma1_frame_len + {10'h0, phy1_dout[16], phy1_dout[17] & (~phy1_dout[16])} ;
						if (phy1_dout[17:16] != 2'b11) begin
							dma1_frame_in <= 1'b0;
							if (dma1_frame_in) begin
								dma1_rx_count <= dma1_rx_count + 8'h1;
								sys_intr <= dma_status[0];
							end
						end
					end
					if (dma1_frame_in)
						phy1_rd_en <= ~phy1_empty & (remain_word[7:1] != 7'h0);
				end else begin
					if (remain_word[0] & dma2_enable)
						dma2_frame_ptr <= dma2_frame_ptr + 30'h1;
					mst_din[15:0] <= {phy2_dout[15:8], phy2_dout[7:0]};
					if (phy2_rd_en) begin
						dma2_frame_len <= dma2_frame_len + {10'h0, phy2_dout[16], phy2_dout[17] & (~phy2_dout[16])} ;
						if (phy2_dout[17:16] != 2'b11) begin
							dma2_frame_in <= 1'b0;
							if (dma2_frame_in) begin
								dma2_rx_count <= dma2_rx_count + 8'h1;
								sys_intr <= dma_status[1];
							end
						end
					end
					if (dma2_frame_in)
						phy2_rd_en <= ~phy2_empty & (remain_word[7:1] != 7'h0);
				end
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
				mst_din[17] <= 1'b0;
				if (remain_word == 8'h00) begin
					mst_din[16] <= 1'b1;
					rec_status <= ((dma1_frame_in & (~sel_phy)) || (dma2_frame_in & sel_phy)) ? REC_IDLE : REC_HEAD20;
				end else
					mst_din[16] <= 1'b0;
			end
			REC_HEAD20: begin
				if ( dma1_frame_ptr > ( dma1_addr_start + dma_length + 30'h10)  && dma1_enable )
					dma1_frame_ptr <= dma1_frame_start;
				if ( dma2_frame_ptr > ( dma2_addr_start + dma_length + 30'h10)  && dma2_enable )
					dma2_frame_ptr <= dma2_frame_start;
				mst_din[17:0] <= {2'b10, 16'h82ff};	// Write 8 byte command
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
				rec_status <= REC_HEAD21;
			end
			REC_HEAD21: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_start[31:16]};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_start[31:16]};
				end
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
				rec_status <= REC_HEAD22;
			end
			REC_HEAD22: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_start[15:2], 2'b00};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_start[15:2], 2'b00};
				end
				dma1_frame_len <=  dma1_frame_len - 12'd10;	// drop Global counter + α? length
				dma2_frame_len <=  dma2_frame_len - 12'd10;
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
				rec_status <= REC_LENGTHL;
			end
			REC_LENGTHL: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_len[7:0], 4'b0000, dma1_frame_len[11:8]};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_len[7:0], 4'b0000, dma2_frame_len[11:8]};
				end
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
				rec_status <= REC_LENGTHH;
			end
			REC_LENGTHH: begin
				mst_din[17:0] <= {2'b00, 16'h0000};
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
				rec_status <= REC_TUPLEL;
			end
			REC_TUPLEL: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, 16'h55_55};
				end else begin
					mst_din[17:0] <= {2'b00, 16'h55_55};
				end
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
				rec_status <= REC_TUPLEH;
			end
			REC_TUPLEH: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, 16'h55_5d};
				end else begin
					mst_din[17:0] <= {2'b00, 16'h55_5d};
				end
				mst_wr_en <= sel_phy ? dma2_enable : dma1_enable;
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
