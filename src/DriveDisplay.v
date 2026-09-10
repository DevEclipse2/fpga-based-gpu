module DVI
(
// hot plug detection : HPD
// tx0 is for blue & sync 
// tx1 is green
// tx2 is red
// txc is clock
    
    input serial_clk,
    input pixel_clk,
    input reset,
    output Tx_0,
    output Tx_1,
    output Tx_2, 
    output Tx_C
);
    parameter active_width  = 1024;
    parameter full_width    = 1184;
    parameter active_height = 768;
    parameter full_height   = 790;

    reg [11:0] h_cnt = 0;
    reg [10:0] v_cnt = 0;
    
    reg de, hsync, vsync;

    // 1. Beam Tracking (VGA Counters)
    always @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end else begin
            if (h_cnt == full_width - 1) begin

                h_cnt <= 0;
                if (v_cnt == full_height - 1) v_cnt <= 0;
                else v_cnt <= v_cnt + 1;
            end else begin
                h_cnt <= h_cnt + 1;
            end
        end
    end

    // 2. Generate Sync Pulses (Example placement in the blanking period)
    always @(posedge pixel_clk) begin
        de <= (h_cnt < active_width) && (v_cnt < active_height);
        hsync <= (h_cnt >= 1048) && (h_cnt < 1080);
        vsync <= (v_cnt >= 771)  && (v_cnt < 775);
    end

    // 3. Hardcoded TMDS Symbols for a Solid Green Screen
    wire [9:0] tmds_red   = de ? 10'b1100000000 : 10'b1101010100;
    wire [9:0] tmds_green = de ? 10'b1000000000 : 10'b1101010100;
    reg  [9:0] tmds_blue;
    
    always @(*) begin
        if (de) tmds_blue = 10'b1100000000;
        else begin
            // Blue channel carries HSYNC and VSYNC during blanking
            case ({vsync, hsync})
                2'b00: tmds_blue = 10'b1101010100;
                2'b01: tmds_blue = 10'b0010101011;
                2'b10: tmds_blue = 10'b0101010100;
                2'b11: tmds_blue = 10'b1010101011;
            endcase
        end
    end
    
    wire [9:0] tmds_clk = 10'b1111100000; // 50% duty cycle clock symbol

    // 4. Gowin High-Speed Serializers (OSER10)
    // Converts parallel 10-bit data into a 279 MHz serial stream
    OSER10 oser_0 (
        .Q(Tx_0), .FCLK(serial_clk), .PCLK(pixel_clk), .RESET(reset),
        .D0(tmds_blue[0]), .D1(tmds_blue[1]), .D2(tmds_blue[2]), .D3(tmds_blue[3]), .D4(tmds_blue[4]),
        .D5(tmds_blue[5]), .D6(tmds_blue[6]), .D7(tmds_blue[7]), .D8(tmds_blue[8]), .D9(tmds_blue[9])
    );

    OSER10 oser_1 (
        .Q(Tx_1), .FCLK(serial_clk), .PCLK(pixel_clk), .RESET(reset),
        .D0(tmds_green[0]), .D1(tmds_green[1]), .D2(tmds_green[2]), .D3(tmds_green[3]), .D4(tmds_green[4]),
        .D5(tmds_green[5]), .D6(tmds_green[6]), .D7(tmds_green[7]), .D8(tmds_green[8]), .D9(tmds_green[9])
    );

    OSER10 oser_2 (
        .Q(Tx_2), .FCLK(serial_clk), .PCLK(pixel_clk), .RESET(reset),
        .D0(tmds_red[0]), .D1(tmds_red[1]), .D2(tmds_red[2]), .D3(tmds_red[3]), .D4(tmds_red[4]),
        .D5(tmds_red[5]), .D6(tmds_red[6]), .D7(tmds_red[7]), .D8(tmds_red[8]), .D9(tmds_red[9])
    );

    OSER10 oser_c (
        .Q(Tx_C), .FCLK(serial_clk), .PCLK(pixel_clk), .RESET(reset),
        .D0(tmds_clk[0]), .D1(tmds_clk[1]), .D2(tmds_clk[2]), .D3(tmds_clk[3]), .D4(tmds_clk[4]),
        .D5(tmds_clk[5]), .D6(tmds_clk[6]), .D7(tmds_clk[7]), .D8(tmds_clk[8]), .D9(tmds_clk[9])
    );

endmodule