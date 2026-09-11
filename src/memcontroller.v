
//based off of 
//Simple low-latency DDR3 PHY controller for Tang Primer 20K
// nand2mario, 2022.9

// this is the primary interface and is a part of the memory controller
// memory controller does mroe stuff 
module memory(
    
    
    // Time delays in nCK (tCK=2.5ns for DDR-800, 1.875ns for DDR-1066).
    parameter         ROW_WIDTH = 14,//16384
    //unknown , datasheet specifies 14 rows for 128MB memory so we're using that
    parameter         COL_WIDTH = 10,//1024 bytes
    parameter         BANK_WIDTH = 3,//8 banks
    
    
    
    // Time delays in nCK (tCK=2.5ns for DDR-800, 1.875ns for DDR-1066).
    parameter CAS  = 7,     // MR0[6,5,4,2] = 0110                                          //column address strobe
    parameter CWL  = 6,     // MR2[5:3] = 001                                               // cas write latency
    parameter RCD  = 8,     // 13.75ns, active to r/w                                       // row address to column address delay
    parameter WR   = 8,     // MR0[11:9] = 100                                              // write recovery time
    parameter MRD  = 8,     // >=4 cycles, mode register set delay                          // Mode Register Set Command Cycle Time
    parameter RP   = 8,     // 13.75ns, precharge to active                                 // row precharge time
    parameter RC   = 26,    // 48.25ns, ref/active to ref/active                            // row cycle time (much thrashing not good)
    parameter MOD  = 12     // 12nCK/15ns, cycles after MRS before any other command        // idk
    //MRS = mode rgister set
    
    // 8 word burst read
    // ddr3 side
    inout [127:0]      DDR3_DQ,
    inout [1:0]       DDR3_DQS, //data strobe
    output[ROW_WIDTH-1:0]  DDR3_A, //address
    output[BANK_WIDTH-1:0] DDR3_BA, //bank address

    output            DDR3_nRAS,    //negative row address strobe
    output            DDR3_nCAS,    //negative column access strobe // why do we have dupplicates of cas?
    output            DDR3_nWE,     //negative write enable
    output            DDR3_nCS,     // always 0 *because we have only 1 chip
    output            DDR3_CK,      // ck, 180-degree shifted fclk //clock
    output     reg    DDR3_CKE,     // clock enable
    output            DDR3_nRESET,  // reset pin
    output     [1:0]  DDR3_DM,      // always 0 //data mask
    output            DDR3_ODT,     // always 1 // on die termination // probably also because we only have 1 chip

    // System side interface
    input             pclk,         // primary clock (rd, wr, etc), e.g. 100Mhz
    input             fclk,         // fast clock (4*pclk), e.g. 400Mhz
    input             ck,           // 90-degree shifted fclk for memory clock
    input             resetn,       // reset (negative)?
    input             rd,           // command: read
    input             wr,           // command: write
    input             refresh,      // command: auto refresh. 4096 refresh cycles in 64ms. Once per 15us.
    input      [BANK_WIDTH+ROW_WIDTH+COL_WIDTH-1:0] 
                      addr,         // word address 
// ah shit now i see the reason why row is smaller (or do i)
    input     [127:0] din,          // 128-bit data input
//i paid for the chip im using the chip
    output    [127:0]  dout128,         // big ahh buffer storing 1 burst of data
//i have no idea whats the difference
//fuck it im commenting this out
//    output    [127:0] dout128,      // 128-bit data output
    output reg        data_ready = 1'b0,   // available 6 cycles after wr is set
    output reg        busy = 1'b1,  // 0: ready for next command

    // Write leveling. This is done after mode registers are set.
    output            write_level_done,  // 1 means write leveling is successful for this DQS
    output reg [7:0]  wstep,        // write delay steps, 8 bits for each DQS. this is result of write leveling.

    // Read calibration
    // Increment rclkpos/rclksel, send a BL8 read command, and once a rburst
    // pulse is detected, then we have read calibration.
    output            read_calib_done,  // 1: read calibration successful
    output reg  [1:0] rclkpos,      // cycle value for read clock (0-3), 2 bits for each DQS
    output reg  [2:0] rclksel,      // phase value for read clock (0-7), 3 bits for each DQS
);
//always run at max speed 1066mhz

// More timing parameters

//First DQS/DQS# rising edge after write leveling mode is programmed
localparam WLMRD= 44;       // Write leveling wait time before DQS pulse

//no clue what these are
localparam SERDES = 16;     // SERDES round-trip latency in (OSER8 is 3 clk, IDER8 is 1 clk)
localparam USEC = 134;  // pclk <= 133Mhz // no clue whats this 

//delay locked loop
// Wait until DLL locked to do anything
wire dlllock;
wire rst_lock_n = resetn & dlllock;
reg resetn_delay;
assign DDR3_nRESET = rst_lock_n & resetn_delay;
assign DDR3_ODT = 1'b1;     // Use dynamic ODT



// Tri-state DQ inout signals (double DDR3_CK speed)
//tri-state area ahh shi
reg [15:0] dq_out [7:0];    // DQ output data outgoing to ram chip
reg [0:3] dq_oen;           // out_enable_n for dq_out[1:0], [3:2], [5:4], [7:6] 
wire [15:0] dq_in [7:0];    // DQ input data incoming from ram chip


//endianness
reg [0:7] dqs_out;          // DQS output : An 8-bit register holding the output pattern
// for the data strobe (DQS) signal used to synchronize read and write data timing.
reg [0:3] dqs_oen;          // out_enable_n for dqs_out[1:0], [3:2], [5:4], [7:6]
reg [0:7] dm_out; //data mask

reg nRAS[3:0], nCAS[3:0], nWE[3:0];
reg [ROW_WIDTH-1:0] A[3:0];
reg [2:0] BA[3:0];
assign DDR3_CK = ck;
assign DDR3_nCS = 1'b0;

//data out 
assign dout128 = {dq_in[0], dq_in[1], dq_in[2], dq_in[3], dq_in[4], dq_in[5], dq_in[6], dq_in[7]};



// Our main FSM state
//finite state machine
reg [3:0] state;            //4 bit state      
localparam RST_WAIT = 4'd0; // reset wai
localparam CKE_WAIT = 4'b1; // probably not charlie kirk fuck its clock enable
localparam CONFIG = 4'd2; 
localparam ZQCL = 4'd3; //zQ calibration long
localparam IDLE = 4'd4;
localparam READ = 4'd5;
localparam WRITE = 4'd6;
localparam REFRESH = 4'd7;
localparam WRITE_LEVELING = 4'd8; //timing delay adjustment
localparam READ_CALIB = 4'd9;
reg [4:0] cycle;        // step within operation (config/read/write) 
reg tick;               // pulse after tick_counter cycles
reg [16:0] tick_counter = 17'd50_000;   

// RAS# CAS# WE#
//i think these are commands
localparam CMD_SetModeReg=3'b000; //set mode register
localparam CMD_AutoRefresh=3'b001;
localparam CMD_PreCharge=3'b010;
localparam CMD_BankActivate=3'b011;
localparam CMD_Write=3'b100;
localparam CMD_Read=3'b101;
localparam CMD_ZQCL=3'b110;
localparam CMD_NOP=3'b111;













//power up
//reset# should be below 0.2x VDD, for 200us min
//cke pull low, pause for 50 ns before reset# de assertation
//(this does not concern me )
//The power voltage ramp time between 300 mv to VDDmin must be no greater than 200 ms; and during the ramp, VDD > VDDQ and (VDD - VDDQ) < 0.3 volts.




endmodule