// ucsbece154_imem.v
// Emulated SDRAM Controller for Lab 3 Baseline ICache
// NEW: Filled out memory controller module for block burst

`define MIN(A,B) (((A)<(B))?(A):(B))

module ucsbece154_imem #(
    parameter TEXT_SIZE = 64,
    parameter BLOCK_WORDS = 4,          // words per burst (must match cache)
    parameter T0_DELAY = 40             // first word delay (cycles)
) (
    input wire clk,
    input wire reset,

    input wire ReadRequest,
    input wire [31:0] ReadAddress,

    output reg [31:0] DataIn,
    output reg DataReady
);

// NEW: Internal ROM (text segment memory)
reg [31:0] textmem[0:TEXT_SIZE-1];
initial begin
    $readmemh("text.dat", textmem);
end

// FSM for burst transfer
localparam IDLE = 0, WAIT_T0 = 1, BURST = 2;
reg [1:0] state;
reg [6:0] cycle_counter;  // big enough for T0
reg [$clog2(BLOCK_WORDS):0] burst_counter;
reg [31:0] base_addr;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        DataReady <= 0;
        DataIn <= 0;
        cycle_counter <= 0;
        burst_counter <= 0;
    end else begin
        case (state)
            IDLE: begin
                DataReady <= 0;
                if (ReadRequest) begin
                    base_addr <= ReadAddress >> 2;  // Convert byte addr to word addr
                    cycle_counter <= 0;
                    burst_counter <= 0;
                    state <= WAIT_T0;
                end
            end

            WAIT_T0: begin
                if (cycle_counter == T0_DELAY) begin
                    DataIn <= textmem[base_addr + burst_counter];
                    DataReady <= 1;
                    burst_counter <= burst_counter + 1;
                    state <= BURST;
                end else begin
                    cycle_counter <= cycle_counter + 1;
                end
            end

            BURST: begin
                if (burst_counter < BLOCK_WORDS) begin
                    DataIn <= textmem[base_addr + burst_counter];
                    DataReady <= 1;
                    burst_counter <= burst_counter + 1;
                end else begin
                    DataReady <= 0;
                    state <= IDLE;
                end
            end
        endcase
    end
end

endmodule