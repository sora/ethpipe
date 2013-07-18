`default_nettype none

//`include "../rtl/setup.v"

//`define DEBUG

module ethpipe_port (
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
  , input  wire [ 7:0] gmii_rxd
  , input  wire        gmii_rx_dv
  , input  wire        gmii_rx_clk

  // RX frame slot
  , output reg  [31:0] slot_rx_eth_data
  , output reg  [ 3:0] slot_rx_eth_byte_en
  , output reg  [10:0] slot_rx_eth_address
  , output reg         slot_rx_eth_wr_en
//  , input  wire [31:0] slot_rx_eth_q

  , input  wire        slot_rx_empty       // RX slot empty
  , output wire        slot_rx_complete    // Received a ethernet frame
);


//-------------------------------------
// Ether frame receiver
//-------------------------------------
parameter [1:0]    // RX status
    RX_IDLE = 2'b00
  , RX_LOAD = 2'b01
  , RX_DONE = 2'b10;
reg [ 1:0] rx_status;
reg [13:0] rx_counter;
reg [63:0] rx_timestamp;
reg        rx_active;
wire       rx_ready;
always @(posedge gmii_rx_clk) begin
    if (sys_rst) begin
        slot_rx_eth_wr_en   <= 1'b0;
        slot_rx_eth_address <= 11'h0;
        slot_rx_eth_data    <= 32'b0;
        rx_counter          <= 14'b0;
        rx_timestamp        <= 64'b0;
        rx_status           <= RX_IDLE;
        rx_active           <= 1'b0;
    end else begin
        if (rx_active == 1'b0) begin
            rx_counter <= 14'b0;

            if (rx_ready == 1'b1 && gmii_rx_dv == 1'b0) begin
                rx_active <= 1'b1;
            end
        end else begin
            rx_status <= RX_IDLE;

            rx_counter        <= 14'b0;
            slot_rx_eth_wr_en <= 1'b0;
            if (gmii_rx_dv) begin
                rx_counter <= rx_counter + 14'b1;
                rx_status  <= RX_LOAD;

                case (rx_counter)
                    // Ethernet preamble
                    14'd0: begin
                        // receive timestamp when first data is received
                        rx_timestamp <= global_counter;
                    end
                    14'd1: begin
                        slot_rx_eth_address <= 11'h1;
                        slot_rx_eth_wr_en   <= 1'b1;
                        slot_rx_eth_byte_en <= 4'b1111;
                        slot_rx_eth_data    <= rx_timestamp[31:0];
                    end
                    14'd2: begin
                        slot_rx_eth_address <= 11'h2;
                        slot_rx_eth_wr_en   <= 1'b1;
                        slot_rx_eth_byte_en <= 4'b1111;
                        slot_rx_eth_data    <= rx_timestamp[63:32];
                    end
                    14'd3: begin // reserved: five-tuple hash
                        slot_rx_eth_address <= 11'h3;
                        slot_rx_eth_wr_en   <= 1'b1;
                        slot_rx_eth_byte_en <= 4'b1111;
                        slot_rx_eth_data    <= 32'h0;
                    end
                    14'd4, // skip
                    14'd5,
                    14'd6,
                    14'd7: begin // Ethernet SFD
                        slot_rx_eth_address <= 11'h4;
                    end
                    // Ethernet frame
                    default: begin
                        slot_rx_eth_wr_en <= 1'b1;
                        case (rx_counter[1:0])
                            2'b00: begin
                                slot_rx_eth_byte_en <= 4'b0001;
                                slot_rx_eth_data    <= {24'h0, gmii_rxd};
                                slot_rx_eth_address <= slot_rx_eth_address + 11'h1;
                            end
                            2'b01: begin
                                slot_rx_eth_byte_en <= 4'b0010;
                                slot_rx_eth_data    <= {16'h0, gmii_rxd, 8'h0};
                            end
                            2'b10: begin
                                slot_rx_eth_byte_en <= 4'b0100;
                                slot_rx_eth_data    <= {8'h0, gmii_rxd, 16'h0};
                            end
                            2'b11: begin
                                slot_rx_eth_byte_en <= 4'b1000;
                                slot_rx_eth_data    <= {gmii_rxd, 24'h0};
                            end
                        endcase
                    end
                endcase
            end else begin
                // frame terminated
                if (rx_counter != 14'h0) begin
                    rx_status <= RX_DONE;
                    rx_active <= 1'b0;

                    // write frame length
                    slot_rx_eth_address <= 11'h4;
                    slot_rx_eth_wr_en   <= 1'b1;
                    slot_rx_eth_byte_en <= 4'b1111;
                    slot_rx_eth_data    <= { 18'h0, rx_counter - 14'd8 };
                end
            end
        end
    end
end
clk_sync pcie2gmii_sync (
    .clk1 (pci_clk)
  , .i    (slot_rx_empty)
  , .clk2 (gmii_rx_clk)
  , .o    (rx_ready)
);
clk_sync_ashot gmii2pcie_sync (
    .clk1 (gmii_rx_clk)
  , .i    (rx_status[1])
  , .clk2 (pci_clk)
  , .o    (slot_rx_complete)
);


//-------------------------------------
// Ether frame sender
//-------------------------------------
reg         crc_rd;
wire        crc_init = (tx_counter == 12'h08);
wire [31:0] crc_out;
wire        crc_data_en = ~crc_rd;
crc_gen tx_fcs_gen (        // TX ethernet FCS generater
    .Reset(~sys_rst)
  , .Clk(gmii_tx_clk)
  , .Init(crc_init)
  , .Frame_data(gmii_txd)
  , .Data_en(crc_data_en)
  , .CRC_rd(crc_rd)
  , .CRC_end()
  , .CRC_out(crc_out)
);

parameter [1:0]    // TX status
    TX_IDLE     = 2'b00
  , TX_SENDING  = 2'b01
  , TX_COMPLETE = 2'b10;

// sender logic
reg [11:0] tx_counter;
reg [ 1:0] tx_status;
wire       tx_ready;
wire       tx_ready_eth;
wire       tx_complete;

wire [31:0] slot_tx_eth_q;

reg [15:0] txd_mem_buf_init;
reg [31:0] txd_mem_buf;

reg [63:0] tx_timestamp;
//reg [31:0] tx_hash;
reg [15:0] tx_ethlen;
reg [10:0] slot_tx_eth_address;
reg [1:0]  tx_comp_counter;

always @(posedge gmii_tx_clk) begin
    if (sys_rst) begin
        tx_counter          <= 12'd0;
        slot_tx_eth_address <= 11'b0;
        txd_mem_buf         <= 32'b0;
        txd_mem_buf_init    <= 16'b0;
    end else begin
        gmii_tx_en <= 1'b0;
        case (tx_status)
            TX_IDLE: begin
                if (tx_ready_eth == 1'b1) begin
                    tx_counter          <= 12'd0;
                    tx_status           <= TX_SENDING;
                    slot_tx_eth_address <= 11'h0;
                end
            end
            TX_SENDING: begin

                // tx_counter
                tx_counter <= tx_counter + 12'd1;

                // gmii_tx_en
                gmii_tx_en <= 1'b1;

                // gmii_txd
                case (tx_counter)
                    12'd0:
                        gmii_txd <= 8'h55;                // preamble
                    12'd1: begin
                        gmii_txd <= 8'h55;

                        slot_tx_eth_address <= 11'h1;
                        tx_timestamp[31:0]  <= { slot_tx_eth_q[7:0], slot_tx_eth_q[15:8], slot_tx_eth_q[23:16], slot_tx_eth_q[31:24] };
                    end
                    12'd2:
                        gmii_txd <= 8'h55;
                    12'd3: begin
                        gmii_txd <= 8'h55;

                        slot_tx_eth_address <= 11'h3;
                        tx_timestamp[63:32] <= { slot_tx_eth_q[7:0], slot_tx_eth_q[15:8], slot_tx_eth_q[23:16], slot_tx_eth_q[31:24] };
                    end
                    12'd4:
                        gmii_txd <= 8'h55;
                    12'd5: begin
                        gmii_txd            <= 8'h55;

                        slot_tx_eth_address <= 11'h4;
                        tx_ethlen           <= { slot_tx_eth_q[23:16], slot_tx_eth_q[31:24] };
                        txd_mem_buf_init    <= slot_tx_eth_q[15:0];
                    end
                    12'd6:
                        gmii_txd <= 8'h55;
                    12'd7:
                        gmii_txd <= 8'hd5;                // preamble + SFD
                    12'd8: begin
                        gmii_txd <= txd_mem_buf_init[15:8];

                        slot_tx_eth_address <= 11'h5;
                    end
                    12'd9:
                        gmii_txd <= txd_mem_buf_init[7:0];
                    default: begin
                        if (tx_counter == tx_ethlen[10:0] + 11'd8) begin
                            tx_status <= TX_COMPLETE;
                            crc_rd    <= 1'b1;
                            gmii_txd  <= crc_out[31:24];
                        end else begin
                            case (tx_counter[1:0])
                                2'b00: begin
                                    gmii_txd <= txd_mem_buf[15:8];

                                    slot_tx_eth_address <= { 2'b00, tx_counter[11:2] } + 12'd3;
                                end
                                2'b01: begin
                                    gmii_txd <= txd_mem_buf[7:0];
                                end
                                2'b10: begin
                                    gmii_txd <= slot_tx_eth_q[31:24];

                                    txd_mem_buf <= slot_tx_eth_q;
                                end
                                2'b11: begin
                                    gmii_txd <= txd_mem_buf[23:16];
                                end
                            endcase
                        end
                    end
                endcase
            end
            TX_COMPLETE: begin
                tx_comp_counter <= tx_comp_counter + 2'd1;

                case (tx_comp_counter)
                  2'b00: begin
                  end
                  2'b01: begin
                  end
                  2'b10: begin
                  end
                  2'b11: begin
                  end
                endcase
                tx_counter <= 12'b0;
                tx_status <= TX_IDLE;
            end
            default:
                tx_status <= TX_IDLE;
        endcase
    end
end
// clock sync
clk_sync tx_pcie2gmii_sync (
    .clk1 (pci_clk)
  , .i    (tx_ready)            // input
  , .clk2 (gmii_tx_clk)
  , .o    (tx_ready_eth)
);
clk_sync_ashot tx_gmii2pcie_sync (
    .clk1 (gmii_tx_clk)
  , .i    (tx_status[1])
  , .clk2 (pci_clk)
  , .o    (tx_complete)         // output
);


endmodule

`default_nettype wire
