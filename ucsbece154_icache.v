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

localparam WORD_OFFSET = $clog2(4);
localparam BLOCK_OFFSET = $clog2(BLOCK_WORDS);
localparam OFFSET = WORD_OFFSET + BLOCK_OFFSET;
localparam NUM_TAG_BITS = 32 - $clog2(NUM_SETS) - OFFSET;

// Cache data structures
reg [NUM_TAG_BITS-1:0] tags     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg                   valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [31:0]            words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

reg [31:0] lastReadAddress; // FIX: hold address for comparison during refill

// Indexed from lastReadAddress (not ReadAddress) to fix mismatch
wire [$clog2(NUM_SETS)-1:0] set_index = lastReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET]; // FIX
wire [$clog2(NUM_TAG_BITS)-1:0] tag_index = lastReadAddress[31:OFFSET + $clog2(NUM_SETS)];   // FIX

wire [$clog2(NUM_SETS)-1:0] mem_set_index = MemReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [$clog2(NUM_TAG_BITS)-1:0] mem_tag_index = MemReadAddress[31:OFFSET + $clog2(NUM_SETS)];

integer i, j, k;
reg hit;
reg was_hit; // latch that hit occurred
reg [$clog2(NUM_WAYS)-1:0] word_iter_way;
reg [1:0] word_counter;
reg found_empty;
reg [31:0] sdram_block [BLOCK_WORDS - 1:0];
reg [31:0] target_word;
reg write_done;
reg need_to_write = 0;

always @ (posedge Clk) begin
    if (Reset) begin
        Ready <= 0; // FIX
        write_done <= 0; // FIX
        was_hit <= 0; // FIX
        Instruction <= 0;
        Busy <= 0;
        MemReadAddress <= 0;
        MemReadRequest <= 0;
        word_counter <= 0;
        need_to_write <= 0;
        target_word <= 0;
        lastReadAddress <= 0; // FIX

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
        was_hit <= 0;

        if (!need_to_write) begin
            MemReadAddress <= 0;
            MemReadRequest <= 0;
            Instruction <= 0;
            hit = 0;
            found_empty = 0;

            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                $display("finding hit in way %d\n", i);
                if (valid[set_index][i] && tags[set_index][i] == tag_index && Busy == 0 && ReadEnable) begin
                    hit = 1;
                    Instruction <= words[set_index][i][lastReadAddress[WORD_OFFSET-1:0]]; // FIX
                    was_hit <= 1;
                    Busy <= 0;
                end
            end

            if (hit == 0) begin
                $display("miss, need to fetch from memory");
                lastReadAddress <= ReadAddress; // FIX
                MemReadAddress <= ReadAddress;
                MemReadRequest <= 1;
                Busy <= 1;

                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    if (!valid[set_index][j] && !found_empty) begin
                        word_iter_way = j;
                        word_counter <= 0;
                        found_empty = 1;
                    end
                end
                if (!found_empty) begin
                    word_iter_way = $random % NUM_WAYS;
                    word_counter <= 0;
                end
                need_to_write <= 1;
            end
        end

        if (MemDataReady && need_to_write) begin
            sdram_block[word_counter] = MemDataIn;

            if (word_counter == MemReadAddress[3:2]) begin
                target_word <= MemDataIn;
            end

            if (word_counter == BLOCK_WORDS - 1) begin
                for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                    words[mem_set_index][word_iter_way][k] <= sdram_block[k];
                end
                tags[mem_set_index][word_iter_way] <= mem_tag_index;
                valid[mem_set_index][word_iter_way] <= 1;
                Busy <= 0;
                MemReadRequest <= 0;
                write_done <= 1;
            end

            word_counter <= word_counter + 1;
            if (word_counter == BLOCK_WORDS - 1) begin
                need_to_write <= 0;
            end
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
            write_done <= 0;
        end else if (was_hit) begin
            Ready <= 1;
        end else begin
            Ready <= 0;
        end
    end
end

endmodule
