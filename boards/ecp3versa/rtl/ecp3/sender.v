`default_nettype none

module sender (
  // system reset
    input  wire        sys_rst

  // PCI clock (125 MHz)
  , input  wire        pci_clk

  // global counter
  , input  wire [63:0] global_counter

  // GMII interfaces
  , input  wire        gmii_tx_clk
  , output reg  [ 7:0] gmii_txd
  , output reg         gmii_tx_en

  // TX frame slot
  , output reg  [15:0] slot_tx_eth_data
  , output reg  [ 1:0] slot_tx_eth_byte_en
  , output reg  [13:0] slot_tx_eth_addr
  , output reg         slot_tx_eth_wr_en
  , input  wire [15:0] slot_tx_eth_q

  , input  wire [13:0] mem_wr_ptr
  , output reg  [13:0] mem_rd_ptr
);

reg [13:0] tx_counter;

/* TX ethernet FCS generater */
reg  crc_rd;
wire crc_init = (tx_counter == 14'h08);
wire [31:0] crc_out;
wire crc_data_en = ~crc_rd;
crc_gen tx_fcs_gen (
    .Reset(~sys_rst)
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
  , TX_SENDING  = 3'b001
  , TX_FCS_1    = 3'b010
  , TX_FCS_2    = 3'b011
  , TX_FCS_3    = 3'b100
  , TX_IFG      = 3'b101
  , TX_COMPLETE = 3'b110;
reg [ 2:0] tx_status;
reg [ 2:0] ifg_count;
reg [15:0] tx_magic;
reg [15:0] tx_frame_len;
reg [63:0] tx_timestamp;
reg [31:0] tx_hash;
reg [15:0] tx_data_tmp;

/* raw format */
parameter magic_offset      = 14'h0;
parameter frame_len_offset  = 14'h1;
parameter ts_1_offset       = 14'h2;
parameter ts_2_offset       = 14'h3;
parameter ts_3_offset       = 14'h4;
parameter ts_4_offset       = 14'h5;
parameter hash_1_offset     = 14'h6;
parameter hash_2_offset     = 14'h7;
parameter frame_data_offset = 14'h8;

/* packet sender logic */
always @(posedge gmii_tx_clk) begin
	if (sys_rst) begin
		tx_status           <= 3'b0;
		ifg_count           <= 3'b0;
		tx_counter          <= 14'd0;
		slot_tx_eth_addr    <= 14'b0;
		tx_magic            <= 16'b0;
		tx_frame_len        <= 16'b0;
		tx_timestamp        <= 64'b0;
		tx_hash             <= 32'b0;
		tx_data_tmp         <= 16'b0;
		mem_rd_ptr          <= 14'b0;
	end else begin
		gmii_tx_en <= 1'b0;
		case (tx_status)
			TX_IDLE: begin
				slot_tx_eth_addr <= mem_rd_ptr;
				tx_counter       <= 14'd0;
				ifg_count        <= 3'b0;
				if (mem_rd_ptr != mem_wr_ptr) begin
					tx_status        <= TX_SENDING;
					slot_tx_eth_addr <= mem_rd_ptr + frame_len_offset;
					tx_magic         <= slot_tx_eth_q;    // must check the magic code :todo
				end
			end
			TX_SENDING: begin

				// tx_counter
				tx_counter <= tx_counter + 14'd1;

				// gmii_tx_en
				gmii_tx_en <= 1'b1;

				// gmii_txd
				case (tx_counter)
					14'd0: begin
						gmii_txd         <= 8'h55;  // preamble
						slot_tx_eth_addr <= mem_rd_ptr + ts_1_offset;
					end
					14'd1: begin
						gmii_txd         <= 8'h55;
						slot_tx_eth_addr <= mem_rd_ptr + ts_2_offset;
						tx_frame_len     <= slot_tx_eth_q;
					end
					14'd2: begin
						gmii_txd            <= 8'h55;
						slot_tx_eth_addr    <= mem_rd_ptr + ts_3_offset;
						tx_timestamp[63:48] <= slot_tx_eth_q;
					end
					14'd3: begin
						gmii_txd            <= 8'h55;
						slot_tx_eth_addr    <= mem_rd_ptr + ts_4_offset;
						tx_timestamp[47:32] <= slot_tx_eth_q;
					end
					14'd4: begin
						gmii_txd            <= 8'h55;
						slot_tx_eth_addr    <= mem_rd_ptr + hash_1_offset;
						tx_timestamp[31:16] <= slot_tx_eth_q;
					end
					14'd5: begin
						gmii_txd            <= 8'h55;
						slot_tx_eth_addr    <= mem_rd_ptr + hash_2_offset;
						tx_timestamp[15:0]  <= slot_tx_eth_q;
					end
					14'd6: begin
						gmii_txd            <= 8'h55;
						slot_tx_eth_addr    <= mem_rd_ptr + frame_data_offset;
						tx_hash[31:16]      <= slot_tx_eth_q;
					end
					14'd7: begin
						gmii_txd            <= 8'hd5;    // preamble + SFD
						tx_hash[15:0]       <= slot_tx_eth_q;
					end
					default: begin
						if (tx_counter == tx_frame_len[13:0] + 14'd8) begin
							tx_status <= TX_FCS_1;
							crc_rd    <= 1'b1;
							gmii_txd  <= crc_out[31:24];
						end else begin
							case (tx_counter[0])
								1'b0: begin
									gmii_txd         <= slot_tx_eth_q[15:8];
									slot_tx_eth_addr <= slot_tx_eth_addr + 14'd1;
									tx_data_tmp      <= slot_tx_eth_q;
								end
								1'b1: begin
									gmii_txd <= tx_data_tmp[7:0];
								end
							endcase
						end
					end
				endcase
			end
			TX_FCS_1: begin
				tx_status  <= TX_FCS_2;
				gmii_tx_en <= 1'b1;
				gmii_txd   <= crc_out[23:16];
			end
			TX_FCS_2: begin
				tx_status  <= TX_FCS_3;
				gmii_tx_en <= 1'b1;
				gmii_txd   <= crc_out[15:8];
			end
			TX_FCS_3: begin
				tx_status  <= TX_IFG;
				gmii_tx_en <= 1'b1;
				gmii_txd   <= crc_out[7:0];
				crc_rd     <= 1'b0;
			end
			TX_IFG: begin
				ifg_count <= ifg_count + 3'd1;
				if (ifg_count == 3'd5) begin
					tx_status <= TX_COMPLETE;

					// '14'd8': etherpipe header size (magic + frame_len + ts + hash)
					mem_rd_ptr <= mem_rd_ptr + tx_frame_len[13:0] + 14'd8;
				end
			end
			TX_COMPLETE: begin
				tx_status        <= TX_IDLE;
				slot_tx_eth_addr <= mem_rd_ptr;
			end
			default:
				tx_status <= TX_IDLE;
		endcase
	end
end

endmodule

`default_nettype wire
