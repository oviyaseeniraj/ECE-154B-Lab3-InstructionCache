// ucsbece154b_top_tb.v
// UPDATED: Measures fetches, hits, and misses for icache

`define SIM

module ucsbece154b_top_tb ();

reg clk = 1;
always #1 clk = ~clk;

reg reset;

// Counters
integer fetch_count = 0;
integer miss_count = 0;
integer hit_count  = 0;

// Track ready and busy for edge detection
reg prev_ready = 0;
reg prev_busy  = 0;

// Instantiate top module
ucsbece154b_top top_inst (
    .clk(clk),
    .reset(reset)
);

initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, ucsbece154b_top_tb);

    reset = 1;
    #5;
    reset = 0;

    // Run simulation
    #2000;

    $display("\n--- ICache Fetch Summary ---");
    $display("Fetches        : %0d", fetch_count);
    $display("Hits           : %0d", hit_count);
    $display("Misses         : %0d", miss_count);
    $display("----------------------------\n");
    $finish;
end

// Count fetches, hits, misses based on Ready and Busy edges
always @(posedge clk) begin
    if (!reset) begin
        // Count fetch when Ready goes high
        if (~prev_ready && top_inst.ReadyF) begin
            fetch_count = fetch_count + 1;
        end

        // Count miss when Busy rises
        if (~prev_busy && top_inst.BusyF) begin
            miss_count = miss_count + 1;
        end

        // Count hit if not busy and Ready rises
        if (~top_inst.BusyF && ~prev_ready && top_inst.ReadyF)
            hit_count = hit_count + 1;
    end

    prev_ready <= top_inst.ReadyF;
    prev_busy  <= top_inst.BusyF;
end

endmodule
