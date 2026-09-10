module led(
    input wire reset,
    output  IO_voltage
);
// outputs clock at 10hz
parameter count_value       = 5_580_000; // flashes at 5.58 hz

reg [23:0]  count_value_reg ; // counter_value
reg         count_value_flag; // IO change flag

//always @(posedge clk_pixel) begin
//    if ( count_value_reg <= count_value ) begin //not count to 0.5S
//        count_value_reg  <= count_value_reg + 1'b1; // Continue counting
//        count_value_flag <= 1'b0 ; // No flip flag
//    end
//    else begin //Count to 0.5S
//        count_value_reg  <= 23'b0; // Clear counter,prepare for next time counting.
//        count_value_flag <= 1'b1 ; // Flip flag
//    end
//end

//quick test to see if the thing is plugged in

///********** IO voltage flip **********/
reg IO_voltage_reg = 1'b0; // Initial state

always @(posedge reset) begin
        IO_voltage_reg <= ~IO_voltage_reg; // IO voltage flip
end

/***** Add an extra line of code *****/
assign IO_voltage = IO_voltage_reg;

endmodule

