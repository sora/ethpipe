`default_nettype none

//`include "../rtl/setup.v"

//`define DEBUG

module ethpipe (
  // system
    input  wire        sys_rst

  , input  wire [63:0] global_counter

  // GMII interfaces
  , input  wire        gmii_tx_clk
  , output wire [ 7:0] gmii_txd
  , output wire        gmii_tx_en
  , input  wire [ 7:0] gmii_rxd
  , input  wire        gmii_rx_dv
  , input  wire        gmii_rx_clk

  // PCI user registers
  , input  wire        pci_clk

  // RX frame slot
  , output reg  [31:0] slot_rx_eth_data
  , output reg  [ 3:0] slot_rx_eth_byte_en
  , output reg  [10:0] slot_rx_eth_address
  , output reg         slot_rx_eth_wr_en
  , input  wire [31:0] slot_rx_eth_q

  , output reg  [63:0] rx_timestamp
  , output reg  [11:0] rx_frame_len
  , input  wire        rx_empty       // RX slot empty
  , output wire        rx_complete    // Received a ethernet frame
);


//-------------------------------------
// Ether frame receiver
//-------------------------------------
parameter [1:0]    // RX status
    RX_IDLE = 2'b00
  , RX_LOAD = 2'b01
  , RX_DONE = 2'b10;
reg [ 1:0] rx_status;
reg [11:0] rx_counter;
reg        rx_active;
wire       rx_ready;
always @(posedge gmii_rx_clk) begin
    if (sys_rst) begin
        slot_rx_eth_wr_en   <=  1'b0;
        slot_rx_eth_address <= 11'b0;
        slot_rx_eth_data    <= 32'b0;
        rx_counter          <= 12'b0;
        rx_timestamp        <= 64'b0;
        rx_frame_len        <= 12'b0;
        rx_status           <= RX_IDLE;
        rx_active           <=  1'b0;
    end else begin
        if (rx_active == 1'b0) begin
            rx_counter <= 12'b0;
            if (rx_ready == 1'b1 && gmii_rx_dv == 1'b0)
                rx_active <= 1'b1;
         end else begin
            slot_rx_eth_wr_en <= 1'b0;
            rx_status <= RX_IDLE;
            if (gmii_rx_dv) begin
                rx_counter <= rx_counter + 12'b1;
                rx_status  <= RX_LOAD;

                // write receive timestamp
                if (rx_counter != 12'h0)
                    rx_timestamp <= global_counter;
                slot_rx_eth_wr_en <= 1'b1;
                case (rx_counter[1:0])
                    2'b00: begin
                        slot_rx_eth_byte_en <= 4'b0001;
                        slot_rx_eth_data    <= {24'h0, gmii_rxd};
                        slot_rx_eth_address <= slot_rx_eth_address + 12'd1;
                    end
                    2'b01: begin
                        slot_rx_eth_byte_en <= 4'b0010;
                        slot_rx_eth_data    <= {16'h0, gmii_rxd, 8'h0};
                    end
                    2'b10: begin
                        slot_rx_eth_byte_en <= 4'b0100;
                        slot_rx_eth_data    <= {8'h0, gmii_rxd, 16'h0};
                    end
                    2'b11: begin
                        slot_rx_eth_byte_en <= 4'b1000;
                        slot_rx_eth_data    <= {gmii_rxd, 24'h0};
                    end
                endcase
            end else begin
                // frame terminated
                if (rx_counter != 12'h0) begin
                    rx_frame_len <= rx_counter - 12'h8;
                    rx_counter   <= 12'b0;
                    slot_rx_eth_address <= 12'd2;
                    rx_status <= RX_DONE;
                    rx_active <= 1'b0;
                end
            end
        end
    end
end


//-------------------------------------
// clock sync
//-------------------------------------
clk_sync pcie2gmii_sync (
    .clk1 (pci_clk)
  , .i    (rx_empty)
  , .clk2 (gmii_rx_clk)
  , .o    (rx_ready)
);
clk_sync_ashot gmii2pcie_sync (
    .clk1 (gmii_rx_clk)
  , .i    (rx_status[1])
  , .clk2 (pci_clk)
  , .o    (rx_complete)
);

endmodule

`default_nettype wire
