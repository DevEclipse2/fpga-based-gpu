module top (
    input  wire clk_27,   // Physical 27 MHz clock pin (H11)
    output wire led_pin   // Physical LED pin (e.g., N16 for Dock)
);

    // 1. Declare internal wires to carry the generated signals
    wire clk_pixel;
    wire clk_serial;

    // 2. Instantiate the PLL module
    HDMI_clock u_pll (
        .clk(clk_27),
        .clk_serial(clk_serial),
        .clk_pixel(clk_pixel)  // The 55.8 MHz clock exits here
    );

    // 3. Instantiate the LED blinker module
    led u_blinker (
        .clk_pixel(clk_pixel),       // The 55.8 MHz clock enters here
        .IO_voltage(led_pin)          // The output goes to the physical pin
    );

endmodule