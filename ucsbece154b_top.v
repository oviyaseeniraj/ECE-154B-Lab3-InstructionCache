// ucsbece154b_top.v
// NEW: Baseline instruction cache and memory wiring

module ucsbece154b_top (
    input clk, reset
);

wire [31:0] pc, pcf, instr, readdata;
wire [31:0] writedata, dataadr;
wire  memwrite,Readenable,busy;
wire [31:0] SDRAM_ReadAddress;
wire [31:0] SDRAM_DataIn;
wire SDRAM_ReadRequest;
wire SDRAM_DataReady;
wire ReadyF;
wire PCenable;
ucsbece154_icache icache (
    .Clk(clk),
    .Reset(reset),
    .ReadEnable(Readenable),          
    .ReadAddress(pcf),
    .Instruction(instr),
    .Ready(ReadyF),
    .Busy(busy),                   
    .MemReadAddress(SDRAM_ReadAddress),
    .MemReadRequest(SDRAM_ReadRequest),
    .MemDataIn(SDRAM_DataIn),
    .MemDataReady(SDRAM_DataReady),
    .PCEnable(PCenable)
);

// Datapath
ucsbece154b_datapath datapath (
    .clk(clk), .reset(reset),
    .PCF_o(pc),
    .InstrF_i(instr),
    .MemWriteM_o(memwrite),
    .ALUResultM_o(dataadr), 
    .WriteDataM_o(writedata),
    .ReadDataM_i(readdata),
    .ReadyF(ReadyF), //added Ready instruction to stall fetch stage in case of cache miss
    .ReadEnable_o(Readenable),
    .PCNewF(pcf), // NEW: feeds icache ReadAddress
    .MemDataReady(SDRAM_DataReady),
    .Busy(busy),
    .PCEnable(PCenable)
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
