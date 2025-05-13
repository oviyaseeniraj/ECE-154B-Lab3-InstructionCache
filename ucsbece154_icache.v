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

reg [NUM_TAG_BITS-1:0] tags     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg                   valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [31:0]            words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

wire [$clog2(NUM_SETS)-1:0] set_index = ReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [$clog2(NUM_TAG_BITS)-1:0] tag_index = ReadAddress[31:OFFSET + $clog2(NUM_SETS)];

integer i, j, k;
reg hit;
reg [$clog2(NUM_WAYS)-1:0] word_iter_way;
reg [1:0] word_counter;
reg found_empty;
reg [31:0] sdram_block [BLOCK_WORDS - 1:0];
reg [31:0] target_word;
reg write_done;
reg need_to_write = 0;

always @ (posedge Clk) begin
    if (!need_to_write) begin
        // MemReadAddress = 0;
        MemReadAddress <= 0; // NEW
        // MemReadRequest = 0;
        MemReadRequest <= 0; // NEW
        // Ready = 0;
        Ready <= 0; // NEW
        // Instruction = 0;
        Instruction <= 0; // NEW
        hit = 0;
        found_empty = 0;

        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            $display("finding hit in way %d\n", i);
            if (valid[set_index][i] && (tags[set_index][i] == tag_index) && Busy == 0 && ReadEnable) begin
                hit = 1;
                // Instruction = words[set_index][i][ReadAddress[WORD_OFFSET-1:0]];
                Instruction <= words[set_index][i][ReadAddress[WORD_OFFSET-1:0]]; // NEW
                // Ready = 1;
                Ready <= 1; // NEW
                // Busy = 0;
                Busy <= 0; // NEW
            end
        end
        if (hit == 0) begin
            $display("miss, need to fetch from memory\n");
            // MemReadAddress = ReadAddress;
            MemReadAddress <= ReadAddress; // NEW
            // MemReadRequest = 1;
            MemReadRequest <= 1; // NEW
            // Busy = 1;
            Busy <= 1; // NEW

            $display("wordcounter=-1\n");
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                if (valid[set_index][j] == 0 && found_empty == 0) begin
                    word_iter_way = j;
                    $display("found empty way %d\n", j);
                    // word_counter = 0;
                    word_counter <= 0; // NEW
                    found_empty = 1;
                end
            end
            if (found_empty == 0) begin
                word_iter_way = $random % NUM_WAYS;
                // word_counter = 0;
                word_counter <= 0; // NEW
            end
            $display("wordcounter=%d\n", word_counter);
            // need_to_write = 1;
            need_to_write <= 1; // NEW
        end
    end

    if (MemDataReady && need_to_write) begin
        $display("writing back to cache\n");
        if (word_counter == MemReadAddress[3:2]) begin
            // target_word <= MemDataIn;
            target_word <= MemDataIn; // NEW (correct already)
        end

        // sdram_block[word_counter] <= MemDataIn;
        sdram_block[word_counter] = MemDataIn; // NEW: use blocking for memory array writes

        if (word_counter == BLOCK_WORDS - 1) begin
            for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                // words[set_index][word_iter_way][k] <= sdram_block[k];
                words[set_index][word_iter_way][k] <= sdram_block[k]; // NEW (correct already)
            end
            // tags[set_index][word_iter_way] <= tag_index;
            tags[set_index][word_iter_way] <= tag_index; // NEW (correct already)
            // valid[set_index][word_iter_way] <= 1;
            valid[set_index][word_iter_way] <= 1; // NEW (correct already)
            // Busy <= 0;
            Busy <= 0; // NEW
            // MemReadRequest <= 0;
            MemReadRequest <= 0; // NEW
            // write_done <= 1;
            write_done <= 1; // NEW
        end
        // word_counter <= word_counter + 1;
        word_counter <= word_counter + 1; // NEW
        $display("wordcounter in write=%d\n", word_counter);
        if (word_counter == BLOCK_WORDS - 1) begin
            // need_to_write <= 0;
            need_to_write <= 0; // NEW
        end
    end
end

always @ (posedge Clk) begin
    if (Reset) begin
        // Ready <= 0;
        Ready <= 0; // NEW
        // write_done <= 0;
        write_done <= 0; // NEW
    end else begin
        if (write_done) begin
            // Instruction <= target_word;
            Instruction <= target_word; // NEW
            // Ready <= 1;
            Ready <= 1; // NEW
            // write_done <= 0;
            write_done <= 0; // NEW
        end else begin
            // Ready <= 0;
            Ready <= 0; // NEW
        end
    end
end

endmodule
