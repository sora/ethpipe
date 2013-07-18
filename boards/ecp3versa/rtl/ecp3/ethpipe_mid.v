`default_nettype none

`include "setup.v"

module ethpipe_mid  (
    input  clk_125
  , input  sys_rst
  , output sys_intr
  , input  [7:0] dipsw
  , output [7:0] led
  , output [13:0] segled
  // PCIe
  , input [6:0] rx_bar_hit
  , input [7:0] bus_num
  , input [4:0] dev_num
  , input [2:0] func_num
  // Receive
  , input rx_st
  , input rx_end
  , input [15:0] rx_data
  // Transmit
  , output tx_req
  , input tx_rdy
  , output tx_st
  , output tx_end
  , output [15:0] tx_data
  // Receive credits
  , output [7:0] pd_num
  , output ph_cr
  , output pd_cr
  , output nph_cr
  , output npd_cr
  // Ethernet PHY#1
  , output phy1_rst_n
  , input  phy1_125M_clk
  , input  phy1_tx_clk
  , output phy1_gtx_clk
  , output phy1_tx_en
  , output [7:0] phy1_tx_data
  , input  phy1_rx_clk
  , input  phy1_rx_dv
  , input  phy1_rx_er
  , input  [7:0] phy1_rx_data
  , input  phy1_col
  , input  phy1_crs
  , output phy1_mii_clk
  , inout  phy1_mii_data

  // Ethernet PHY#2
  , output phy2_rst_n
  , input  phy2_125M_clk
  , input  phy2_tx_clk
  , output phy2_gtx_clk
  , output phy2_tx_en
  , output [7:0] phy2_tx_data
  , input  phy2_rx_clk
  , input  phy2_rx_dv
  , input  phy2_rx_er
  , input  [7:0] phy2_rx_data
  , input  phy2_col
  , input  phy2_crs
  , output phy2_mii_clk
  , inout  phy2_mii_data
);

reg  [63:0] global_counter;

// BUS Master Command FIFO
wire [17:0] wr_mstq_din, wr_mstq_dout;
wire wr_mstq_full, wr_mstq_wr_en;
wire wr_mstq_empty, wr_mstq_rd_en;

fifo fifo_wr_mstq (
	.Data(wr_mstq_din),
	.Clock(clk_125),
	.WrEn(wr_mstq_wr_en),
	.RdEn(wr_mstq_rd_en),
	.Reset(sys_rst),
	.Q(wr_mstq_dout),
	.Empty(wr_mstq_empty),
	.Full(wr_mstq_full)
);

// PHY#1 RX Receive AFIFO
wire [17:0] rx1_phyq_din, rx1_phyq_dout;
wire rx1_phyq_full, rx1_phyq_wr_en;
wire rx1_phyq_empty, rx1_phyq_rd_en;
wire [7:0] rx1_phyq_count;

afifo18 afifo18_rx1_phyq (
        .Data(rx1_phyq_din),
	.WrClock(phy1_rx_clk),
	.RdClock(clk_125),
	.WrEn(rx1_phyq_wr_en),
	.RdEn(rx1_phyq_rd_en),
	.Reset(sys_rst),
	.RPReset(sys_rst),
	.Q(rx1_phyq_dout),
	.Empty(rx1_phyq_empty),
	.Full(rx1_phyq_full)
);

// PHY#2 RX Receive AFIFO
wire [17:0] rx2_phyq_din, rx2_phyq_dout;
wire rx2_phyq_full, rx2_phyq_wr_en;
wire rx2_phyq_empty, rx2_phyq_rd_en;
wire [7:0] rx2_phyq_count;

afifo18 afifo18_rx2_phyq (
        .Data(rx2_phyq_din),
	.WrClock(phy2_rx_clk),
	.RdClock(clk_125),
	.WrEn(rx2_phyq_wr_en),
	.RdEn(rx2_phyq_rd_en),
	.Reset(sys_rst),
	.RPReset(sys_rst),
	.Q(rx2_phyq_dout),
	.Empty(rx2_phyq_empty),
	.Full(rx2_phyq_full)
);

// PHY#1 RX GMII2FIFO18 module
gmii2fifo18 # (
	.Gap(4'h8)
) rx1gmii2fifo (
	.sys_rst(sys_rst),
	.global_counter(global_counter),
	.gmii_rx_clk(phy1_rx_clk),
	.gmii_rx_dv(phy1_rx_dv),
	.gmii_rxd(phy1_rx_data),
	.din(rx1_phyq_din),
	.full(rx1_phyq_full),
	.wr_en(rx1_phyq_wr_en),
	.wr_count(rx1_phyq_count),
	.wr_clk()
);

// PHY#2 RX GMII2FIFO18 module
gmii2fifo18 # (
	.Gap(4'h8)
) rx2gmii2fifo (
	.sys_rst(sys_rst),
	.global_counter(global_counter),
	.gmii_rx_clk(phy2_rx_clk),
	.gmii_rx_dv(phy2_rx_dv),
	.gmii_rxd(phy2_rx_data),
	.din(rx2_phyq_din),
	.full(rx2_phyq_full),
	.wr_en(rx2_phyq_wr_en),
	.wr_count(rx2_phyq_count),
	.wr_clk()
);

// Slave bus
wire [6:0] slv_bar_i;
wire slv_ce_i;
wire slv_we_i;
wire [19:1] slv_adr_i;
wire [15:0] slv_dat_i;
wire [1:0] slv_sel_i;
wire [15:0] slv_dat_o, slv_dat1_o, slv_dat2_o;
reg [15:0] slv_dat0_o;

// DMA wire & regs
reg [7:0]  dma_status;
reg [21:2] dma_length;
reg [31:2] dma1_addr_start, dma2_addr_start;
wire [31:2] dma1_addr_cur, dma2_addr_cur;


pcie_tlp inst_pcie_tlp (
  // System
    .pcie_clk(clk_125)
  , .sys_rst(sys_rst)
  // Management
  , .rx_bar_hit(rx_bar_hit)
  , .bus_num(bus_num)
  , .dev_num(dev_num)
  , .func_num(func_num)
  // Receive
  , .rx_st(rx_st)
  , .rx_end(rx_end)
  , .rx_data(rx_data)
  // Transmit
  , .tx_req(tx_req)
  , .tx_rdy(tx_rdy)
  , .tx_st(tx_st)
  , .tx_end(tx_end)
  , .tx_data(tx_data)
  //Receive credits
  , .pd_num(pd_num)
  , .ph_cr(ph_cr)
  , .pd_cr(pd_cr)
  , .nph_cr(nph_cr)
  , .npd_cr(npd_cr)
  // Master FIFO
  , .mst_rd_en(wr_mstq_rd_en)
  , .mst_empty(wr_mstq_empty)
  , .mst_dout(wr_mstq_dout)
  , .mst_wr_en()
  , .mst_full()
  , .mst_din()
  // Slave BUS
  , .slv_bar_i(slv_bar_i)
  , .slv_ce_i(slv_ce_i)
  , .slv_we_i(slv_we_i)
  , .slv_adr_i(slv_adr_i)
  , .slv_dat_i(slv_dat_i)
  , .slv_sel_i(slv_sel_i)
  , .slv_dat_o(slv_dat_o)
  // Slave FIFO
  , .slv_rd_en()
  , .slv_empty()
  , .slv_dout()
  , .slv_wr_en()
  , .slv_full()
  , .slv_din()
  // LED and Switches
  , .dipsw()
  , .led()
  , .segled()
  , .btn()
);

// PHY Receiver
wire btn;
wire rec_intr;
`ifdef ENABLE_RECEIVER
receiver receiver_inst (
	.sys_clk(clk_125),
	.sys_rst(sys_rst),
	.sys_intr(rec_intr),
	// Phy1 FIFO
	.phy1_dout(rx1_phyq_dout),
	.phy1_empty(rx1_phyq_empty),
	.phy1_rd_en(rx1_phyq_rd_en),
	.phy1_rx_count(rx1_phyq_count),
	// Phy2 FIFO
	.phy2_dout(rx2_phyq_dout),
	.phy2_empty(rx2_phyq_empty),
	.phy2_rd_en(rx2_phyq_rd_en),
	.phy2_rx_count(rx2_phyq_count),
	// Master FIFO
	.mst_din(wr_mstq_din),
	.mst_full(wr_mstq_full),
	.mst_wr_en(wr_mstq_wr_en),
	.mst_dout(),
	.mst_empty(),
	.mst_rd_en(),
	// DMA regs
	.dma_status(dma_status),
	.dma_length(dma_length),
	.dma1_addr_start(dma1_addr_start),
	.dma1_addr_cur(dma1_addr_cur),
	.dma2_addr_start(dma2_addr_start),
	.dma2_addr_cur(dma2_addr_cur),
	// LED and Switches
	.dipsw(),
	.led(),
	.segled(),
	.btn(btn)
);
`endif

`ifdef ENABLE_TRANSMITTER
`endif

reg [3:0] rx_slots_status = 4'b0000;
reg [3:0] tx_slots_status = 4'b0000;

//-------------------------------------
// ethpipe Port0
//-------------------------------------

// Slot0 RX (A: host, B: ethernet)
wire [15:0] mem0_dataB;
wire [ 1:0] mem0_byte_enB;
wire [13:0] mem0_addressB;
wire        mem0_wr_enB;
wire [15:0] mem0_qB;
ram_dp_true mem0read (
    .DataInA(slv_dat_i)
  , .DataInB(mem0_dataB)
  , .ByteEnA(slv_sel_i)
  , .ByteEnB(mem0_byte_enB)
  , .AddressA(slv_adr_i[14:1])
  , .AddressB(mem0_addressB)
  , .ClockA(clk_125)
  , .ClockB(phy1_rx_clk)
  , .ClockEnA(slv_ce_i & slv_bar_i[2] & ~slv_adr_i[15])
  , .ClockEnB(1'b1)
  , .WrA(slv_we_i)
  , .WrB(mem0_wr_enB)
  , .ResetA(sys_rst)
  , .ResetB(sys_rst)
  , .QA(slv_dat1_o)
  , .QB(mem0_qB)
);

// Slot1 RX (A: host, B: ethernet)
wire [15:0] mem1_dataB;
wire [ 1:0] mem1_byte_enB;
wire [13:0] mem1_addressB;
wire        mem1_wr_enB;
wire [15:0] mem1_qB;
ram_dp_true mem1read (
    .DataInA(slv_dat_i)
  , .DataInB(mem1_dataB)
  , .ByteEnA(slv_sel_i)
  , .ByteEnB(mem1_byte_enB)
  , .AddressA(slv_adr_i[14:1])
  , .AddressB(mem1_addressB)
  , .ClockA(clk_125)
  , .ClockB(phy2_rx_clk)
  , .ClockEnA(slv_ce_i & slv_bar_i[2] & slv_adr_i[15])
  , .ClockEnB(1'b1)
  , .WrA(slv_we_i)
  , .WrB(mem1_wr_enB)
  , .ResetA(sys_rst)
  , .ResetB(sys_rst)
  , .QA(slv_dat2_o)
  , .QB(mem1_qB)
);


wire        slot0_rx_ready;
wire        slot1_rx_ready;
`ifdef NO
ethpipe ethpipe_ins (
  // system
    .sys_rst(sys_rst)

  // PCI user registers
  , .pci_clk(clk_125)

  , .global_counter_rst(global_counter_rst)
  , .global_counter(global_counter)

  // Port 0
  , .gmii0_tx_clk(phy1_125M_clk)
  , .gmii0_txd()
  , .gmii0_tx_en()
  , .gmii0_rxd(phy1_rx_data)
  , .gmii0_rx_dv(phy1_rx_dv)
  , .gmii0_rx_clk(phy1_rx_clk)

  , .slot0_rx_eth_data(mem0_dataB)
  , .slot0_rx_eth_byte_en(mem0_byte_enB)
  , .slot0_rx_eth_address(mem0_addressB)
  , .slot0_rx_eth_wr_en(mem0_wr_enB)
//  , .slot0_rx_eth_q(mem0_qB)

  , .slot0_rx_empty(rx_slots_status[1])      // RX slot empty
  , .slot0_rx_complete(slot0_rx_ready)       // RX slot read ready

  // Port 1
  , .gmii1_tx_clk(phy2_125M_clk)
  , .gmii1_txd()
  , .gmii1_tx_en()
  , .gmii1_rxd(phy2_rx_data)
  , .gmii1_rx_dv(phy2_rx_dv)
  , .gmii1_rx_clk(phy2_rx_clk)

  , .slot1_rx_eth_data(mem1_dataB)
  , .slot1_rx_eth_byte_en(mem1_byte_enB)
  , .slot1_rx_eth_address(mem1_addressB)
  , .slot1_rx_eth_wr_en(mem1_wr_enB)
//  , .slot1_rx_eth_q(mem1_qB)

  , .slot1_rx_empty(rx_slots_status[3])      // RX slot empty
  , .slot1_rx_complete(slot1_rx_ready)       // RX slot read ready
);
`endif
assign phy1_mii_clk  = 1'b0;
assign phy1_mii_data = 1'b0;
assign phy1_tx_en    = 1'b0;
assign phy1_tx_data  = 8'h0;
assign phy1_gtx_clk  = phy1_125M_clk;
assign phy2_mii_clk  = 1'b0;
assign phy2_mii_data = 1'b0;
assign phy2_tx_en    = 1'b0;
assign phy2_tx_data  = 8'h0;
assign phy2_gtx_clk  = phy2_125M_clk;

// Global counter
always @(posedge clk_125) begin
	if (sys_rst == 1'b1)
		global_counter <= 64'h0;
	else
		global_counter <= global_counter + 64'h1;
end

//-------------------------------------
// PCI I/O memory mapping
//-------------------------------------
always @(posedge clk_125) begin
	if (sys_rst == 1'b1) begin
		slv_dat0_o <= 16'h0;
		dma_status     <= 8'h00;
		dma_length   <= ( 22'h1_0000 >> 2 );
		dma1_addr_start <= ( 32'h1000_0000 >> 2 );
		dma2_addr_start <= ( 32'h1010_0000 >> 2 );
	end else begin
		if (rec_intr)
			dma_status[3] <= 1'b1;
		if (slv_bar_i[0] & slv_ce_i) begin
			if (slv_adr_i[11:7] == 5'h0) begin
				case (slv_adr_i[6:1])
					// slots status
					6'h00: begin
					end
					// global counter [15:0]
					6'h02: begin
						if (~slv_we_i) begin
							slv_dat0_o <= {global_counter[7:0], global_counter[15:8]};
						end
					end
					// global counter [31:16]
					6'h03: begin
						if (~slv_we_i) begin
							slv_dat0_o <= {global_counter[23:16], global_counter[31:24]};
						end
					end
					// global counter [47:32]
					6'h04: begin
						if (~slv_we_i) begin
							slv_dat0_o <= {global_counter[39:32], global_counter[47:40]};
						end
					end
					// global counter [63:48]
					6'h05: begin
						if (~slv_we_i) begin
							slv_dat0_o <= {global_counter[55:48], global_counter[63:56]};
						end
					end
					// dma status regs
					6'h08: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								dma_status[ 7: 0] <= slv_dat_i[15:8];
						end else
							slv_dat0_o <= {dma_status[7:0], 8'h00};
					end
					// dma length
					6'h0a: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								dma_length[ 7: 2] <= slv_dat_i[15:10];
							if (slv_sel_i[0])
								dma_length[15: 8] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma_length[7:2], 2'b00, dma_length[15:8]};
					end
					6'h0b: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								dma_length[21:16] <= slv_dat_i[13: 8];
						end else
							slv_dat0_o <= {2'b00, dma_length[21:16], 8'h00};
					end
					// dma1 start address
					6'h10: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								dma1_addr_start[ 7: 2] <= slv_dat_i[15:10];
							if (slv_sel_i[0])
								dma1_addr_start[15: 8] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma1_addr_start[7:2], 2'b00, dma1_addr_start[15:8]};
					end
					6'h11: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								dma1_addr_start[23:16] <= slv_dat_i[15: 8];
							if (slv_sel_i[0])
								dma1_addr_start[31:24] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma1_addr_start[23:16], dma1_addr_start[31:24]};
					end
					// dma1 current address
					6'h12: begin
						slv_dat0_o <= {dma1_addr_cur[7:2], 2'b00, dma1_addr_cur[15:8]};
					end
					6'h13: begin
						slv_dat0_o <= {dma1_addr_cur[23:16], dma1_addr_cur[31:24]};
					end
					// dma2 start address
					6'h14: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								dma2_addr_start[ 7: 2] <= slv_dat_i[15:10];
							if (slv_sel_i[0])
								dma2_addr_start[15: 8] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma2_addr_start[7:2], 2'b00, dma2_addr_start[15:8]};
					end
					6'h15: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								dma2_addr_start[23:16] <= slv_dat_i[15: 8];
							if (slv_sel_i[0])
								dma2_addr_start[31:24] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma2_addr_start[23:16], dma2_addr_start[31:24]};
					end
					// dma2 current address
					6'h16: begin
						slv_dat0_o <= {dma2_addr_cur[7:2], 2'b00, dma2_addr_cur[15:8]};
					end
					6'h17: begin
						slv_dat0_o <= {dma2_addr_cur[23:16], dma2_addr_cur[31:24]};
					end
					default:
						slv_dat0_o <= 16'h0; // slv_adr_i[16:1];
				endcase
			end else
				slv_dat0_o <= 16'h0; // slv_adr_i[16:1];
		end
	end
end

assign slv_dat_o = ( {16{slv_bar_i[0]}} & slv_dat0_o ) | ( {16{slv_bar_i[2] & ~slv_adr_i[15]}} & slv_dat1_o ) | ( {16{slv_bar_i[2] & slv_adr_i[15]}} & slv_dat2_o );

assign sys_intr = rec_intr;

endmodule

`default_nettype wire
