`default_nettype none
module receiver (
	// System
	input sys_clk,
	input sys_rst,
	input [63:0] global_counter,
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

parameter [2:0]
	REC_IDLE     = 3'h0,
	REC_START    = 3'h1,
	REC_HEAD0    = 3'h2,
	REC_HEAD1    = 3'h3,
	REC_HEAD2    = 3'h4,
	REC_DATA     = 3'h5,
	REC_FIN      = 3'h7;
reg [2:0] rec_status = REC_IDLE;

reg [31:2] dma1_frame_start, dma2_frame_start;	// current frame start addr
reg [31:2] dma1_frame_ptr, dma2_frame_ptr;	// current frame ptr
reg [11:0] dma1_frame_len, dma2_frame_len;	// current frame length (0-4095)
reg dma1_frame_in, dma2_frame_in;		// in frame ?
reg [7:0] dma1_rx_count, dma2_rx_count;		// frame received count
reg sel_phy;					// selected phy number (0-1)
	
reg [11:0] counter;
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
		counter <= 12'h0;
		phy1_rd_en <= 1'b0;
		phy2_rd_en <= 1'b0;
		sel_phy <= 1'b0;
		mst_wr_en <= 1'b0;
		rec_status <= REC_IDLE;
	end else begin
		mst_wr_en <= 1'b0;
		case ( rec_status )
			REC_IDLE: begin
				if ( dma1_frame_ptr == 30'h0 )
					dma1_frame_ptr <= dma1_addr_start;
				if ( dma2_frame_ptr == 30'h0 )
					dma2_frame_ptr <= dma2_addr_start;
				if ( dma1_frame_in  & ~phy1_empty ) begin
					sel_phy <= 1'b0;
					phy1_rd_en <= 1'b1;
					rec_status <= REC_DATA;
				end else if ( dma2_frame_in & ~phy2_empty ) begin
					sel_phy <= 1'b1;
					phy2_rd_en <= 1'b1;
					rec_status <= REC_DATA;
				end else begin
					if ( phy1_rx_count != dma1_rx_count ) begin
						sel_phy <= 1'b0;
						dma1_frame_start <= dma1_frame_ptr;
						dma1_frame_ptr   <= dma1_frame_ptr + 30'd4; 	// Payload = Start + 0x10
						rec_status <= REC_HEAD0;
					end if ( phy2_rx_count != dma2_rx_count ) begin
						sel_phy <= 1'b1;
						dma2_frame_start <= dma2_frame_ptr;
						dma2_frame_ptr   <= dma2_frame_ptr + 30'd4; 	// Payload = Start + 0x10
						rec_status <= REC_HEAD0;
					end
				end
			end
			REC_HEAD0: begin
				mst_din[17:0] <= {2'b10, 16'h90ff};	// Write 64 byte command
				mst_wr_en <= 1'b1;
				rec_status <= REC_HEAD1;
			end
			REC_HEAD1: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_ptr[31:16]};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_ptr[31:16]};
				end
				mst_wr_en <= 1'b1;
				rec_status <= REC_HEAD2;
			end
			REC_HEAD2: begin
				if (~sel_phy) begin
					mst_din[17:0] <= {2'b00, dma1_frame_ptr[15:2], 2'b00};
				end else begin
					mst_din[17:0] <= {2'b00, dma2_frame_ptr[15:2], 2'b00};
				end
				mst_wr_en <= 1'b1;
				rec_status <= REC_DATA;
			end
			REC_DATA: begin
			end
		endcase
	end
end

//assign led[7:0] = ~eth_dest[7:0];

assign	dma1_addr_cur = dma1_frame_ptr;
assign	dma2_addr_cur = dma2_frame_ptr;

endmodule
`default_nettype wire
