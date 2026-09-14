module flash_reader #(
    parameter START_ADDR = 24'h100000 // Safe offset above the bitstream
)(
    input  wire       clk,          // 56 MHz system clock
    input  wire       rst_n,        // Active-low reset
    input  wire       fifo_full,    // Backpressure from your BRAM buffer
    
    
    // MSPI Physical Pins (Map in .cst as IO_TYPE=LVCMOS33)
    output reg        spi_cs_n,
    output reg        spi_sclk,
    output reg        spi_mosi,
    input  wire       spi_miso,

    // Decoded 10-bit output
    output reg [9:0]  data_out,
    output reg        data_valid    // 1-cycle pulse when data_out is ready
);

    // --------------------------------------------------------
    // Clock Divider: 28 MHz SPI Clock
    // --------------------------------------------------------
reg clk_div = 1'b0;
wire tick_fall = (clk_div == 1'b0); // Update MOSI / Drop SCLK
wire tick_rise = (clk_div == 1'b1); // Sample MISO / Raise SCLK

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) clk_div <= 1'b0;
    else clk_div <= ~clk_div;
end

    // --------------------------------------------------------
    // SPI State Machine
    // --------------------------------------------------------
    localparam S_IDLE       = 2'd0;
    localparam S_CMD_ADDR   = 2'd1;
    localparam S_READ_10BIT = 2'd2;
    localparam S_PAUSE      = 2'd3;

    reg [1:0]  state;
    reg [5:0]  bit_cnt;
    reg [31:0] cmd_addr_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            spi_cs_n       <= 1'b1;
            spi_sclk       <= 1'b0;
            spi_mosi       <= 1'b0;
            data_out       <= 10'd0;
            data_valid     <= 1'b0;
            bit_cnt        <= 6'd0;
            cmd_addr_shift <= 32'd0;
        end else begin
            data_valid <= 1'b0; // Default off, pulses for 1 cycle

            case (state)
                S_IDLE: begin
                    spi_cs_n       <= 1'b0; // Lock chip select
                    spi_sclk       <= 1'b0;
                    // Standard Read (0x03) + 24-bit Address
                    cmd_addr_shift <= {8'h03, START_ADDR};
                    bit_cnt        <= 6'd32;
                    state          <= S_CMD_ADDR;
                end

                S_CMD_ADDR: begin
                    if (tick_fall) begin
                        spi_sclk <= 1'b0;
                        spi_mosi <= cmd_addr_shift[31];
                    end else if (tick_rise) begin
                        spi_sclk       <= 1'b1;
                        cmd_addr_shift <= {cmd_addr_shift[30:0], 1'b0};
                        bit_cnt        <= bit_cnt - 1'b1;
                        
                        if (bit_cnt == 6'd1) begin
                            bit_cnt <= 6'd10; // Setup for 10-bit reads
                            state   <= S_READ_10BIT;
                        end
                    end
                end

                S_READ_10BIT: begin
                    if (tick_fall) begin
                        spi_sclk <= 1'b0;
                    end else if (tick_rise) begin
                        spi_sclk <= 1'b1;
                        // Shift bit into MSB-first 10-bit register
                        data_out <= {data_out[8:0], spi_miso}; 
                        bit_cnt  <= bit_cnt - 1'b1;
                        
                        if (bit_cnt == 6'd1) begin
                            data_valid <= 1'b1;
                            bit_cnt    <= 6'd10;
                            
                            // Check backpressure before next read
                            if (fifo_full) begin
                                state <= S_PAUSE;
                            end
                        end
                    end
                end
                S_PAUSE: begin
                if (tick_fall) begin
                    spi_sclk <= 1'b0; // Safely park clock low
                end
                
                // CRITICAL FIX: Only exit pause on tick_fall to prevent dropped bits
                if (!fifo_full && tick_fall) begin
                    state <= S_READ_10BIT;
                end
                end
            endcase
        end
    end
endmodule