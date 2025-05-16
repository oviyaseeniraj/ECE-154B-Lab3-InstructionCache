// ucsbece154b_top_tb.v (updated for latched ReadAddress in icache)
`define SIM

`define ASSERT(CONDITION, MESSAGE) if ((CONDITION)==1'b1); else begin $error($sformatf MESSAGE); end

module ucsbece154b_top_tb ();

reg clk = 1;
always #1 clk <= ~clk;
reg reset;

integer jumptotal = 0;
integer jumppredictedcorrectly = 0;
integer branchtotal = 0;
integer branchpredictedcorrectly = 0;

// HIT/MISS TRACKING
integer total_fetches = 0;
integer icachehits = 0;
integer icachemisses = 0;

ucsbece154b_top top (
    .clk(clk), .reset(reset)
);

wire [31:0] reg_zero = top.riscv.dp.rf.zero;
wire [31:0] reg_ra = top.riscv.dp.rf.ra;
wire [31:0] reg_sp = top.riscv.dp.rf.sp;
wire [31:0] reg_gp = top.riscv.dp.rf.gp;
wire [31:0] reg_tp = top.riscv.dp.rf.tp;
wire [31:0] reg_t0 = top.riscv.dp.rf.t0;
wire [31:0] reg_t1 = top.riscv.dp.rf.t1;
wire [31:0] reg_t2 = top.riscv.dp.rf.t2;
wire [31:0] reg_s0 = top.riscv.dp.rf.s0;
wire [31:0] reg_s1 = top.riscv.dp.rf.s1;
wire [31:0] reg_a0 = top.riscv.dp.rf.a0;
wire [31:0] reg_a1 = top.riscv.dp.rf.a1;
wire [31:0] reg_a2 = top.riscv.dp.rf.a2;
wire [31:0] reg_a3 = top.riscv.dp.rf.a3;
wire [31:0] reg_a4 = top.riscv.dp.rf.a4;
wire [31:0] reg_a5 = top.riscv.dp.rf.a5;
wire [31:0] reg_a6 = top.riscv.dp.rf.a6;
wire [31:0] reg_a7 = top.riscv.dp.rf.a7;
wire [31:0] reg_s2 = top.riscv.dp.rf.s2;
wire [31:0] reg_s3 = top.riscv.dp.rf.s3;
wire [31:0] reg_s4 = top.riscv.dp.rf.s4;
wire [31:0] reg_s5 = top.riscv.dp.rf.s5;
wire [31:0] reg_s6 = top.riscv.dp.rf.s6;
wire [31:0] reg_s7 = top.riscv.dp.rf.s7;
wire [31:0] reg_s8 = top.riscv.dp.rf.s8;
wire [31:0] reg_s9 = top.riscv.dp.rf.s9;
wire [31:0] reg_s10 = top.riscv.dp.rf.s10;
wire [31:0] reg_s11 = top.riscv.dp.rf.s11;
wire [31:0] reg_t3 = top.riscv.dp.rf.t3;
wire [31:0] reg_t4 = top.riscv.dp.rf.t4;
wire [31:0] reg_t5 = top.riscv.dp.rf.t5;
wire [31:0] reg_t6 = top.riscv.dp.rf.t6;

wire [31:0] fetchpc = top.riscv.dp.PCPlus4W;

integer i;
reg prev_ready = 0;
reg prev_memread = 0;

initial begin
    $display("Begin simulation.");
    reset = 1;
    @(negedge clk);
    @(negedge clk);
    reset = 0;

    for (i = 0; i < 10000; i = i + 1) begin
        @(negedge clk);

        if (top.icache.Ready) begin
            total_fetches = total_fetches + 1;
            if (top.icache.hit_this_cycle == 1)
                icachehits = icachehits + 1;
            else
                icachemisses = icachemisses + 1;
        end

        prev_ready = top.icache.Ready;
        prev_memread = top.icache.MemReadRequest;
    end

    $display("Total fetches: %d", total_fetches);
    $display("Total icache hits: %d", icachehits);
    $display("Total icache misses: %d", icachemisses);

    if (total_fetches != 0) begin
        $display("Instruction cache hit rate: %f", (icachehits * 100.0) / total_fetches);
        $display("Instruction cache miss rate: %f", (icachemisses * 100.0) / total_fetches);
    end else begin
        $display("No fetches occurred.");
    end

    $display("End simulation.");
    $stop;
end

endmodule

`undef ASSERT