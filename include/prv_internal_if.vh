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
*   Filename:     prv_internal_if.vh
*
*   Created by:   Jacob R. Stevens
*   Email:        steven69@purdue.edu
*   Date Created: 09/20/2016
*   Description:  Interface for components within the privilege block 
*/

`ifndef PRV_INTERNAL_IF_VH
`define PRV_INTERNAL_IF_VH
interface prv_internal_if;
  import machine_mode_types_pkg::*;
  import rv32i_types_pkg::*;

  logic mip_rup;
  logic mbadaddr_rup;
  logic mcause_rup;
  logic mepc_rup;
  logic mstatus_rup;
  logic clear_timer_int;
  logic intr;
  logic pipe_clear;
  logic ret;
  logic fault_insn, mal_insn, illegal_insn, fault_l, mal_l, fault_s, mal_s;
  logic breakpoint, env_m, timer_int, soft_int, ext_int;
  logic insert_pc;
  logic swap, clr, set;
  logic valid_write, invalid_csr;
  logic instr_retired;

  word_t epc, badaddr, priv_pc;
  word_t [3:0] xtvec, xepc_r;
  word_t wdata, rdata;

  mip_t       mip, mip_next;
  mbadaddr_t  mbadaddr_next;
  mcause_t    mcause, mcause_next;
  mepc_t      mepc, mepc_next;
  mstatus_t   mstatus, mstatus_next;

  mtvec_t     mtvec;
  mie_t       mie;

  csr_addr_t addr;

  modport csr (
    input mip_rup, mbadaddr_rup, mcause_rup, mepc_rup, mstatus_rup,
      mip_next, mbadaddr_next, mcause_next, mepc_next, mstatus_next,
      swap, clr, set, wdata, addr, valid_write, instr_retired, 
    output mtvec, mepc, mie, timer_int, mip, mcause, mstatus, clear_timer_int,
      rdata, invalid_csr, xtvec, xepc_r
  );

  modport prv_control (
    output mip_rup, mbadaddr_rup, mcause_rup, mepc_rup, mstatus_rup,
      mip_next, mcause_next, mepc_next, mstatus_next, mbadaddr_next, intr, 
    input mepc, mie, mip, mcause, mstatus, clear_timer_int, pipe_clear, ret,
      epc, fault_insn, mal_insn, illegal_insn, fault_l, mal_l, fault_s, mal_s,
      breakpoint, env_m, timer_int, soft_int, ext_int, badaddr
  );

  modport pipe_ctrl (
    input intr, ret, pipe_clear, xtvec, xepc_r,
    output insert_pc, priv_pc
  );

endinterface
`endif // PRV_INTERNAL_IF_VH
