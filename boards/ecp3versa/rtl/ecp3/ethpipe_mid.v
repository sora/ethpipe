`default_nettype none

`include "setup.v"

module ethpipe_mid  (
    input  clk_125
  , input  sys_rst
  , output sys_intr
  , input  [7:0] dipsw
  , output wire [7:0] led
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

`ifdef ENABLE_PHY2
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
`endif

// PHY#1 RX Receive Length AFIFO
wire [17:0] rx1_lenq_din, rx1_lenq_dout;
wire rx1_lenq_full, rx1_lenq_wr_en;
wire rx1_lenq_empty, rx1_lenq_rd_en;

afifo18_7 afifo18_rx1_lenq (
	.Data(rx1_lenq_din),
	.WrClock(phy1_rx_clk),
	.RdClock(clk_125),
	.WrEn(rx1_lenq_wr_en),
	.RdEn(rx1_lenq_rd_en),
	.Reset(sys_rst),
	.RPReset(sys_rst),
	.Q(rx1_lenq_dout),
	.Empty(rx1_lenq_empty),
	.Full(rx1_lenq_full)
);

`ifdef ENABLE_PHY2
afifo18_7 afifo18_rx2_lenq (
	.Data(rx2_lenq_din),
	.WrClock(phy2_rx_clk),
	.RdClock(clk_125),
	.WrEn(rx2_lenq_wr_en),
	.RdEn(rx2_lenq_rd_en),
	.Reset(sys_rst),
	.RPReset(sys_rst),
	.Q(rx2_lenq_dout),
	.Empty(rx2_lenq_empty),
	.Full(rx2_lenq_full)
);
`endif

// PHY#1 RX GMII2FIFO18 module
gmii2fifo18 # (
	.Gap(4'h4)
) rx1gmii2fifo (
	.sys_rst(sys_rst),
	.global_counter(global_counter),
	.gmii_rx_clk(phy1_rx_clk),
	.gmii_rx_dv(phy1_rx_dv),
	.gmii_rxd(phy1_rx_data),
	.data_din(rx1_phyq_din),
	.data_full(rx1_phyq_full),
	.data_wr_en(rx1_phyq_wr_en),
	.len_din(rx1_lenq_din),
	.len_full(rx1_lenq_full),
	.len_wr_en(rx1_lenq_wr_en),
	.wr_clk()
);

// PHY#2 RX GMII2FIFO18 module
`ifdef ENABLE_PHY2
gmii2fifo18 # (
	.Gap(4'h4)
) rx2gmii2fifo (
	.sys_rst(sys_rst),
	.global_counter(global_counter),
	.gmii_rx_clk(phy2_rx_clk),
	.gmii_rx_dv(phy2_rx_dv),
	.gmii_rxd(phy2_rx_data),
	.data_din(rx2_phyq_din),
	.data_full(rx2_phyq_full),
	.data_wr_en(rx2_phyq_wr_en),
	.length_din(rx2_lenq_din),
	.length_full(rx2_lenq_full),
	.length_wr_en(rx2_lenq_wr_en),
	.wr_clk()
);
`endif

// Slave bus
wire [6:0] slv_bar_i;
wire slv_ce_i;
wire slv_we_i;
wire [19:1] slv_adr_i;
wire [15:0] slv_dat_i;
wire [1:0] slv_sel_i;
wire [15:0] slv_dat_o, slv_dat1_o, slv_dat2_o;
reg [15:0] slv_dat0_o, slv_dat0_o2;

// DMA wire & regs
reg [7:0]  dma_status;
reg [21:2] dma_length;
reg [31:2] dma1_addr_start, dma2_addr_start;
wire [31:2] dma1_addr_cur, dma2_addr_cur;

reg dma1_load, dma2_load;

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

// local time registers
reg [47:0] local_time1;
reg [47:0] local_time2;
reg [47:0] local_time3;
reg [47:0] local_time4;
reg [47:0] local_time5;
reg [47:0] local_time6;
reg [47:0] local_time7;

// PHY Receiver
wire btn;
wire rec_intr;
`ifdef ENABLE_RECEIVER
receiver receiver_phy1 (
	.sys_clk(clk_125),
	.sys_rst(sys_rst),
	.sys_intr(rec_intr),
	// Phy FIFO
	.phy_dout(rx1_phyq_dout),
	.phy_empty(rx1_phyq_empty),
	.phy_rd_en(rx1_phyq_rd_en),
	// Length FIFO
	.len_dout(rx1_lenq_dout),
	.len_empty(rx1_lenq_empty),
	.len_rd_en(rx1_lenq_rd_en),
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
	.dma_addr_start(dma1_addr_start),
	.dma_addr_cur(dma1_addr_cur),
	.dma_load(dma1_load),
	// LED and Switches
	.dipsw(),
	.led(),
	.segled(),
	.btn(btn)
);
`endif

// sender slot (A: PCIe, B: Ethernet PHY)
wire [15:0] tx0mem_dataB;
wire [ 1:0] tx0mem_byte_enB;
wire [13:0] tx0mem_addressB;
wire        tx0mem_wr_enB;
wire [15:0] tx0mem_qB;
wire [15:0] tx1mem_dataB;
wire [ 1:0] tx1mem_byte_enB;
wire [13:0] tx1mem_addressB;
wire        tx1mem_wr_enB;
wire [15:0] tx1mem_qB;
`ifdef ENABLE_TRANSMITTER
ram_dp_true tx0_mem (
    .DataInA(slv_dat_i)
  , .DataInB(tx0mem_dataB)
  , .ByteEnA(slv_sel_i)
  , .ByteEnB(tx0mem_byte_enB)
  , .AddressA(slv_adr_i[14:1])
  , .AddressB(tx0mem_addressB)
  , .ClockA(clk_125)
  , .ClockB(phy1_rx_clk)
  , .ClockEnA(slv_ce_i & slv_bar_i[2] & ~slv_adr_i[15])
  , .ClockEnB(1'b1)
  , .WrA(slv_we_i)
  , .WrB(tx0mem_wr_enB)
  , .ResetA(sys_rst)
  , .ResetB(sys_rst)
  , .QA(slv_dat1_o)
  , .QB(tx0mem_qB)
);

`ifdef ENABLE_PHY2
ram_dp_true tx1_mem (
    .DataInA(slv_dat_i)
  , .DataInB(tx1mem_dataB)
  , .ByteEnA(slv_sel_i)
  , .ByteEnB(tx1mem_byte_enB)
  , .AddressA(slv_adr_i[14:1])
  , .AddressB(tx1mem_addressB)
  , .ClockA(clk_125)
  , .ClockB(phy1_rx_clk)
  , .ClockEnA(slv_ce_i & slv_bar_i[2] & slv_adr_i[15])
  , .ClockEnB(1'b1)
  , .WrA(slv_we_i)
  , .WrB(tx1mem_wr_enB)
  , .ResetA(sys_rst)
  , .ResetB(sys_rst)
  , .QA(slv_dat2_o)
  , .QB(tx1mem_qB)
);
`endif
`endif

wire [13:0] tx0mem_rd_ptr;
reg  [13:0] tx0mem_wr_ptr;
wire [13:0] tx1mem_rd_ptr;
reg  [13:0] tx1mem_wr_ptr;
wire [ 6:0] tx0local_time_req;
wire [ 6:0] tx1local_time_req;
`ifdef ENABLE_TRANSMITTER
sender sender_phy1_ins (
    .sys_rst(sys_rst)

  , .global_counter(global_counter)

  , .gmii_tx_clk(clk_125)
  , .gmii_txd(phy1_tx_data)
  , .gmii_tx_en(phy1_tx_en)
  , .slot_tx_eth_data(tx0mem_dataB)
  , .slot_tx_eth_byte_en(tx0mem_byte_enB)
  , .slot_tx_eth_addr(tx0mem_addressB)
  , .slot_tx_eth_wr_en(tx0mem_wr_enB)
  , .slot_tx_eth_q(tx0mem_qB)

  , .mem_wr_ptr(tx0mem_wr_ptr)
  , .mem_rd_ptr(tx0mem_rd_ptr)

  , .local_time1(local_time1)
  , .local_time2()
  , .local_time3()
  , .local_time4()
  , .local_time5()
  , .local_time6()
  , .local_time7()

  , .local_time_req(tx0local_time_req)

  , .led(led)
  , .dipsw(dipsw)
);

`ifdef ENABLE_PHY2
sender sender_phy2_ins (
    .sys_rst(sys_rst)

  , .global_counter(global_counter)

  , .gmii_tx_clk(clk_125)
  , .gmii_txd(phy2_tx_data)
  , .gmii_tx_en(phy2_tx_en)
  , .slot_tx_eth_data(tx1mem_dataB)
  , .slot_tx_eth_byte_en(tx1mem_byte_enB)
  , .slot_tx_eth_addr(tx1mem_addressB)
  , .slot_tx_eth_wr_en(tx1mem_wr_enB)
  , .slot_tx_eth_q(tx1mem_qB)

  , .mem_wr_ptr(tx1mem_wr_ptr)
  , .mem_rd_ptr(tx1mem_rd_ptr)

  , .local_time1(local_time1)
  , .local_time2()
  , .local_time3()
  , .local_time4()
  , .local_time5()
  , .local_time6()
  , .local_time7()

  , .local_time_req(tx1local_time_req)
);
`endif
`endif

assign phy1_mii_clk  = 1'b0;
assign phy1_mii_data = 1'b0;
assign phy1_gtx_clk  = clk_125;
assign phy2_mii_clk  = 1'b0;
assign phy2_mii_data = 1'b0;
assign phy2_gtx_clk  = clk_125;

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
reg [6:0] local_time_update_pending;
reg       local_time_update_ack;
always @(posedge clk_125) begin
//	if (rec_intr)
//		led <= led + 8'h1;
	if (sys_rst == 1'b1) begin
		slv_dat0_o                <= 16'h0;
		dma_status                <= 8'h00;
		dma_length                <= ( 22'h1_0000 >> 2 );
		dma1_addr_start           <= ( 32'h1000_0000 >> 2 );
		dma2_addr_start           <= ( 32'h1010_0000 >> 2 );
		dma1_load                 <= 1'b0;
		dma2_load                 <= 1'b0;
		tx0mem_wr_ptr             <= 14'h0;
		tx1mem_wr_ptr             <= 14'h0;
		local_time1               <= 48'h0;
		local_time2               <= 48'h0;
		local_time3               <= 48'h0;
		local_time4               <= 48'h0;
		local_time5               <= 48'h0;
		local_time6               <= 48'h0;
		local_time7               <= 48'h0;
		local_time_update_pending <= 7'b0;
		local_time_update_ack     <= 1'b0;
	end else begin

		if (tx0local_time_req != 7'b0)
			local_time_update_pending <= tx0local_time_req;
		else if(tx1local_time_req != 7'b0)
			local_time_update_pending <= tx1local_time_req;
		else if (local_time_update_ack == 1'b1)
			local_time_update_pending <= 7'b0;

		dma1_load <= 1'b0;
		dma2_load <= 1'b0;
		if (rec_intr)
			dma_status[3] <= 1'b1;
		if (slv_bar_i[0] & slv_ce_i) begin
			if (slv_adr_i[11:9] == 3'h0) begin
				case (slv_adr_i[8:1])
					// slots status
					8'h00: begin
					end
					// global counter [15:0]
					8'h02: begin
						if (~slv_we_i) begin
							slv_dat0_o <= {global_counter[7:0], global_counter[15:8]};
						end
					end
					// global counter [31:16]
					8'h03: begin
						if (~slv_we_i) begin
							slv_dat0_o <= {global_counter[23:16], global_counter[31:24]};
						end
					end
					// global counter [47:32]
					8'h04: begin
						if (~slv_we_i) begin
							slv_dat0_o <= {global_counter[39:32], global_counter[47:40]};
						end
					end
					// global counter [63:48]
					8'h05: begin
						if (~slv_we_i) begin
							slv_dat0_o <= {global_counter[55:48], global_counter[63:56]};
						end
					end
					// dma status regs
					8'h08: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								dma_status[ 7: 0] <= slv_dat_i[15:8];
						end else
							slv_dat0_o <= {dma_status[7:0], 8'h00};
					end
					// dma length
					8'h0a: begin
						if (slv_we_i) begin
							dma1_load <= 1'b1;
							dma2_load <= 1'b1;
							if (slv_sel_i[1])
								dma_length[ 7: 2] <= slv_dat_i[15:10];
							if (slv_sel_i[0])
								dma_length[15: 8] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma_length[7:2], 2'b00, dma_length[15:8]};
					end
					8'h0b: begin
						if (slv_we_i) begin
							dma1_load <= 1'b1;
							dma2_load <= 1'b1;
							if (slv_sel_i[1])
								dma_length[21:16] <= slv_dat_i[13: 8];
						end else
							slv_dat0_o <= {2'b00, dma_length[21:16], 8'h00};
					end
					// dma1 start address
					8'h10: begin
						if (slv_we_i) begin
							dma1_load <= 1'b1;
							if (slv_sel_i[1])
								dma1_addr_start[ 7: 2] <= slv_dat_i[15:10];
							if (slv_sel_i[0])
								dma1_addr_start[15: 8] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma1_addr_start[7:2], 2'b00, dma1_addr_start[15:8]};
					end
					8'h11: begin
						if (slv_we_i) begin
							dma1_load <= 1'b1;
							if (slv_sel_i[1])
								dma1_addr_start[23:16] <= slv_dat_i[15: 8];
							if (slv_sel_i[0])
								dma1_addr_start[31:24] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma1_addr_start[23:16], dma1_addr_start[31:24]};
					end
					// dma1 current address
					8'h12: begin
						slv_dat0_o <= {dma1_addr_cur[7:2], 2'b00, dma1_addr_cur[15:8]};
						slv_dat0_o2 <= {dma1_addr_cur[23:16], dma1_addr_cur[31:24]};
					end
					8'h13: begin
						slv_dat0_o <= slv_dat0_o2;
					end
`ifdef ENABLE_PHY2
					// dma2 start address
					8'h14: begin
						if (slv_we_i) begin
							dma2_load <= 1'b1;
							if (slv_sel_i[1])
								dma2_addr_start[ 7: 2] <= slv_dat_i[15:10];
							if (slv_sel_i[0])
								dma2_addr_start[15: 8] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma2_addr_start[7:2], 2'b00, dma2_addr_start[15:8]};
					end
					8'h15: begin
						if (slv_we_i) begin
							dma2_load <= 1'b1;
							if (slv_sel_i[1])
								dma2_addr_start[23:16] <= slv_dat_i[15: 8];
							if (slv_sel_i[0])
								dma2_addr_start[31:24] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {dma2_addr_start[23:16], dma2_addr_start[31:24]};
					end
					// dma2 current address
					8'h16: begin
						slv_dat0_o <= {dma2_addr_cur[7:2], 2'b00, dma2_addr_cur[15:8]};
						slv_dat0_o2 <= {dma2_addr_cur[23:16], dma2_addr_cur[31:24]};
					end
					8'h17: begin
						slv_dat0_o <= slv_dat0_o2;
					end
`endif
					// TX0 write ptr
					8'h18: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								tx0mem_wr_ptr[ 7:0] <= slv_dat_i[15: 8];
							if (slv_sel_i[0])
								tx0mem_wr_ptr[13:8] <= slv_dat_i[ 5: 0];
						end else
							slv_dat0_o <= {tx0mem_wr_ptr[7:0], 2'b00, tx0mem_wr_ptr[13:8]};
					end
					// TX1 write ptr
					8'h19: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								tx1mem_wr_ptr[ 7:0] <= slv_dat_i[15: 8];
							if (slv_sel_i[0])
								tx1mem_wr_ptr[13:8] <= slv_dat_i[ 5: 0];
						end else
							slv_dat0_o <= {tx1mem_wr_ptr[7:0], 2'b00, tx1mem_wr_ptr[13:8]};
					end
					// TX0 read ptr
					8'h1a: begin
						slv_dat0_o <= {tx0mem_rd_ptr[7:0], 2'b00, tx0mem_rd_ptr[13:8]};
					end
					// TX1 read ptr
					8'h1b: begin
						slv_dat0_o <= {tx1mem_rd_ptr[7:0], 2'b00, tx1mem_rd_ptr[13:8]};
					end
					// local time 1 [15:0]
					8'h80: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								local_time1[ 7:0] <= slv_dat_i[15: 8];
						if (slv_sel_i[0])
								local_time1[15:8] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {local_time1[7:0], local_time1[15:8]};
					end
					// local time 1 [31:16]
					8'h81: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								local_time1[23:16] <= slv_dat_i[15: 8];
						if (slv_sel_i[0])
								local_time1[31:24] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {local_time1[23:16], local_time1[31:24]};
					end
					// local time 1 [47:32]
					8'h82: begin
						if (slv_we_i) begin
							if (slv_sel_i[1])
								local_time1[39:32] <= slv_dat_i[15: 8];
						if (slv_sel_i[0])
								local_time1[47:40] <= slv_dat_i[ 7: 0];
						end else
							slv_dat0_o <= {local_time1[39:32], local_time1[47:40]};
					end
					// local time 2 [15:0]
					// local time 2 [31:16]
					// local time 2 [47:32]
					// local time 3 [15:0]
					// local time 3 [31:16]
					// local time 3 [47:32]
					// local time 4 [15:0]
					// local time 4 [31:16]
					// local time 4 [47:32]
					// local time 5 [15:0]
					// local time 5 [31:16]
					// local time 5 [47:32]
					// local time 6 [15:0]
					// local time 6 [31:16]
					// local time 6 [47:32]
					// local time 7 [15:0]
					// local time 7 [31:16]
					// local time 7 [47:32]
					default:
						slv_dat0_o <= 16'h0; // slv_adr_i[16:1];
				endcase
			end else
				slv_dat0_o <= 16'h0; // slv_adr_i[16:1];
		end else begin
			if (local_time_update_pending[0]) begin
				local_time1           <= global_counter - 48'h3;
				local_time_update_ack <= 1'b1;
			end else if (local_time_update_pending[1]) begin
				local_time2           <= global_counter - 48'h3;
				local_time_update_ack <= 1'b1;
			end else if (local_time_update_pending[2]) begin
				local_time3           <= global_counter - 48'h3;
				local_time_update_ack <= 1'b1;
			end else if (local_time_update_pending[3]) begin
				local_time4           <= global_counter - 48'h3;
				local_time_update_ack <= 1'b1;
			end else if (local_time_update_pending[4]) begin
				local_time5           <= global_counter - 48'h3;
				local_time_update_ack <= 1'b1;
			end else if (local_time_update_pending[5]) begin
				local_time6           <= global_counter - 48'h3;
				local_time_update_ack <= 1'b1;
			end else if (local_time_update_pending[6]) begin
				local_time7           <= global_counter - 48'h3;
				local_time_update_ack <= 1'b1;
			end else begin
				local_time_update_ack <= 1'b0;
			end
		end
	end
end

assign slv_dat_o = ( {16{slv_bar_i[0]}} & slv_dat0_o ) | ( {16{slv_bar_i[2] & ~slv_adr_i[15]}} & slv_dat1_o ) | ( {16{slv_bar_i[2] & slv_adr_i[15]}} & slv_dat2_o );

assign sys_intr = dma_status[3];

endmodule

`default_nettype wire
