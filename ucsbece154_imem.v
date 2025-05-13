module ucsbece154_imem #(
    parameter TEXT_SIZE = 64,
    parameter BLOCK_WORDS = 4,
    parameter T0_DELAY = 40 // Initial delay for the first word
) (
    input wire clk,
    input wire reset,
    input wire ReadRequest,
    input wire [31:0] ReadAddress,
    output reg [31:0] DataIn,
    output reg DataReady
);

    localparam T_BURST_INTER_WORD_DELAY = 0; // For T_burst=1, delay between subsequent words is 0 additional cycles

    reg [31:0] TEXT [0:TEXT_SIZE-1];
    initial $readmemh("text.dat", TEXT);

    localparam TEXT_START = 32'h00010000;
    // Define MIN securely for Verilog-2001
    // `define MIN(A,B) (((A)<(B))?(A):(B)) -> this is a macro, should be outside module or in `include
    // For a localparam, we might need to calculate it if it's simple, or use a fixed value if complex.
    // For this specific usage, TEXT_SIZE * 4 is likely less than the upper bound.
    localparam TEXT_END   = TEXT_START + (TEXT_SIZE * 4);
    localparam TEXT_ADDRESS_WIDTH = $clog2(TEXT_SIZE);

    reg [31:0] base_addr;
    reg [$clog2(T0_DELAY+1 > T_BURST_INTER_WORD_DELAY+1 ? T0_DELAY+1 : T_BURST_INTER_WORD_DELAY+1):0] delay_counter;
    reg [$clog2(BLOCK_WORDS):0] word_counter; // Needs to count up to BLOCK_WORDS
    reg reading;
    reg first_word_of_burst_sent;

    wire [31:0] a_i = base_addr + (word_counter << 2);
    wire text_enable = (a_i >= TEXT_START) && (a_i < TEXT_END);
    wire [TEXT_ADDRESS_WIDTH-1:0] text_address = (a_i - TEXT_START) >> 2; // Assuming TEXT_START is word aligned
    wire [31:0] text_data = TEXT[text_address];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            DataIn <= 0;
            DataReady <= 0;
            reading <= 0;
            delay_counter <= 0;
            word_counter <= 0;
            first_word_of_burst_sent <= 0;
        end else begin
            DataReady <= 0; // Default

            if (ReadRequest && !reading) begin
                base_addr <= {ReadAddress[31:($clog2(BLOCK_WORDS* (WORD_SIZE/8)))], {($clog2(BLOCK_WORDS* (WORD_SIZE/8))){1'b0}}}; // Align to block boundary
                delay_counter <= T0_DELAY;      // Initial delay for the first word
                word_counter <= 0;              // Reset for new block
                reading <= 1;
                first_word_of_burst_sent <= 0;  // Reset for new burst
            end

            if (reading) begin
                if (delay_counter > 0) begin
                    delay_counter <= delay_counter - 1;
                end else begin // delay_counter is 0
                    if (word_counter < BLOCK_WORDS) begin
                        DataIn <= text_enable ? text_data : 32'hDEADBEEF; // Use a visible error value if not text_enable
                        DataReady <= 1;
                        word_counter <= word_counter + 1;

                        if (!first_word_of_burst_sent) begin
                            first_word_of_burst_sent <= 1;
                            delay_counter <= T_BURST_INTER_WORD_DELAY; // Delay for subsequent words
                        end else begin
                            delay_counter <= T_BURST_INTER_WORD_DELAY;
                        end
                    end else begin // word_counter == BLOCK_WORDS, entire block sent
                        reading <= 0;
                        // first_word_of_burst_sent will be reset when a new ReadRequest starts
                    end
                end
            end
        end
    end


`ifdef SIM
always @* begin
    if (a_i[1:0] != 2'b0)
        $warning("Attempted to access misaligned address 0x%h", a_i);
end
`endif

endmodule

`undef MIN
