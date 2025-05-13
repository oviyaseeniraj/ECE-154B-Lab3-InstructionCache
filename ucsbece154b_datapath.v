// ucsbece154b_datapath.v
// ECE 154B, RISC-V pipelined processor 
// All Rights Reserved
// Copyright (c) 2024 UCSB ECE
// Distribution Prohibited

`define GL_NUM_BTB_ENTRIES 32
`define GL_NUM_GHR_BITS 3
`define GL_NUM_PHT_ENTRIES 1024

module ucsbece154b_datapath (
    input                clk, reset,
    output               MisspredictE_o,  
    input                StallF_i,
    output reg    [31:0] PCF_o,
    input                StallD_i,
    input                FlushD_i,
    input         [31:0] InstrF_i,
    output wire    [6:0] op_o,
    output wire    [2:0] funct3_o,
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
    output wire [31:0] PCNewF_o
);

`include "ucsbece154b_defines.vh"

parameter pc_start = 32'h00010000; // NEW

wire [31:0] PCTargetE;
wire [31:0] PCcorrecttargetE;
reg [31:0] ResultW;
reg validE; // NEW

// FETCH STAGE
wire [31:0] PCPlus4F = PCF_o + 32'd4;
wire [31:0] BTBTargetF;
wire BranchTakenF;
wire [31:0] PCTargetF = BranchTakenF ? BTBTargetF : PCPlus4F;
wire [31:0] PCnewF = MisspredictE_o ? PCcorrecttargetE : PCTargetF;
wire [$clog2(`GL_NUM_PHT_ENTRIES)-1:0] PHTindexF;

always @ (posedge clk) begin
    if (reset)
        PCF_o <= pc_start;
    else if (!StallF_i && (validE || ~MisspredictE_o)) // NEW
        PCF_o <= PCnewF;
end

assign PCNewF_o = PCnewF;

// DECODE STAGE
reg [31:0] InstrD, PCPlus4D, PCD;
wire [4:0] RdD;
reg [$clog2(`GL_NUM_PHT_ENTRIES)-1:0] PHTindexD;

assign op_o       = InstrD[6:0];
assign funct3_o   = InstrD[14:12];
assign funct7b5_o = InstrD[30];
assign Rs1D_o = InstrD[19:15];
assign Rs2D_o = InstrD[24:20];
assign RdD = InstrD[11:7];

wire [31:0] RD1D, RD2D;
ucsbece154b_rf rf (
    .clk(~clk),
    .a1_i(Rs1D_o), .a2_i(Rs2D_o), .a3_i(RdW_o),
    .rd1_o(RD1D), .rd2_o(RD2D),
    .we3_i(RegWriteW_i), .wd3_i(ResultW)
);

reg [31:0] ExtImmD;
always @ * begin
   case(ImmSrcD_i)
      imm_Itype: ExtImmD = {{20{InstrD[31]}},InstrD[31:20]};
      imm_Stype: ExtImmD = {{20{InstrD[31]}},InstrD[31:25],InstrD[11:7]};
      imm_Btype: ExtImmD = {{20{InstrD[31]}},InstrD[7],InstrD[30:25], InstrD[11:8],1'b0};
      imm_Jtype: ExtImmD = {{12{InstrD[31]}},InstrD[19:12],InstrD[20],InstrD[30:21],1'b0};
      imm_Utype: ExtImmD = {InstrD[31:12],12'b0};
      default:   ExtImmD = 32'bx;
   endcase
end

always @ (posedge clk) begin
    if (reset | FlushD_i) begin
        InstrD   <= 32'b0;
        PCPlus4D <= 32'b0;
        PCD      <= 32'b0;
        PHTindexD <= {$clog2(`GL_NUM_PHT_ENTRIES){1'b0}};
    end else if (!StallD_i) begin 
        InstrD   <= InstrF_i;
        PCPlus4D <= PCPlus4F;
        PCD      <= PCF_o;
        PHTindexD <= PHTindexF;
    end 
end

// EXECUTE STAGE
reg [31:0] RD1E, RD2E, PCPlus4E, ExtImmE, PCE; 
reg [31:0] ForwardDataM;
reg [$clog2(`GL_NUM_PHT_ENTRIES)-1:0] PHTindexE;

reg [31:0] SrcAE;
always @ * begin
    case (ForwardAE_i)
       forward_mem: SrcAE = ALUResultM_o; 
       forward_wb: SrcAE = ResultW;
       forward_ex: SrcAE = RD1E;
       default: SrcAE = 32'bx;
    endcase
end

reg [31:0] SrcBE;
reg [31:0] WriteDataE;
always @ * begin
    case (ForwardBE_i)
       forward_mem: WriteDataE = ForwardDataM; 
       forward_wb: WriteDataE = ResultW;
       forward_ex: WriteDataE = RD2E;
       default: WriteDataE = 32'bx;
    endcase
end

always @ * begin
    case (ALUSrcE_i)
        SrcB_imm: SrcBE = ExtImmE;
        SrcB_reg: SrcBE = WriteDataE;
        default: SrcBE = 32'bx;
    endcase
end

wire [31:0] ALUResultE;
ucsbece154b_alu alu (
    .a_i(SrcAE), .b_i(SrcBE),
    .alucontrol_i(ALUControlE_i),
    .result_o(ALUResultE),
    .zero_o(ZeroE_o)
);

assign PCTargetE = PCE + ExtImmE;

always @ (posedge clk) begin
    if (reset | FlushE_i) begin
        RD1E     <= 32'b0;
        RD2E     <= 32'b0;
        PCE      <= 32'b0;
        ExtImmE  <= 32'b0;
        PCPlus4E <= 32'b0;
        Rs1E_o   <=  5'b0;
        Rs2E_o   <=  5'b0;
        RdE_o    <=  5'b0;
        PHTindexE <= {$clog2(`GL_NUM_PHT_ENTRIES){1'b0}};
        validE   <= 1'b0; // NEW
    end else begin 
        RD1E     <= RD1D;
        RD2E     <= RD2D;
        PCE      <= PCD;
        ExtImmE  <= ExtImmD;
        PCPlus4E <= PCPlus4D;
        Rs1E_o   <= Rs1D_o;
        Rs2E_o   <= Rs2D_o;
        RdE_o    <= RdD;
        PHTindexE <= PHTindexD;
        validE   <= 1'b1; // NEW
    end 
end

// MEMORY STAGE
reg [31:0] ExtImmM, PCPlus4M;

always @ * begin
   case(ResultSrcM_i)
     MuxResult_aluout:  ForwardDataM = ALUResultM_o;
     MuxResult_PCPlus4: ForwardDataM = PCPlus4M;
     MuxResult_imm:     ForwardDataM = ExtImmM;
     default:           ForwardDataM = 32'bx;
   endcase
end

always @ (posedge clk) begin
    if (reset) begin
        ALUResultM_o <= 32'b0;
        WriteDataM_o <= 32'b0;
        ExtImmM      <= 32'b0;
        PCPlus4M     <= 32'b0;
        RdM_o        <=  5'b0;
    end else begin 
        ALUResultM_o <= ALUResultE;
        WriteDataM_o <= WriteDataE;
        ExtImmM      <= ExtImmE;
        PCPlus4M     <= PCPlus4E;
        RdM_o        <= RdE_o;
    end 
end

// WRITEBACK STAGE
reg [31:0] PCPlus4W, ALUResultW, ReadDataW, ExtImmW;

always @ * begin
   case(ResultSrcW_i)
     MuxResult_mem:     ResultW = ReadDataW;
     MuxResult_aluout:  ResultW = ALUResultW;
     MuxResult_PCPlus4: ResultW = PCPlus4W;
     MuxResult_imm:     ResultW = ExtImmW;
     default:           ResultW = 32'bx;
endcase
end

always @ (posedge clk) begin
    if (reset) begin
        ALUResultW <= 32'b0;
        ReadDataW  <= 32'b0;
        ExtImmW    <= 32'b0;
        PCPlus4W   <= 32'b0;
        RdW_o      <=  5'b0;
    end else begin 
        ALUResultW <= ALUResultM_o;
        ReadDataW  <= ReadDataM_i;
        ExtImmW    <= ExtImmM;
        PCPlus4W   <= PCPlus4M;
        RdW_o      <= RdM_o;
    end 
end

// BRANCH PREDICTOR

wire BranchTakenE = BranchE_i & (ZeroE_o ^ BranchTypeE_i);
wire BranchNotTakenE = BranchE_i & ~(ZeroE_o ^ BranchTypeE_i);
wire nextTakenE = (PCTargetE == PCD); 
assign MisspredictE_o = validE && ((~nextTakenE & (BranchTakenE | JumpE_i)) | (nextTakenE & BranchNotTakenE)); // MODIFIED
wire MisspredictbranchE = (~nextTakenE & BranchTakenE) | (nextTakenE & BranchNotTakenE);    
wire BTBupdateE = JumpE_i | BranchTakenE;
assign PCcorrecttargetE = (BranchTakenE | JumpE_i) ? PCTargetE : PCPlus4E; 

ucsbece154b_branch #(`GL_NUM_BTB_ENTRIES, `GL_NUM_GHR_BITS, `GL_NUM_PHT_ENTRIES) bp (
    .clk(clk),
    .reset_i(reset), 
    .pc_i(PCF_o),
    .BTBwriteaddress_i(PCE),
    .BTBwritedata_i(PCTargetE),
    .BTBwriteB_i(BranchE_i),   
    .BTBwe_i (BTBupdateE), 
    .BTBtarget_o(BTBTargetF),  
    .BranchTaken_o(BranchTakenF),
    .op_i(InstrF_i[6:0]), 
    .PHTincrement_i(BranchTakenE), 
    .GHRreset_i(MisspredictbranchE),
    .PHTwe_i(BranchE_i),
    .PHTwriteindex_i(PHTindexE),
    .PHTreadindex_o(PHTindexF)
);

endmodule