module led(
    input  Clock,
    output IO_voltage
);

/**********计时部分**********/
//parameter Clock_frequency = 27_000_000; // 时钟频率为27Mhz
parameter count_value       = 5_436_241; // beats per second of all the small things
parameter max_blink         = 181; //blinks 182 times 

reg [23:0]  count_value_reg ; // timer register
reg         count_value_flag; // IO 电平翻转标志
reg [7:0]   blink_value_reg;

always @(posedge Clock) begin
    if ( count_value_reg <= count_value ) begin //没有计数到 0.5S
        if(blink_value_reg <= max_blink) begin
            count_value_reg  <= count_value_reg + 1'b1; // 继续计数
            count_value_flag <= 1'b0 ; // 不产生翻转标志
        end
    end
    else begin 
        count_value_reg  <= 23'b0; // clears
        count_value_flag <= 1'b1 ; // flag triggerd
        blink_value_reg <= blink_value_reg + 1'b1; //increments counter
    end
end

/**********电平翻转部分**********/
reg IO_voltage_reg = 1'b0; // 声明 IO 电平状态用于达到计时时间后的翻转，并赋予一个低电平初始态

always @(posedge Clock) begin
    if ( count_value_flag )  //  电平翻转标志有效
        IO_voltage_reg <= ~IO_voltage_reg; // IO 电平翻转
    else //  电平翻转标志无效
        IO_voltage_reg <= IO_voltage_reg; // IO 电平不变
end

/**********补充一行代码**********/
assign IO_voltage = IO_voltage_reg;

endmodule
