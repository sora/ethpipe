module top  (
   input rstn,
   input FLIP_LANES,
   input refclkp,
   input refclkn,
   input hdinp,
   input hdinn,
   output hdoutp,
   output hdoutn,
   input [7:0] dip_switch,
   output [13:0] led_out,
   output dp,
   input reset_n,
 // Ethernet PHY#1
    output phy1_rst_n,
    input phy1_125M_clk,
    input phy1_tx_clk,
    output phy1_gtx_clk,
    output phy1_tx_en,
    output [7:0] phy1_tx_data,
    input phy1_rx_clk,
    input phy1_rx_dv,
    input phy1_rx_er,
    input [7:0] phy1_rx_data,
    input phy1_col,
    input phy1_crs,
    output phy1_mii_clk,
    inout phy1_mii_data,
// Ethernet PHY#2
    output phy2_rst_n,
    input phy2_125M_clk,
    input phy2_tx_clk,
    output phy2_gtx_clk,
    output phy2_tx_en,
    output [7:0] phy2_tx_data,
    input phy2_rx_clk,
    input phy2_rx_dv,
    input phy2_rx_er,
    input [7:0] phy2_rx_data,
    input phy2_col,
    input phy2_crs,
    output phy2_mii_clk,
    inout phy2_mii_data
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

wire [7:0] bus_num ;
wire [4:0] dev_num ;
wire [2:0] func_num ;

wire [8:0] tx_ca_ph ;
wire [12:0] tx_ca_pd  ;
wire [8:0] tx_ca_nph ;
wire [12:0] tx_ca_npd ;
wire [8:0] tx_ca_cplh;
wire [12:0] tx_ca_cpld ;
wire clk_125;
wire tx_eop_wbm;
// Reset management
always @(posedge clk_125 or negedge rstn) begin
   if (!rstn) begin
       rstn_cnt   <= 21'd0 ;
       core_rst_n <= 1'b0 ;
   end else begin
      if (rstn_cnt[20])            // 4ms in real hardware
         core_rst_n <= 1'b1 ;
      else
         rstn_cnt <= rstn_cnt + 1'b1 ;
   end
end

reg rx_st_d;
reg tx_st_d;
reg [15:0] tx_tlp_cnt;
reg [15:0] rx_tlp_cnt;
always @(posedge clk_125 or negedge core_rst_n)
   if (!core_rst_n) begin
      tx_st_d <= 0;
      rx_st_d <= 0;
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


//-----------------------------------
// RX slot (inoutA: PCIe, inoutB: ethernet)
//-----------------------------------
reg [15:0]  mem_dataA;
reg [15:0]  mem_dataB;
reg [ 1:0]  mem_byte_enA;
reg [ 1:0]  mem_byte_enB;
reg [11:0]  mem_addressA;
reg [11:0]  mem_addressB;
reg         mem_wr_enA;
reg         mem_wr_enB;
wire [15:0] mem_qA;
wire [15:0] mem_qB;
ram_dp_true mem0read (
    .DataInA(mem_dataA)
  , .DataInB(mem_dataB)
  , .ByteEnA(mem_byte_enA)
  , .ByteEnB(mem_byte_enB)
  , .AddressA(mem_addressA)
  , .AddressB(mem_addressB)
  , .ClockA(clk_125)
  , .ClockB(phy1_rx_clk)
  , .ClockEnA(core_rst_n)
  , .ClockEnB(core_rst_n)
  , .WrA(mem_wr_enA)
  , .WrB(mem_wr_enB)
  , .ResetA(~core_rst_n)
  , .ResetB(~core_rst_n)
  , .QA(mem_qA)
  , .QB(mem_qB)
);

//-----------------------------------
// TX slot (inoutA: PCIe, inoutB: ethernet)
//-----------------------------------

//-------------------------------------
// PYH cold reset
//-------------------------------------
reg [9:0] coldsys_rst = 0;
assign coldsys_rst520 = (coldsys_rst==10'd520);
always @(posedge clk_125)
    coldsys_rst <= !coldsys_rst520 ? coldsys_rst + 10'd1 : 10'd520;
assign phy1_rst_n = coldsys_rst520 & reset_n;

//-------------------------------------
// PHY tmp wire
//-------------------------------------
assign phy1_mii_clk = 1'b0;
assign phy1_mii_data = 1'b0;
assign phy1_tx_en = 1'b0;
assign phy1_tx_data = 8'h0;
assign phy1_gtx_clk = phy1_125M_clk;

//-------------------------------------
// PCI I/O memory mapping
//-------------------------------------
assign rd = ~pcie_we && pcie_cyc && pcie_stb;
assign wr = pcie_we && pcie_cyc && pcie_stb;
reg [15:0] wb_dat;
reg wb_ack;
assign next_wb_ack = ~wb_ack && pcie_cyc && pcie_stb;
reg [ 1:0] waiting;
reg [15:0] prev_data = 16'h0;
reg [ 3:0] slots_status;
reg [31:0] global_counter;

wire rx1_ready;
wire rx1_done;
clk_sync rx1_rdy (
    .clk1 (clk_125)
  , .i    (slots_status[1])
  , .clk2 (phy1_rx_clk)
  , .o    (rx1_ready)
);
clk_sync2 rx1_don (
    .clk1 (phy1_rx_clk)
  , .i    (rx1_status[1])
  , .clk2 (clk_125)
  , .o    (rx1_done)
);

pcie_top pcie(
   .refclkp                    ( refclkp ),
   .refclkn                    ( refclkn ),
   .sys_clk_125                ( clk_125 ),
   .ext_reset_n                ( rstn ),
   .rstn                       ( core_rst_n ),
   .flip_lanes                 ( FLIP_LANES ),
   .hdinp0                     ( hdinp ),
   .hdinn0                     ( hdinn ),
   .hdoutp0                    ( hdoutp ),
   .hdoutn0                    ( hdoutn ),
   .msi                        (  8'd0 ),
   .inta_n                     (  ~rx1_done ),
   // This PCIe interface uses dynamic IDs.
   .vendor_id                  (16'h3776),
   .device_id                  (16'h8001),
   .rev_id                     (8'h00),
   .class_code                 (24'h000000),
   .subsys_ven_id              (16'h3776),
   .subsys_id                  (16'h8001),
   .load_id                    (1'b1),
   // Inputs
   .force_lsm_active           ( 1'b0 ),
   .force_rec_ei               ( 1'b0 ),
   .force_phy_status           ( 1'b0 ),
   .force_disable_scr          ( 1'b0 ),
   .hl_snd_beacon              ( 1'b0 ),
   .hl_disable_scr             ( 1'b0 ),
   .hl_gto_dis                 ( 1'b0 ),
   .hl_gto_det                 ( 1'b0 ),
   .hl_gto_hrst                ( 1'b0 ),
   .hl_gto_l0stx               ( 1'b0 ),
   .hl_gto_l1                  ( 1'b0 ),
   .hl_gto_l2                  ( 1'b0 ),
   .hl_gto_l0stxfts            ( 1'b0 ),
   .hl_gto_lbk                 ( 1'd0 ),
   .hl_gto_rcvry               ( 1'b0 ),
   .hl_gto_cfg                 ( 1'b0 ),
   .no_pcie_train              ( 1'b0 ),
   // Power Management Interface
   .tx_dllp_val                ( 2'd0 ),
   .tx_pmtype                  ( 3'd0 ),
   .tx_vsd_data                ( 24'd0 ),
   .tx_req_vc0                 ( tx_req ),
   .tx_data_vc0                ( tx_data ),
   .tx_st_vc0                  ( tx_st ),
   .tx_end_vc0                 ( tx_end ),
   .tx_nlfy_vc0                ( 1'b0 ),
   .ph_buf_status_vc0       ( 1'b0 ),
   .pd_buf_status_vc0       ( 1'b0 ),
   .nph_buf_status_vc0      ( 1'b0 ),
   .npd_buf_status_vc0      ( 1'b0 ),
   .ph_processed_vc0        ( ph_cr ),
   .pd_processed_vc0        ( pd_cr ),
   .nph_processed_vc0       ( nph_cr ),
   .npd_processed_vc0       ( npd_cr ),
   .pd_num_vc0              ( pd_num ),
   .npd_num_vc0             ( 8'd1 ),
   // From User logic
   .cmpln_tout                 ( 1'b0 ),
   .cmpltr_abort_np            ( 1'b0 ),
   .cmpltr_abort_p             ( 1'b0 ),
   .unexp_cmpln                ( 1'b0 ),
   .ur_np_ext                  ( 1'b0 ),
   .ur_p_ext                   ( 1'b0 ),
   .np_req_pend                ( 1'b0 ),
   .pme_status                 ( 1'b0 ),
   .tx_rdy_vc0                 ( tx_rdy),
   .tx_ca_ph_vc0               ( tx_ca_ph),
   .tx_ca_pd_vc0               ( tx_ca_pd),
   .tx_ca_nph_vc0              ( tx_ca_nph),
   .tx_ca_npd_vc0              ( tx_ca_npd ),
   .tx_ca_cplh_vc0             ( tx_ca_cplh ),
   .tx_ca_cpld_vc0             ( tx_ca_cpld ),
   .tx_ca_p_recheck_vc0        ( tx_ca_p_recheck ),
   .tx_ca_cpl_recheck_vc0      ( tx_ca_cpl_recheck ),
   .rx_data_vc0                ( rx_data),
   .rx_st_vc0                  ( rx_st),
   .rx_end_vc0                 ( rx_end),
   .rx_us_req_vc0              ( rx_us_req ),
   .rx_malf_tlp_vc0            ( rx_malf_tlp ),
   .rx_bar_hit                 ( rx_bar_hit ),
   // From Config Registers
   .bus_num                    ( bus_num  ),
   .dev_num                    ( dev_num  ),
   .func_num                   ( func_num  )
);

always @(posedge clk_125 or negedge core_rst_n) begin
    if (!core_rst_n) begin
        wb_dat         <= 16'h0;
        mem_dataA      <= 16'h0;
        mem_wr_enA     <=  1'b0;
        mem_byte_enA   <=  2'b0;
        mem_addressA   <= 12'b0;
        global_counter <= 32'b0;
    end else begin
        waiting <= 2'h0;
        wb_ack  <= 1'b0;
        global_counter <= global_counter + 32'b1;

        if (rx1_done)
            slots_status[1:0] <= 2'b01;

        mem_wr_enA <= 1'b0;
        case (pcie_adr[15:13])
            // global config
            3'b000: begin
                wb_ack <= next_wb_ack;
                if (pcie_adr[12:3] == 10'b0) begin
                    case (pcie_adr[3:1])
                        // slots status
                        3'd0: begin
                            if (rd) begin
                                wb_dat <= { 12'b0, slots_status };
                            end else if (wr) begin
                                if (pcie_sel[1])
                                    slots_status <= pcie_dat_o[3:0];
                            end
                        end
                        // global counter [15:0]
                        3'd1: begin
                            if (rd) begin
                                wb_dat <= global_counter[15:0];
                            end else if (wr) begin
                                if (pcie_sel[0])
                                    global_counter[7:0] <= pcie_dat_o[15:8];
                                if (pcie_sel[1])
                                    global_counter[15:8] <= pcie_dat_o[7:0];
                            end
                        end
                        // global counter [31:16]
                        3'd2: begin
                            if (rd) begin
                                wb_dat <= global_counter[31:16];
                            end else if (wr) begin
                                if (pcie_sel[0])
                                    global_counter[23:16] <= pcie_dat_o[15:8];
                                if (pcie_sel[1])
                                    global_counter[31:24] <= pcie_dat_o[7:0];
                            end
                        end
                        default:
                            if (rd)
                                wb_dat <= 16'h0;
                    endcase
                end else begin
                    if (rd)
                        wb_dat <= 16'h0;
                end
            end
            // RX0
            //3'b000: begin
            //end
            // TX0
            //3'b000: begin
            //end
            // RX1
            3'b100: begin
                if (pcie_adr[12:3] == 10'b0) begin
                    wb_ack <= next_wb_ack;
                    case (pcie_adr[3:1])
                        // rx timestamp [15:0]
                        3'd0: begin
                            if (rd)
                                wb_dat <= rx_timestamp[15:0];
                        end
                        // rx timestamp [31:16]
                        3'd1: begin
                            if (rd)
                                wb_dat <= rx_timestamp[31:16];
                        end
                        // rx frame length
                        3'd2: begin
                            if (rd)
                                wb_dat <= { 4'b0, rx_frame_len[11:0] };
                        end
                        default:
                            if (rd)
                                wb_dat <= 16'h0;
                    endcase
                end else begin
                    if (rd) begin
                        if (waiting == 2'h0) begin
                            mem_addressA <= pcie_adr[12:1];
                        end else if (waiting == 2'h2) begin
                            wb_ack  <= next_wb_ack;
                            wb_dat  <= mem_qA;
                            waiting <= 2'h0;
                        end
                        waiting <= waiting + 2'h1;
                    end else if (wr) begin
                        wb_ack <= next_wb_ack;
                        mem_wr_enA   <= 1'b1;
                        mem_addressA <= pcie_adr[12:1];
                        mem_byte_enA <= {pcie_sel[0], pcie_sel[1]};
                        if (pcie_sel[0])
                            mem_dataA[15:8] <= pcie_dat_o[15:8];
                        if (pcie_sel[1])
                            mem_dataA[7:0] <= pcie_dat_o[7:0];
                    end
                end
            end
            // TX1
            //3'b101: begin
            //end
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


//-------------------------------------
// Ether frame receiver
//-------------------------------------
reg [1:0] rx1_status;
parameter [1:0]
    RX_IDLE = 2'b00
  , RX_LOAD = 2'b01
  , RX_DONE = 2'b10;
reg [11:0] rx_counter;
reg [31:0] rx_timestamp;
reg [11:0] rx_frame_len;
reg        rx_active;
always @(posedge phy1_rx_clk) begin
    if (!core_rst_n) begin
        mem_wr_enB   <=  1'b0;
        mem_addressB <= 12'b0;
        mem_dataB    <= 16'b0;
        rx_counter   <= 12'b0;
        rx_timestamp <= 32'b0;
        rx_frame_len <= 12'b0;
        rx1_status   <=  2'b0;
        rx_active    <=  1'b0;
    end else begin
        if (rx_active == 1'b0) begin
            rx_counter <= 12'b0;
            if (rx1_ready == 1'b1 && phy1_rx_dv == 1'b0)
                rx_active <= 1'b1;
         end else begin
            mem_wr_enB <= 1'b0;
            rx1_status <= RX_IDLE;
            if (phy1_rx_dv) begin
                rx1_status <= RX_LOAD;
                // write receive timestamp
                if (!rx_counter)
                    rx_timestamp <= global_counter;
                mem_wr_enB <= 1'b1;
                if (rx_counter[0]) begin
                    mem_byte_enB <= 2'b10;
                    mem_dataB    <= {phy1_rx_data, 8'b0};
                end else begin
                    mem_byte_enB <= 2'b01;
                    mem_dataB    <= {8'b0, phy1_rx_data};
                    mem_addressB <= mem_addressB + 12'd1;
                end
                rx_counter <= rx_counter + 12'b1;
            end else begin
                // frame terminated
                if (rx_counter != 12'b0) begin
                    rx_frame_len <= rx_counter;
                    rx_counter   <= 12'b0;
                    mem_addressB <= 12'd2;
                    rx1_status   <= RX_DONE;
                    rx_active    <= 1'b0;
                end
            end
        end
    end
end

assign led_out[0] = ~rx_active;

endmodule

