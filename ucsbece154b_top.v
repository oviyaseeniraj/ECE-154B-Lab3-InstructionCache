// ucsbece154b_top.v
// ECE 154B, RISC-V pipelined processor 
// All Rights Reserved
// Copyright (c) 2024 UCSB ECE
// Distribution Prohibited


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
wire flush;
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
    .FlushF(flush)
);


// processor and memories are instantiated here
ucsbece154b_riscv_pipe riscv (
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
    .FlushF(flush)
);
ucsbece154_imem imem (
    .clk(clk),
    .reset(reset),

    .ReadRequest(SDRAM_ReadRequest),
    .ReadAddress(SDRAM_ReadAddress),
    .DataIn(SDRAM_DataIn),
    .DataReady(SDRAM_DataReady)
);
ucsbece154_dmem dmem (
    .clk(clk), .we_i(memwrite),
    .a_i(dataadr), .wd_i(writedata),
    .rd_o(readdata)
);

endmodule
