/*******************************************************************************
 * Module: sens_parallel12
 * Date:2015-05-10  
 * Author: andrey     
 * Description: Sensor interface with 12-bit for parallel bus
 *
 * Copyright (c) 2015 Elphel, Inc.
 * sens_parallel12.v is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 *  sens_parallel12.v is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/> .
 *******************************************************************************/
`timescale 1ns/1ps

module  sens_parallel12 #(
    parameter SENSIO_ADDR =        'h330,
    parameter SENSIO_ADDR_MASK =   'h3f8,
    parameter SENSIO_CTRL =        'h0,
    parameter SENSIO_STATUS =      'h1,
    parameter SENSIO_JTAG =        'h2,
    parameter SENSIO_WIDTH =       'h3, // 1.. 2^16, 0 - use HACT
    parameter SENSIO_DELAYS =      'h4, // 'h4..'h7
    parameter SENSIO_STATUS_REG =  'h31,

    parameter SENS_JTAG_PGMEN =    8,
    parameter SENS_JTAG_PROG =     6,
    parameter SENS_JTAG_TCK =      4,
    parameter SENS_JTAG_TMS =      2,
    parameter SENS_JTAG_TDI =      0,
    
    parameter SENS_CTRL_MRST=      0,  //  1: 0
    parameter SENS_CTRL_ARST=      2,  //  3: 2
    parameter SENS_CTRL_ARO=       4,  //  5: 4
    parameter SENS_CTRL_RST_MMCM=  6,  //  7: 6
    parameter SENS_CTRL_EXT_CLK=   8,  //  9: 8
    parameter SENS_CTRL_LD_DLY=   10,  // 10
    parameter SENS_CTRL_QUADRANTS=12,  // 17:12, enable - 20
    
    parameter LINE_WIDTH_BITS =   16,
    
    parameter IODELAY_GRP ="IODELAY_SENSOR", // may need different for different channels?
    parameter integer IDELAY_VALUE = 0,
    parameter integer PXD_DRIVE = 12,
    parameter PXD_IBUF_LOW_PWR = "TRUE",
    parameter PXD_IOSTANDARD = "DEFAULT",
    parameter PXD_SLEW = "SLOW",
    parameter real REFCLK_FREQUENCY = 300.0,
    parameter HIGH_PERFORMANCE_MODE = "FALSE",
    
    parameter PHASE_WIDTH=      8,      // number of bits for te phase counter (depends on divisors)
    parameter PCLK_PERIOD =     10.000,  // input period in ns, 0..100.000 - MANDATORY, resolution down to 1 ps
    parameter BANDWIDTH =       "OPTIMIZED",  //"OPTIMIZED", "HIGH","LOW"

    parameter CLKFBOUT_MULT_SENSOR =   8,  // 100 MHz --> 800 MHz
    parameter CLKFBOUT_PHASE_SENSOR =  0.000,  // CLOCK FEEDBACK phase in degrees (3 significant digits, -360.000...+360.000)
    parameter IPCLK_PHASE =           0.000,
    parameter IPCLK2X_PHASE =         0.000,
    

    parameter DIVCLK_DIVIDE =         1,            // Integer 1..106. Divides all outputs with respect to CLKIN
    parameter REF_JITTER1   =         0.010,        // Expectet jitter on CLKIN1 (0.000..0.999)
    parameter REF_JITTER2   =         0.010,
    parameter SS_EN         =         "FALSE",      // Enables Spread Spectrum mode
    parameter SS_MODE       =         "CENTER_HIGH",//"CENTER_HIGH","CENTER_LOW","DOWN_HIGH","DOWN_LOW"
    parameter SS_MOD_PERIOD =         10000        // integer 4000-40000 - SS modulation period in ns
    
)(
    input         rst,
    input         pclk,   // global clock input, pixel rate (96MHz for MT9P006)
    output        ipclk,  // re-generated sensor output clock (regional clock to drive external fifo) 
    output        ipclk2x,// twice frequency regenerated sensor clock (possibly to run external fifo)
//    input         pclk2x, // maybe not needed here
    // sensor pads excluding i2c
    input         vact,
    input         hact, //output in fillfactory mode
    inout         bpf,  // output in fillfactory mode
    inout  [11:0] pxd, //actually only 2 LSBs are inouts
    inout         mrst,
    inout         senspgm,    // SENSPGM I/O pin
    
    inout         arst,
    inout         aro,
    output        dclk,
    // output
    output [11:0] pxd_out,
    output        vact_out, 
    output        hact_out, 

    // JTAG to program 10359
//    input          xpgmen,     // enable programming mode for external FPGA
//    input          xfpgaprog,  // PROG_B to be sent to an external FPGA
//    output         xfpgadone,  // state of the MRST pin ("DONE" pin on external FPGA)
//    input          xfpgatck,   // TCK to be sent to external FPGA
//    input          xfpgatms,   // TMS to be sent to external FPGA
//    input          xfpgatdi,   // TDI to be sent to external FPGA
//    output         xfpgatdo,   // TDO read from external FPGA
//    output         senspgmin,    
    
    // programming interface
    input         mclk,     // global clock, half DDR3 clock, synchronizes all I/O through the command port
    input   [7:0] cmd_ad,      // byte-serial command address/data (up to 6 bytes: AL-AH-D0-D1-D2-D3 
    input         cmd_stb,     // strobe (with first byte) for the command a/d
    output  [7:0] status_ad,   // status address/data - up to 5 bytes: A - {seq,status[1:0]} - status[2:9] - status[10:17] - status[18:25]
    output        status_rq,   // input request to send status downstream
    input         status_start // Acknowledge of the first status packet byte (address)
);

//    wire tdi,tdo,done,tms,tck,ten;
    wire ibpf;
    wire ipclk_pre, ipclk2x_pre;
//    wire ipclk, ipclk2x;
    
    reg  [31:0] data_r; 
    reg   [3:0] set_idelay;
    reg         set_ctrl_r;
    reg         set_status_r;
    reg   [1:0] set_width_r; // to make double-cycle subtract
    reg         set_jtag_r;
    
    reg [LINE_WIDTH_BITS-1:0] line_width_m1;  // regenerated HACT duration; 
    reg                       line_width_internal; // use regenetrated ( 0 - use HACT as is)
    reg [LINE_WIDTH_BITS-1:0] hact_cntr;
    
//    reg         set_quad; // [1:0] - px, [3:2] - HACT, [5:4] - VACT,
    wire        clk_fb;
    
    wire  [2:0] set_pxd_delay;
    wire        set_other_delay;
    
    wire        ps_rdy;
    wire  [7:0] ps_out;      
    wire        locked_pxd_mmcm;
    wire        clkin_pxd_stopped_mmcm;
    wire        clkfb_pxd_stopped_mmcm;
    
    // programmed resets to the sensor 
    reg         iaro  = 0;
    reg         iarst = 0;
    reg         imrst = 0;
    reg         rst_mmcm=1; // rst and command - en/dis 
    reg  [5:0]  quadrants=0;
    reg         ld_idelay=0;
    reg         sel_ext_clk=0; // select clock source from the sensor (0 - use internal clock - to sesnor)



    wire [14:0] status;
    
    wire        cmd_we;
    wire  [2:0] cmd_a;
    wire [31:0] cmd_data;
    
    wire           xfpgadone;  // state of the MRST pin ("DONE" pin on external FPGA)
    wire           xfpgatdo;   // TDO read from external FPGA
    wire           senspgmin;    

    reg            xpgmen=0;     // enable programming mode for external FPGA
    reg            xfpgaprog=0;  // PROG_B to be sent to an external FPGA
    reg            xfpgatck=0;   // TCK to be sent to external FPGA
    reg            xfpgatms=0;   // TMS to be sent to external FPGA
    reg            xfpgatdi=0;   // TDI to be sent to external FPGA
    wire           hact_ext;     // received hact signal
    reg            hact_ext_r;   // received hact signal, delayed by 1 clock
    reg            hact_r;       // received or regenerated hact  
    
    assign set_pxd_delay =   set_idelay[2:0];
    assign set_other_delay = set_idelay[3];
    assign status = {locked_pxd_mmcm,clkin_pxd_stopped_mmcm,clkfb_pxd_stopped_mmcm,xfpgadone,ps_rdy, ps_out,xfpgatdo,senspgmin};
    assign hact_out = hact_r;
    
    always @(posedge rst or posedge mclk) begin
        if      (rst)     data_r <= 0;
        else if (cmd_we)  data_r <= cmd_data;
        if      (rst)     set_idelay <= 0;
        else   set_idelay <=  {4{cmd_we}} & {(cmd_a==(SENSIO_DELAYS+3))?1'b1:1'b0,
                                             (cmd_a==(SENSIO_DELAYS+2))?1'b1:1'b0,
                                             (cmd_a==(SENSIO_DELAYS+1))?1'b1:1'b0,
                                             (cmd_a==(SENSIO_DELAYS+0))?1'b1:1'b0};
        if (rst) set_status_r <=0;
        else     set_status_r <= cmd_we && (cmd_a== SENSIO_STATUS);                             
        if (rst) set_ctrl_r <=0;
        else     set_ctrl_r <= cmd_we && (cmd_a== SENSIO_CTRL);                             
        if (rst) set_jtag_r <=0;
        else     set_jtag_r <= cmd_we && (cmd_a== SENSIO_JTAG);
        
        if      (rst)                                       xpgmen <= 0;
        else if (set_jtag_r && data_r[SENS_JTAG_PGMEN + 1]) xpgmen <= data_r[SENS_JTAG_PGMEN]; 

        if      (rst)                                       xfpgaprog <= 0;
        else if (set_jtag_r && data_r[SENS_JTAG_PROG + 1])  xfpgaprog <= data_r[SENS_JTAG_PROG]; 
                                     
        if      (rst)                                       xfpgatck <= 0;
        else if (set_jtag_r && data_r[SENS_JTAG_TCK + 1])   xfpgatck <= data_r[SENS_JTAG_TCK]; 

        if      (rst)                                       xfpgatms <= 0;
        else if (set_jtag_r && data_r[SENS_JTAG_TMS + 1])   xfpgatms <= data_r[SENS_JTAG_TMS]; 

        if      (rst)                                       xfpgatdi <= 0;
        else if (set_jtag_r && data_r[SENS_JTAG_TDI + 1])   xfpgatdi <= data_r[SENS_JTAG_TDI];
        
        if      (rst)                                           imrst <= 0;
        else if (set_ctrl_r && data_r[SENS_CTRL_MRST + 1])      imrst <= data_r[SENS_CTRL_MRST]; 
         
        if      (rst)                                           iarst <= 0;
        else if (set_ctrl_r && data_r[SENS_CTRL_ARST + 1])      iarst <= data_r[SENS_CTRL_ARST]; 
         
        if      (rst)                                           iaro <= 0;
        else if (set_ctrl_r && data_r[SENS_CTRL_MRST + 1])      iaro <= data_r[SENS_CTRL_ARO]; 
         
        if      (rst)                                           rst_mmcm <= 0;
        else if (set_ctrl_r && data_r[SENS_CTRL_RST_MMCM + 1])  rst_mmcm <= data_r[SENS_CTRL_RST_MMCM]; 
         
        if      (rst)                                           sel_ext_clk <= 0;
        else if (set_ctrl_r && data_r[SENS_CTRL_EXT_CLK + 1])   sel_ext_clk <= data_r[SENS_CTRL_EXT_CLK]; 
         
        if      (rst)                                           quadrants <= 0;
        else if (set_ctrl_r && data_r[SENS_CTRL_QUADRANTS + 8]) quadrants <= data_r[SENS_CTRL_QUADRANTS+:6]; 

        if  (rst) ld_idelay <= 0;
        else      ld_idelay <= set_ctrl_r && data_r[SENS_CTRL_LD_DLY]; 
        
        if  (rst) set_width_r <= 0;
        else      set_width_r <= {set_width_r[0],cmd_we && (cmd_a== SENSIO_WIDTH)}; 
        
        if      (rst)            line_width_m1 <= 0;
        else if (set_width_r[1]) line_width_m1 <= data_r[LINE_WIDTH_BITS-1:0] -1;
        
        if      (rst)            line_width_internal <= 0;
        else if (set_width_r[1]) line_width_internal <= ~ (|data_r[LINE_WIDTH_BITS:0]);
        
        // regenerate/propagate  HACT
        
        if (rst) hact_ext_r <= 1'b0;
        else     hact_ext_r <= hact_ext;
        
        if      (rst)                                                  hact_r <= 0;
        else if (hact_ext && !hact_ext_r)                              hact_r <= 1;
        else if (line_width_internal?(hact_cntr == 0):( hact_ext ==0)) hact_r <= 0; 
        
        if      (rst)                     hact_cntr <= 0;
        else if (hact_ext && !hact_ext_r) hact_cntr <= line_width_m1;
        else if (hact_r)                  hact_cntr <= hact_cntr - 1;
        
    end
    
/*
 Control programming of external FPGA on the sensor/sensor multiplexor board
 Mulptiplex status signals into a single line
 bits:
  9: 8 - 3 - set xpgmen,
       - 2 - reset xpgmen,  
       - 0, 1 - no changes to xpgmen
  7: 6 - 3 - set xfpgaprog,
       - 2 - reset xfpgaprog,  
       - 0, 1 - no changes to xfpgaprog
  5: 4 - 3 - set xfpgatck,
       - 2 - reset xfpgatck,  
       - 0, 1 - no changes to xfpgatck
  3: 2 - 3 - set xfpgatms,
       - 2 - reset xfpgatms,
       - 0, 1 - no changes to xfpgatms
  1: 0 - 3 - set xfpgatdi,
       - 2 - reset xfpgatdi,
       - 0, 1 - no changes to xfpgatdi
    parameter SENS_CTRL_MRST=      0,  //  1: 0
    parameter SENS_CTRL_ARST=      2,  //  3: 2
    parameter SENS_CTRL_ARO=       4,  //  5: 4
    parameter SENS_CTRL_RST_MMCM=  6,  //  7: 6
    parameter SENS_CTRL_EXT_CLK=   8,  //  9: 8
    parameter SENS_CTRL_LD_DLY=   10,  // 10
    parameter SENS_CTRL_QUADRANTS=12,  // 17:12, enable - 20
       
*/
    
    
    
    
    cmd_deser #(
        .ADDR        (SENSIO_ADDR),
        .ADDR_MASK   (SENSIO_ADDR_MASK),
        .NUM_CYCLES  (6),
        .ADDR_WIDTH  (3),
        .DATA_WIDTH  (32)
    ) cmd_deser_sens_io_i (
        .rst         (rst), // input
        .clk         (mclk), // input
        .ad          (cmd_ad), // input[7:0] 
        .stb         (cmd_stb), // input
        .addr        (cmd_a), // output[15:0] 
        .data        (cmd_data), // output[31:0] 
        .we          (cmd_we) // output
    );

    status_generate #(
        .STATUS_REG_ADDR(SENSIO_STATUS_REG),
        .PAYLOAD_BITS(15) // STATUS_PAYLOAD_BITS)
    ) status_generate_sens_io_i (
        .rst        (rst), // input
        .clk        (mclk), // input
        .we         (set_status_r), // input
        .wd         (data_r[7:0]), // input[7:0] 
        .status     (status), // input[25:0] 
        .ad         (status_ad), // output[7:0] 
        .rq         (status_rq), // output
        .start      (status_start) // input
    );
    
    
    
    
    // 2 lower PXD bits are multifunction (used for JTAG), instance them individually
    pxd_single #(
        .IODELAY_GRP           (IODELAY_GRP),
        .IDELAY_VALUE          (IDELAY_VALUE),
        .PXD_DRIVE             (PXD_DRIVE),
        .PXD_IBUF_LOW_PWR      (PXD_IBUF_LOW_PWR),
        .PXD_IOSTANDARD        (PXD_IOSTANDARD),
        .PXD_SLEW              (PXD_SLEW),
        .REFCLK_FREQUENCY      (REFCLK_FREQUENCY),
        .HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE)
    ) pxd_pxd0_i (
        .pxd            (pxd[0]),          // inout
        .pxd_out        (xfpgatdi),            // input
        .pxd_en         (xpgmen),            // input
        .pxd_async      (),             // output
        .pxd_in         (pxd_out[0]),      // output
        .ipclk          (ipclk),           // input
        .ipclk2x        (ipclk2x),         // input
        .rst            (rst),             // input
        .mclk           (mclk),            // input
        .dly_data       (data_r[7:0]),          // input[7:0] 
        .set_idelay     (set_pxd_delay[0]),// input
        .ld_idelay      (ld_idelay),       // input
        .quadrant       (quadrants[1:0])   // input[1:0] 
    );

    pxd_single #(
        .IODELAY_GRP           (IODELAY_GRP),
        .IDELAY_VALUE          (IDELAY_VALUE),
        .PXD_DRIVE             (PXD_DRIVE),
        .PXD_IBUF_LOW_PWR      (PXD_IBUF_LOW_PWR),
        .PXD_IOSTANDARD        (PXD_IOSTANDARD),
        .PXD_SLEW              (PXD_SLEW),
        .REFCLK_FREQUENCY      (REFCLK_FREQUENCY),
        .HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE)
    ) pxd_pxd1_i (
        .pxd            (pxd[1]),          // inout
        .pxd_out        (1'b0),            // input
        .pxd_en         (1'b0),            // input
        .pxd_async      (xfpgatdo),        // output
        .pxd_in         (pxd_out[1]),      // output
        .ipclk          (ipclk),           // input
        .ipclk2x        (ipclk2x),         // input
        .rst            (rst),             // input
        .mclk           (mclk),            // input
        .dly_data       (data_r[15:8]),          // input[7:0] 
        .set_idelay     (set_pxd_delay[0]),// input
        .ld_idelay      (ld_idelay),       // input
        .quadrant       (quadrants[1:0])   // input[1:0] 
    );
    // bits 2..11 are just PXD inputs, instance them all together
    generate
        genvar i;
        for (i=2; i < 12; i=i+1) begin: pxd_block
            pxd_single #(
                .IODELAY_GRP           (IODELAY_GRP),
                .IDELAY_VALUE          (IDELAY_VALUE),
                .PXD_DRIVE             (PXD_DRIVE),
                .PXD_IBUF_LOW_PWR      (PXD_IBUF_LOW_PWR),
                .PXD_IOSTANDARD        (PXD_IOSTANDARD),
                .PXD_SLEW              (PXD_SLEW),
                .REFCLK_FREQUENCY      (REFCLK_FREQUENCY),
                .HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE)
            ) pxd_pxd1_i (
                .pxd            (pxd[i]),          // inout
                .pxd_out        (1'b0),            // input
                .pxd_en         (1'b0),            // input
                .pxd_async      (),                // output
                .pxd_in         (pxd_out[i]),      // output
                .ipclk          (ipclk),           // input
                .ipclk2x        (ipclk2x),         // input
                .rst            (rst),             // input
                .mclk           (mclk),            // input
                .dly_data       (data_r[8*((i+2)&3)+:8]), // input[7:0] alternating bytes of 32-bit word
                .set_idelay     (set_pxd_delay[(i+2)>>2]),// input 0 for pxd[3:2], 1 for pxd[7:4], 2 for pxd [11:8]
                .ld_idelay      (ld_idelay),       // input
                .quadrant       (quadrants[1:0])   // input[1:0] 
            );
        end
    endgenerate
    
    pxd_single #(
        .IODELAY_GRP           (IODELAY_GRP),
        .IDELAY_VALUE          (IDELAY_VALUE),
        .PXD_DRIVE             (PXD_DRIVE),
        .PXD_IBUF_LOW_PWR      (PXD_IBUF_LOW_PWR),
        .PXD_IOSTANDARD        (PXD_IOSTANDARD),
        .PXD_SLEW              (PXD_SLEW),
        .REFCLK_FREQUENCY      (REFCLK_FREQUENCY),
        .HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE)
    ) pxd_hact_i (
        .pxd            (hact),          // inout
        .pxd_out        (1'b0),          // input
        .pxd_en         (1'b0),          // input
        .pxd_async      (),              // output
        .pxd_in         (hact_ext),      // output
        .ipclk          (ipclk),         // input
        .ipclk2x        (ipclk2x),       // input
        .rst            (rst),           // input
        .mclk           (mclk),          // input
        .dly_data       (data_r[7:0]),        // input[7:0] 
        .set_idelay     (set_other_delay),// input
        .ld_idelay      (ld_idelay),     // input
        .quadrant       (quadrants[3:2]) // input[1:0] 
    );
    
    pxd_single #(
        .IODELAY_GRP           (IODELAY_GRP),
        .IDELAY_VALUE          (IDELAY_VALUE),
        .PXD_DRIVE             (PXD_DRIVE),
        .PXD_IBUF_LOW_PWR      (PXD_IBUF_LOW_PWR),
        .PXD_IOSTANDARD        (PXD_IOSTANDARD),
        .PXD_SLEW              (PXD_SLEW),
        .REFCLK_FREQUENCY      (REFCLK_FREQUENCY),
        .HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE)
    ) pxd_vact_i (
        .pxd            (vact),          // inout
        .pxd_out        (1'b0),          // input
        .pxd_en         (1'b0),          // input
        .pxd_async      (),              // output
        .pxd_in         (vact_out),      // output
        .ipclk          (ipclk),         // input
        .ipclk2x        (ipclk2x),       // input
        .rst            (rst),           // input
        .mclk           (mclk),          // input
        .dly_data       (data_r[15:8]),  // input[7:0] 
        .set_idelay     (set_other_delay),// input
        .ld_idelay      (ld_idelay),     // input
        .quadrant       (quadrants[5:4]) // input[1:0] 
    );
    // receive clock from sensor
    pxd_clock #(
        .IODELAY_GRP           (IODELAY_GRP),
        .IDELAY_VALUE          (IDELAY_VALUE),
        .PXD_DRIVE             (PXD_DRIVE),
        .PXD_IBUF_LOW_PWR      (PXD_IBUF_LOW_PWR),
        .PXD_IOSTANDARD        (PXD_IOSTANDARD),
        .PXD_SLEW              (PXD_SLEW),
        .REFCLK_FREQUENCY      (REFCLK_FREQUENCY),
        .HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE)
    ) pxd_clock_i (
        .pxclk      (bpf),             // inout
        .pxclk_out  (1'b0),            // input
        .pxclk_en   (1'b0),            // input
        .pxclk_in   (ibpf),            // output
        .rst        (rst),             // input
        .mclk       (mclk),            // input
        .dly_data   (data_r[23:16]),   // input[7:0] 
        .set_idelay (set_other_delay), // input
        .ld_idelay  (ld_idelay)        // input
    );
    // generate dclk output
    oddr_ss #(
        .IOSTANDARD   (PXD_IOSTANDARD),
        .SLEW         (PXD_SLEW),
        .DDR_CLK_EDGE ("OPPOSITE_EDGE"),
        .INIT         (1'b0),
        .SRTYPE       ("SYNC")
    ) dclk_i (
        .clk   (pclk), // input
        .ce    (1'b1), // input
        .rst   (rst), // input
        .set   (1'b0), // input
        .din   (2'b01), // input[1:0] 
        .tin   (1'b0), // input
        .dq    (dclk) // output
    );

    // generate ARO/TCK
    iobuf #(
        .DRIVE        (PXD_DRIVE),
        .IBUF_LOW_PWR (PXD_IBUF_LOW_PWR),
        .IOSTANDARD   (PXD_IOSTANDARD),
        .SLEW         (PXD_SLEW)
    ) aro_tck_i (
        .O  (),                        // output - currently not used
        .IO (aro),                     // inout I/O pad
        .I  (xpgmen? xfpgatck : iaro), // input
        .T  (1'b0)                     // input - always on
    );

    // generate ARST/TMS
    iobuf #(
        .DRIVE        (PXD_DRIVE),
        .IBUF_LOW_PWR (PXD_IBUF_LOW_PWR),
        .IOSTANDARD   (PXD_IOSTANDARD),
        .SLEW         (PXD_SLEW)
    ) arst_tms_i (
        .O  (),                         // output - currently not used
        .IO (arst),                     // inout I/O pad
        .I  (xpgmen? xfpgatms : iarst), // input
        .T  (1'b0)                      // input - always on
    );
    
    // generate MRST/ receive DONE
    iobuf #(
        .DRIVE        (PXD_DRIVE),
        .IBUF_LOW_PWR (PXD_IBUF_LOW_PWR),
        .IOSTANDARD   (PXD_IOSTANDARD),
        .SLEW         (PXD_SLEW)
    ) mrst_done_i (
        .O  (xfpgadone),  // output - done from external FPGA
        .IO (mrst),       // inout I/O pad
        .I  (imrst),      // input
        .T  (xpgmen)      // input - disable when reading DONE
    );
    
    // Probe programmable/ control PROGRAM pin
    reg [1:0] xpgmen_d;
    reg force_senspgm=0;
    
    iobuf #(
        .DRIVE        (PXD_DRIVE),
        .IBUF_LOW_PWR (PXD_IBUF_LOW_PWR),
        .IOSTANDARD   (PXD_IOSTANDARD),
        .SLEW         (PXD_SLEW)
    ) senspgm_i (
        .O  (senspgmin),                         // output -senspgm pin state
        .IO (senspgm),                           // inout I/O pad
        .I  (xpgmen?(~xfpgaprog):force_senspgm), // input
        .T  (~(xpgmen || force_senspgm))         // input - disable when reading DONE
    );
    // pullup for mrst (used as input for "DONE") and senspgm (grounded on sesnor boards)
    mpullup i_mrst_pullup(mrst);
    mpullup i_senspgm_pullup(senspgm);
    always @ (posedge mclk or posedge rst) begin
        if      (rst)                  force_senspgm <= 0;
        else if (xpgmen_d[1:0]==2'b10) force_senspgm <= senspgmin;
        if      (rst) xpgmen_d <= 0;
        else          xpgmen_d <= {xpgmen_d[0], xpgmen};
    end

    // generate phase-shifterd pixel clock (and 2x version) from either the internal clock (that is output to the sensor) or from the clock
    // received from the sensor (may need to reset MMCM after resetting sensor)
    mmcm_phase_cntr #(
        .PHASE_WIDTH         (PHASE_WIDTH),
        .CLKIN_PERIOD        (PCLK_PERIOD),
        .BANDWIDTH           (BANDWIDTH),
        .CLKFBOUT_MULT_F     (CLKFBOUT_MULT_SENSOR), //8
        .DIVCLK_DIVIDE       (DIVCLK_DIVIDE),
        .CLKFBOUT_PHASE      (CLKFBOUT_PHASE_SENSOR),
        .CLKOUT0_PHASE       (IPCLK_PHASE),
        .CLKOUT1_PHASE       (IPCLK2X_PHASE),
//        .CLKOUT2_PHASE          (0.000),
//        .CLKOUT3_PHASE          (0.000),
//        .CLKOUT4_PHASE          (0.000),
//        .CLKOUT5_PHASE          (0.000),
//        .CLKOUT6_PHASE          (0.000),
        .CLKFBOUT_USE_FINE_PS("FALSE"),
        .CLKOUT0_USE_FINE_PS ("TRUE"),
        .CLKOUT1_USE_FINE_PS ("TRUE"),
//        .CLKOUT2_USE_FINE_PS ("FALSE"),
//        .CLKOUT3_USE_FINE_PS ("FALSE"),
//        .CLKOUT4_USE_FINE_PS("FALSE"),
//        .CLKOUT5_USE_FINE_PS("FALSE"),
//        .CLKOUT6_USE_FINE_PS("FALSE"),
        .CLKOUT0_DIVIDE_F    (4.000),
        .CLKOUT1_DIVIDE      (8),
//        .CLKOUT2_DIVIDE      (1),
//        .CLKOUT3_DIVIDE      (1),
//        .CLKOUT4_DIVIDE(1),
//        .CLKOUT5_DIVIDE(1),
//        .CLKOUT6_DIVIDE(1),
        .COMPENSATION        ("ZHOLD"),
        .REF_JITTER1         (REF_JITTER1),
        .REF_JITTER2         (REF_JITTER2),
        .SS_EN               (SS_EN),
        .SS_MODE             (SS_MODE),
        .SS_MOD_PERIOD       (SS_MOD_PERIOD),
        .STARTUP_WAIT        ("FALSE")
    ) mmcm_phase_cntr_i (
        .clkin1              (pclk),            // input
        .clkin2              (ibpf),            // input
        .clkinsel            (sel_ext_clk),     // input
        .clkfbin             (clk_fb),          // input
        .rst                 (rst_mmcm),        // input
        .pwrdwn              (1'b0),            // input
        .psclk               (mclk),            // input
        .ps_we               (set_other_delay), // input
        .ps_din              (data_r[31:24]),   // input[7:0] 
        .ps_ready            (ps_rdy),          // output
        .ps_dout             (ps_out),          // output[7:0] reg 
        .clkout0             (ipclk_pre),       // output
        .clkout1             (ipclk2x_pre),     // output
        .clkout2(), // output
        .clkout3(), // output
        .clkout4(), // output
        .clkout5(), // output
        .clkout6(), // output
        .clkout0b(), // output
        .clkout1b(), // output
        .clkout2b(), // output
        .clkout3b(), // output
        .clkfbout            (clk_fb), // output
        .clkfboutb(), // output
        .locked              (locked_pxd_mmcm),
        .clkin_stopped       (clkin_pxd_stopped_mmcm), // output
        .clkfb_stopped       (clkfb_pxd_stopped_mmcm) // output
         // output
    );

BUFR ipclk_bufr_i   (.O(ipclk),   .CE(), .CLR(), .I(ipclk_pre));
BUFR ipclk2x_bufr_i (.O(ipclk2x), .CE(), .CLR(), .I(ipclk2x_pre));


endmodule

