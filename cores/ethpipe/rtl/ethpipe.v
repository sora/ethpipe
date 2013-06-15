`default_nettype none

//`include "../rtl/setup.v"

//`define DEBUG

module ethpipe (
  // system
    input  wire        sys_rst

  // PCI user registers
  , input  wire        pci_clk

  // global counter
  , input  wire        global_counter_rst
  , output reg  [63:0] global_counter

  // GMII interfaces
  , input  wire        gmii_tx_clk
  , output wire [ 7:0] gmii_txd
  , output wire        gmii_tx_en
  , input  wire [ 7:0] gmii_rxd
  , input  wire        gmii_rx_dv
  , input  wire        gmii_rx_clk

  // RX frame slot
  , output reg  [31:0] slot_rx_eth_data
  , output reg  [ 3:0] slot_rx_eth_byte_en
  , output reg  [10:0] slot_rx_eth_address
  , output reg         slot_rx_eth_wr_en
  , input  wire [31:0] slot_rx_eth_q

  , input  wire        rx_empty       // RX slot empty
  , output wire        rx_complete    // Received a ethernet frame
);

//-------------------------------------
// Global counter
//-------------------------------------
always @(posedge gmii_tx_clk) begin
    if (sys_rst) begin
        global_counter <= 64'b0;
    end else begin
        if (global_counter_rst) begin
            global_counter <= 64'b0;
        end else begin
            global_counter <= global_counter + 64'b1;
        end
    end
end

//-------------------------------------
// Ether frame receiver
//-------------------------------------
parameter [1:0]    // RX status
    RX_IDLE = 2'b00
  , RX_LOAD = 2'b01
  , RX_DONE = 2'b10;
reg [ 1:0] rx_status;
reg [10:0] rx_counter;
reg [63:0] rx_timestamp;
reg        rx_active;
wire       rx_ready;
always @(posedge gmii_rx_clk) begin
    if (sys_rst) begin
        slot_rx_eth_wr_en   <=  1'b0;
        slot_rx_eth_address <= 11'h0;
        slot_rx_eth_data    <= 32'b0;
        rx_counter          <= 11'b0;
        rx_timestamp        <= 64'b0;
        rx_status           <= RX_IDLE;
        rx_active           <=  1'b0;
    end else begin
        if (rx_active == 1'b0) begin
            rx_counter <= 11'b0;

            if (rx_ready == 1'b1 && gmii_rx_dv == 1'b0) begin
                rx_active <= 1'b1;
            end
        end else begin
            rx_status <= RX_IDLE;

            rx_counter        <= 11'b0;
            slot_rx_eth_wr_en <= 1'b0;
            if (gmii_rx_dv) begin
                rx_counter <= rx_counter + 11'b1;
                rx_status  <= RX_LOAD;

                case (rx_counter)
                    // Ethernet preamble
                    11'd0: begin
                        // receive timestamp when first data is received
                        rx_timestamp <= global_counter;
                    end
                    11'd1: begin
                        slot_rx_eth_address <= 11'h0;
                        slot_rx_eth_wr_en   <= 1'b1;
                        slot_rx_eth_byte_en <= 4'b1111;
                        slot_rx_eth_data    <= rx_timestamp[31:0];
                    end
                    11'd2: begin
                        slot_rx_eth_address <= 11'h1;
                        slot_rx_eth_wr_en   <= 1'b1;
                        slot_rx_eth_byte_en <= 4'b1111;
                        slot_rx_eth_data    <= rx_timestamp[63:32];
                    end
                    11'd3: begin // reserved: five-tuple hash
                        slot_rx_eth_address <= 11'h2;
                        slot_rx_eth_wr_en   <= 1'b1;
                        slot_rx_eth_byte_en <= 4'b1111;
                        slot_rx_eth_data    <= 32'h0;
                    end
                    11'd4: begin // skip
                        slot_rx_eth_address <= 11'h1;
                    end
                    11'd5: begin // skip
                        slot_rx_eth_address <= 11'h1;
                    end
                    11'd6: begin // skip
                        slot_rx_eth_address <= 11'h1;
                    end
                    11'd7: begin // skip
                        slot_rx_eth_address <= 11'h1;
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
                if (rx_counter != 12'h0) begin
                    rx_status <= RX_DONE;
                    rx_active <= 1'b0;
    
                    // write frame length
                    slot_rx_eth_address <= 11'h3;
                    slot_rx_eth_wr_en   <= 1'b1;
                    slot_rx_eth_byte_en <= 4'b1111;
                    slot_rx_eth_data    <= {5'h0, rx_counter - 11'h8, 16'h0};
                end
            end
        end
    end
end


//-------------------------------------
// clock sync
//-------------------------------------
clk_sync pcie2gmii_sync (
    .clk1 (pci_clk)
  , .i    (rx_empty)
  , .clk2 (gmii_rx_clk)
  , .o    (rx_ready)
);
clk_sync_ashot gmii2pcie_sync (
    .clk1 (gmii_rx_clk)
  , .i    (rx_status[1])
  , .clk2 (pci_clk)
  , .o    (rx_complete)
);

endmodule

`default_nettype wire
