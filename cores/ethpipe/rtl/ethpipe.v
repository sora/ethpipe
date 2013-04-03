`default_nettype none

//`include "../rtl/setup.v"

//`define DEBUG

module ethpipe (
  // system
    input  wire        sys_rst
  , input  wire [31:0] global_counter

  // GMII interfaces
  , input  wire        gmii_tx_clk
  , output wire [ 7:0] gmii_txd
  , output wire        gmii_tx_en
  , input  wire [ 7:0] gmii_rxd
  , input  wire        gmii_rx_dv
  , input  wire        gmii_rx_clk

  // PCI user registers

  // RX frame slot
  , input  wire [15:0] slot_rx_host_data
  , input  wire [ 1:0] slot_rx_host_byte_en
  , input  wire [11:0] slot_rx_host_address
  , input  wire        slot_rx_host_wr_en
  , input  wire [15:0] slot_rx_host_q
  , output reg  [15:0] slot_rx_eth_data
  , output reg  [ 1:0] slot_rx_eth_byte_en
  , output reg  [11:0] slot_rx_eth_address
  , output reg         slot_rx_eth_wr_en
  , input  wire [15:0] slot_rx_eth_q

  , output reg  [31:0] rx_timestamp
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
always @(posedge gmii_rx_clk) begin
    if (sys_rst) begin
        slot_rx_eth_wr_en   <=  1'b0;
        slot_rx_eth_address <= 12'b0;
        slot_rx_eth_data    <= 16'b0;
        rx_counter          <= 12'b0;
        rx_timestamp        <= 32'b0;
        rx_frame_len        <= 12'b0;
        rx_status           <=  2'b0;
        rx_active           <=  1'b0;
    end else begin
        if (rx_active == 1'b0) begin
            rx_counter <= 12'b0;
            if (rx_empty == 1'b1 && gmii_rx_dv == 1'b0)
                rx_active <= 1'b1;
         end else begin
            slot_rx_eth_wr_en <= 1'b0;
            rx_status <= RX_IDLE;
            if (gmii_rx_dv) begin
                rx_counter <= rx_counter + 12'b1;
                rx_status <= RX_LOAD;

                // write receive timestamp
                if (rx_counter != 12'b0)
                    rx_timestamp <= global_counter;
                slot_rx_eth_wr_en <= 1'b1;
                if (rx_counter[0]) begin
                    slot_rx_eth_byte_en <= 2'b10;
                    slot_rx_eth_data    <= {gmii_rxd, 8'b0};
                end else begin
                    slot_rx_eth_byte_en <= 2'b01;
                    slot_rx_eth_data    <= {8'b0, gmii_rxd};
                    slot_rx_eth_address <= slot_rx_eth_address + 12'd1;
                end
            end else begin
                // frame terminated
                if (rx_counter != 12'b0) begin
                    rx_frame_len <= rx_counter;
                    rx_counter   <= 12'b0;
                    slot_rx_eth_address <= 12'd2;
                    rx_status <= RX_DONE;
                    rx_active <= 1'b0;
                end
            end
        end
    end
end
assign rx_complete = rx_status[1];

endmodule

`default_nettype wire

