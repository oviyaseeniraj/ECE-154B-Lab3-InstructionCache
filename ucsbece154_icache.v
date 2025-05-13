module ucsbece154b_icache #(
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

localparam WORD_OFFSET = $clog2(4);
localparam BLOCK_OFFSET = $clog2(BLOCK_WORDS);
localparam OFFSET = WORD_OFFSET + BLOCK_OFFSET;
localparam NUM_TAG_BITS = 32 - $clog2(NUM_SETS) - OFFSET;
localparam TAG_WIDTH = NUM_TAG_BITS;
localparam INDEX_WIDTH = $clog2(NUM_SETS);

// FSM states
localparam IDLE = 0, LOOKUP = 1, MISS_REQ = 2, MISS_WAIT = 3, MISS_COMPLETE = 4, SEND_INSTR = 5;
reg [2:0] state, next_state;

// Cache memory: valid, tag, data
reg                  valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [TAG_WIDTH-1:0]  tags      [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [31:0]           data      [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

// Miss buffer for full block
reg [31:0] block_buf [0:BLOCK_WORDS-1];
reg [$clog2(BLOCK_WORDS)-1:0] word_counter;

// Internal registers
reg [31:0] saved_addr;
reg [INDEX_WIDTH-1:0] index;
reg [TAG_WIDTH-1:0] tag;
reg [1:0] hit_way;
reg        hit;
reg [1:0] replace_way;

integer i, j;

// Random replacement: simple counter based pseudo-random
reg [1:0] random_counter;
always @(posedge Clk) begin
    if (Reset) random_counter <= 0;
    else       random_counter <= random_counter + 1;
end

// Tag/index extraction
wire [INDEX_WIDTH-1:0] index_extracted = ReadAddress[OFFSET +: INDEX_WIDTH];
wire [TAG_WIDTH-1:0] tag_extracted = ReadAddress[31 -: TAG_WIDTH];
wire [$clog2(BLOCK_WORDS)-1:0] word_offset = ReadAddress[WORD_OFFSET +: $clog2(BLOCK_WORDS)];

// FSM
always @(posedge Clk) begin
    if (Reset) begin
        state <= IDLE;
        for (i = 0; i < NUM_SETS; i = i + 1)
            for (j = 0; j < NUM_WAYS; j = j + 1)
                valid[i][j] <= 0;
    end else begin
        state <= next_state;
        if (state == MISS_WAIT && MemDataReady) begin
            block_buf[word_counter] <= MemDataIn;
            word_counter <= word_counter + 1;
        end
    end
end

always @(*) begin
    next_state = state;
    Ready = 0;
    Busy = 0;
    MemReadRequest = 0;
    MemReadAddress = 0;
    Instruction = 32'b0;
    hit = 0;
    hit_way = 0;

    case (state)
        IDLE: begin
            if (ReadEnable) next_state = LOOKUP;
        end

        LOOKUP: begin
            index = index_extracted;
            tag = tag_extracted;
            saved_addr = ReadAddress;
            // Check all ways for a hit
            hit = 0;
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                if (valid[index][i] && tags[index][i] == tag) begin
                    hit = 1;
                    hit_way = i[1:0];
                end
            end
            if (hit) begin
                Instruction = data[index][hit_way][word_offset];
                Ready = 1;
                next_state = IDLE;
            end else begin
                replace_way = random_counter;
                MemReadRequest = 1;
                MemReadAddress = {tag_extracted, index_extracted, {WORD_OFFSET{1'b0}}};
                word_counter = 0;
                next_state = MISS_WAIT;
                Busy = 1;
            end
        end

        MISS_WAIT: begin
            MemReadRequest = 1;
            MemReadAddress = {tag_extracted, index_extracted, {WORD_OFFSET{1'b0}}};
            Busy = 1;
            if (word_counter == BLOCK_WORDS) next_state = MISS_COMPLETE;
        end

        MISS_COMPLETE: begin
            // Write block to cache
            for (i = 0; i < BLOCK_WORDS; i = i + 1)
                data[index_extracted][replace_way][i] = block_buf[i];
            tags[index_extracted][replace_way] = tag_extracted;
            valid[index_extracted][replace_way] = 1;
            next_state = SEND_INSTR;
        end

        SEND_INSTR: begin
            Instruction = block_buf[word_offset];
            Ready = 1;
            next_state = IDLE;
        end
    endcase
end

endmodule
