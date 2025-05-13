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

localparam WORD_OFFSET = $clog2(4); // word offset
localparam BLOCK_OFFSET = $clog2(BLOCK_WORDS); // block offset
localparam OFFSET = WORD_OFFSET + BLOCK_OFFSET; // offset
localparam NUM_TAG_BITS = 32 - $clog2(NUM_SETS) - OFFSET;

// Tags: One tag per way per set
reg [NUM_TAG_BITS-1:0] tags     [0:NUM_SETS-1][0:NUM_WAYS-1];

// Valids: One valid bit per way per set
reg                   valid     [0:NUM_SETS-1][0:NUM_WAYS-1];

// Words: A cache block = multiple 32-bit words per way per set
reg [31:0]            words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

// use read address to determine the set, way, and block offset and check if there's a hit
wire [$clog2(NUM_SETS)-1:0] set_index = ReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0] tag_index = ReadAddress[31:OFFSET + $clog2(NUM_SETS)];

integer i, j, k;
reg hit;
reg miss;
reg [$clog2(NUM_WAYS)-1:0] word_iter_way;
reg [1:0] word_counter;
reg [1:0] critical_word_index;  // stores which word we actually want
integer found;

always @ (posedge Clk) begin
    MemReadAddress <= 0;
    MemReadRequest <= 0;
    Ready <= 0;
    Instruction <= 0;
    hit = 0;

    if (!Busy && ReadEnable) begin
        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            if (valid[set_index][i] && (tags[set_index][i] == tag_index)) begin
                hit = 1;
                Instruction <= words[set_index][i][ReadAddress[WORD_OFFSET-1:0]];
                Ready <= 1;
                Busy <= 0;
            end
        end

        if (!hit) begin
            MemReadAddress <= {ReadAddress[31:4], 4'b0000}; // Align to block boundary
            MemReadRequest <= 1;
            Busy <= 1;
            critical_word_index <= ReadAddress[3:2]; // Save the target word index
            word_counter <= 0;

            // Pick replacement way (empty if available)
            found = 0;
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                if (valid[set_index][j] == 0 && !found) begin
                    word_iter_way = j;
                    found = 1;
                end
            end
            if (!found) begin
                word_iter_way = $random % NUM_WAYS;
            end
        end
    end
end

reg [31:0] sdram_block [BLOCK_WORDS - 1:0];
reg [31:0] target_word;
reg write_done;

always @ (posedge Clk) begin
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
end

always @ (posedge Clk) begin
    if (Reset) begin
        Ready <= 0;
        write_done <= 0;
    end else begin
        if (write_done) begin
            Instruction <= target_word;
            Ready <= 1;
            write_done <= 0; // consume write_done after use
        end else begin
            Ready <= 0; // default case only when not writing
        end
    end
end

endmodule
