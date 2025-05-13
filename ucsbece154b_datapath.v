// ucsbece154b_datapath.v
// ECE 154B, RISC-V pipelined processor 
// Baseline instruction cache integration (patched)

`include "ucsbece154b_defines.vh"  // NEW: include macro definitions

module ucsbece154b_datapath (
    input                clk, reset,
    output               MisspredictE_o,  
    input                StallF_i,
    output reg    [31:0] PCF_o,
    input                StallD_i,
    input                FlushD_i,
    input         [31:0] InstrF_i,      // fixed: this is external input now
    output wire    [6:0] op_o,
    output wire    [2:0] funct3_o,
    output wire          funct7b5_o,
    input                RegWriteW,
    input         [31:0] ResultW,
    input         [4:0]  RdW,
    output wire   [5:0]  Rs1D_o,
    output wire   [5:0]  Rs2D_o,
    input         [31:0] ReadDataE,
    output wire          MemWriteM,
    output wire   [31:0] ALUOutM,
    output wire   [31:0] WriteDataM,
    output wire   [3:0]  WriteStrobeM,
    output wire   [31:0] PCSrcE_o,
    output wire   [31:0] PCBranchE_o,
    output wire   [31:0] InstrD_o,
    output wire   [31:0] InstrE_o,
    output wire   [31:0] InstrM_o,
    output wire   [31:0] InstrW_o,
    output               BusyF_o,
    output               ReadyF_o,
    output        [31:0] ReadAddrF
);

// FETCH STAGE
reg [31:0] PCF;
wire [31:0] PCNextF, PCPlus4F;
assign PCPlus4F = PCF + 4;
assign PCNextF = PCF;  // to be overridden by branch logic
assign ReadAddrF = PCNextF;

// PC update logic
always @(posedge clk) begin
    if (reset)
        PCF <= 32'h00000000;
    else if (!StallF_i)
        PCF <= PCNextF;
end
assign PCF_o = PCF;

// Pipeline register IF/ID
reg [31:0] InstrD;  // only one declaration
always @(posedge clk) begin
    if (reset || FlushD_i)
        InstrD <= 32'b0;
    else if (!StallD_i)
        InstrD <= InstrF_i;  // now coming from icache
end
assign InstrD_o = InstrD;

assign ReadyF_o = 1'b1;  // patch default output for compile
assign BusyF_o  = 1'b0;  // patch default output for compile

// CONTINUE with decode, execute, memory, writeback stages...

endmodule