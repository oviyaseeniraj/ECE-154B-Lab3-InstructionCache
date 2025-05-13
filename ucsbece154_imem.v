// ucsbece154_imem.v
// All Rights Reserved
// Copyright (c) 2024 UCSB ECE
// Distribution Prohibited

`define MIN(A,B) (((A)<(B))?(A):(B))

module ucsbece154_imem #(
    parameter TEXT_SIZE = 64,
    parameter BLOCK_WORDS = 4,          // words per burst (must match cache)
    parameter T0_DELAY = 40             // first word delay (cycles)
) (
    input wire clk,
    input wire reset,

    input wire ReadRequest,
    input wire [31:0] ReadAddress,

    output reg [31:0] DataIn,
    output reg DataReady
);
   
wire [31:0] a_i;//address to memory map read address

wire [31:0] rd_o;// read data from memory

// Implement SDRAM interface here
always @ * begin
    DataIn = rd_o;
end

// instantiate/initialize BRAM
reg [31:0] TEXT [0:TEXT_SIZE-1];

// initialize memory with test program. Change this with your file for running custom code
initial $readmemh("text.dat", TEXT);

// calculate address bounds for memory
localparam TEXT_START = 32'h00010000;
localparam TEXT_END   = `MIN( TEXT_START + (TEXT_SIZE*4), 32'h10000000);

// calculate address width
localparam TEXT_ADDRESS_WIDTH = $clog2(TEXT_SIZE);

// create flags to specify whether in-range 
wire text_enable = (TEXT_START <= a_i) && (a_i < TEXT_END);

// create addresses 
wire [TEXT_ADDRESS_WIDTH-1:0] text_address = a_i[2 +: TEXT_ADDRESS_WIDTH]-(TEXT_START[2 +: TEXT_ADDRESS_WIDTH]);

// get read-data 
wire [31:0] text_data = TEXT[ text_address ];

// internal state
reg [31:0] base_addr;
reg [$clog2(T0_DELAY+1):0] delay_counter;
reg [$clog2(BLOCK_WORDS+1):0] word_counter;
reg reading;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        DataIn <= 0;
        DataReady <= 0;
        reading <= 0;
        delay_counter <= 0;
        word_counter <= 0;
    end else begin
        DataReady <= 0; // default

        if (ReadRequest && !reading) begin
            base_addr <= {ReadAddress[31:4], 4'b0000}; // align to block
            delay_counter <= T0_DELAY;
            word_counter <= 0;
            reading <= 1;
        end

        if (reading) begin
            if (delay_counter > 0) begin
                delay_counter <= delay_counter - 1;
            end else begin
                // output one word
                if (word_counter < BLOCK_WORDS) begin
                    DataIn <= text_enable ? text_data : {32{1'bz}};
                    DataReady <= 1;
                    word_counter <= word_counter + 1;
                end else if (word_counter == BLOCK_WORDS) begin
                    DataReady <= 0;
                    reading <= 0;
                end
            end
        end
    end
end

`ifdef SIM
always @ * begin
    if (a_i[1:0]!=2'b0)
        $warning("Attempted to access invalid address 0x%h. Address coerced to 0x%h.", a_i, (a_i&(~32'b11)));
end
`endif

endmodule

`undef MIN
