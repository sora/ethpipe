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
  , output reg  [15:0] slot_tx_eth_data
  , output reg  [ 1:0] slot_tx_eth_byte_en
  , output wire [13:0] slot_tx_eth_addr
  , output reg         slot_tx_eth_wr_en
  , input  wire [15:0] slot_tx_eth_q

  , input  wire [13:0] mem_wr_ptr
  , output reg  [13:0] mem_rd_ptr
);

reg [13:0] rd_ptr;
reg [13:0] tx_counter;

/* TX ethernet FCS generater */
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
  , TX_HDR_LOAD = 3'b001
  , TX_SENDING  = 3'b010
  , TX_FCS_1    = 3'b011
  , TX_FCS_2    = 3'b100
  , TX_FCS_3    = 3'b101;
reg [ 2:0] tx_status;
reg [ 1:0] ifg_count;
reg [ 3:0] hdr_load_count;
reg [15:0] tx_frame_len;
reg [63:0] tx_timestamp;
reg [31:0] tx_hash;
reg [15:0] tx_data_tmp;

/* packet sender logic */
always @(posedge gmii_tx_clk) begin
	if (sys_rst) begin
		tx_status      <= 3'b0;
		ifg_count      <= 2'b0;
		hdr_load_count <= 4'b0;
		tx_counter     <= 14'd0;
		tx_frame_len   <= 16'b0;
		tx_timestamp   <= 64'b0;
		tx_hash        <= 32'b0;
		tx_data_tmp    <= 16'b0;
		rd_ptr         <= 14'b0;
		mem_rd_ptr     <= 14'b0;
		crc_rd         <= 1'b0;
	end else begin

		gmii_tx_en <= 1'b0;

		/* interframe gap counter */
		if (tx_status == TX_IDLE) begin
			if (ifg_count != 2'd2)
				ifg_count <= ifg_count + 2'd1;
		end else begin
			ifg_count <= 4'd0;
		end

		/* ethpipe header loading counter */
		if (tx_status == TX_HDR_LOAD) begin
			if (hdr_load_count != 4'd8)
				hdr_load_count <= hdr_load_count + 4'd1;
		end else begin
			hdr_load_count <= 4'd0;
		end

		/* transmit counter */
		if (tx_status == TX_SENDING) begin
			tx_counter <= tx_counter + 14'd1;
		end else begin
			tx_counter <= 14'd0;
		end

		/* transmit main */
		case (tx_status)
			TX_IDLE: begin

				crc_rd <= 1'b0;

				if (ifg_count == 2'd2 && mem_rd_ptr != mem_wr_ptr) begin
					tx_status <= TX_HDR_LOAD;
					rd_ptr    <= mem_rd_ptr;
				end
			end
			TX_HDR_LOAD: begin

				if (hdr_load_count != 4'd7 && hdr_load_count != 4'd8 && rd_ptr != mem_wr_ptr)
					rd_ptr <= rd_ptr + 14'h1;
				
				case (hdr_load_count)
					4'd0: begin
					end
					4'd1: tx_frame_len        <= slot_tx_eth_q;
					4'd2: tx_timestamp[63:48] <= slot_tx_eth_q;
					4'd3: tx_timestamp[47:32] <= slot_tx_eth_q;
					4'd4: tx_timestamp[31:16] <= slot_tx_eth_q;
					4'd5: tx_timestamp[15: 0] <= slot_tx_eth_q;
					4'd6: tx_hash[31:16]      <= slot_tx_eth_q;
					4'd7: tx_hash[15: 0]      <= slot_tx_eth_q;
					4'd8: tx_status           <= TX_SENDING;
					default: begin
						tx_status <= TX_IDLE;
					end
				endcase
			end
			TX_SENDING: begin

				// gmii_tx_en
				gmii_tx_en <= 1'b1;

				// gmii_txd
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
						if (tx_counter == tx_frame_len[13:0] + 14'd8) begin
							tx_status  <= TX_FCS_1;
							crc_rd     <= 1'b1;
							gmii_txd   <= crc_out[31:24];   // ethernet FCS 0
						end else begin
							// send frame data
							case (tx_counter[0])
								1'b0: begin
									gmii_txd    <= slot_tx_eth_q[15:8];
									tx_data_tmp <= slot_tx_eth_q;
									if (rd_ptr != mem_wr_ptr)
										rd_ptr <= rd_ptr + 14'h1;
								end
								1'b1: begin
									gmii_txd <= tx_data_tmp[7:0];
								end
							endcase
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
				crc_rd     <= 1'b0;
				mem_rd_ptr <= rd_ptr;                 // update mem_rd_ptr
			end
			default: begin
				tx_status <= TX_IDLE;
			end
		endcase
	end
end
assign slot_tx_eth_addr = rd_ptr;

endmodule

`default_nettype wire

