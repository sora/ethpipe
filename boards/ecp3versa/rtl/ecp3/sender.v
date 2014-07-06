`default_nettype none

module sender (
  // system reset
    input  wire        sys_rst

  // global counter
  , input  wire [63:0] global_counter

  // GMII interfaces
  , input  wire        gmii_tx_clk
  , output reg  [ 7:0] gmii_txd
  , output reg         gmii_tx_en

  // TX frame slot
  , output      [15:0] slot_tx_eth_data
  , output      [ 1:0] slot_tx_eth_byte_en
  , output wire [15:0] slot_tx_eth_addr
  , output reg         slot_tx_eth_en
  , output             slot_tx_eth_wr_en
  , input  wire [15:0] slot_tx_eth_q

  , input  wire [15:0] mem_wr_ptr
  , output reg  [15:0] mem_rd_ptr

  , input  wire [47:0] local_time1
  , input  wire [47:0] local_time2
  , input  wire [47:0] local_time3
  , input  wire [47:0] local_time4
  , input  wire [47:0] local_time5
  , input  wire [47:0] local_time6
  , input  wire [47:0] local_time7

  , output reg  [ 6:0] local_time_req

  , output wire [ 7:0] led
  , input  wire [ 7:0] dipsw

  // interrupts
  // 50% space is free
  , output reg txfifo_free
);

function [47:0] select_local_time;
	input [ 2:0] sel;
	input [47:0] time1;
	input [47:0] time2;
	input [47:0] time3;
	input [47:0] time4;
	input [47:0] time5;
	input [47:0] time6;
	input [47:0] time7;
	case (sel)
		3'd0: select_local_time = 48'h0;
		3'd1: select_local_time = time1;
		3'd2: select_local_time = time2;
		3'd3: select_local_time = time3;
		3'd4: select_local_time = time4;
		3'd5: select_local_time = time5;
		3'd6: select_local_time = time6;
		3'd7: select_local_time = time7;
	endcase
endfunction

/* TX ethernet FCS generater */
reg [13:0] tx_counter;

reg  crc_rd;
wire crc_init = (tx_counter == 14'h08);
wire [31:0] crc_out;
wire crc_data_en = ~crc_rd;
crc_gen tx_fcs_gen (
    .Reset(sys_rst)
  , .Clk(gmii_tx_clk)
  , .Init(crc_init)
  , .Frame_data(gmii_txd)
  , .Data_en(crc_data_en)
  , .CRC_rd(crc_rd)
  , .CRC_end()
  , .CRC_out(crc_out)
);

/* sender logic */
parameter [2:0]            // TX status
    TX_IDLE     = 3'b000
  , TX_MEMWAIT  = 3'b001
  , TX_HDR_LOAD = 3'b010
  , TX_WAITING  = 3'b011
  , TX_SENDING  = 3'b100
  , TX_FCS_1    = 3'b101
  , TX_FCS_2    = 3'b110
  , TX_FCS_3    = 3'b111;
reg [ 2:0] tx_status;
//reg [ 3:0] ifg_count;
reg [ 3:0] IFG_count;
reg [ 3:0] hdr_load_count;
reg [15:0] tx_frame_len;
reg [63:0] tx_timestamp;
reg [31:0] tx_hash;
reg [15:0] tx_data_tmp;
reg [15:0] rd_ptr;

/* packet sender logic */
always @(posedge gmii_tx_clk) begin
	if (sys_rst) begin
		gmii_txd       <= 8'h0;
		tx_status      <= 3'b0;
		IFG_count      <= 4'd0;
		hdr_load_count <= 4'b0;
		tx_counter     <= 14'd0;
		tx_frame_len   <= 16'b0;
		tx_timestamp   <= 64'b0;
		tx_hash        <= 32'b0;
		tx_data_tmp    <= 16'b0;
		rd_ptr         <= 16'b0;
		mem_rd_ptr     <= 16'b0;
		crc_rd         <= 1'b0;
		slot_tx_eth_en <= 1'b0;
	end else begin

		local_time_req <= 7'b0;

		/* count Inter-frame Gap (12 clock) */
		if (IFG_count != 4'd11 && tx_status != TX_FCS_3)
			IFG_count <= IFG_count + 4'd1;

		/* transmit main */
		case (tx_status)
			TX_IDLE: begin
				gmii_tx_en     <= 1'b0;
				crc_rd         <= 1'b0;
				hdr_load_count <= 4'd0;
				tx_counter     <= 14'd0;
				if (mem_rd_ptr != mem_wr_ptr) begin
					slot_tx_eth_en <= 1'b1;
					tx_status      <= TX_MEMWAIT;
					rd_ptr         <= mem_rd_ptr;
				end else
					slot_tx_eth_en <= 1'b0;
			end
			TX_MEMWAIT: begin
					rd_ptr         <= rd_ptr + 16'h1;
					tx_status      <= TX_HDR_LOAD;
			end
			TX_HDR_LOAD: begin
				if (hdr_load_count != 4'd6) begin
					hdr_load_count <= hdr_load_count + 4'd1;
					if (rd_ptr != mem_wr_ptr)
						rd_ptr <= rd_ptr + 16'h1;
				end


				case (hdr_load_count)
					4'd0: tx_frame_len[15: 0] <= slot_tx_eth_q;
					4'd1: tx_timestamp[63:48] <= slot_tx_eth_q;
					4'd2: tx_timestamp[47:32] <= slot_tx_eth_q;
					4'd3: tx_timestamp[31:16] <= slot_tx_eth_q;
					4'd4: tx_timestamp[15: 0] <= slot_tx_eth_q;
					4'd5: tx_hash[31:16]      <= slot_tx_eth_q;
					4'd6: begin
						tx_hash[15:0] <= slot_tx_eth_q;
						tx_status     <= TX_WAITING;
					end
				endcase
			end
			TX_WAITING: begin
				if (IFG_count == 4'd11) begin
					// reset command
					if (tx_timestamp[63]) begin
						tx_status <= TX_SENDING;
						case (tx_timestamp[62:60])
							3'd0: begin  // reset global counter :todo
							end
							3'd1: local_time_req[0] <= 1'b1;
							3'd2: local_time_req[1] <= 1'b1;
							3'd3: local_time_req[2] <= 1'b1;
							3'd4: local_time_req[3] <= 1'b1;
							3'd5: local_time_req[4] <= 1'b1;
							3'd6: local_time_req[5] <= 1'b1;
							3'd7: local_time_req[6] <= 1'b1;
						endcase
					end else begin
						// global time
						if (tx_timestamp[62:60] == 4'h0) begin
							if (global_counter[47:0] >= tx_timestamp[47:0]) begin
								tx_status <= TX_SENDING;
							end
						// local time
						end else begin
							if (global_counter[47:0] >= tx_timestamp[47:0] + select_local_time( tx_timestamp[62:60],
												local_time1, local_time2, local_time3, local_time4,
												local_time5, local_time6, local_time7 )) begin
								tx_status <= TX_SENDING;
							end
						end
					end
				end
			end
			TX_SENDING: begin
				/* transmit counter */
				tx_counter <= tx_counter + 14'd1;

				// gmii_tx_en
				gmii_tx_en     <= 1'b1;

				// gmii_tx_din
				case (tx_counter)
					14'd0: gmii_txd <= 8'h55;   // preamble
					14'd1: gmii_txd <= 8'h55;
					14'd2: gmii_txd <= 8'h55;
					14'd3: gmii_txd <= 8'h55;
					14'd4: gmii_txd <= 8'h55;
					14'd5: gmii_txd <= 8'h55;
					14'd6: gmii_txd <= 8'h55;
					14'd7: gmii_txd <= 8'hd5;   // preamble+SFD
					default: begin
						if (tx_counter[13:0] == tx_frame_len[13:0] + 14'd8) begin
							tx_status <= TX_FCS_1;
							slot_tx_eth_en <= 1'b0;
							crc_rd    <= 1'b1;
							gmii_txd <= crc_out[31:24];   // ethernet FCS 0
						end else begin
							// send frame data
							if (tx_counter[0]==1'b0) begin
									gmii_txd    <= slot_tx_eth_q[15:8];
									tx_data_tmp <= slot_tx_eth_q;
									if (rd_ptr != mem_wr_ptr)
										rd_ptr <= rd_ptr + 16'h1;
							end else begin
									gmii_txd <= tx_data_tmp[7:0];
							end
						end
					end
				endcase
			end
			TX_FCS_1: begin                           // ethernet FCS 1
				tx_status  <= TX_FCS_2;
				gmii_tx_en <= 1'b1;
				gmii_txd   <= crc_out[23:16];
			end
			TX_FCS_2: begin                           // ethernet FCS 2
				tx_status  <= TX_FCS_3;
				gmii_tx_en <= 1'b1;
				gmii_txd   <= crc_out[15:8];
			end
			TX_FCS_3: begin                           // ethernet FCS 3
				tx_status  <= TX_IDLE;
				gmii_tx_en <= 1'b1;
				gmii_txd   <= crc_out[7:0];
				// reset IFG_count
				IFG_count  <= 4'd0;
				// update mem_rd_ptr
				mem_rd_ptr <= rd_ptr;
			end
		endcase
	end
end
assign slot_tx_eth_data = 16'hz;
assign slot_tx_eth_byte_en = 2'b00;
assign slot_tx_eth_wr_en = 1'b0;
assign slot_tx_eth_addr = rd_ptr;

// interrupts
wire [15:0] txfifo_free_space = mem_rd_ptr - mem_wr_ptr;
reg [1:0] txfifo_free_pre;
reg [7:0] intr_count;
always @(posedge gmii_tx_clk) begin
  if (sys_rst) begin
    txfifo_free_pre <= 2'b00;
    txfifo_free <= 1'b0;
    intr_count <= 8'b0;
  end else begin
    txfifo_free <= 1'b0;
    // when free space become 50%
    if (txfifo_free_pre == 2'b01 && txfifo_free_space[15:14] == 2'b10) begin
      txfifo_free <= 1'b1;
      intr_count <= intr_count + 8'h1;
    end
    txfifo_free_pre <= txfifo_free_space[15:14];
  end
end

led = ~{ intr_count[7:0] };
/*
always @* begin
  case (dipsw)
    // tx_timestamp
    8'h00: led = ~tx_timestamp[ 7: 0];
    8'h01: led = ~tx_timestamp[15: 8];
    8'h02: led = ~tx_timestamp[23:16];
    8'h03: led = ~tx_timestamp[31:24];
    8'h04: led = ~tx_timestamp[39:32];
    8'h05: led = ~tx_timestamp[47:40];
    8'h06: led = ~tx_timestamp[55:48];
    8'h07: led = ~tx_timestamp[63:56];
    // mem_wr_ptr
    8'h10: led = ~mem_wr_ptr[ 7: 0];
    8'h11: led = ~mem_wr_ptr[15: 8];
    // mem_rd_ptr
    8'h12: led = ~mem_rd_ptr[ 7: 0];
    8'h13: led = ~mem_rd_ptr[15: 8];
    // rd_ptr
    8'h14: led = ~rd_ptr[ 7: 0];
    8'h15: led = ~rd_ptr[15: 8];
    // tx_status and debug
    // 8'h20: led = ~{ debug5, debug4, debug3, debug2, debug1, tx_status[2:0] };
    // IFG_count
    8'h30: led = ~{ 4'b0, IFG_count[3:0] };
    // hdr_load_count
    8'h40: led = ~{ 4'b0, hdr_load_count[3:0] };
    // tx_counter
    8'h50: led = ~tx_counter[ 7: 0];
    8'h51: led = ~{ 2'b0, tx_counter[13: 8] };
    // tx_frame_len
    8'h60: led = ~tx_frame_len[ 7: 0];
    8'h61: led = ~tx_frame_len[15: 8];
    // tx_hash
    8'h70: led = ~tx_hash[ 7: 0];
    8'h71: led = ~tx_hash[15: 8];
    8'h72: led = ~tx_hash[23:16];
    8'h73: led = ~tx_hash[31:24];
    default: begin
      led = ~{ 8'b0 };
    end
  endcase
end
*/

endmodule

`default_nettype wire
