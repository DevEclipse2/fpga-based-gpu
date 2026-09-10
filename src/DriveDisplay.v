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

//timing system : 56 ish MHZ for 1024 x 768 screen
// chose to use this to drive cause the clock multipier sux

    parameter active_width  = 1024;
    parameter full_width    = 1184;
    parameter active_height = 768;
    parameter full_height   = 790;

    reg [11:0] h_cnt = 0;
    reg [10:0] v_cnt = 0;
    
    reg de, hsync, vsync;

    // 1. Beam Tracking (VGA Counters)
    // for rising edge of the pixel clock
    // or the rising edge of the reset flag
    // if the reset flag is always triggered (no screen)
    // the timing doesnt fuck itself up
    always @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end else begin
            if (h_cnt == full_width - 1) begin
                //this is the maximum width
                //resets horizontal counter
                h_cnt <= 0;
                //checks if full screen
                if (v_cnt == full_height - 1) v_cnt <= 0;
                else v_cnt <= v_cnt + 1;
            end else begin
                //moves the piss beam (tm) to the right
                h_cnt <= h_cnt + 1;
            end
        end
    end

    // 2. Generate Sync Pulses (Example placement in the blanking period)
        
    reg [7:0] red_8b = 0;
    reg [7:0] blu_8b = 0;
    reg [7:0] grn_8b = 0;
    reg [1:0] whoIncrement = 0;
    
    always @(posedge pixel_clk) begin
        de    <= (h_cnt < active_width) && (v_cnt < active_height);
        hsync <= (h_cnt >= 1048) && (h_cnt < 1080);
        vsync <= (v_cnt >= 771)  && (v_cnt < 775);
        
        if (de) begin
            red_8b <= h_cnt[7:0];
            grn_8b <= v_cnt[7:0];
            blu_8b <= h_cnt[7:0] + v_cnt[7:0];
        end
    end

    // 3. TMDS Encoders
    wire [9:0] tmds_red, tmds_green, tmds_blue; 
    wire [9:0] tmds_clk = 10'b1111100000; // 50% duty cycle clock symbol

    //these are the tmds encoders
    TMDS_encoder enc_b (
        .clk(pixel_clk),
        .VD(blu_8b),
        .CD({vsync, hsync}), // Blue channel carries H/V sync
        .VDE(de),
        .TMDS(tmds_blue)
    );

    TMDS_encoder enc_g (
        .clk(pixel_clk),
        .VD(grn_8b),
        .CD(2'b00),          // Green ctrl is always 0
        .VDE(de),
        .TMDS(tmds_green)
    );

    TMDS_encoder enc_r (
        .clk(pixel_clk),
        .VD(red_8b),
        .CD(2'b00),          // Red ctrl is always 0
        .VDE(de),
        .TMDS(tmds_red)
    );
    

    // 4. Gowin High-Speed Serializers (OSER10)
    // Converts parallel 10-bit data into a 279 MHz serial stream
    // the internal registers don't flip fast enough lmao
    

    OSER10 oser_0 (
         // as you can see this just reads the bits
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

    // this is the clock pulses
    OSER10 oser_c (
        .Q(Tx_C), .FCLK(serial_clk), .PCLK(pixel_clk), .RESET(reset),
        .D0(tmds_clk[0]), .D1(tmds_clk[1]), .D2(tmds_clk[2]), .D3(tmds_clk[3]), .D4(tmds_clk[4]),
        .D5(tmds_clk[5]), .D6(tmds_clk[6]), .D7(tmds_clk[7]), .D8(tmds_clk[8]), .D9(tmds_clk[9])
    );
    //ideally should produce green on a screen that i dont have access to rn

endmodule