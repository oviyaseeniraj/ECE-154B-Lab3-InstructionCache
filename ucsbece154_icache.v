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

localparam WORD_OFFSET = 2; // Fixed for word-aligned addresses
localparam BLOCK_OFFSET = $clog2(BLOCK_WORDS);
localparam OFFSET = WORD_OFFSET + BLOCK_OFFSET;
localparam NUM_TAG_BITS = 32 - $clog2(NUM_SETS) - OFFSET;

// Cache data structures
reg [NUM_TAG_BITS-1:0] tags     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg                   valid     [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [31:0]            words     [0:NUM_SETS-1][0:NUM_WAYS-1][0:BLOCK_WORDS-1];
reg [$clog2(NUM_WAYS)-1:0] lru_counters [0:NUM_SETS-1][0:NUM_WAYS-1];

reg [31:0] lastReadAddress;
reg [31:0] currentAddress;
reg [1:0] saved_word_offset;

// Extract indices from current read address
wire [$clog2(NUM_SETS)-1:0] set_index = ReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0] tag_index = ReadAddress[31:OFFSET + $clog2(NUM_SETS)];
wire [1:0] word_offset = ReadAddress[3:2];

// For memory reads
wire [$clog2(NUM_SETS)-1:0] mem_set_index = lastReadAddress[OFFSET + $clog2(NUM_SETS)-1:OFFSET];
wire [NUM_TAG_BITS-1:0] mem_tag_index = lastReadAddress[31:OFFSET + $clog2(NUM_SETS)];

integer i, j, k;
wire hit;
reg [$clog2(NUM_WAYS)-1:0] hit_way;
reg [$clog2(NUM_WAYS)-1:0] replace_way;
reg [1:0] word_counter;
reg need_to_write;
reg last_read_enable;
reg addr_changed;

// Combinational hit detection
reg hit_found;
reg [$clog2(NUM_WAYS)-1:0] found_way;

always @* begin
    hit_found = 0;
    found_way = 0;
    for (i = 0; i < NUM_WAYS; i = i + 1) begin
        if (valid[set_index][i] && tags[set_index][i] == tag_index) begin
            hit_found = 1;
            found_way = i;
        end
    end
end

assign hit = hit_found;

// LRU replacement policy
function automatic [$clog2(NUM_WAYS)-1:0] find_lru_way;
    input [$clog2(NUM_SETS)-1:0] set;
    reg [$clog2(NUM_WAYS)-1:0] max_count;
    reg [$clog2(NUM_WAYS)-1:0] lru_way;
    begin
        max_count = 0;
        lru_way = 0;
        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            if (!valid[set][i]) begin
                lru_way = i;
                max_count = {$clog2(NUM_WAYS){1'b1}};
            end else if (lru_counters[set][i] > max_count) begin
                max_count = lru_counters[set][i];
                lru_way = i;
            end
        end
        find_lru_way = lru_way;
    end
endfunction

always @ (posedge Clk) begin
    if (Reset) begin
        Ready <= 0;
        Instruction <= 0;
        Busy <= 0;
        MemReadAddress <= 0;
        MemReadRequest <= 0;
        word_counter <= 0;
        need_to_write <= 0;
        lastReadAddress <= 0;
        currentAddress <= 0;
        saved_word_offset <= 0;
        replace_way <= 0;
        last_read_enable <= 0;
        addr_changed <= 0;

        for (i = 0; i < NUM_SETS; i = i + 1) begin
            for (j = 0; j < NUM_WAYS; j = j + 1) begin
                valid[i][j] <= 0;
                tags[i][j] <= 0;
                lru_counters[i][j] <= j;
                for (k = 0; k < BLOCK_WORDS; k = k + 1) begin
                    words[i][j][k] <= 0;
                end
            end
        end
    end else begin
        // Track ReadEnable transitions and address changes
        last_read_enable <= ReadEnable;
        addr_changed <= (ReadAddress != currentAddress);
        
        // Default: maintain Ready unless explicitly changed
        Ready <= Ready;
        
        if (!ReadEnable) begin
            // When ReadEnable is low, clear request and Ready
            MemReadRequest <= 0;
            Ready <= 0;
            if (!need_to_write) begin
                Busy <= 0;
            end
        end else begin
            // Clear Ready on address change
            if (addr_changed) begin
                Ready <= 0;
                currentAddress <= ReadAddress;
            end
            
            // Process new request when:
            // 1. Address changes
            // 2. ReadEnable transitions from low to high
            // 3. Not currently processing a request
            if (addr_changed || !last_read_enable || (!Ready && !Busy && !need_to_write)) begin
                if (hit) begin
                    // Cache hit - immediately output the data
                    Instruction <= words[set_index][found_way][word_offset];
                    Ready <= 1;
                    Busy <= 0;
                    MemReadRequest <= 0;
                    
                    // Update LRU counters
                    for (i = 0; i < NUM_WAYS; i = i + 1) begin
                        if (i == found_way)
                            lru_counters[set_index][i] <= 0;
                        else if (lru_counters[set_index][i] < lru_counters[set_index][found_way])
                            lru_counters[set_index][i] <= lru_counters[set_index][i] + 1;
                    end
                end else if (!need_to_write && !Busy) begin
                    // Cache miss, initiate memory read
                    lastReadAddress <= ReadAddress;
                    saved_word_offset <= word_offset;
                    MemReadAddress <= {ReadAddress[31:4], 4'b0000};  // Align to 16-byte block
                    MemReadRequest <= 1;
                    Busy <= 1;
                    Ready <= 0;
                    
                    // Find LRU way for replacement
                    replace_way <= find_lru_way(set_index);
                    
                    word_counter <= 0;
                    need_to_write <= 1;
                end
            end
        end

        // Handle memory response
        if (MemDataReady && need_to_write) begin
            // Store word directly into cache
            words[mem_set_index][replace_way][word_counter] <= MemDataIn;
            
            // Check if this is the word we need
            if (word_counter == saved_word_offset) begin
                Instruction <= MemDataIn;
                Ready <= 1;
            end
            
            if (word_counter == BLOCK_WORDS - 1) begin
                tags[mem_set_index][replace_way] <= mem_tag_index;
                valid[mem_set_index][replace_way] <= 1;
                
                // Reset LRU counter for new entry
                for (i = 0; i < NUM_WAYS; i = i + 1) begin
                    if (i == replace_way)
                        lru_counters[mem_set_index][i] <= 0;
                    else
                        lru_counters[mem_set_index][i] <= lru_counters[mem_set_index][i] + 1;
                end
                
                Busy <= 0;
                MemReadRequest <= 0;
                need_to_write <= 0;
            end
            
            word_counter <= word_counter + 1;
        end
    end
end

endmodule
