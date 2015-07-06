/*******************************************************************************
 * Module: pxd_clock
 * Date:2015-05-16  
 * Author: andrey     
 * Description: pixel clock line input
 *
 * Copyright (c) 2015 Elphel, Inc.
 * pxd_clock.v is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 *  pxd_clock.v is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/> .
 *******************************************************************************/
`timescale 1ns/1ps

module  pxd_clock #(
    parameter IODELAY_GRP ="IODELAY_SENSOR", // may need different for different channels?
    parameter integer IDELAY_VALUE = 0,
    parameter integer PXD_DRIVE = 12,
    parameter PXD_IBUF_LOW_PWR = "TRUE",
    parameter PXD_IOSTANDARD = "DEFAULT",
    parameter PXD_SLEW = "SLOW",
    parameter real REFCLK_FREQUENCY = 300.0,
    parameter HIGH_PERFORMANCE_MODE = "FALSE"

) (
    inout        pxclk,          // I/O pad
    input        pxclk_out,      // data to be sent out through the pad (normally not used)
    input        pxclk_en,       // enable data output (normally not used)
    output       pxclk_in,       // data output - delayed pad data
    input        rst,            // reset
    input        mclk,           // clock for setting delay values
    input  [7:0] dly_data,       // delay value (3 LSB - fine delay) - @posedge mclk
    input        set_idelay,     // mclk synchronous load idelay value
    input        ld_idelay       // mclk synchronous set idealy value
);
    wire pxclk_iobuf;

    iobuf #(
        .DRIVE        (PXD_DRIVE),
        .IBUF_LOW_PWR (PXD_IBUF_LOW_PWR),
        .IOSTANDARD   (PXD_IOSTANDARD),
        .SLEW         (PXD_SLEW)
    ) iobuf_pxclk_i (
        .O     (pxclk_iobuf), // output
        .IO    (pxclk), // inout
        .I     (pxclk_out), // input
        .T     (!pxclk_en) // input
    );

    idelay_fine_pipe # (
        .IODELAY_GRP           (IODELAY_GRP),
        .DELAY_VALUE           (IDELAY_VALUE),
        .REFCLK_FREQUENCY      (REFCLK_FREQUENCY),
        .HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE)
    ) pxclk_dly_i(
        .clk          (mclk),
        .rst          (rst),
        .set          (set_idelay),
        .ld           (ld_idelay),
        .delay        (dly_data[7:0]),
        .data_in      (pxclk_iobuf),
        .data_out     (pxclk_in)
    );


endmodule

