`include "setup.v"

module ethpipe_mid  (
    input  clk_125
  , input  sys_rst
  , input  [7:0] dip_switch
  , output [13:0] led_out
  , output dp
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


// Slave bus
wire [6:0] slv_bar_i;
wire slv_ce_i;
wire slv_we_i;
wire [19:1] slv_adr_i;
wire [15:0] slv_dat_i;
wire [1:0] slv_sel_i;
wire [15:0] slv_dat_o, slv_dat1_o, slv_dat2_o;
reg [15:0] slv_dat0_o;

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

reg [3:0] rx_slots_status = 4'b0000;
reg [3:0] tx_slots_status = 4'b0000;

//-------------------------------------
// ethpipe Port0
//-------------------------------------

// Slot0 RX (A: host, B: ethernet)
reg  [15:0] mem0_dataA;
reg  [ 1:0] mem0_byte_enA;
reg  [11:0] mem0_addressA;
reg         mem0_wr_enA;
wire [15:0] mem0_qA;
wire [15:0] mem0_dataB;
wire [ 1:0] mem0_byte_enB;
wire [11:0] mem0_addressB;
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
  , .ClockEnA(slv_ce_i & slv_bar_i[2] & ~slv_adr_i[13])
  , .ClockEnB(1'b1)
  , .WrA(slv_we_i)
  , .WrB(mem0_wr_enB)
  , .ResetA(sys_rst)
  , .ResetB(sys_rst)
  , .QA(slv_dat1_o)
  , .QB(mem0_qB)
);

// Slot1 RX (A: host, B: ethernet)
reg  [15:0] mem1_dataA;
reg  [ 1:0] mem1_byte_enA;
reg  [11:0] mem1_addressA;
reg         mem1_wr_enA;
wire [15:0] mem1_qA;
wire [15:0] mem1_dataB;
wire [ 1:0] mem1_byte_enB;
wire [11:0] mem1_addressB;
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
  , .ClockEnA(slv_ce_i & slv_bar_i[2] & slv_adr_i[13])
  , .ClockEnB(1'b1)
  , .WrA(slv_we_i)
  , .WrB(mem1_wr_enB)
  , .ResetA(sys_rst)
  , .ResetB(sys_rst)
  , .QA(slv_dat2_o)
  , .QB(mem1_qB)
);


reg         global_counter_rst;
wire [63:0] global_counter;
wire        slot0_rx_ready;
wire        slot1_rx_ready;
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


//-------------------------------------
// PCI I/O memory mapping
//-------------------------------------
reg [13:0] segledr;
always @(posedge clk_125) begin
	if (sys_rst == 1'b1) begin
		slv_dat0_o <= 16'h0;
		segledr[13:0] <= 14'h3fff;
	end else begin
		if (slv_bar_i[0] & slv_ce_i) begin
			case (slv_adr_i[4:1])
                        	// slots status
				4'b0000: begin
					if (slv_we_i) begin
						if (slv_sel_i[0])
                                    			rx_slots_status <= slv_dat_i[3:0];
					end else
						slv_dat0_o <= { 12'b0, rx_slots_status };
				end
				// global counter [15:0]
				4'b0010: begin
					if (~slv_we_i) begin
						slv_dat0_o <= global_counter[15:0];
					end
				end
				// global counter [31:16]
				4'b0011: begin
					if (~slv_we_i) begin
						slv_dat0_o <= global_counter[31:16];
					end
				end
				// global counter [47:32]
				4'b0100: begin
					if (~slv_we_i) begin
						slv_dat0_o <= global_counter[47:32];
					end
				end
				// global counter [63:48]
				4'b0101: begin
					if (~slv_we_i) begin
						slv_dat0_o <= global_counter[63:48];
					end
				end
				default: begin
					slv_dat0_o <= 16'h0; // slv_adr_i[16:1];
				end
			endcase
		end
	end
end

assign slv_dat_o = ( {16{slv_bar_i[0]}} & slv_dat0_o ) | ( {16{slv_bar_i[2] & ~slv_adr_i[13]}} & slv_dat1_o ) | ( {16{slv_bar_i[2] & slv_adr_i[13]}} & slv_dat2_o );

endmodule
