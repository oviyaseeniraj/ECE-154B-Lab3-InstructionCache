`define MIN(A,B) (((A)<(B))?(A):(B))

module ucsbece154_imem #(
    parameter TEXT_SIZE = 64,
    parameter BLOCK_WORDS = 4,
    parameter T0_DELAY = 40
) (
    input wire clk,
    input wire reset,

    input wire ReadRequest,
    input wire [31:0] ReadAddress,

    output reg [31:0] DataIn,
    output reg DataReady
);

// BRAM
reg [31:0] TEXT [0:TEXT_SIZE-1];
initial $readmemh("text.dat", TEXT);

// Address layout
localparam TEXT_START = 32'h00010000;
localparam TEXT_END   = `MIN(TEXT_START + (TEXT_SIZE * 4), 32'h10000000);
localparam TEXT_ADDRESS_WIDTH = $clog2(TEXT_SIZE);

// Internal state
reg [31:0] base_addr;
reg [$clog2(T0_DELAY+1):0] delay_counter;
reg [$clog2(BLOCK_WORDS):0] word_counter;
reg reading;

// Computed access address
wire [31:0] a_i = base_addr + (word_counter << 2);
wire text_enable = (a_i >= TEXT_START) && (a_i < TEXT_END);
wire [TEXT_ADDRESS_WIDTH-1:0] text_address = a_i[2 +: TEXT_ADDRESS_WIDTH] - TEXT_START[2 +: TEXT_ADDRESS_WIDTH];
wire [31:0] text_data = TEXT[text_address];

always @(posedge clk or posedge reset) begin
    if (reset) begin
        DataIn <= 0;
        DataReady <= 0;
        reading <= 0;
        delay_counter <= 0;
        word_counter <= 0;
    end else begin
        DataReady <= 0; // default

        // Start a new burst
        if (ReadRequest && !reading) begin
            base_addr <= {ReadAddress[31:4], 4'b0000}; // align to block
            delay_counter <= T0_DELAY;
            word_counter <= 0;
            reading <= 1;
        end

        // Handle active burst
        if (reading) begin
            if (delay_counter > 0) begin
                delay_counter <= delay_counter - 1;
            end else begin
                if (word_counter < BLOCK_WORDS) begin
                    DataIn <= text_enable ? text_data : 32'hZZZZZZZZ;
                    DataReady <= 1;
                    word_counter <= word_counter + 1;
                    // delay_counter <= T0_DELAY;
                end else begin
                    reading <= 0;
                end
            end
        end
    end
end

`ifdef SIM
always @* begin
    if (a_i[1:0] != 2'b0)
        $warning("Misaligned memory access: 0x%h", a_i);
end
`endif

endmodule

`undef MIN