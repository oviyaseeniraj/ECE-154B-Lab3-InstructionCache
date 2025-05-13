module ucsbece154_icache #(
    parameter NUM_SETS   = 8,
    parameter NUM_WAYS   = 4,
    parameter BLOCK_WORDS= 4,
    parameter WORD_SIZE  = 32
)(
    input                     Clk,
    input                     Reset,
    input                     ReadEnable,
    input      [31:0]         ReadAddress,
    output reg [WORD_SIZE-1:0]Instruction,
    output reg                Ready,
    output reg                Busy,
    output reg [31:0]         MemReadAddress,
    output reg                MemReadRequest,
    input      [31:0]         MemDataIn,
    input                     MemDataReady
);

    localparam WORD_BYTES_LOG2 = $clog2(WORD_SIZE/8);
    localparam BLOCK_WORDS_LOG2 = $clog2(BLOCK_WORDS);
    localparam SET_INDEX_BITS = $clog2(NUM_SETS);
    localparam OFFSET_BITS = BLOCK_WORDS_LOG2 + WORD_BYTES_LOG2;
    localparam NUM_TAG_BITS = 32 - SET_INDEX_BITS - OFFSET_BITS;

    reg [NUM_TAG_BITS-1:0] tags      [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                    valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [WORD_SIZE-1:0]    words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

    reg [31:0]             r_last_miss_address;
    reg                    r_refill_in_progress;
    reg [$clog2(NUM_WAYS)-1:0] r_way_to_refill;
    reg [$clog2(BLOCK_WORDS)-1:0] r_word_counter_refill;
    reg [WORD_SIZE-1:0]    r_sdram_block_buffer [0:BLOCK_WORDS-1];
    reg [WORD_SIZE-1:0]    r_target_word_from_refill;
    
    // Registers for state to be used by the output logic in the next cycle
    reg                    r_is_hit_for_output;
    reg [WORD_SIZE-1:0]    r_data_from_hit_for_output;
    reg                    r_refill_done_for_output;


    integer i, j, k;

    wire [SET_INDEX_BITS-1:0]   w_current_set_index = ReadAddress[OFFSET_BITS + SET_INDEX_BITS - 1 : OFFSET_BITS];
    wire [NUM_TAG_BITS-1:0]     w_current_tag_value = ReadAddress[31 : OFFSET_BITS + SET_INDEX_BITS];
    wire [BLOCK_WORDS_LOG2-1:0] w_current_word_offset_in_block = ReadAddress[OFFSET_BITS -1 : WORD_BYTES_LOG2];

    wire [SET_INDEX_BITS-1:0]   w_refill_set_index = r_last_miss_address[OFFSET_BITS + SET_INDEX_BITS - 1 : OFFSET_BITS];
    wire [NUM_TAG_BITS-1:0]     w_refill_tag_value = r_last_miss_address[31 : OFFSET_BITS + SET_INDEX_BITS];
    wire [BLOCK_WORDS_LOG2-1:0] w_refill_word_offset_in_block = r_last_miss_address[OFFSET_BITS - 1 : WORD_BYTES_LOG2];

    always @(posedge Clk) begin
        if (Reset) begin
            Busy <= 0;
            MemReadAddress <= 0;
            MemReadRequest <= 0;
            r_refill_in_progress <= 0;
            r_word_counter_refill <= 0;
            r_last_miss_address <= 0;

            r_is_hit_for_output <= 0;
            r_refill_done_for_output <= 0;
            // r_data_from_hit_for_output and r_target_word_from_refill don't need reset if only used when flags are set

            for (i = 0; i < NUM_SETS; i = i + 1) begin
                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    valid[i][j] <= 0;
                end
            end
        end else begin
            // Default values for next cycle's output stage flags
            r_is_hit_for_output <= 0;
            r_refill_done_for_output <= 0;

            // --- Cache Access Logic (Hit/Miss Detection) ---
            if (ReadEnable && !r_refill_in_progress) begin
                reg hit_found_this_evaluation; // Temporary for this cycle's logic
                reg [WORD_SIZE-1:0] data_if_hit_temp;
                hit_found_this_evaluation = 0;
                data_if_hit_temp = 32'bx; // Default

                for (i = 0; i < NUM_WAYS; i = i + 1) begin
                    if (!hit_found_this_evaluation && valid[w_current_set_index][i] && (tags[w_current_set_index][i] == w_current_tag_value)) begin
                        data_if_hit_temp = words[w_current_set_index][i][w_current_word_offset_in_block];
                        hit_found_this_evaluation = 1;
                    end
                end

                if (hit_found_this_evaluation) begin
                    r_data_from_hit_for_output <= data_if_hit_temp;
                    r_is_hit_for_output <= 1; // For next cycle's output logic
                    Busy <= 0;
                    MemReadRequest <= 0; // Ensure request is low on a hit
                end else begin // Cache Miss
                    Busy <= 1;
                    r_refill_in_progress <= 1;
                    MemReadRequest <= 1;
                    r_last_miss_address <= ReadAddress;
                    MemReadAddress <= ReadAddress; // Or block-aligned version

                    // Select way for replacement
                    reg empty_way_found_temp;
                    reg [$clog2(NUM_WAYS)-1:0] way_to_refill_temp;

                    empty_way_found_temp = 0;
                    way_to_refill_temp = $random % NUM_WAYS; // Default to random

                    for (j = 0; j < NUM_WAYS; j = j + 1) begin
                        if (!empty_way_found_temp && !valid[w_refill_set_index][j]) begin
                            way_to_refill_temp = j;
                            empty_way_found_temp = 1;
                        end
                    end
                    r_way_to_refill <= way_to_refill_temp;
                    r_word_counter_refill <= 0;
                end
            end

            // --- Cache Refill Logic ---
            if (r_refill_in_progress) begin
                if (MemDataReady) begin
                    r_sdram_block_buffer[r_word_counter_refill] = MemDataIn;

                    if (r_word_counter_refill == w_refill_word_offset_in_block) begin
                        r_target_word_from_refill <= MemDataIn;
                    end

                    if (r_word_counter_refill == BLOCK_WORDS - 1) begin
                        for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                            words[w_refill_set_index][r_way_to_refill][k] <= r_sdram_block_buffer[k];
                        end
                        tags[w_refill_set_index][r_way_to_refill] <= w_refill_tag_value;
                        valid[w_refill_set_index][r_way_to_refill] <= 1;

                        MemReadRequest <= 0;
                        r_refill_in_progress <= 0;
                        r_refill_done_for_output <= 1; // For next cycle's output logic
                        Busy <= 0;
                    end else begin
                        r_word_counter_refill <= r_word_counter_refill + 1;
                    end
                end
                // If still refilling, MemReadRequest was set high on miss and remains high until refill done.
            end else begin // Not refilling
                 // If not initiating a new miss (covered by ReadEnable && !r_refill_in_progress && !hit),
                 // ensure MemReadRequest is low.
                 if (!(ReadEnable && !r_refill_in_progress && !r_is_hit_for_output)) begin // Be careful with r_is_hit_for_output, it's for next cycle
                     // A simpler approach: MemReadRequest is set high on miss, low on refill completion or hit.
                     // If current state is a hit (determined this cycle), MemReadRequest should be low.
                     // This is handled in the hit condition already.
                 end
            end
        end
    end

    // Output logic for Instruction and Ready
    always @(posedge Clk) begin
        if (Reset) begin
            Instruction <= 0;
            Ready <= 0;
        end else begin
            Ready <= 0; // Default

            if (r_refill_done_for_output) begin // From previous cycle's operation
                Instruction <= r_target_word_from_refill;
                Ready <= 1;
            end else if (r_is_hit_for_output) begin // From previous cycle's operation
                Instruction <= r_data_from_hit_for_output;
                Ready <= 1;
            end
        end
    end
endmodule
