module top  (
    input  rstn
  , input  FLIP_LANES
  , input  refclkp
  , input  refclkn
  , input  hdinp
  , input  hdinn
  , output hdoutp
  , output hdoutn
  , input  [7:0] dip_switch
  , output [13:0] led_out
  , output dp
  , input  reset_n

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

reg  [20:0] rstn_cnt;
reg  core_rst_n;
wire [15:0] rx_data, tx_data,  tx_dout_wbm, tx_dout_ur;
wire [6:0] rx_bar_hit;
wire [7:0] pd_num, pd_num_ur, pd_num_wb;

wire [15:0] pcie_dat_i, pcie_dat_o;
wire [31:0] pcie_adr;
wire [1:0] pcie_sel;
wire [2:0] pcie_cti;
wire pcie_cyc;
wire pcie_we;
wire pcie_stb;
wire pcie_ack;

wire [7:0] bus_num;
wire [4:0] dev_num;
wire [2:0] func_num;

wire [8:0] tx_ca_ph;
wire [12:0] tx_ca_pd;
wire [8:0] tx_ca_nph;
wire [12:0] tx_ca_npd;
wire [8:0] tx_ca_cplh;
wire [12:0] tx_ca_cpld;
wire clk_125;
wire tx_eop_wbm;
// PCI Reset management
always @(posedge clk_125 or negedge rstn) begin
   if (!rstn) begin
       rstn_cnt   <= 21'd0;
       core_rst_n <= 1'b0;
   end else begin
      if (rstn_cnt[20])            // 4ms in real hardware
         core_rst_n <= 1'b1;
      else
         rstn_cnt <= rstn_cnt + 1'b1;
   end
end

reg [3:0] rx_slots_status = 4'b0000;
reg [3:0] tx_slots_status = 4'b0000;

pcie_top pcie (
    .refclkp                    ( refclkp )
  , .refclkn                    ( refclkn )
  , .sys_clk_125                ( clk_125 )
  , .ext_reset_n                ( rstn )
  , .rstn                       ( core_rst_n )
  , .flip_lanes                 ( FLIP_LANES )
  , .hdinp0                     ( hdinp )
  , .hdinn0                     ( hdinn )
  , .hdoutp0                    ( hdoutp )
  , .hdoutn0                    ( hdoutn )
  , .msi                        (  8'd0 )
  , .inta_n                     ( ~(rx_slots_status[0] | rx_slots_status[2]) )
  // This PCIe interface uses dynamic IDs.
  , .vendor_id                  (16'h3776)
  , .device_id                  (16'h8001)
  , .rev_id                     (8'h00)
  , .class_code                 (24'h000000)
  , .subsys_ven_id              (16'h3776)
  , .subsys_id                  (16'h8001)
  , .load_id                    (1'b1)
  // Inputs
  , .force_lsm_active           ( 1'b0 )
  , .force_rec_ei               ( 1'b0 )
  , .force_phy_status           ( 1'b0 )
  , .force_disable_scr          ( 1'b0 )
  , .hl_snd_beacon              ( 1'b0 )
  , .hl_disable_scr             ( 1'b0 )
  , .hl_gto_dis                 ( 1'b0 )
  , .hl_gto_det                 ( 1'b0 )
  , .hl_gto_hrst                ( 1'b0 )
  , .hl_gto_l0stx               ( 1'b0 )
  , .hl_gto_l1                  ( 1'b0 )
  , .hl_gto_l2                  ( 1'b0 )
  , .hl_gto_l0stxfts            ( 1'b0 )
  , .hl_gto_lbk                 ( 1'd0 )
  , .hl_gto_rcvry               ( 1'b0 )
  , .hl_gto_cfg                 ( 1'b0 )
  , .no_pcie_train              ( 1'b0 )
  // Power Management Interface
  , .tx_dllp_val                ( 2'd0 )
  , .tx_pmtype                  ( 3'd0 )
  , .tx_vsd_data                ( 24'd0 )
  , .tx_req_vc0                 ( tx_req )
  , .tx_data_vc0                ( tx_data )
  , .tx_st_vc0                  ( tx_st )
  , .tx_end_vc0                 ( tx_end )
  , .tx_nlfy_vc0                ( 1'b0 )
  , .ph_buf_status_vc0       ( 1'b0 )
  , .pd_buf_status_vc0       ( 1'b0 )
  , .nph_buf_status_vc0      ( 1'b0 )
  , .npd_buf_status_vc0      ( 1'b0 )
  , .ph_processed_vc0        ( ph_cr )
  , .pd_processed_vc0        ( pd_cr )
  , .nph_processed_vc0       ( nph_cr )
  , .npd_processed_vc0       ( npd_cr )
  , .pd_num_vc0              ( pd_num )
  , .npd_num_vc0             ( 8'd1 )
  // From User logic
  , .cmpln_tout                 ( 1'b0 )
  , .cmpltr_abort_np            ( 1'b0 )
  , .cmpltr_abort_p             ( 1'b0 )
  , .unexp_cmpln                ( 1'b0 )
  , .ur_np_ext                  ( 1'b0 )
  , .ur_p_ext                   ( 1'b0 )
  , .np_req_pend                ( 1'b0 )
  , .pme_status                 ( 1'b0 )
  , .tx_rdy_vc0                 ( tx_rdy)
  , .tx_ca_ph_vc0               ( tx_ca_ph)
  , .tx_ca_pd_vc0               ( tx_ca_pd)
  , .tx_ca_nph_vc0              ( tx_ca_nph)
  , .tx_ca_npd_vc0              ( tx_ca_npd )
  , .tx_ca_cplh_vc0             ( tx_ca_cplh )
  , .tx_ca_cpld_vc0             ( tx_ca_cpld )
  , .tx_ca_p_recheck_vc0        ( tx_ca_p_recheck )
  , .tx_ca_cpl_recheck_vc0      ( tx_ca_cpl_recheck )
  , .rx_data_vc0                ( rx_data)
  , .rx_st_vc0                  ( rx_st)
  , .rx_end_vc0                 ( rx_end)
  , .rx_us_req_vc0              ( rx_us_req )
  , .rx_malf_tlp_vc0            ( rx_malf_tlp )
  , .rx_bar_hit                 ( rx_bar_hit )
  // From Config Registers
  , .bus_num                    ( bus_num  )
  , .dev_num                    ( dev_num  )
  , .func_num                   ( func_num  )
);

reg rx_st_d;
reg tx_st_d;
reg [15:0] tx_tlp_cnt;
reg [15:0] rx_tlp_cnt;
always @(posedge clk_125 or negedge core_rst_n)
   if (!core_rst_n) begin
      tx_st_d    <= 0;
      rx_st_d    <= 0;
      tx_tlp_cnt <= 0;
      rx_tlp_cnt <= 0;
   end else begin
      tx_st_d <= tx_st;
      rx_st_d <= rx_st;
      if (tx_st_d) tx_tlp_cnt <= tx_tlp_cnt + 1;
      if (rx_st_d) rx_tlp_cnt <= rx_tlp_cnt + 1;
   end

ip_rx_crpr cr (.clk(clk_125), .rstn(core_rst_n), .rx_bar_hit(rx_bar_hit),
               .rx_st(rx_st), .rx_end(rx_end), .rx_din(rx_data),
               .pd_cr(pd_cr_ur), .pd_num(pd_num_ur), .ph_cr(ph_cr_ur), .npd_cr(npd_cr_ur), .nph_cr(nph_cr_ur)
);

ip_crpr_arb crarb(.clk(clk_125), .rstn(core_rst_n),
            .pd_cr_0(pd_cr_ur), .pd_num_0(pd_num_ur), .ph_cr_0(ph_cr_ur), .npd_cr_0(npd_cr_ur), .nph_cr_0(nph_cr_ur),
            .pd_cr_1(pd_cr_wb), .pd_num_1(pd_num_wb), .ph_cr_1(ph_cr_wb), .npd_cr_1(1'b0), .nph_cr_1(nph_cr_wb),
            .pd_cr(pd_cr), .pd_num(pd_num), .ph_cr(ph_cr), .npd_cr(npd_cr), .nph_cr(nph_cr)
);

ip_tx_arbiter #(.c_DATA_WIDTH (16))
           tx_arb(.clk(clk_125), .rstn(core_rst_n), .tx_val(1'b1),
                  .tx_req_0(tx_req_wbm), .tx_din_0(tx_dout_wbm), .tx_sop_0(tx_sop_wbm), .tx_eop_0(tx_eop_wbm), .tx_dwen_0(1'b0),
                  .tx_req_1(1'b0), .tx_din_1(16'd0), .tx_sop_1(1'b0), .tx_eop_1(1'b0), .tx_dwen_1(1'b0),
                  .tx_req_2(1'b0), .tx_din_2(16'd0), .tx_sop_2(1'b0), .tx_eop_2(1'b0), .tx_dwen_2(1'b0),
                  .tx_req_3(tx_req_ur), .tx_din_3(tx_dout_ur), .tx_sop_3(tx_sop_ur), .tx_eop_3(tx_eop_ur), .tx_dwen_3(1'b0),
                  .tx_rdy_0(tx_rdy_wbm), .tx_rdy_1(), .tx_rdy_2( ), .tx_rdy_3(tx_rdy_ur),
                  .tx_req(tx_req), .tx_dout(tx_data), .tx_sop(tx_st), .tx_eop(tx_end), .tx_dwen(),
                  .tx_rdy(tx_rdy)

);

wb_tlc wb_tlc(.clk_125(clk_125), .wb_clk(clk_125), .rstn(core_rst_n),
              .rx_data(rx_data), .rx_st(rx_st), .rx_end(rx_end), .rx_bar_hit(rx_bar_hit),
              .wb_adr_o(pcie_adr), .wb_dat_o(pcie_dat_o), .wb_cti_o(pcie_cti), .wb_we_o(pcie_we), .wb_sel_o(pcie_sel), .wb_stb_o(pcie_stb), .wb_cyc_o(pcie_cyc), .wb_lock_o(),
              .wb_dat_i(pcie_dat_i), .wb_ack_i(pcie_ack),
              .pd_cr(pd_cr_wb), .pd_num(pd_num_wb), .ph_cr(ph_cr_wb), .npd_cr(npd_cr_wb), .nph_cr(nph_cr_wb),
              .tx_rdy(tx_rdy_wbm),
              .tx_req(tx_req_wbm), .tx_data(tx_dout_wbm), .tx_st(tx_sop_wbm), .tx_end(tx_eop_wbm), .tx_ca_cpl_recheck(1'b0), .tx_ca_cplh(tx_ca_cplh), .tx_ca_cpld(tx_ca_cpld),
              .comp_id({bus_num, dev_num, func_num}),
              .debug()
);

//-------------------------------------
// PYH cold reset
//-------------------------------------
reg [9:0] coldsys_rst = 0;
wire coldsys_rst520 = (coldsys_rst==10'd520);
always @(posedge clk_125)
    coldsys_rst <= !coldsys_rst520 ? coldsys_rst + 10'd1 : 10'd520;
assign phy1_rst_n = coldsys_rst520 & reset_n;
assign phy2_rst_n = coldsys_rst520 & reset_n;

//-------------------------------------
// ethpipe Port0
//-------------------------------------

// Slot0 RX (A: host, B: ethernet)
reg  [31:0] mem0_dataA;
reg  [ 3:0] mem0_byte_enA;
reg  [10:0] mem0_addressA;
reg         mem0_wr_enA;
wire [31:0] mem0_qA;
wire [31:0] mem0_dataB;
wire [ 3:0] mem0_byte_enB;
wire [10:0] mem0_addressB;
wire        mem0_wr_enB;
wire [31:0] mem0_qB;
ram_dp_true mem0read (
    .DataInA(mem0_dataA)
  , .DataInB(mem0_dataB)
  , .ByteEnA(mem0_byte_enA)
  , .ByteEnB(mem0_byte_enB)
  , .AddressA(mem0_addressA)
  , .AddressB(mem0_addressB)
  , .ClockA(clk_125)
  , .ClockB(phy1_rx_clk)
  , .ClockEnA(core_rst_n)
  , .ClockEnB(core_rst_n)
  , .WrA(mem0_wr_enA)
  , .WrB(mem0_wr_enB)
  , .ResetA(~core_rst_n)
  , .ResetB(~core_rst_n)
  , .QA(mem0_qA)
  , .QB(mem0_qB)
);

// Slot1 RX (A: host, B: ethernet)
reg  [31:0] mem1_dataA;
reg  [ 3:0] mem1_byte_enA;
reg  [10:0] mem1_addressA;
reg         mem1_wr_enA;
wire [31:0] mem1_qA;
wire [31:0] mem1_dataB;
wire [ 3:0] mem1_byte_enB;
wire [10:0] mem1_addressB;
wire        mem1_wr_enB;
wire [31:0] mem1_qB;
ram_dp_true mem1read (
    .DataInA(mem1_dataA)
  , .DataInB(mem1_dataB)
  , .ByteEnA(mem1_byte_enA)
  , .ByteEnB(mem1_byte_enB)
  , .AddressA(mem1_addressA)
  , .AddressB(mem1_addressB)
  , .ClockA(clk_125)
  , .ClockB(phy2_rx_clk)
  , .ClockEnA(core_rst_n)
  , .ClockEnB(core_rst_n)
  , .WrA(mem1_wr_enA)
  , .WrB(mem1_wr_enB)
  , .ResetA(~core_rst_n)
  , .ResetB(~core_rst_n)
  , .QA(mem1_qA)
  , .QB(mem1_qB)
);


reg         global_counter_rst;
wire [63:0] global_counter;
wire        slot0_rx_ready;
wire        slot1_rx_ready;
ethpipe ethpipe_ins (
  // system
    .sys_rst(~core_rst_n)

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
assign rd = ~pcie_we && pcie_cyc && pcie_stb;
assign wr = pcie_we && pcie_cyc && pcie_stb;
reg [15:0] wb_dat;
reg wb_ack;
assign next_wb_ack = ~wb_ack && pcie_cyc && pcie_stb;
reg [ 1:0] mem_rd_waiting;
reg [15:0] prev_data = 16'h0;
always @(posedge clk_125 or negedge core_rst_n) begin
    if (!core_rst_n) begin
        wb_dat             <= 16'h0;
        global_counter_rst <= 1'b0;
        rx_slots_status    <= 4'b0;

        mem0_dataA         <= 32'h0;
        mem0_wr_enA        <= 1'b0;
        mem0_byte_enA      <= 4'b0;
        mem0_addressA      <= 11'b0;
        mem1_dataA         <= 32'h0;
        mem1_wr_enA        <= 1'b0;
        mem1_byte_enA      <= 4'b0;
        mem1_addressA      <= 11'b0;
    end else begin
        mem_rd_waiting <= 2'h0;
        wb_ack         <= 1'b0;

        global_counter_rst <= 1'b0;

        if (slot0_rx_ready) begin
            rx_slots_status[1:0] <= 2'b01;
        end

        if (slot1_rx_ready) begin
            rx_slots_status[3:2] <= 2'b01;
        end

        mem0_wr_enA <= 1'b0;
        case (pcie_adr[15:13])
            // global config
            3'b000: begin
                wb_ack <= next_wb_ack;
                if (pcie_adr[12:4] == 9'b0) begin
                    case (pcie_adr[3:1])
                        // slots status
                        3'b000: begin
                            if (rd) begin
                                wb_dat <= { 12'b0, rx_slots_status };
                            end else if (wr) begin
                                if (pcie_sel[1])
                                    rx_slots_status <= pcie_dat_o[3:0];
                            end
                        end
                        // global counter [15:0]
                        3'b010: begin
                            if (rd) begin
                                wb_dat <= global_counter[15:0];
                            end
                        end
                        // global counter [31:16]
                        3'b011: begin
                            if (rd) begin
                                wb_dat <= global_counter[31:16];
                            end
                        end
                        // global counter [47:32]
                        3'b100: begin
                            if (rd) begin
                                wb_dat <= global_counter[47:32];
                            end
                        end
                        // global counter [63:48]
                        3'b101: begin
                            if (rd) begin
                                wb_dat <= global_counter[63:48];
                            end
                        end
                        default:
                            if (rd) begin
                                wb_dat <= 16'h0;
                            end
                    endcase
                end else begin
                    if (rd) begin
                        wb_dat <= 16'h0;
                    end
                end
            end
            // RX0
            3'b100: begin
                wb_ack <= next_wb_ack;
                if (rd) begin
                    if (pcie_adr[1] == 1'b0) begin
                        if (mem_rd_waiting == 2'h0 || mem_rd_waiting == 2'h1) begin
                            mem0_addressA <= pcie_adr[12:2] + 12'h1;
                            wb_ack  <= 1'b0;
                        end else if (mem_rdwaiting == 2'h2) begin
                            wb_dat         <= mem0_qA[15:0];
                            mem_rd_waiting <= 2'h0;
                        end
                        mem_rd_waiting <= mem_rd_waiting + 2'h1;
                    end else begin
                        wb_dat <= mem0_qA[31:16];
                    end
                end else if (wr) begin
                    mem0_wr_enA   <= 1'b1;
                    mem0_addressA <= pcie_adr[12:2] + 12'h1;
                    if (pcie_adr[1] == 1'b0) begin
                        mem0_byte_enA <= {2'b00, pcie_sel[0], pcie_sel[1]};
                        if (pcie_sel[0])
                            mem0_dataA[15:8] <= pcie_dat_o[15:8];
                        if (pcie_sel[1])
                            mem0_dataA[7:0]  <= pcie_dat_o[7:0];
                    end else begin
                        mem0_byte_enA <= {pcie_sel[0], pcie_sel[1], 2'b00};
                        if (pcie_sel[0])
                            mem0_dataA[31:24] <= pcie_dat_o[15:8];
                        if (pcie_sel[1])
                            mem0_dataA[23:16] <= pcie_dat_o[7:0];
                    end
                end
            end
            // RX1
            3'b101: begin
                wb_ack <= next_wb_ack;
                if (rd) begin
                    if (pcie_adr[1] == 1'b0) begin
                        if (mem_rd_waiting == 2'h0 || mem_rd_waiting == 2'h1) begin
                            mem1_addressA <= pcie_adr[12:2] + 12'h1;
                            wb_ack  <= 1'b0;
                        end else if (mem_rd_waiting == 2'h2) begin
                            wb_dat         <= mem1_qA[15:0];
                            mem_rd_waiting <= 2'h0;
                        end
                        mem_rd_waiting <= mem_rd_waiting + 2'h1;
                    end else begin
                        wb_dat <= mem1_qA[31:16];
                    end
                end else if (wr) begin
                    mem1_wr_enA   <= 1'b1;
                    mem1_addressA <= pcie_adr[12:2] + 12'h1;
                    if (pcie_adr[1] == 1'b0) begin
                        mem1_byte_enA <= {2'b00, pcie_sel[0], pcie_sel[1]};
                        if (pcie_sel[0])
                            mem1_dataA[15:8] <= pcie_dat_o[15:8];
                        if (pcie_sel[1])
                            mem1_dataA[7:0] <= pcie_dat_o[7:0];
                    end else begin
                        mem1_byte_enA <= {pcie_sel[0], pcie_sel[1], 2'b00};
                        if (pcie_sel[0])
                            mem1_dataA[31:24] <= pcie_dat_o[15:8];
                        if (pcie_sel[1])
                            mem1_dataA[23:16] <= pcie_dat_o[7:0];
                    end
                end
            end
            default: begin
                wb_ack <= next_wb_ack;
                if (rd)
                    wb_dat <= 16'h0;
            end
        endcase
    end
end
assign pcie_dat_i = wb_dat;
assign pcie_ack   = wb_ack;

endmodule
