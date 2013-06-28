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

  // Port 0
  , input  wire        gmii0_tx_clk
  , output wire [ 7:0] gmii0_txd
  , output wire        gmii0_tx_en
  , input  wire [ 7:0] gmii0_rxd
  , input  wire        gmii0_rx_dv
  , input  wire        gmii0_rx_clk

  , output wire [31:0] slot0_rx_eth_data
  , output wire [ 3:0] slot0_rx_eth_byte_en
  , output wire [10:0] slot0_rx_eth_address
  , output wire        slot0_rx_eth_wr_en
 // , input  wire [31:0] slot0_rx_eth_q

  , input  wire        slot0_rx_empty       // RX slot empty
  , output wire        slot0_rx_complete    // Received a ethernet frame

  // Port 1
  , input  wire        gmii1_tx_clk
  , output wire [ 7:0] gmii1_txd
  , output wire        gmii1_tx_en
  , input  wire [ 7:0] gmii1_rxd
  , input  wire        gmii1_rx_dv
  , input  wire        gmii1_rx_clk

  , output wire [31:0] slot1_rx_eth_data
  , output wire [ 3:0] slot1_rx_eth_byte_en
  , output wire [10:0] slot1_rx_eth_address
  , output wire        slot1_rx_eth_wr_en
 // , input  wire [31:0] slot1_rx_eth_q

  , input  wire        slot1_rx_empty       // RX slot empty
  , output wire        slot1_rx_complete    // Received a ethernet frame
);

//-------------------------------------
// Global counter (clock: gmii0_tx_clk)
//-------------------------------------
always @(posedge gmii0_tx_clk) begin
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

// Port 0
ethpipe_port ethpipe_port0 (
    .sys_rst(sys_rst)
  , .pci_clk(pci_clk)

  , .global_counter(global_counter)

  , .gmii_tx_clk(gmii0_tx_clk)
  , .gmii_txd(gmii0_txd)
  , .gmii_tx_en(gmii0_tx_en)
  , .gmii_rxd(gmii0_rxd)
  , .gmii_rx_dv(gmii0_rx_dv)
  , .gmii_rx_clk(gmii0_rx_clk)

  , .slot_rx_eth_data(slot0_rx_eth_data)
  , .slot_rx_eth_byte_en(slot0_rx_eth_byte_en)
  , .slot_rx_eth_address(slot0_rx_eth_address)
  , .slot_rx_eth_wr_en(slot0_rx_eth_wr_en)
  , .slot_rx_empty(slot0_rx_empty)
  , .slot_rx_complete(slot0_rx_complete)
);

// Port 1
ethpipe_port ethpipe_port1 (
    .sys_rst(sys_rst)
  , .pci_clk(pci_clk)

  , .global_counter(global_counter)

  , .gmii_tx_clk(gmii1_tx_clk)
  , .gmii_txd(gmii1_txd)
  , .gmii_tx_en(gmii1_tx_en)
  , .gmii_rxd(gmii1_rxd)
  , .gmii_rx_dv(gmii1_rx_dv)
  , .gmii_rx_clk(gmii1_rx_clk)

  , .slot_rx_eth_data(slot1_rx_eth_data)
  , .slot_rx_eth_byte_en(slot1_rx_eth_byte_en)
  , .slot_rx_eth_address(slot1_rx_eth_address)
  , .slot_rx_eth_wr_en(slot1_rx_eth_wr_en)
  , .slot_rx_empty(slot1_rx_empty)
  , .slot_rx_complete(slot1_rx_complete)
);

endmodule

`default_nettype wire
