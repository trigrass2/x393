/*******************************************************************************
 * Module: odelay_pipe
 * Date:2014-04-25  
 * Author: Andrey Filippov
 * Description: ODELAYE2 wrapper pipelined
 *
 * Copyright (c) 2014 Elphel, Inc.
 * idelay_fine_pipe.v is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 *  odelay_pipe.v is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/> .
 *
 * Additional permission under GNU GPL version 3 section 7:
 * If you modify this Program, or any covered work, by linking or combining it
 * with independent modules provided by the FPGA vendor only (this permission
 * does not extend to any 3-rd party modules, "soft cores" or macros) under
 * different license terms solely for the purpose of generating binary "bitstream"
 * files * and/or simulating the code, the copyright holders of this Program give
 * you the right to distribute the covered work without those independent modules
 * as long as the source code for them is available from the FPGA vendor free of
 * charge, and there is no dependence on any ecrypted modules for simulating of
 * the combined code. This permission applies to you if the distributed code
 * contains all the components and scripts required to completely simulate it
 * with at least one of the Free Software programs.
 *******************************************************************************/
`timescale 1ns/1ps

module  odelay_pipe
//SuppressWarnings VEditor - IODELAY_GRP used in (* *) construnt
# ( parameter  IODELAY_GRP  = "IODELAY_MEMORY",
    parameter integer DELAY_VALUE = 0,
    parameter real REFCLK_FREQUENCY = 200.0,
    parameter HIGH_PERFORMANCE_MODE    = "FALSE"
) (
    input clk,
    input rst,
    input set,
    input ld,
    input [4:0] delay,
    input data_in,
    output data_out
);
 
`ifndef IGNORE_ATTR
    (* IODELAY_GROUP = IODELAY_GRP *)
`endif    
  ODELAYE2 #(
        .CINVCTRL_SEL("FALSE"),
        .DELAY_SRC("ODATAIN"),
//        .FINEDELAY("ADD_DLY"),
        .HIGH_PERFORMANCE_MODE(HIGH_PERFORMANCE_MODE),
        .ODELAY_TYPE("VAR_LOAD_PIPE"),
        .ODELAY_VALUE(DELAY_VALUE),
        .IS_C_INVERTED(1'b0),
        .IS_ODATAIN_INVERTED(1'b0),
        .PIPE_SEL("TRUE"),
        .REFCLK_FREQUENCY(REFCLK_FREQUENCY),
        .SIGNAL_PATTERN("DATA")
    )
    odelay2_finedelay_i(
        .CNTVALUEOUT(),
        .DATAOUT(data_out),
        .C(clk),
        .CE(1'b0),
        .CINVCTRL(1'b0),
        .CNTVALUEIN(delay[4:0]),
        .CLKIN(1'b0),
        .ODATAIN(data_in),
        .INC(1'b0),
        .LD(set),
        .LDPIPEEN(ld),
        .REGRST(rst)
    );
    
endmodule

