module framebuffer (
    input  wire        clk,
    // Write Port (From Decoder)
    input  wire        we,
    input  wire [15:0] write_addr, // 49,152 total words
    input  wire [15:0] write_data,
    // Read Port (From DVI Monitor)
    input  wire [15:0] read_addr,
    output reg  [15:0] read_data
);
    // 49,152 words * 16 bits = 786,432 pixels (Fits in 46 BRAM blocks)
    (* syn_ramstyle = "block_ram" *)
    reg [15:0] ram [0:49151];

    always @(posedge clk) begin
        if (we) begin
            ram[write_addr] <= write_data;
        end
        read_data <= ram[read_addr];
    end
endmodule