module top(
    input base_clock,
    input HPD,
//output timer
    output wire tmds_clk_p,
//output tx as a bus
    output wire [2:0] tmds_d_p
);

    wire clock_pixel;
    wire clock_serial;
    wire sysrst = ~HPD;

    HDMI_clock u_pll (
        .clk(base_clock),
        .clk_serial(clock_serial),
        .clk_pixel(clock_pixel)  // The 55.8 MHz clock exits here
    );

    DVI u_DVI (
        .serial_clk(clock_serial),
        .pixel_clk(clock_pixel),
        .reset(sysrst),
        .Tx_0(tmds_d_p[0]),
        .Tx_1(tmds_d_p[1]),
        .Tx_2(tmds_d_p[2]), 
        .Tx_C(tmds_clk_p)
    );
endmodule