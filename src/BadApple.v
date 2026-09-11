module badapple
(
    input pixel_clock, // 56 ish mhz
    input VDE,
    input vsync,
    input isHDMIHOT,
    input  wire spi_miso,
    output wire spi_cs_n,
    output wire spi_sclk,
    output wire spi_mosi,
    output invert
    
);
//the bad apple module works by flipping or not flipping the output bit
// eg 0 is white and if next 4 pixels are white it doesnt flip for 4 pixel clocks


// 1 2 4 8 16
//stream from the flash chip data
    reg [9:0] pixel_counter = 10'd1;
    reg [9:0] read_buf [31:0];
    reg [4:0] buffer_index = 5'd0;
    reg [4:0] fill_index   = 5'd0;
    reg current_is_white = 1'b0; //starts off false
    reg past_is_white = 1'b0;

 // marks as true if it has been read        
    reg [31:0] finished_read = 32'hFFFFFFFF; // Starts fully consumed (all 1s)
    reg [5:0]  empty_banks   = 6'd32;        // Starts completely empty

    // Wires from SPI Reader
    wire       spi_valid;
    wire [9:0] spi_data;

    reg consumed_this_cycle;
    reg startup_lock = 1'b1;
    reg [15:0] boot_delay = 16'd0;

    reg reader_rst_n = 1'b0;
    reg vsync_d = 1'b0;
    wire frame_start = (vsync_d && !vsync); // Falling edge of vsync
    reg running = 1'b0;


    wire fifo_empty = (empty_banks == 6'd32);
    // Simple, safe backpressure: pause SPI when less than 4 banks are empty
    wire fifo_full_signal = (empty_banks < 6'd4); 

    reg armed = 1'b0;

    always @(posedge pixel_clock) begin
        //this iterates pixel_counter 
        vsync_d <= vsync;
        if (boot_delay != 8'hFF) begin
            boot_delay <= boot_delay + 1'b1;
            reader_rst_n <= 1'b0;
            running <= 1'b0;
            armed <= 1'b0;
            buffer_index <= 5'd0;
            fill_index <= 5'd0;
            empty_banks <= 6'd32;
            pixel_counter <= 10'd1;
            current_is_white <= 1'b0;
        end 
        else begin
            reader_rst_n <= 1'b1; // Wake up SPI Reader

            // Wait for FIFO to safely pre-load at least 20 words
            if (!armed && (empty_banks < 6'd12)) begin
                armed <= 1'b1;
            end

            // Lock to the exact start of a frame (vsync falling edge)
            if (armed && !running && (vsync_d && !vsync)) begin
                running <= 1'b1;
                // Note: We DO NOT reset buffer_index here. It was primed by the reader.
            end

        //a 1 frame delay is written to the registers
        //a frame is 935360
        //pretty crappy fix imo
        //whats happening right now
        //q1 |q2
        //q3 |q4
        //frame mismatching, split fully in half
        
        
        consumed_this_cycle = 1'b0;

        
        if(VDE && running && !fifo_empty) begin
            if (pixel_counter == read_buf[buffer_index]) begin
                if (pixel_counter != 10'd1023) begin //not a special char
                    current_is_white <= ~current_is_white;
                end
                pixel_counter <= 10'd1;
                finished_read[buffer_index] <= 1'b1; // Mark as read
                buffer_index <= buffer_index + 1'b1;
                consumed_this_cycle = 1'b1;
            end
            else begin
                pixel_counter <= pixel_counter + 1'b1;
                //bs pattern to test
            end
        end
end
        
        if (spi_valid) begin
            // 10-bit word drops perfectly into the array natively
            read_buf[fill_index] <= spi_data;
            finished_read[fill_index] <= 1'b0; // Mark as filled/ready
            fill_index <= fill_index + 1'b1;
        end
        
        if (consumed_this_cycle && !spi_valid) begin
            empty_banks <= empty_banks + 1'b1;
        end else if (!consumed_this_cycle && spi_valid) begin
            empty_banks <= empty_banks - 1'b1;
        end
        // If both happen on the exact same clock cycle, empty_banks stays the same.
        //during blanking times if finished read > 12 banks or not during blanking but finished over 20 banks
        //reads in round robin style, from 0 to 31 
        //fills also begin from 0 to 31
        //reads 10 bits and splits them
        //fills bits here
    end
    assign invert = current_is_white;
    //assign invert = current_is_white ^ past_is_white; //im damn smart
    flash_reader #(
        .START_ADDR(24'h100000)
    ) u_reader (
        .clk(pixel_clock),
        .rst_n(reader_rst_n), 
        .fifo_full(fifo_full_signal),
        
        .spi_cs_n(spi_cs_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        
        .data_out(spi_data),
        .data_valid(spi_valid)
    );
    
endmodule