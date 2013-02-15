`timescale 1ns / 1ps
`include "../rtl/setup.v"
//`define DEBUG

module ethpipe (
  input         sys_rst,
  input         sys_clk,
  input         pci_clk,

  // GMII interfaces for 4 MACs
  input         gmii_0_tx_clk,
  output [7:0]  gmii_0_txd,
  output        gmii_0_tx_en,
  input  [7:0]  gmii_0_rxd,
  input         gmii_0_rx_dv,
  input         gmii_0_rx_clk,

  input         gmii_1_tx_clk,
  output [7:0]  gmii_1_txd,
  output        gmii_1_tx_en,
  input  [7:0]  gmii_1_rxd,
  input         gmii_1_rx_dv,
  input         gmii_1_rx_clk,

  input         gmii_2_tx_clk,
  output [7:0]  gmii_2_txd,
  output        gmii_2_tx_en,
  input  [7:0]  gmii_2_rxd,
  input         gmii_2_rx_dv,
  input         gmii_2_rx_clk,

  input         gmii_3_tx_clk,
  output [7:0]  gmii_3_txd,
  output        gmii_3_tx_en,
  input  [7:0]  gmii_3_rxd,
  input         gmii_3_rx_dv,
  input         gmii_3_rx_clk

  // PCI user registers

);

assign gmii_0_txd_en = 1'b0;
assign gmii_1_txd_en = 1'b0;
assign gmii_2_txd_en = 1'b0;
assign gmii_3_txd_en = 1'b0;

endmodule
