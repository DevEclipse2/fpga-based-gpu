module flash_reader #(
    parameter START_ADDR = 24'h200000
)(
    input  wire        clk,          // 56 MHz system clock
    input  wire        rst_n,        // Active-low reset
    input  wire        fifo_full,    // Backpressure from FIFO buffer
    
    // MSPI Physical Pins
    output reg         spi_cs_n,
    output reg         spi_sclk,
    output reg         spi_mosi,
    input  wire        spi_miso,

    // Decoded 10-bit output
    output reg [9:0]   data_out,
    output reg         data_valid    // 1-cycle pulse when data_out is ready
);

    // --------------------------------------------------------
    // Clock Divider & Phase Generator (14 MHz SPI Clock)
    // --------------------------------------------------------
    reg [1:0] clk_div;
    
    // SPI Mode 0 Phase definitions:
    // 00: Drive MOSI / Lower SCLK
    // 10: Sample MISO internally (half a cycle before rising SCLK or stable before edge)
    // 11: Raise SCLK
    wire tick_drive  = (clk_div == 2'b00); 
    wire tick_sample = (clk_div == 2'b10); 
    wire tick_sclk_h = (clk_div == 2'b11); 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            clk_div <= 2'b00;
        else 
            clk_div <= clk_div + 1'b1;
    end

    // --------------------------------------------------------
    // SPI State Machine
    // --------------------------------------------------------
    localparam S_IDLE       = 3'd0;
    localparam S_CS_SETUP   = 3'd1;
    localparam S_CMD_ADDR   = 3'd2;
    localparam S_READ_10BIT = 3'd3;
    localparam S_PAUSE      = 3'd4;

    reg [2:0]  state;
    reg [5:0]  bit_cnt;
    reg [31:0] cmd_addr_shift;
    reg [9:0]  shift_in;

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
            shift_in       <= 10'd0;
        end else begin
            data_valid <= 1'b0; // Default 1-cycle pulse

            case (state)
                S_IDLE: begin
                    spi_cs_n <= 1'b1;
                    spi_sclk <= 1'b0;
                    spi_mosi <= 1'b0;
                    // Synchronize start to the base of the clock divider
                    if (clk_div == 2'b11) begin
                        spi_cs_n       <= 1'b0; // Assert CS#
                        cmd_addr_shift <= {8'h03, START_ADDR};
                        bit_cnt        <= 6'd32;
                        state          <= S_CS_SETUP;
                    end
                end

                // Ensure CS# setup time (Tcss) before pulsing SCLK
                S_CS_SETUP: begin
                    if (tick_drive) begin
                        spi_mosi <= cmd_addr_shift[31];
                        state    <= S_CMD_ADDR;
                    end
                end

                S_CMD_ADDR: begin
                    if (tick_sclk_h) begin
                        spi_sclk       <= 1'b1;
                        cmd_addr_shift <= {cmd_addr_shift[30:0], 1'b0};
                        bit_cnt        <= bit_cnt - 1'b1;
                    end else if (tick_drive) begin
                        spi_sclk <= 1'b0;
                        if (bit_cnt == 6'd0) begin
                            bit_cnt  <= 6'd10;
                            shift_in <= 10'd0;
                            state    <= S_READ_10BIT;
                        end else begin
                            spi_mosi <= cmd_addr_shift[31];
                        end
                    end
                end

                S_READ_10BIT: begin
                    // Sample MISO while SCLK is low to meet setup constraints
                    if (tick_sample) begin
                        shift_in <= {shift_in[8:0], spi_miso};
                    end else if (tick_sclk_h) begin
                        spi_sclk <= 1'b1;
                        bit_cnt  <= bit_cnt - 1'b1;
                    end else if (tick_drive) begin
                        spi_sclk <= 1'b0;
                        if (bit_cnt == 6'd0) begin
                            data_out   <= shift_in;
                            data_valid <= 1'b1;
                            bit_cnt    <= 6'd10;

                            // Only pause on a clean 10-bit word boundary
                            if (fifo_full) begin
                                state <= S_PAUSE;
                            end
                        end
                    end
                end

                S_PAUSE: begin
                    spi_sclk <= 1'b0; // Park SCLK low
                    // Exit pause strictly on tick_drive to preserve exact bit phase
                    if (!fifo_full && tick_drive) begin
                        state <= S_READ_10BIT;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule