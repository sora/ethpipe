`default_nettype none

`timescale 1ps / 1ps
`define SIMULATION

module tb_top;

//------------------------------------------------------------------
// Clocks
//------------------------------------------------------------------

// verilator lint_save
// verilator lint_off STMTDLY
reg sys_clk;
initial sys_clk = 1'b0;
always #8 sys_clk = ~sys_clk;

// 125MHz PCI clock
reg pci_clk;
initial pci_clk = 1'b0;
always #8 pci_clk = ~pci_clk;

// 125MHz RX clock
reg phy_rx_clk;
initial phy_rx_clk = 1'b0;
always #8 phy_rx_clk = ~phy_rx_clk;

// 125MHz TX clock
reg phy_tx_clk;
initial phy_tx_clk = 1'b0;
always #8 phy_tx_clk = ~phy_tx_clk;
// verilator lint_restore


//------------------------------------------------------------------
// testbench
//------------------------------------------------------------------
reg         sys_rst;
reg         rx_dv;
reg  [ 7:0] rxd;

reg         global_counter_rst;
wire [63:0] global_counter;
wire [31:0] slot_rx_eth_data;
wire [ 3:0] slot_rx_eth_byte_en;
wire [10:0] slot_rx_eth_address;
wire        slot_rx_eth_wr_en;
reg  [31:0] slot_rx_eth_q;
reg         rx_empty;
wire        rx_complete;
ethpipe ethpipe_ins (
  // system
    .sys_rst(sys_rst)

  // PCI user registers
  , .pci_clk(pci_clk)

  , .global_counter_rst(global_counter_rst)
  , .global_counter(global_counter)

  // GMII interfaces
  , .gmii_tx_clk(phy_tx_clk)
  , .gmii_txd()
  , .gmii_tx_en()
  , .gmii_rxd(rxd)
  , .gmii_rx_dv(rx_dv)
  , .gmii_rx_clk(phy_rx_clk)

  // RX frame slot
  , .slot_rx_eth_data(slot_rx_eth_data)
  , .slot_rx_eth_byte_en(slot_rx_eth_byte_en)
  , .slot_rx_eth_address(slot_rx_eth_address)
  , .slot_rx_eth_wr_en(slot_rx_eth_wr_en)
  , .slot_rx_eth_q(slot_rx_eth_q)

  , .rx_empty(rx_empty)           // RX slot empty
  , .rx_complete(rx_complete)     // RX slot read ready
);


//------------------------------------------------------------------
// a clock
//------------------------------------------------------------------
task waitclock;
begin
  @(posedge sys_clk);
  #1;
end
endtask


//------------------------------------------------------------------
// scinario
//------------------------------------------------------------------
reg [8:0] rom [0:1024];
reg [11:0] counter = 12'b0;

always @(posedge phy_rx_clk) begin
  { rx_dv, rxd } <= rom[counter];
  counter        <= counter + 1;
//  $display("rx_dv: %x, rxd: %x", rx_dv, rxd);
end

initial begin
  $dumpfile("./test.vcd");
  $dumpvars(0, tb_top);
  $readmemh("request.hex", rom);
  sys_rst = 1'b1;
  counter = 0;

  waitclock;
  waitclock;

  sys_rst = 1'b0;
  rx_empty = 1'b1;

  waitclock;

  // verilator lint_off STMTDLY
  #10000;
  $finish;
end

endmodule

`default_nettype wire

