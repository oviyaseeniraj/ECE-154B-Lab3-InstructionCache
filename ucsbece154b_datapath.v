// ucsbece154b_datapath.v
// ECE 154B, RISC-V pipelined processor 
// All Rights Reserved
// Copyright (c) 2024 UCSB ECE
// Distribution Prohibited

`define GL_NUM_BTB_ENTRIES 32
`define GL_NUM_GHR_BITS 3
`define GL_NUM_PHT_ENTRIES 1024

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// TO DO: MODIFY FETCH, DECODE, AND EXECUTE STAGE BELOW TO IMPLEMENT BRANCH PREDICTOR
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

module ucsbece154b_datapath (
    input                clk, reset,
    output               MisspredictE_o,
    input                StallF_i,
    output reg    [31:0] PCF_o,
    input                StallD_i,
    input                FlushD_i,
    input         [31:0] InstrF_i,
    output wire   [6:0]  op_o,
    output wire   [2:0]  funct3_o,
    output wire          funct7b5_o,
    input                RegWriteW_i,
    input          [2:0] ImmSrcD_i,
    output wire    [4:0] Rs1D_o,
    output wire    [4:0] Rs2D_o,
    input  wire          FlushE_i,
    output reg     [4:0] Rs1E_o,
    output reg     [4:0] Rs2E_o, 
    output reg     [4:0] RdE_o, 
    input                ALUSrcE_i,
    input          [2:0] ALUControlE_i,
    input          [1:0] ForwardAE_i,
    input          [1:0] ForwardBE_i,
  //  output               ZeroE_o,
    output reg     [4:0] RdM_o, 
    output reg    [31:0] ALUResultM_o,
    output reg    [31:0] WriteDataM_o,
    input         [31:0] ReadDataM_i,
    input          [1:0] ResultSrcW_i,
    output reg     [4:0] RdW_o,
    input          [1:0] ResultSrcM_i, 
    input                BranchE_i,
    input                JumpE_i,
    input                BranchTypeE_i,
    output wire [31:0] PCNewF_o, // NEW: feeds icache ReadAddress
    input		 Busy_i,
    input  		 MemDataReady_i,
    input		 ReadyF_i,
    output		 PCEnable
);

`include "ucsbece154b_defines.vh"

// Define signals earleir if needed here
wire [31:0] PCTargetE;
wire [31:0] PCcorrecttargetE;
reg [31:0] ResultW;
// wire MisspredictE;

// ***** FETCH STAGE *********************************

// Mux feeding to PC
wire [31:0] PCPlus4F = PCF_o + 32'd4;

wire [31:0] BTBTargetF;
wire BranchTakenF;

assign PCEnable = (ReadyF_i) && ~Busy_i && ~MemDataReady_i;

wire [31:0] PCTargetF =  BranchTakenF ? BTBTargetF : PCPlus4F;
wire [31:0] PCnewF =  MisspredictE_o ? PCcorrecttargetE : PCTargetF;

//wire [NUM_GHR_BITS-1:0] PHTindexF;
wire [$clog2(`GL_NUM_PHT_ENTRIES)-1:0] PHTindexF;

// Update registers
always @ (posedge clk) begin
    if (reset)        PCF_o <= pc_start;
    // else if (!StallF_i) PCF_o <= PCnewF;
    else if (PCEnable) PCF_o <= PCnewF;
end
assign PCNewF_o = PCnewF; // NEW: expose speculative PC to top-level
=======
    input                RegWriteW,
    input         [31:0] ResultW,
    input         [4:0]  RdW,
    output wire   [4:0]  Rs1D_o,
    output wire   [4:0]  Rs2D_o,
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
assign PCNextF = PCF; // override later if branch taken
assign ReadAddrF = PCNextF;

// PC register
always @(posedge clk) begin
    if (reset)
        PCF <= 32'h00000000;
    else if (!StallF_i)
        PCF <= PCNextF;
end
assign PCF_o = PCF;

// IF/ID pipeline register
reg [31:0] InstrD;
always @(posedge clk) begin
    if (reset || FlushD_i)
        InstrD <= 32'b0;
    else if (!StallD_i)
        InstrD <= InstrF_i;
end
assign InstrD_o = InstrD;

// Wire through dummy outputs for icache connection (replaced in top)
assign ReadyF_o = 1'b1;  // connect this to icache.Ready in top
assign BusyF_o  = 1'b0;  // connect this to icache.Busy in top