// ucsbece154b_top.v
// NEW: Baseline instruction cache and memory wiring

module ucsbece154b_top (
    input clk, reset
);

// NEW: Signals between datapath, icache, and imem
wire [31:0] PCF, InstrF;
wire ReadyF, BusyF;
wire StallF;
assign StallF = ~ReadyF;

wire MemReadRequest;
wire [31:0] MemReadAddress;
wire [31:0] MemDataIn;
wire MemDataReady;

// Datapath
ucsbece154b_datapath datapath (
    .clk(clk), .reset(reset),
    .MisspredictE_o(),
    .StallF_i(StallF),
    .PCF_o(PCF),
    .StallD_i(1'b0),
    .FlushD_i(1'b0),
    .InstrF_i(InstrF),
    .op_o(), .funct3_o(), .funct7b5_o(),
    .RegWriteW(1'b0), .ResultW(32'b0), .RdW(5'b0),
    .Rs1D_o(), .Rs2D_o(),
    .ReadDataE(32'b0),
    .MemWriteM(), .ALUOutM(), .WriteDataM(), .WriteStrobeM(),
    .PCSrcE_o(), .PCBranchE_o(),
    .InstrD_o(), .InstrE_o(), .InstrM_o(), .InstrW_o(),
    .BusyF_o(BusyF), .ReadyF_o(ReadyF), .ReadAddrF(PCF)
);

// Instruction Cache
ucsbece154b_icache icache (
    .Clk(clk), .Reset(reset),
    .ReadEnable(~StallF),
    .ReadAddress(PCF),
    .Instruction(InstrF),
    .Ready(ReadyF),
    .Busy(BusyF),
    .MemReadAddress(MemReadAddress),
    .MemReadRequest(MemReadRequest),
    .MemDataIn(MemDataIn),
    .MemDataReady(MemDataReady)
);

// Emulated SDRAM (main memory)
ucsbece154_imem imem (
    .clk(clk), .reset(reset),
    .ReadRequest(MemReadRequest),
    .ReadAddress(MemReadAddress),
    .DataIn(MemDataIn),
    .DataReady(MemDataReady)
);

endmodule
