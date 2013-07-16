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
	output reg [31:2] dma1_addr_cur,
	input [31:2] dma2_addr_start,
	output reg [31:2] dma2_addr_cur,
	// LED and Switches
	input [7:0] dipsw,
	output [7:0] led,
	output [13:0] segled,
	input btn
);

parameter [2:0]
	REC_IDLE     = 3'h0,
	REC_DATA     = 3'h1,
	REC_FIN      = 3'h3;
reg [2:0] rec_status = REC_IDLE;
	
reg [11:0] counter;
reg [7:0] remain_word;
always @(posedge sys_clk) begin
	if (sys_rst) begin
		counter <= 12'h0;
		phy1_rd_en <= 1'b0;
		phy2_rd_en <= 1'b0;
		rec_status <= REC_IDLE;
		mst_wr_en <= 1'b0;
		dma1_addr_cur <= 30'h0;
	end else begin
              	phy1_rd_en  <= ~phy1_empty;
		mst_wr_en <= 1'b0;
`ifdef SIMULATION
		if ( phy1_rd_en == 1'b1 ) begin
`else
		if ( phy1_rd_en == 1'b1 && dma_status[0] == 1'b1 ) begin
`endif
			if (phy1_dout[8] == 1'b1) begin
				counter <= counter + 12'h1;
				case ( rec_status )
					REC_IDLE:
						case (counter)
							12'h00: begin
								if ( dma1_addr_cur == 30'h0 )
									dma1_addr_cur <= dma1_addr_start;
								mst_din[17:0] <= {2'b10, 16'h90ff};
								mst_wr_en <= 1'b1;
							end
							12'h01: begin
								mst_din[17:0] <= {2'b00, dma1_addr_cur[31:16]};
								mst_wr_en <= 1'b1;
							end
							12'h02: begin
								mst_din[17:0] <= {2'b00, dma1_addr_cur[15:2], 2'b00};
								mst_wr_en <= 1'b1;
								remain_word <= 8'd32;
								rec_status <= REC_DATA;
							end
						endcase
					REC_DATA: begin
						remain_word <= remain_word - 8'd1;
						if ( remain_word[0] == 1'b0 ) begin
							mst_din[15:8] <= phy1_dout[7:0];
						end else begin
							mst_din[7:0] <= phy1_dout[7:0];
							dma1_addr_cur <= dma1_addr_cur + 30'd4;
							if ( dma1_addr_cur == dma_length )
								dma1_addr_cur <= dma1_addr_start;
							mst_wr_en <= 1'b1;
						end
						if ( remain_word == 8'h1 ) begin
							mst_din[17:16] <= 2'b01;
							counter <= 12'h0;
							rec_status <= REC_IDLE;
						end else begin
							mst_din[17:16] <= 2'b00;
						end
					end
				endcase
			end else begin
				counter <= 12'h0;
			end
		end
	end
end

//assign led[7:0] = ~eth_dest[7:0];

endmodule
`default_nettype wire
