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

// Internal constants
localparam WORD_OFFSET = $clog2(4);
localparam BLOCK_OFFSET = $clog2(BLOCK_WORDS);
localparam OFFSET = WORD_OFFSET + BLOCK_OFFSET;
localparam NUM_TAG_BITS = 32 - $clog2(NUM_SETS) - OFFSET;

// Cache data structures
reg [NUM_TAG_BITS-1:0] tags     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg                   valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [31:0]            words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

// Extract indices from read address
wire [$clog2(NUM_SETS)-1:0] set_index = ReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0]     tag_index = ReadAddress[31:OFFSET + $clog2(NUM_SETS)];
wire [BLOCK_OFFSET-1:0]     word_offset = ReadAddress[OFFSET-1:WORD_OFFSET];

reg [31:0] lastReadAddress;

integer i, j, k;
reg hit;
reg hit_latched;                  // NEW: latch to act on hit 1 cycle later
reg [$clog2(NUM_WAYS)-1:0] hit_way;
reg [$clog2(NUM_WAYS)-1:0] replace_way;
reg [1:0] word_counter;
reg [31:0] sdram_block [BLOCK_WORDS - 1:0];
reg need_to_write;

always @(posedge Clk) begin
    if (Reset) begin
        Ready <= 0;
        Instruction <= 0;
        Busy <= 0;
        MemReadAddress <= 0;
        MemReadRequest <= 0;
        word_counter <= 0;
        need_to_write <= 0;
        lastReadAddress <= 0;
        hit <= 0;                          // NEW
        hit_latched <= 0;                 // NEW

        for (i = 0; i < NUM_SETS; i = i + 1) begin
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                valid[i][j] <= 0;
                tags[i][j] <= 0;
                for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                    words[i][j][k] <= 0;
                end
            end
        end
    end else begin
        Ready <= 0;
        hit <= 0; // reset hit signal every cycle unless re-detected

        if (ReadEnable && !Busy) begin
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                if (valid[set_index][i] && tags[set_index][i] == tag_index) begin
                    hit <= 1;
                    hit_way <= i;
                end
            end
        end

        // NEW: Handle hit on next cycle
        if (hit_latched) begin
            Instruction <= words[set_index][hit_way][word_offset];
            Ready <= 1;
            Busy <= 0;
            hit_latched <= 0;
        end else if (hit) begin
            hit_latched <= 1;
        end else if (!need_to_write && !Busy && ReadEnable) begin
            // Cache miss: initiate memory read
            lastReadAddress <= ReadAddress;
            MemReadAddress <= {ReadAddress[31:OFFSET], {OFFSET{1'b0}}};  // align to block
            MemReadRequest <= 1;
            Busy <= 1;

            // Find replacement way (first invalid or random)
            replace_way <= 0;
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                if (!valid[set_index][j]) begin
                    replace_way <= j;
                end
            end

            word_counter <= 0;
            need_to_write <= 1;
        end

        // Handle SDRAM response
        if (MemDataReady && need_to_write) begin
            sdram_block[word_counter] <= MemDataIn;

            if (word_counter == BLOCK_WORDS - 1) begin
                // Finish refill and write to cache
                for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                    words[set_index][replace_way][k] <= sdram_block[k];
                end
                tags[set_index][replace_way] <= tag_index;
                valid[set_index][replace_way] <= 1;

                Instruction <= sdram_block[word_offset]; // serve instruction now
                Ready <= 1;
                Busy <= 0;
                MemReadRequest <= 0;
                need_to_write <= 0;
            end

            word_counter <= word_counter + 1;
        end
    end
end

endmodule
