/*
*   Copyright 2016 Purdue University
*   
*   Licensed under the Apache License, Version 2.0 (the "License");
*   you may not use this file except in compliance with the License.
*   You may obtain a copy of the License at
*   
*       http://www.apache.org/licenses/LICENSE-2.0
*   
*   Unless required by applicable law or agreed to in writing, software
*   distributed under the License is distributed on an "AS IS" BASIS,
*   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*   See the License for the specific language governing permissions and
*   limitations under the License.
*
*
*   Filename:     execute_stage.sv
*
*   Created by:   Jacob R. Stevens
*   Email:        steven69@purdue.edu
*   Date Created: 06/16/2016
*   Description:  Execute Stage for the Two Stage Pipeline 
*/

`include "fetch_execute_if.vh"
`include "hazard_unit_if.vh"
`include "predictor_pipeline_if.vh"
`include "control_unit_if.vh"
`include "rv32i_reg_file_if.vh"
`include "ram_if.vh"
`include "alu_if.vh"

module execute_stage(
  input logic CLK, nRST,
  fetch_execute_if.execute fetch_ex_if,
  hazard_unit_if.execute hazard_if,
  predictor_pipeline_if.update predict_if,
  ram_if.cpu dram_if,
  output halt 
);

  // Interface declarations
  control_unit_if   cu_if();
  rv32i_reg_file_if rf_if(); 
  alu_if            alu_if();
  jump_calc_if      jump_if();
  branch_res_if     branch_if(); 
 
  // Module instantiations
  control_unit cu (
    .cu_if(cu_if),
    .rf_if(rf_if)
  );

  rv32i_reg_file rf (
    .CLK(CLK),
    .nRST(nRST),
    .rf_if(rf_if)
  );

  alu alu (
    .alu_if(alu_if)
  );

  jump_calc jump_calc (
    .jump_if(jump_if)
  );

  branch_res branch_res (
    .br_if(branch_if)
  ); 

  word_t store_swapped;
  endian_swapper store_swap (
    .word_in(rf_if.rs2_data),
    .word_out(store_swapped)
  );

  word_t dload_ext;
  logic [3:0] byte_en;
  dmem_extender dmem_ext (
    .dmem_in(dram_if.rdata),
    .load_type(cu_if.load_type),
    .byte_en(byte_en),
    .ext_out(dload_ext)
  );

  // TODO: Guard this with ifdefs so only used in simulation
  cpu_tracker cpu_tracker (
      .CLK(CLK),
      .wb_stall(hazard_if.if_ex_stall & ~hazard_if.jump & ~hazard_if.branch),
      .instr(fetch_ex_if.fetch_ex_reg.instr),
      .pc(fetch_ex_if.fetch_ex_reg.pc),
      .opcode(cu_if.opcode),
      .funct3(cu_if.instr[14:12])
  );
  
  assign cu_if.instr = fetch_ex_if.fetch_ex_reg.instr;

  /*******************************************************
  *** Sign Extensions 
  *******************************************************/
  word_t imm_I_ext, imm_S_ext, imm_UJ_ext;
  assign imm_I_ext  = {{20{cu_if.imm_I[11]}}, cu_if.imm_I};
  assign imm_UJ_ext = {{20{cu_if.imm_UJ[11]}}, cu_if.imm_UJ};
  assign imm_S_ext  = {{20{cu_if.imm_S[11]}}, cu_if.imm_S};

  /*******************************************************
  *** Jump Target Calculator and Associated Logic 
  *******************************************************/
  word_t jump_addr;
  always_comb begin
    if (cu_if.j_sel) begin
      jump_if.base = fetch_ex_if.fetch_ex_reg.pc;
      jump_if.offset = imm_UJ_ext;
      jump_addr = jump_if.jal_addr;
    end else begin
      jump_if.base = rf_if.rs1_data;
      jump_if.offset = imm_I_ext;
      jump_addr = jump_if.jalr_addr;
    end
  end 

  /*******************************************************
  *** ALU and Associated Logic 
  *******************************************************/
  word_t imm_or_shamt;
  assign imm_or_shamt = (cu_if.imm_shamt_sel == 1'b1) ? cu_if.shamt : imm_I_ext;
  assign alu_if.aluop = cu_if.alu_op;
 
  always_comb begin
    case (cu_if.alu_a_sel)
      2'd0: alu_if.port_a = rf_if.rs1_data;
      2'd1: alu_if.port_a = imm_S_ext;
      2'd2: alu_if.port_a = fetch_ex_if.fetch_ex_reg.pc;
      2'd3: alu_if.port_a = '0; //Not Used 
    endcase
  end

  always_comb begin
    case(cu_if.alu_b_sel)
      2'd0: alu_if.port_b = rf_if.rs1_data;
      2'd1: alu_if.port_b = rf_if.rs2_data;
      2'd2: alu_if.port_b = imm_or_shamt;
      2'd3: alu_if.port_b = cu_if.imm_U;
    endcase
  end

  always_comb begin
    case(cu_if.w_sel)
      2'd0: rf_if.w_data = dload_ext;
      2'd1: rf_if.w_data = fetch_ex_if.fetch_ex_reg.pc4;
      2'd2: rf_if.w_data = cu_if.imm_U;
      2'd3: rf_if.w_data = alu_if.port_out;
    endcase
  end

  assign rf_if.wen = cu_if.wen & (~hazard_if.if_ex_stall | hazard_if.npc_sel); 
  /*******************************************************
  *** Branch Target Resolution and Associated Logic 
  *******************************************************/
  word_t resolved_addr;
  assign branch_if.rs1_data    = rf_if.rs1_data;
  assign branch_if.rs2_data    = rf_if.rs2_data;
  assign branch_if.pc          = fetch_ex_if.fetch_ex_reg.pc;
  assign branch_if.imm_sb      = cu_if.imm_SB;
  assign branch_if.branch_type = cu_if.branch_type;

  assign resolved_addr = branch_if.branch_taken ?
                          branch_if.branch_addr : fetch_ex_if.fetch_ex_reg.pc4;
  
  assign fetch_ex_if.brj_addr = (cu_if.ex_pc_sel == 1'b1) ?
                                jump_addr : resolved_addr;
  
  assign hazard_if.mispredict =  fetch_ex_if.fetch_ex_reg.prediction ^
                                branch_if.branch_taken;
  
  /*******************************************************
  *** Data Ram Interface Logic 
  *******************************************************/
  logic [1:0] byte_offset;

  assign dram_if.ren           = cu_if.dren;
  assign dram_if.wen           = cu_if.dwen;
  assign dram_if.byte_en       = cu_if.dren ? byte_en:
                                {byte_en[0], byte_en[1], byte_en[2], byte_en[3]};
  assign dram_if.addr          = alu_if.port_out;
  assign hazard_if.d_ram_busy  = dram_if.busy;
  assign byte_offset          = alu_if.port_out[1:0]; 
  
  always_comb begin
    // load_type can be used for store_type as well
    case(cu_if.load_type)
      LB: dram_if.wdata = {4{store_swapped[31:24]}};
      LH: dram_if.wdata = {2{store_swapped[31:16]}};
      LW: dram_if.wdata = store_swapped; 
    endcase
  end


  // Assign byte_en based on load type 
  // funct3 for loads and stores are the same bit positions
  // byte_en is valid for both loads and stores 
  always_comb begin
    unique case(cu_if.load_type)
      LB : begin
        unique case(byte_offset)
          2'b00   : byte_en = 4'b0001;
          2'b01   : byte_en = 4'b0010;
          2'b10   : byte_en = 4'b0100;
          2'b11   : byte_en = 4'b1000;
          default : byte_en = 4'b0000;
        endcase
      end
      LBU : begin
        unique case(byte_offset)
          2'b00   : byte_en = 4'b0001;
          2'b01   : byte_en = 4'b0010;
          2'b10   : byte_en = 4'b0100;
          2'b11   : byte_en = 4'b1000;
          default : byte_en = 4'b0000;
        endcase
      end
      LH : begin
        unique case(byte_offset)
          2'b00   : byte_en = 4'b0011;
          2'b10   : byte_en = 4'b1100;
          default : byte_en = 4'b0000;
        endcase
      end
      LHU : begin
        unique case(byte_offset)
          2'b00   : byte_en = 4'b0011;
          2'b10   : byte_en = 4'b1100;
          default : byte_en = 4'b0000;
        endcase
      end
      LW:           byte_en = 4'b1111;
      default :     byte_en = 4'b0000;
    endcase
  end

  /*******************************************************
  *** Hazard Unit Interface Logic 
  *******************************************************/
  assign hazard_if.dren    = cu_if.dren;
  assign hazard_if.dwen    = cu_if.dwen;
  assign hazard_if.jump    = cu_if.jump;
  assign hazard_if.branch  = cu_if.branch;
  assign hazard_if.halt    = halt;
  
  assign halt = cu_if.halt;

endmodule

