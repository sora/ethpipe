`default_nettype none

`include "../rtl/setup.v"

//`define DEBUG

module ethpipe (
    input wire        sys_rst
  , input wire        sys_clk
  , input wire        pci_clk

  , // GMII interfaces
  , input  wire       gmii_tx_clk
  , output wire [7:0] gmii_txd
  , output wire       gmii_tx_en
  , input  wire [7:0] gmii_rxd
  , input  wire       gmii_rx_dv
  , input  wire       gmii_rx_clk

  // PCI user registers

);

assign gmii_txd_en = 1'b0;

endmodule

`default_nettype wire

