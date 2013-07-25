`default_nettype none
module receiver (
	// System
	input sys_clk,
	input sys_rst,
	output reg sys_intr,
	// Phy FIFO
	input [17:0] phy_dout,
	input phy_empty,
	output reg phy_rd_en,
	input [7:0] phy_rx_count,
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
	output [31:2] dma_addr_cur,
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

reg [31:2] dma_frame_start;	// current frame start addr
reg [31:2] dma_frame_ptr;	// current frame ptr
reg [11:0] dma_frame_len;	// current frame length (0-4095)
reg dma_frame_in;		// in frame ?
reg [7:0] dma_rx_count;	// frame received count
reg dma_enable;
	
reg [7:0] remain_word;
always @(posedge sys_clk) begin
	if (sys_rst) begin
		sys_intr <= 1'b0;
		dma_frame_start <= 30'h0;
		dma_frame_ptr <= 30'h0;
		dma_frame_len <= 12'h0;
		dma_frame_in <= 1'b0;
		dma_rx_count <= 8'h0;
		dma_enable <= 1'b0;
		phy_rd_en <= 1'b0;
		mst_wr_en <= 1'b0;
		rec_status <= REC_IDLE;
	end else begin
		sys_intr <= 1'b0;
		phy_rd_en <= 1'b0;
		mst_wr_en <= 1'b0;
		case ( rec_status )
			REC_IDLE: begin
				if ( dma_frame_ptr < dma_addr_start || ( dma_addr_start + dma_length ) < dma_frame_ptr )
					dma_frame_ptr <= dma_addr_start;
				if ( dma_frame_in  & ~phy_empty ) begin
					remain_word <= (8'd64 >> 1);
					rec_status <= REC_HEAD10;
				end else begin
					if ( phy_rx_count != dma_rx_count ) begin
						dma_frame_len <= 12'h0;
						dma_frame_start <= dma_frame_ptr;
`ifdef SIMULATION
						dma_frame_ptr   <= dma_frame_ptr + 30'd2; 	// GCounter = Start + 0x8
						dma_enable <= 1'b1;
`else
						if (dma_status[0])
							dma_frame_ptr   <= dma_frame_ptr + 30'd2; 	// GCounter = Start + 0x8
						dma_enable <= dma_status[0];
`endif
						remain_word <= ((8'd64-8'd8) >> 1);
						rec_status <= REC_HEAD10;
					end
				end
			end
			REC_HEAD10: begin
				mst_din[17:0] <= {2'b10, 16'h90ff};	// Write 64 byte command
				mst_wr_en <= dma_enable;
				rec_status <= REC_HEAD11;
			end
			REC_HEAD11: begin
				mst_din[17:0] <= {2'b00, dma_frame_ptr[31:16]};
				mst_wr_en <= dma_enable;
				rec_status <= REC_HEAD12;
			end
			REC_HEAD12: begin
				phy_rd_en <= ~phy_empty;
				mst_din[17:0] <= {2'b00, dma_frame_ptr[15:2], 2'b00};
				if (dma_frame_in) begin
					rec_status <= REC_DATA;
				end else begin
					rec_status <= REC_SKIP;
				end
				mst_wr_en <= dma_enable;
			end
			REC_SKIP: begin
				phy_rd_en <= ~phy_empty;
				if (phy_rd_en && phy_dout[17]) begin
					dma_frame_in <= 1'b1;
					mst_din[17:0] <= {2'b00, phy_dout[15:0]};
					mst_wr_en <= dma_enable;
					rec_status <= REC_DATA;
				end
			end
			REC_DATA: begin
				remain_word <= remain_word - 8'd1;
				if (remain_word[0] & dma_enable)
					dma_frame_ptr <= dma_frame_ptr + 30'h1;
				mst_din[15:0] <= {phy_dout[15:8], phy_dout[7:0]};
				if (phy_rd_en) begin
					dma_frame_len <= dma_frame_len + {10'h0, phy_dout[16], phy_dout[17] & (~phy_dout[16])} ;
					if (phy_dout[17:16] != 2'b11) begin
						dma_frame_in <= 1'b0;
						if (dma_frame_in) begin
							dma_rx_count <= dma_rx_count + 8'h1;
							sys_intr <= dma_status[0];
						end
					end
				end
				if (dma_frame_in)
					phy_rd_en <= ~phy_empty & (remain_word[7:1] != 7'h0);
				mst_wr_en <= dma_enable;
				mst_din[17] <= 1'b0;
				if (remain_word == 8'h00) begin
					mst_din[16] <= 1'b1;
					rec_status <= dma_frame_in ? REC_IDLE : REC_HEAD20;
				end else
					mst_din[16] <= 1'b0;
			end
			REC_HEAD20: begin
				if ( dma_frame_ptr > ( dma_addr_start + dma_length + 30'h10)  && dma_enable )
					dma_frame_ptr <= dma_frame_start;
				mst_din[17:0] <= {2'b10, 16'h82ff};	// Write 8 byte command
				mst_wr_en <= dma_enable;
				rec_status <= REC_HEAD21;
			end
			REC_HEAD21: begin
				mst_din[17:0] <= {2'b00, dma_frame_start[31:16]};
				mst_wr_en <= dma_enable;
				rec_status <= REC_HEAD22;
			end
			REC_HEAD22: begin
				mst_din[17:0] <= {2'b00, dma_frame_start[15:2], 2'b00};
				dma_frame_len <=  dma_frame_len - 12'd10;	// drop Global counter + α? length
				mst_wr_en <= dma_enable;
				rec_status <= REC_LENGTHL;
			end
			REC_LENGTHL: begin
				mst_din[17:0] <= {2'b00, dma_frame_len[7:0], 4'b0000, dma_frame_len[11:8]};
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
				mst_din[17:0] <= {2'b00, 16'h55_5d};
				mst_wr_en <= dma_enable;
				rec_status <= REC_FIN;
			end
			REC_FIN: begin
				rec_status <= REC_IDLE;
			end
		endcase
	end
end

//assign led[7:0] = ~eth_dest[7:0];

assign	dma_addr_cur = dma_frame_ptr;

endmodule
`default_nettype wire
