// --- Corrected ucsbece154_icache.v (Verilog-2001 declaration fix) ---
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

    // Cache data structures
    reg [NUM_TAG_BITS-1:0] tags      [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                    valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [WORD_SIZE-1:0]    words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

    // Internal state registers
    reg [31:0]             r_last_miss_address;
    reg                    r_refill_in_progress;
    reg [$clog2(NUM_WAYS)-1:0] r_way_to_refill;
    reg [$clog2(BLOCK_WORDS)-1:0] r_word_counter_refill; // Max value is BLOCK_WORDS-1
    reg [WORD_SIZE-1:0]    r_sdram_block_buffer [0:BLOCK_WORDS-1];
    reg [WORD_SIZE-1:0]    r_target_word_from_refill;
    
    // Registers for state to be used by the output logic in the next cycle
    reg                    r_is_hit_for_output;          // Registered: indicates if previous cycle was a hit
    reg [WORD_SIZE-1:0]    r_data_from_hit_for_output; // Registered: data if previous cycle was a hit
    reg                    r_refill_done_for_output;     // Registered: indicates if previous cycle completed a refill

    // Temporary registers needed for logic within a single cycle in the always block
    // These are not strictly "state" across cycles but are used to hold values
    // during the evaluation of the always block before assigning to state registers.
    // For Verilog-2001, they must be declared here if assigned procedurally.
    reg                    s_hit_found_this_evaluation; // 's_' for "scratch" or "sequential-logic-temp"
    reg [WORD_SIZE-1:0]    s_data_if_hit_temp;
    reg                    s_empty_way_found_temp;
    reg [$clog2(NUM_WAYS)-1:0] s_way_to_refill_temp;


    integer i, j, k; // Loop iterators

    // Wires for address decomposition
    wire [SET_INDEX_BITS-1:0]   w_current_set_index = ReadAddress[OFFSET_BITS + SET_INDEX_BITS - 1 : OFFSET_BITS];
    wire [NUM_TAG_BITS-1:0]     w_current_tag_value = ReadAddress[31 : OFFSET_BITS + SET_INDEX_BITS];
    wire [BLOCK_WORDS_LOG2-1:0] w_current_word_offset_in_block = ReadAddress[OFFSET_BITS -1 : WORD_BYTES_LOG2];

    wire [SET_INDEX_BITS-1:0]   w_refill_set_index = r_last_miss_address[OFFSET_BITS + SET_INDEX_BITS - 1 : OFFSET_BITS];
    wire [NUM_TAG_BITS-1:0]     w_refill_tag_value = r_last_miss_address[31 : OFFSET_BITS + SET_INDEX_BITS];
    wire [BLOCK_WORDS_LOG2-1:0] w_refill_word_offset_in_block = r_last_miss_address[OFFSET_BITS - 1 : WORD_BYTES_LOG2];

    // Main state machine, hit/miss logic, memory interface
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
            // r_data_from_hit_for_output and r_target_word_from_refill reset is optional
            // as they are only used when the corresponding flags are set.
            // Instruction and Ready are reset in their own always block.

            for (i = 0; i < NUM_SETS; i = i + 1) begin
                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    valid[i][j] <= 0;
                    // tags[i][j] <= 0; // Optional, valid bit is primary
                end
            end
        end else begin
            // Default values for output stage flags (for the *next* clock cycle)
            r_is_hit_for_output <= 0;
            r_refill_done_for_output <= 0;

            // --- Cache Access Logic (Hit/Miss Detection) ---
            if (ReadEnable && !r_refill_in_progress) begin
                // Use s_ prefixed regs for this cycle's combinational-like evaluation
                s_hit_found_this_evaluation = 0;
                s_data_if_hit_temp = 32'bx; // Default to x for uninitialized

                for (i = 0; i < NUM_WAYS; i = i + 1) begin
                    if (!s_hit_found_this_evaluation && valid[w_current_set_index][i] && (tags[w_current_set_index][i] == w_current_tag_value)) begin
                        s_data_if_hit_temp = words[w_current_set_index][i][w_current_word_offset_in_block];
                        s_hit_found_this_evaluation = 1;
                        // No break in Verilog-2001, this flag handles it.
                    end
                end

                if (s_hit_found_this_evaluation) begin // Cache Hit
                    r_data_from_hit_for_output <= s_data_if_hit_temp; // Register for next cycle's output
                    r_is_hit_for_output <= 1;                         // Register for next cycle's output
                    Busy <= 0;
                    MemReadRequest <= 0; // Ensure request is low on a hit
                end else begin // Cache Miss
                    // r_is_hit_for_output already defaulted to 0 or will be set to 0 by previous default
                    Busy <= 1;
                    r_refill_in_progress <= 1;
                    MemReadRequest <= 1;
                    r_last_miss_address <= ReadAddress;
                    MemReadAddress <= ReadAddress; // Or block-aligned version

                    // Select way for replacement using s_ prefixed temp regs
                    s_empty_way_found_temp = 0;
                    s_way_to_refill_temp = $random % NUM_WAYS; // Default to random

                    for (j = 0; j < NUM_WAYS; j = j + 1) begin
                        if (!s_empty_way_found_temp && !valid[w_refill_set_index][j]) begin
                            s_way_to_refill_temp = j;
                            s_empty_way_found_temp = 1;
                        end
                    end
                    r_way_to_refill <= s_way_to_refill_temp; // Register chosen way
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
                        r_refill_done_for_output <= 1; // Register for next cycle's output logic
                        Busy <= 0;
                    end else begin
                        r_word_counter_refill <= r_word_counter_refill + 1;
                    end
                end
                // If still refilling, MemReadRequest was set high on miss and remains high until refill done.
            end else begin // Not refilling
                 // If a new request isn't a miss (i.e., it was a hit or no ReadEnable), MemReadRequest should be low.
                 // This is handled: on a hit, MemReadRequest <= 0. On miss, MemReadRequest <= 1.
                 // When idle (no ReadEnable), it depends on the previous state.
                 // To be safe, if not refilling and not a new miss starting, ensure it's low.
                 if (!(ReadEnable && !r_refill_in_progress && !s_hit_found_this_evaluation)) begin // If not starting a new miss
                    if (!r_refill_in_progress) begin // And not already refilling (double check)
                        MemReadRequest <= 0;
                    end
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

            if (r_refill_done_for_output) begin // True if refill completed in the *previous* cycle
                Instruction <= r_target_word_from_refill;
                Ready <= 1;
            end else if (r_is_hit_for_output) begin // True if a hit occurred in the *previous* cycle
                Instruction <= r_data_from_hit_for_output;
                Ready <= 1;
            end
            // No else for Instruction: it holds its value if not a hit and not refill_done
        end
    end
endmodule