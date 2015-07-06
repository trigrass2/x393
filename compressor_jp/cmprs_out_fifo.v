/*******************************************************************************
 * Module: cmprs_out_fifo
 * Date:2015-06-25  
 * Author: andrey     
 * Description: Compressor output FIFO
 *
 * Copyright (c) 2015 Elphel, Inc.
 * cmprs_out_fifo.v is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 *  cmprs_out_fifo.v is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/> .
 *******************************************************************************/
`timescale 1ns/1ps

module  cmprs_out_fifo(
    input              rst,          // mostly for simulation
    // wclk domain
    input              wclk,         // source clock (2x pixel clock, inverted)
    input              we,
    input       [15:0] wdata,
    input              wa_rst,       // reset low address bits when stuffer is disabled (to make sure it is multiple of 32 bytes
    input              wlast,        // written last 32 bytes of a frame (flush FIFO) - stuffer_done (has to be later than we)
    output             eof_written_wclk, // eof_written - reclocked to wclk
    
    // rclk domain
    input              rclk,
    input              rst_fifo,      // reset FIFO (set read address to write, reset count)
    input              ren,
    output      [63:0] rdata,
    output             eof,           // single rclk pulse signalling EOF
    input              eof_written,   // confirm frame written ofer AFI to the system memory (single rclk pulse)
    output             flush_fifo,    // EOF, need to output all what is in FIFO (Stays active until enough data chunks are read)
    output      [7:0]  fifo_count     // number of 32-byte chunks in FIFO

);
    reg        regen;
    reg [ 8:0] raddr;
    reg [ 7:0] count32;
    reg [ 7:0] lcount32; // counting chunks left in the same frame
    reg [10:0] waddr;
    wire       written32b; // written 32 bytes, re-clocked to read clock domain (single-cycle)
    wire       wlast_rclk;
    reg        flush_fifo_r;
    
    assign flush_fifo = flush_fifo_r;
    assign fifo_count = count32;
    assign eof = wlast_rclk;
    
    always @ (posedge rst or posedge wclk) begin
        if      (rst)    waddr <= 0;
        else if (wa_rst) waddr <= waddr & 11'h7f0; // reset 4 LSBs only
        else if (we)     waddr <= waddr + 1;
    end
    
    always @ (posedge rclk) begin
        regen <= ren;
        
        if (rst_fifo) raddr <= {waddr[10:4],2'b0};
        else if (ren) raddr <= raddr + 1;
        
        if      (rst_fifo)                               count32 <= 0;
        else if ( written32b && !(ren && (&raddr[1:0]))) count32 <=  count32 + 1;
        else if (!written32b &&  (ren && (&raddr[1:0]))) count32 <=  count32 - 1;
        
        
        if      (rst_fifo)                               lcount32 <= 0;
        else if (wlast_rclk)                             lcount32 <= count32;
        else if ((lcount32 !=0) && ren && (&raddr[1:0])) lcount32 <= lcount32 - 1;
        
        if (rst_fifo)                                          flush_fifo_r <= 0;
        else if (wlast_rclk)                                   flush_fifo_r <= 1;
        else if ((count32[7:1] == 0) && ( !count32[0] || ren)) flush_fifo_r <= 0;
        
    end

// wclk -> rclk
    pulse_cross_clock written32b_i (.rst(rst), .src_clk(wclk), .dst_clk(rclk), .in_pulse(we && (&waddr[3:0])), .out_pulse(written32b),.busy());
    pulse_cross_clock wlast_rclk_i (.rst(rst), .src_clk(wclk), .dst_clk(rclk), .in_pulse(wlast),               .out_pulse(wlast_rclk),.busy());
// rclk -> wclk
    pulse_cross_clock eof_written_wclk_i (.rst(rst), .src_clk(rclk), .dst_clk(wclk), .in_pulse(eof_written), .out_pulse(eof_written_wclk),.busy());
    ram_var_w_var_r #(
        .REGISTERS(1),
        .LOG2WIDTH_WR(4),
        .LOG2WIDTH_RD(6)
    ) fifo_i (
        .rclk     (rclk),                // input
        .raddr    (raddr),               // input[8:0] 
        .ren      (ren),                  // input
        .regen    (regen),                // input
        .data_out (rdata),                // output[63:0] 
        .wclk     (wclk),                 // input - OK, negedge mclk
        .waddr    (waddr),                // input[10:0]
        .we       (we),                   // input
        .web      (8'hff),                // input[7:0]
        .data_in  (wdata)                 // input[15:0]
    );


endmodule

