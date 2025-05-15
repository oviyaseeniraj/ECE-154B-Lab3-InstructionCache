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
    input                     MemDataReady,
    input                     PCEnable,
    input                     Mispredict,
    input                     Flush
);

localparam WORD_OFFSET   = $clog2(4);
localparam BLOCK_OFFSET  = $clog2(BLOCK_WORDS);
localparam OFFSET        = WORD_OFFSET + BLOCK_OFFSET;
localparam NUM_TAG_BITS  = 32 - $clog2(NUM_SETS) - OFFSET;

// Cache structures
reg [NUM_TAG_BITS-1:0] tags     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg                   valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [31:0]            words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

// Indices
wire [$clog2(NUM_SETS)-1:0] set_index = ReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0]     tag_index = ReadAddress[31:OFFSET + $clog2(NUM_SETS)];
wire [BLOCK_OFFSET-1:0]     word_offset = ReadAddress[OFFSET-1:WORD_OFFSET];

// Refill state
reg [31:0] lastReadAddress;
wire [$clog2(NUM_SETS)-1:0] refill_set_index = lastReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0]     refill_tag_index = lastReadAddress[31:OFFSET + $clog2(NUM_SETS)];
wire [BLOCK_OFFSET-1:0]     refill_word_offset = lastReadAddress[OFFSET-1:WORD_OFFSET];

integer i, j, k;
reg [$clog2(NUM_WAYS)-1:0] hit_way;
reg hit_this_cycle;
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
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                valid[i][j] <= 0;
                tags[i][j] <= 0;
                for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                    words[i][j][k] <= 0;
                end
            end
        end
    end else if (Flush || Mispredict) begin // NEW: cancel current refill
        Busy <= 0;
        MemReadRequest <= 0;
        need_to_write <= 0;
        word_counter <= 0;
        Ready <= 0;
        lastReadAddress <= 32'hFFFFFFFF; // mark as invalid
    end else begin
        Ready <= 0;
        hit_this_cycle = 0;

        // Hit detection
        if (ReadEnable && !Busy && !need_to_write) begin
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                if (valid[set_index][i] && tags[set_index][i] == tag_index) begin
                    hit_this_cycle = 1;
                    hit_way = i;
                end
            end
        end

        if (hit_this_cycle) begin
            Instruction <= words[set_index][hit_way][ReadAddress[OFFSET-1:WORD_OFFSET]];
            Ready <= 1;
            Busy <= 0;
        end

        // Miss handling
        if (!hit_this_cycle && ReadEnable && !Busy && !need_to_write) begin
            lastReadAddress <= ReadAddress;
            MemReadAddress <= {ReadAddress[31:OFFSET], {OFFSET{1'b0}}}; // align
            MemReadRequest <= 1;
            replace_way <= 0;
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                if (!valid[set_index][j]) replace_way <= j;
            end
            word_counter <= 0;
            need_to_write <= 1;
        end

        if (MemDataReady && need_to_write) begin
            sdram_block[word_counter] = MemDataIn;
            if (word_counter == BLOCK_WORDS - 1) begin
                for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                    words[refill_set_index][replace_way][k] <= sdram_block[k];
                end
                tags[refill_set_index][replace_way] <= refill_tag_index;
                valid[refill_set_index][replace_way] <= 1;
                Instruction <= sdram_block[refill_word_offset];
                Ready <= 1;
                Busy <= 0;
                MemReadRequest <= 0;
                need_to_write <= 0;
            end
            word_counter <= word_counter + 1;
            Busy <= 1;
        end
    end
end

endmodule
