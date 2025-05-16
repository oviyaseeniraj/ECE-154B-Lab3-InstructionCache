module ucsbece154_icache #(
    parameter NUM_SETS   = 8,
    parameter NUM_WAYS   = 4,
    parameter BLOCK_WORDS= 4,
    parameter WORD_SIZE  = 32,
    parameter ADVANCED   = 1,
    parameter PREFETCH = 1
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
    input                     Misprediction,
    output reg		      imem_reset
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

// Refills use this stored address
reg [31:0] lastReadAddress;
wire [$clog2(NUM_SETS)-1:0] refill_set_index = lastReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0]     refill_tag_index = lastReadAddress[31:OFFSET + $clog2(NUM_SETS)];
wire [BLOCK_OFFSET-1:0]     refill_word_offset = lastReadAddress[OFFSET-1:WORD_OFFSET];

integer i, j, k;
reg [$clog2(NUM_WAYS)-1:0] hit_way;
reg [$clog2(NUM_WAYS)-1:0] latched_hit_way;
reg [$clog2(NUM_SETS)-1:0] latched_set_index;
reg hit_latched;
reg hit_this_cycle;

reg [$clog2(NUM_WAYS)-1:0] replace_way;
reg [1:0] word_counter;
reg [1:0] offset;
reg [31:0] sdram_block [BLOCK_WORDS - 1:0];
reg need_to_write;

reg [31:0] latchedReadAddress;

reg [31:0] prefetch_buffer [BLOCK_WORDS - 1:0];
reg [NUM_TAG_BITS-1:0] prefetch_tag;
reg [$clog2(NUM_SETS)-1:0] prefetch_index;
reg prefetch_valid;
reg [31:0] prefetch_address;
reg prefetch_in_progress;
wire is_prefetch_hit = prefetch_valid && (prefetch_tag == tag_index);
reg prefetch_word_counter;

always @ (posedge Clk) begin
    if (Reset) begin
        Ready <= 0;
        Instruction <= 0;
        Busy <= 0;
        MemReadAddress <= 0;
        MemReadRequest <= 0;
        word_counter <= 0;
        offset <= 0;
        need_to_write <= 0;
        lastReadAddress <= 0;
        hit_latched <= 0;
        latched_hit_way <= 0;
        hit_this_cycle <= 0;
        latchedReadAddress <= 0;
        prefetch_valid <= 0;
        prefetch_in_progress <= 0;
        prefetch_word_counter <= 0;

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
        // Default values
        Ready <= 0;
        imem_reset <= 0;
        hit_this_cycle = 0;

        // --- HIT DETECTION LOGIC ---
        if (Misprediction || (ReadEnable && !Busy && !need_to_write)) begin
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                if (valid[set_index][i] && tags[set_index][i] == tag_index) begin
                    hit_this_cycle = 1;
                    hit_way = i;
                end
            end
        end

        // CASE 1: HIT IN CACHE
        if (hit_this_cycle) begin
            if (Misprediction) begin
                MemReadRequest <= 0;
                MemReadAddress <= 0;
                need_to_write <= 0;
                imem_reset <= 1;
                Busy <= 0;
            end
            Instruction = words[set_index][hit_way][ReadAddress[OFFSET-1:WORD_OFFSET]];
            $display("instr at pc %h is %h", ReadAddress, Instruction);
            Ready <= 1;
            Busy <= 0;
        end else if (PREFETCH && prefetch_valid && prefetch_tag == tag_index && prefetch_index == set_index) begin
            // CASE 2: PREFETCH HIT
            // the requested word is supplied from prefetch buffer with no miss penalty
            Instruction <= prefetch_buffer[word_offset];
            Ready <= 1;
            Busy <= 0;

            // next cycle, the block in question from the prefetch buffer is written into cache
            need_to_write <= 1;
            lastReadAddress <= {ReadAddress[31:OFFSET], {(OFFSET){1'b0}}};

            // move from prefetch buffer into sdram buffer for cache writeback
            for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                sdram_block[k] = prefetch_buffer[k];
            end
            prefetch_valid <= 0;
        end


        // --- ONLY ENTER REFILL ON CONFIRMED MISS ---
        if (!hit_this_cycle && (Misprediction || (ReadEnable && !Busy && !need_to_write))) begin
            if (prefetch_in_progress && prefetch_word_counter == 0) begin
                // However, a block prefetch could be canceled if it is not yet started.
                prefetch_in_progress <= 0;
                MemReadRequest <= 0;
            end

            if (Misprediction) begin
                imem_reset <= 1;
                Busy <= 0;
            end
            $display("miss at time %0t, read_address=%h", $time, ReadAddress);
            lastReadAddress <= ReadAddress;
            MemReadAddress <= ReadAddress; // align to block
            MemReadRequest <= 1;

            // Choose replacement or empty way
            replace_way <= 0;
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                if (!valid[set_index][j]) begin
                    replace_way <= j;
                end
            end

            word_counter <= 0;
            offset <= 0;
            need_to_write = 1;
        end

        if (MemDataReady && need_to_write) begin
            Busy = 1;

            if (ADVANCED) begin
                if (word_counter == 0) begin
                    sdram_block[refill_word_offset] = MemDataIn;
                    Instruction <= MemDataIn;
                    Ready <= 1;
                end else begin
                    if (offset == refill_word_offset) begin
                        offset = offset + 1;
                    end
                    sdram_block[offset] = MemDataIn;
		            offset <= offset + 1;
                end
            end else begin
                sdram_block[word_counter] = MemDataIn;
            end

            if (word_counter == BLOCK_WORDS - 1) begin
                $display("writing to cache at time %0t, read_address=%h, refill_set_index=%0b, replace_way=%0b", $time, ReadAddress - 4, refill_set_index, replace_way);
                for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                    words[refill_set_index][replace_way][k] <= sdram_block[k];
                    $display("sdram_block[%0d] = %0h", k, sdram_block[k]);
                end
                tags[refill_set_index][replace_way] <= refill_tag_index;
                valid[refill_set_index][replace_way] <= 1;

                if (MemReadAddress < 32'h00010060 && !ADVANCED) begin
                    Instruction <= sdram_block[refill_word_offset];
                end
                Ready <= 1;
                Busy <= 0;
                MemReadRequest <= 0;
                need_to_write <= 0;

                // the prefetching of a new block from main memory is initiated to replace the block that was moved to cache
                if (PREFETCH && !prefetch_in_progress) begin
                    prefetch_address = {lastReadAddress[31:OFFSET], {(OFFSET){1'b0}}} + (BLOCK_WORDS << 2);
                    //MemReadAddress <= {lastReadAddress[31:OFFSET], {(OFFSET){1'b0}}} + (BLOCK_WORDS << 2);
                    MemReadAddress <= prefetch_address;
                    MemReadRequest <= 1;
                    prefetch_tag <= prefetch_address[31:OFFSET + $clog2(NUM_SETS)];
                    prefetch_index <= prefetch_address[OFFSET + $clog2(NUM_SETS) - 1 : OFFSET];
                    prefetch_in_progress <= 1;
                    prefetch_word_counter <= 0;
                end
            end
            word_counter <= word_counter + 1;
        end else if (PREFETCH && MemDataReady && prefetch_in_progress) begin 
        // Block transfer from SDRAM controller to cache controller cannot be interrupted
            prefetch_buffer[prefetch_word_counter] <= MemDataIn;
            prefetch_word_counter <= prefetch_word_counter + 1;
            if (prefetch_word_counter == BLOCK_WORDS-1) begin
                prefetch_valid <= 1;
                prefetch_in_progress <= 0;
                MemReadRequest <= 0;
            end
        end

    end
end

endmodule
