module ucsbece154_icache #(
    parameter NUM_SETS   = 8,
    parameter NUM_WAYS   = 4,
    parameter BLOCK_WORDS= 4,
    parameter WORD_SIZE  = 32
)(
    input                     Clk,
    input                     Reset,

    // core fetch interface
    input                     ReadEnable,
    input      [31:0]         ReadAddress,
    output reg [WORD_SIZE-1:0]Instruction,
    output reg                Ready,
    output reg                Busy,

    // SDRAM-controller interface
    output reg [31:0]         MemReadAddress,
    output reg                MemReadRequest,
    input      [31:0]         MemDataIn,
    input                     MemDataReady
);

localparam WORD_OFFSET = $clog2(4); // 2 for 4-byte words
localparam BLOCK_OFFSET = $clog2(BLOCK_WORDS);
localparam OFFSET = WORD_OFFSET + BLOCK_OFFSET;
localparam NUM_TAG_BITS = 32 - $clog2(NUM_SETS) - OFFSET;

reg [NUM_TAG_BITS-1:0] tags     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg                   valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [31:0]            words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

wire [$clog2(NUM_SETS)-1:0] set_index = ReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0] tag_index = ReadAddress[31:OFFSET + $clog2(NUM_SETS)];
wire [1:0] block_offset = ReadAddress[3:2];

integer i, j, k;
reg hit;
reg [$clog2(NUM_WAYS)-1:0] word_iter_way;
reg [1:0] word_counter;
reg [1:0] critical_word_index;
reg [31:0] sdram_block [BLOCK_WORDS - 1:0];
reg [31:0] target_word;
reg write_done;

always @ (posedge Clk) begin
    if (Reset) begin
        Ready <= 0;
        Busy <= 0;
        MemReadRequest <= 0;
        Instruction <= 0;
        write_done <= 0;
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                valid[i][j] <= 0;
            end
        end
    end else begin
        Ready <= 0; // Default

        // Cache hit logic
        hit = 0;
        if (ReadEnable && !Busy) begin
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                if (valid[set_index][i] && tags[set_index][i] == tag_index) begin
                    Instruction <= words[set_index][i][block_offset];
                    Ready <= 1;
                    hit = 1;
                end
            end

            // On miss, initiate memory read
            if (!hit) begin
                MemReadAddress <= {ReadAddress[31:4], 4'b0000}; // block-aligned address
                MemReadRequest <= 1;
                Busy <= 1;
                critical_word_index <= block_offset;
                word_counter <= 0;

                // Choose replacement way (empty if available)
                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    if (valid[set_index][j] == 0) begin
                        word_iter_way = j;
                        disable choose_way;
                    end
                end
                word_iter_way = $random % NUM_WAYS; // random if no invalid found
            end
        end

        // SDRAM data reception
        if (Busy && MemDataReady) begin
            sdram_block[word_counter] <= MemDataIn;
            if (word_counter == critical_word_index) begin
                target_word <= MemDataIn;
            end
            word_counter <= word_counter + 1;

            if (word_counter == BLOCK_WORDS - 1) begin
                for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                    words[set_index][word_iter_way][k] <= sdram_block[k];
                end
                tags[set_index][word_iter_way] <= tag_index;
                valid[set_index][word_iter_way] <= 1;
                Busy <= 0;
                MemReadRequest <= 0;
                write_done <= 1;
            end
        end

        // Final output of the word after full block write
        if (write_done) begin
            Instruction <= target_word;
            Ready <= 1;
            write_done <= 0;
        end
    end
end

endmodule
