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

reg [NUM_TAG_BITS-1:0] tags     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg                   valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [31:0]            words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

wire [$clog2(NUM_SETS)-1:0] set_index = ReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0] tag_index = ReadAddress[31:OFFSET + $clog2(NUM_SETS)];

integer i, j, k;
reg [$clog2(NUM_WAYS)-1:0] word_iter_way;
reg [1:0] word_counter;
reg found_empty;
reg [31:0] sdram_block [BLOCK_WORDS - 1:0];
reg [31:0] target_word;
reg write_done;
reg need_to_write = 0;
reg hit_flag;

always @ (posedge Clk) begin
    if (!need_to_write) begin
        MemReadAddress <= 0;
        MemReadRequest <= 0;
        Ready <= 0;
        Instruction <= 0;
        hit_flag = 0;
        found_empty <= 0;

        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            $display("DEBUG: Checking tag[%0d][%0d] = %h, valid = %b, incoming = %h", set_index, i, tags[set_index][i], valid[set_index][i], tag_index);
            if (valid[set_index][i] && (tags[set_index][i] == tag_index) && Busy == 0 && ReadEnable) begin
                hit_flag = 1;
                Instruction <= words[set_index][i][ReadAddress[WORD_OFFSET-1:0]];
                Ready <= 1;
                Busy <= 0;
                $display("DEBUG: HIT! Set=%0d Way=%0d Word=%h", set_index, i, Instruction);
            end
        end

        if (hit_flag == 0 && ReadEnable && !Busy) begin
            $display("DEBUG: MISS! ReadAddress=%h Set=%0d Tag=%h", ReadAddress, set_index, tag_index);
            MemReadAddress <= ReadAddress;
            MemReadRequest <= 1;
            Busy <= 1;
            word_counter <= 0;

            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                if (valid[set_index][j] == 0 && !found_empty) begin
                    word_iter_way <= j;
                    found_empty <= 1;
                    $display("DEBUG: Chose empty way %0d", j);
                end
            end
            if (!found_empty) begin
                word_iter_way <= $random % NUM_WAYS;
                $display("DEBUG: Chose random way %0d", word_iter_way);
            end

            need_to_write <= 1;
        end
    end

    if (MemDataReady && need_to_write) begin
        $display("DEBUG: Receiving MemDataIn=%h at word_counter=%0d", MemDataIn, word_counter);
        sdram_block[word_counter] <= MemDataIn;
        if (word_counter == MemReadAddress[3:2]) begin
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
            need_to_write <= 0;
            $display("DEBUG: Wrote full block to cache at set %0d way %0d", set_index, word_iter_way);
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
