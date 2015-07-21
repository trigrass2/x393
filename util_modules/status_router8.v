/*******************************************************************************
 * Module: status_router8
 * Date:2015-01-31  
 * Author: Andrey Filippov     
 * Description: Routes status data from 8 sources
 *
 * Copyright (c) 2015 Elphel, Inc.
 * status_router8.v is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 *  status_router8.v is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/> .
 *******************************************************************************/
`timescale 1ns/1ps

module  status_router8(
    input        rst,
    input        clk,
    input        srst, // @ posedge clk
    // 4 input channels 
    input [7:0]  db_in0,
    input        rq_in0,
    output       start_in0, // only for the first cycle, combinatorial
    input [7:0]  db_in1,
    input        rq_in1,
    output       start_in1, // only for the first cycle, combinatorial
    input [7:0]  db_in2,
    input        rq_in2,
    output       start_in2, // only for the first cycle, combinatorial
    input [7:0]  db_in3,
    input        rq_in3,
    output       start_in3, // only for the first cycle, combinatorial
    input [7:0]  db_in4,
    input        rq_in4,
    output       start_in4, // only for the first cycle, combinatorial
    input [7:0]  db_in5,
    input        rq_in5,
    output       start_in5, // only for the first cycle, combinatorial
    input [7:0]  db_in6,
    input        rq_in6,
    output       start_in6, // only for the first cycle, combinatorial
    input [7:0]  db_in7,
    input        rq_in7,
    output       start_in7, // only for the first cycle, combinatorial
    // output (multiplexed) channel
    output [7:0] db_out,
    output       rq_out,
    input        start_out  // only for the first cycle, combinatorial
);
//TODO: now just uses 3 of status_router2 (tree) - maybe make a dedicated 4-input one?
    wire   [7:0] db_int [1:0];
    wire   [1:0] rq_int;
    wire   [1:0] start_int;  // only for the first cycle, combinatorial

    status_router2 status_router2_top_i (
        .rst       (rst), // input
        .clk       (clk), // input
        .srst      (srst), // input
        .db_in0    (db_int[0]), // input[7:0] 
        .rq_in0    (rq_int[0]), // input
        .start_in0 (start_int[0]), // output
        .db_in1    (db_int[1]), // input[7:0] 
        .rq_in1    (rq_int[1]), // input
        .start_in1 (start_int[1]), // output
        .db_out    (db_out), // output[7:0] 
        .rq_out    (rq_out), // output
        .start_out (start_out) // input
    );

    status_router4 status_router4_0123_i (
        .rst       (rst), // input
        .clk       (clk), // input
        .srst      (srst), // input
        .db_in0    (db_in0), // input[7:0] 
        .rq_in0    (rq_in0), // input
        .start_in0 (start_in0), // output
        .db_in1    (db_in1), // input[7:0] 
        .rq_in1    (rq_in1), // input
        .start_in1 (start_in1), // output
        .db_in2    (db_in2), // input[7:0] 
        .rq_in2    (rq_in2), // input
        .start_in2 (start_in2), // output
        .db_in3    (db_in3), // input[7:0] 
        .rq_in3    (rq_in3), // input
        .start_in3 (start_in3), // output
        .db_out    (db_int[0]), // output[7:0] 
        .rq_out    (rq_int[0]), // output
        .start_out (start_int[0]) // input
    );

    status_router4 status_router4_4567_i (
        .rst       (rst), // input
        .clk       (clk), // input
        .srst      (srst), // input
        .db_in0    (db_in4), // input[7:0] 
        .rq_in0    (rq_in4), // input
        .start_in0 (start_in4), // output
        .db_in1    (db_in5), // input[7:0] 
        .rq_in1    (rq_in5), // input
        .start_in1 (start_in5), // output
        .db_in2    (db_in6), // input[7:0] 
        .rq_in2    (rq_in6), // input
        .start_in2 (start_in6), // output
        .db_in3    (db_in7), // input[7:0] 
        .rq_in3    (rq_in7), // input
        .start_in3 (start_in7), // output
        .db_out    (db_int[1]), // output[7:0] 
        .rq_out    (rq_int[1]), // output
        .start_out (start_int[1]) // input
    );

endmodule

