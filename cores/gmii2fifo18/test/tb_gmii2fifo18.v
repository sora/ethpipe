module tb_gmii2fifo18();

/* 125MHz system clock */
reg sys_clk;
initial sys_clk = 1'b0;
always #8 sys_clk = ~sys_clk;

/* 33MHz PCI clock */
reg pci_clk;
initial pci_clk = 1'b0;
always #30 pci_clk = ~pci_clk;

/* 62.5MHz CPCI clock */
reg cpci_clk;
initial cpci_clk = 1'b0;
always #16 cpci_clk = ~cpci_clk;

/* 125MHz RX clock */
reg phy_rx_clk;
initial phy_rx_clk = 1'b0;
always #8 phy_rx_clk = ~phy_rx_clk;

/* 125MHz TX clock */
reg phy_tx_clk;
initial phy_tx_clk = 1'b0;
always #8 phy_tx_clk = ~phy_tx_clk;


reg sys_rst;
reg phy_rx_dv;
reg [7:0] phy_rxd;
wire [17:0] data_din, len_din;
reg data_full, len_full;
wire data_wr_en, len_wr_en;
wire wr_clk;
reg [63:0] global_counter;

gmii2fifo18 # (
        .Gap(4'h4)
) gmii2fifo18_tb (
        .sys_rst(sys_rst),
	.global_counter(global_counter),

        .gmii_rx_clk(phy_rx_clk),
        .gmii_rx_dv(phy_rx_dv),
        .gmii_rxd(phy_rxd),

        .data_din(data_din),
        .data_full(data_full),
        .data_wr_en(data_wr_en),

        .len_din(len_din),
        .len_full(len_full),
        .len_wr_en(len_wr_en),

        .wr_clk()
);

task waitclock;
begin
	@(posedge phy_rx_clk);
	#1;
end
endtask

always @(posedge phy_rx_clk) begin
	if (data_wr_en == 1'b1)
		$display("din: %05x", data_din);
end

reg [8:0] rom [0:199];
reg [11:0] counter;

always @(posedge phy_rx_clk) begin
	{phy_rx_dv,phy_rxd} <= rom[ counter ];
	counter <= counter + 1;
	global_counter <= global_counter + 64'h1;
end

initial begin
        $dumpfile("./test.vcd");
	$dumpvars(0, tb_gmii2fifo18); 
	$readmemh("./phy_rx.hex", rom);
	/* Reset / Initialize our logic */
	sys_rst = 1'b1;
	data_full = 1'b0;
	global_counter <= 64'h0;
	counter = 0;

	waitclock;
	waitclock;

	sys_rst = 1'b0;

	waitclock;


	#30000;

	$finish;
end

endmodule
