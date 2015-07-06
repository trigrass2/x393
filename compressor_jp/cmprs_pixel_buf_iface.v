/*******************************************************************************
 * Module: cmprs_pixel_buf_iface
 * Date:2015-06-11  
 * Author: andrey     
 * Description: Communicates with compressor memory buffer, generates pixel
 * stream matching selected color mode, accommodates for the buffer latency,
 * acts as a pacemaker for the whole compressor (next stages are able to keep up).
 *
 * Copyright (c) 2015 Elphel, Inc.
 * cmprs_pixel_buf_iface.v is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 *  cmprs_pixel_buf_iface.v is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/> .
 *******************************************************************************/
`timescale 1ns/1ps

module  cmprs_pixel_buf_iface #(
        parameter CMPRS_PREEND_EARLY =      6, // TODO: adjust according to cmprs_macroblock_buf_iface latency. In
                                               // color18 mode this should be later than end of address run - (6*64>18*18)
                                               // "0" would generate pulse at eth same time as next macro mb_pre_start
        parameter CMPRS_RELEASE_EARLY =    16, // set to minimal actual latency in memory read, but not more than 
        parameter CMPRS_BUF_EXTRA_LATENCY = 0,  // extra register layers insered between the buffer and this module
        parameter CMPRS_COLOR18 =           0, // JPEG 4:2:0 with 18x18 overlapping tiles for de-bayer
        parameter CMPRS_COLOR20 =           1, // JPEG 4:2:0 with 18x18 overlapping tiles for de-bayer (not implemented)
        parameter CMPRS_MONO16 =            2, // JPEG 4:2:0 with 16x16 non-overlapping tiles, color components zeroed
        parameter CMPRS_JP4 =               3, // JP4 mode with 16x16 macroblocks
        parameter CMPRS_JP4DIFF =           4, // JP4DIFF mode TODO: see if correct
        parameter CMPRS_MONO8 =             7  // Regular JPEG monochrome with 8x8 macroblocks (not yet implemented)
        
    )(
    input         xclk,               // global clock input, compressor single clock rate
    input         frame_en,           // if 0 - will reset logic immediately (but not page number)
    // buffer interface, DDR3 memory read
    input  [ 7:0] buf_di,             // data from the buffer
    output [11:0] buf_ra,             // buffer read address (2 MSB - page number)
    output [ 1:0] buf_rd,             // buf {regen, re}
                                      // if running - will not restart a new frame if 0.
    input  [ 2:0] converter_type,    // 0 - color18, 1 - color20, 2 - mono, 3 - jp4, 4 - jp4-diff, 7 - mono8 (not yet implemented)
    input  [ 5:0] mb_w_m1,            // macroblock width minus 1 // 3 LSB not used, SHOULD BE SET to 3'b111
    input  [ 5:0] mb_h_m1,            // macroblock horizontal period (8/16) // 3 LSB not used  SHOULD BE SET to 3'b111
    input  [ 1:0] tile_width,         // memory tile width (can be 128 for monochrome JPEG)   Can be 32/64/128: 0 - 16, 1 - 32, 2 - 64, 3 - 128
    input         tile_col_width,     // 0 - 16 pixels,  1 -32 pixels
    // Tiles/macroblocks level (from cmprs_macroblock_buf_iface)
    output        mb_pre_end,         // just in time to start a new macroblock w/o gaps
    output        mb_release_buf,     // send required "next_page" pulses to buffer. Having rather long minimal latency in the memory
                                      // controller this can just be the same as mb_pre_end_in        
    input         mb_pre_start,       // 1 clock cycle before stream of addresses to the buffer
    input  [ 1:0] start_page,         // page to read next tile from (or first of several pages)
    input  [ 6:0] macroblock_x,       // macroblock left pixel x relative to a tile (page) Maximal page - 128 bytes wide
    output [ 7:0] data_out,           //
    output        pre_first_out,      // For each macroblock in a frame
    output        data_valid          //
);
    localparam PERIOD_COLOR18 = 384; // >18*18, limited by 6*64 (macroblocks)
    localparam PERIOD_COLOR20 = 400; // limited by the 20x20 padded macroblock
    localparam PERIOD_MONO16 =  384; // 6*64 - sends 2 of zeroed blobks
    localparam PERIOD_JP4 =     256; // 4*64 - exact match
    localparam PERIOD_JP4DIFF = 256; // TODO: see if correct
    localparam PERIOD_MONO8 =    64; // 1*64 - exact match - not yet implemented (normal mono JPEG)
    

    reg   [CMPRS_BUF_EXTRA_LATENCY+3:0] buf_re=0;
    reg    [ 7:0] do_r;
    reg    [11:0] bufa_r;             // buffer read address (2 MSB - page number)
    reg    [11:0] row_sa;             // row start address
    reg    [ 9:0] tile_sa;            // tile start address for the same row (w/o page number) for continuing row
                                      // to the next tile. Valid @ first column (first column is always from the start tile)
    reg    [ 9:4] col_inc;            // address increment when crossing tile column (1 + (macroblock_height - 1) * tile_column_width)
                                      // inc by 1 - always
    reg    [ 5:0] cols_left;
    reg    [ 5:0] rows_left;
    reg    [ 6:0] tile_x;             // horizontal position in a tile
    reg    [ 4:0] column_x;           // horizontal position in a column (0..31 or 0..15)
    reg           last_col;
    reg           first_col;
    reg           last_row;
    
    wire          addr_run_end; // generate last cycle of address run
    wire   [ 6:0] tile_width_or; // set unused msb to all 1
    wire   [ 4:0] column_width_or;// set unused msb to all 1
    wire          last_in_col;    // last pixel in a tile column
    wire          last_in_tile;   // last pixel in a tile
    
    reg    [ 8:0] period_cntr;
    reg           mb_pre_end_r;
    reg           mb_release_buf_r;
    reg           pre_first_out_r;
     
    
    assign buf_ra = bufa_r;
    assign tile_width_or=      tile_width[1]?(tile_width[0]?0:'h40):(tile_width[0]?'h60:'h70);
    assign column_width_or =   tile_col_width? 0: 'h10;
    assign last_in_col =       &column_x;
    assign last_in_tile =      &tile_x;
    assign addr_run_end =      last_col &&  last_row;

    assign mb_pre_end =        mb_pre_end_r;
    assign mb_release_buf =    mb_release_buf_r;
    assign buf_rd =            buf_re[1:0];
    assign data_out =          do_r;
    assign pre_first_out =     pre_first_out_r;
    assign data_valid =        buf_re[CMPRS_BUF_EXTRA_LATENCY+2];

    always @(posedge xclk) begin
        if      (!frame_en)     buf_re[0] <= 0;
        else if (mb_pre_start)  buf_re[0] <= 1'b1;
        else if (addr_run_end)  buf_re[0] <= 1'b0;
        
        if      (!frame_en)     buf_re[CMPRS_BUF_EXTRA_LATENCY+3:1] <= 0;
        else                    buf_re[CMPRS_BUF_EXTRA_LATENCY+3:1] <= {buf_re[CMPRS_BUF_EXTRA_LATENCY+2:0]};

        // Buffer data read:
        if (buf_re[CMPRS_BUF_EXTRA_LATENCY+2]) do_r <= buf_di;
        
        if (!frame_en) pre_first_out_r <= 0;
        else pre_first_out_r <= buf_re[CMPRS_BUF_EXTRA_LATENCY+1] && ! buf_re[CMPRS_BUF_EXTRA_LATENCY+2];
        
        if      (mb_pre_start) rows_left <= mb_h_m1;
        else if (last_col)     rows_left <= rows_left - 1;

        if      (mb_pre_start || last_col) cols_left <= mb_w_m1;
        else if (buf_re[0])                cols_left <= cols_left - 1;
        
        if      (!frame_en)     buf_re[CMPRS_BUF_EXTRA_LATENCY+2:1] <= 0;
        
        if (buf_re[0]) last_col <= 0;
        else           last_col <= (cols_left == 1);
        
        if     (buf_re[0]) last_row <= 0;
        else if (last_col) last_row <= (rows_left == 1);

        first_col <= (mb_pre_start || (last_col && !last_row));
        
        if   (mb_pre_start) row_sa <= {start_page,3'b0,macroblock_x};
        else if (first_col) row_sa <= row_sa + (tile_col_width ? 12'h20:12'h10);

        if  (mb_pre_start) tile_sa <= 0;
        else if (last_col) tile_sa <= tile_sa + (tile_col_width ? 10'h20:10'h10);
        
        if  (mb_pre_start) col_inc[9:4] <= (tile_col_width ?{mb_h_m1[4:0],1'b0} : {mb_h_m1}); // valid at first column
        
        if  (mb_pre_start || last_col) column_x <= macroblock_x[4:0] | column_width_or;
        else if (buf_re[0]) column_x <= (column_x + 1)               | column_width_or;

        if  (mb_pre_start || last_col) tile_x <= {2'b0,macroblock_x[4:0]} | tile_width_or;
        else if (buf_re[0])            tile_x <= (tile_x+1)               | tile_width_or;
        
        if  (mb_pre_start || last_col)  bufa_r[11:10] <= start_page;
        else if (last_in_tile)          bufa_r[11:10] <= bufa_r[11:10] + 1;
        
        // Most time critical - calculation of the buffer address
        if  (mb_pre_start)              bufa_r[9:0] <= {3'b0,macroblock_x};
        else if (last_col)              bufa_r[9:0] <= row_sa[9:0];
        else if (last_in_tile)          bufa_r[9:0] <= tile_sa;
        else if (buf_re[0])             bufa_r[9:0] <= bufa_r[9:0] + {last_in_col?col_inc[9:4]:6'b0,4'b1};  
        
        // now just generate delayed outputs
        if      (!frame_en)     period_cntr <= 0;
        else if (mb_pre_start) begin
            case (converter_type[2:0])
                CMPRS_COLOR18: period_cntr <= PERIOD_COLOR18 - 1;
                CMPRS_COLOR20: period_cntr <= PERIOD_COLOR20 - 1;
                CMPRS_MONO16:  period_cntr <= PERIOD_MONO16  - 1;
                CMPRS_JP4:     period_cntr <= PERIOD_JP4     - 1;
                CMPRS_JP4DIFF: period_cntr <= PERIOD_JP4DIFF - 1;
                CMPRS_MONO8:   period_cntr <= PERIOD_MONO8   - 1;
                default:       period_cntr <= 'bx;
            endcase
        end else if (|period_cntr) period_cntr <= period_cntr - 1;
        
        if (!frame_en) mb_pre_end_r     <= 0;
        else           mb_pre_end_r     <= (period_cntr == (CMPRS_PREEND_EARLY+1));
        
        if (!frame_en) mb_release_buf_r <= 0;
        else           mb_release_buf_r <= (period_cntr == (CMPRS_RELEASE_EARLY+1));
        
    end
    
endmodule
