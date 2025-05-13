module ucsbece154_icache #(
    parameter NUM_SETS    = 8,
    parameter NUM_WAYS    = 4,
    parameter BLOCK_WORDS = 4,
    parameter WORD_SIZE   = 32
)(
    input                     Clk,
    input                     Reset,

    // core fetch interface
    input                     ReadEnable,     // Asserted by core when it wants to read
    input      [31:0]         ReadAddress,    // Address from core (PC)
    output reg [WORD_SIZE-1:0]Instruction,    // Instruction to core
    output reg                Ready,          // High when Instruction is valid for one cycle
    output reg                Busy,           // High when cache is busy with a refill

    // SDRAM-controller interface
    output reg [31:0]         MemReadAddress, // Address to memory for refill
    output reg                MemReadRequest, // Request to memory
    input      [31:0]         MemDataIn,      // Data from memory
    input                     MemDataReady    // Memory data is ready
);

    localparam WORD_BYTES_LOG2 = $clog2(WORD_SIZE/8); // e.g., 2 for 32-bit words (4 bytes)
    localparam BLOCK_WORDS_LOG2 = $clog2(BLOCK_WORDS); // e.g., 2 for 4 words/block
    localparam SET_INDEX_BITS = $clog2(NUM_SETS);    // e.g., 3 for 8 sets

    // Offset to get to the start of the set index bits from LSB of address
    localparam OFFSET_BITS = WORD_BYTES_LOG2 + BLOCK_WORDS_LOG2; // e.g., 2 + 2 = 4. Addr[3:2] is word in block. Addr[6:4] is set.

    localparam TAG_BITS = WORD_SIZE - SET_INDEX_BITS - OFFSET_BITS;

    // Cache data structures
    reg [TAG_BITS-1:0]    tags     [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                   valid    [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [WORD_SIZE-1:0]   words    [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];

    // Internal signals for FSM and data path
    reg [31:0]            lastReadAddress_missed; // Stores the ReadAddress that caused the current miss

    // Signals derived from current ReadAddress for hit checking
    wire [SET_INDEX_BITS-1:0] current_set_idx;
    wire [TAG_BITS-1:0]       current_tag_val;
    wire [BLOCK_WORDS_LOG2-1:0] current_word_offset_in_block; // Word index within the block

    // Signals derived from lastReadAddress_missed for refill operations
    wire [SET_INDEX_BITS-1:0] refill_set_idx;
    wire [TAG_BITS-1:0]       refill_tag_val;
    wire [BLOCK_WORDS_LOG2-1:0] refill_target_word_offset;


    assign current_set_idx = ReadAddress[OFFSET_BITS + SET_INDEX_BITS - 1 : OFFSET_BITS];
    assign current_tag_val = ReadAddress[WORD_SIZE - 1 : OFFSET_BITS + SET_INDEX_BITS];
    assign current_word_offset_in_block = (BLOCK_WORDS > 1) ? ReadAddress[OFFSET_BITS - 1 : WORD_BYTES_LOG2] : 0;

    assign refill_set_idx = lastReadAddress_missed[OFFSET_BITS + SET_INDEX_BITS - 1 : OFFSET_BITS];
    assign refill_tag_val = lastReadAddress_missed[WORD_SIZE - 1 : OFFSET_BITS + SET_INDEX_BITS];
    assign refill_target_word_offset = (BLOCK_WORDS > 1) ? lastReadAddress_missed[OFFSET_BITS - 1 : WORD_BYTES_LOG2] : 0;


    // State and temporary registers
    reg hit_this_cycle_flag;
    reg [$clog2(NUM_WAYS)-1:0] way_of_hit;
    reg [WORD_SIZE-1:0] data_from_cache_hit;   // Data read from cache on a hit

    reg refill_in_progress;      // True when waiting for memory
    reg [$clog2(NUM_WAYS)-1:0] way_to_refill;
    reg [$clog2(BLOCK_WORDS)-1:0] word_counter_refill; // Counts words received from memory
    reg [WORD_SIZE-1:0] sdram_block_buffer [0:BLOCK_WORDS-1];
    reg [WORD_SIZE-1:0] target_word_from_refill; // The specific instruction fetched from memory
    reg refill_block_written_flag; // Set for one cycle after block write to cache is done

    integer i, j, k; // Loop iterators
    integer found_empty_way; // Flag to indicate if an empty way was found in the set

    // Main FSM and Cache Operation Logic
    always @(posedge Clk) begin
        if (Reset) begin
            Busy <= 0;
            MemReadRequest <= 0;
            lastReadAddress_missed <= 0;

            hit_this_cycle_flag <= 0;
            refill_in_progress <= 0;
            refill_block_written_flag <= 0;
            word_counter_refill <= 0;
            // target_word_from_refill, data_from_cache_hit will be assigned before use or in output block reset

            for (i = 0; i < NUM_SETS; i = i + 1) begin
                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    valid[i][j] <= 0;
                    tags[i][j] <= 0; // Optional: can be garbage if valid is 0
                    // words can also be left as garbage if valid is 0
                end
            end
        end else begin
            // Default values for flags that are pulse-like or re-evaluated each cycle
            hit_this_cycle_flag <= 0;
            refill_block_written_flag <= 0; // Cleared each cycle, set only when refill completes

            if (!refill_in_progress) begin // Only process new requests if not already refilling
                MemReadRequest <= 0; // Default unless a new miss occurs

                if (ReadEnable) begin
                    // --- Cache Hit Detection ---
                    for (i = 0; i < NUM_WAYS; i = i + 1) begin
                        if (valid[current_set_idx][i] && (tags[current_set_idx][i] == current_tag_val)) begin
                            data_from_cache_hit <= words[current_set_idx][i][current_word_offset_in_block];
                            hit_this_cycle_flag <= 1;
                            way_of_hit <= i; // Not used in random, but good for other policies
                            Busy <= 0; // A hit means we are not busy (or become not busy)
                            break; // Found hit
                        end
                    end

                    if (!hit_this_cycle_flag) begin // This was a ReadEnable, but not a hit -> MISS
                        Busy <= 1; // Cache is busy fetching from memory
                        refill_in_progress <= 1;
                        MemReadRequest <= 1;
                        lastReadAddress_missed <= ReadAddress; // Store the address that missed
                        // Align MemReadAddress to the start of the block for the memory request
                        MemReadAddress <= {ReadAddress[WORD_SIZE-1:OFFSET_BITS], {OFFSET_BITS{1'b0}} };

                        // Select way for replacement (random or find empty)
                        // For simplicity using $random, ensure your synthesis tool supports it or use an LFSR
                        // Or, implement finding an empty way first
                        found_empty_way = 0;
                        for (j = 0; j < NUM_WAYS; j = j + 1) begin
                            if (!valid[current_set_idx][j]) begin // Check in the set of the current miss
                                way_to_refill <= j;
                                found_empty_way = 1;
                                break;
                            end
                        end
                        if (!found_empty_way) begin
                            way_to_refill <= $random % NUM_WAYS;
                        end
                        word_counter_refill <= 0; // Reset for block refill
                    end
                end else begin // No ReadEnable
                    Busy <= 0; // If not ReadEnable and not refilling, not busy
                end
            end // end if (!refill_in_progress)

            // --- Cache Refill Logic (when MemDataReady) ---
            if (refill_in_progress && MemDataReady) begin
                sdram_block_buffer[word_counter_refill] = MemDataIn;

                // Check if this is the target word for the original miss
                if (word_counter_refill == refill_target_word_offset) begin
                    target_word_from_refill <= MemDataIn;
                end

                if (word_counter_refill == BLOCK_WORDS - 1) begin
                    // Entire block received, write to cache
                    for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                        words[refill_set_idx][way_to_refill][k] <= sdram_block_buffer[k];
                    end
                    tags[refill_set_idx][way_to_refill] <= refill_tag_val;
                    valid[refill_set_idx][way_to_refill] <= 1;

                    MemReadRequest <= 0;
                    refill_in_progress <= 0; // Done with memory fetch
                    refill_block_written_flag <= 1;  // Indicate to output logic that data is ready
                    Busy <= 0; // Cache is no longer busy with this refill
                    word_counter_refill <= 0; // Reset for next potential refill
                end else begin
                    word_counter_refill <= word_counter_refill + 1;
                end
            end
        end
    end

    // Output Logic for Instruction and Ready (combinatorial based on registered flags)
    always @(posedge Clk) begin
        if (Reset) begin
            Instruction <= {WORD_SIZE{1'b0}};
            Ready <= 0;
        end else begin
            // These flags (hit_this_cycle_flag, refill_block_written_flag) were set in the previous cycle's
            // main always block and are now stable inputs to this output logic block.
            if (refill_block_written_flag) begin // Priority to just refilled data
                Instruction <= target_word_from_refill;
                Ready <= 1;
            end else if (hit_this_cycle_flag) begin
                Instruction <= data_from_cache_hit;
                Ready <= 1;
            end else begin
                Ready <= 0; // Instruction holds previous value if not a hit or fresh refill
            end
        end
    end

endmodule