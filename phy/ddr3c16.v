/*******************************************************************************
 * Module: ddr3c16
 * Date:2014-05-16  
 * Author: Andrey Filippov
 * Description: ddr3 controller, 16 channel
 *
 * Copyright (c) 2014 Elphel, Inc.
 * ddr3c16.v is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 *  ddr3c16.v is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/> .
 *******************************************************************************/
`timescale 1ns/1ps

module  ddr3c16   #(
    parameter PHASE_WIDTH =     8,
    parameter SLEW_DQ =         "SLOW",
    parameter SLEW_DQS =        "SLOW",
    parameter SLEW_CMDA =       "SLOW",
    parameter SLEW_CLK =       "SLOW",
    parameter IBUF_LOW_PWR =    "TRUE",
    parameter real REFCLK_FREQUENCY = 300.0,
    parameter HIGH_PERFORMANCE_MODE = "FALSE",
    parameter CLKIN_PERIOD          = 10, //ns >1.25, 600<Fvco<1200
    parameter CLKFBOUT_MULT =       8, // Fvco=Fclkin*CLKFBOUT_MULT_F/DIVCLK_DIVIDE, Fout=Fvco/CLKOUT#_DIVIDE
    parameter CLKFBOUT_MULT_REF =   9, // Fvco=Fclkin*CLKFBOUT_MULT_F/DIVCLK_DIVIDE, Fout=Fvco/CLKOUT#_DIVIDE
    parameter CLKFBOUT_DIV_REF =    3, // To get 300MHz for the reference clock
    parameter DIVCLK_DIVIDE=        1,
    parameter CLKFBOUT_PHASE =      0.000,
    parameter ICLK_PHASE =          0.000,
    parameter CLK_PHASE =           0.000,
    parameter CLK_DIV_PHASE =       0.000,
    parameter MCLK_PHASE =          90.000,
    parameter REF_JITTER1 =         0.010,
    parameter SS_EN =              "FALSE",
    parameter SS_MODE =      "CENTER_HIGH",
    parameter SS_MOD_PERIOD =       10000,
    parameter CMD_PAUSE_BITS=       6,
    parameter CMD_DONE_BIT=         6
)(
    // DDR3 interface
    output                       SDCLK, // DDR3 clock differential output, positive
    output                       SDNCLK,// DDR3 clock differential output, negative
    output  [ADDRESS_NUMBER-1:0] SDA,   // output address ports (14:0) for 4Gb device
    output                 [2:0] SDBA,  // output bank address ports
    output                       SDWE,  // output WE port
    output                       SDRAS, // output RAS port
    output                       SDCAS, // output CAS port
    output                       SDCKE, // output Clock Enable port
    output                       SDODT, // output ODT port

    inout                 [15:0] SDD,   // DQ  I/O pads
    inout                        SDDML, // LDM  I/O pad (actually only output)
    inout                        DQSL,  // LDQS I/O pad
    inout                        NDQSL, // ~LDQS I/O pad
    inout                        SDDMU, // UDM  I/O pad (actually only output)
    inout                        DQSU,  // UDQS I/O pad
    inout                        NDQSU, // ~UDQS I/O pad
// clocks, reset
    input                        clk_in,
    input                        rst_in,
    output                       mclk,     // global clock, half DDR3 clock, synchronizes all I/O thorough the command port
// command port 0 (filled by software - 32w->32r) - used for mode set, refresh, write levelling, ...
    input                        cmd0_clk,
    input                        cmd0_we,
    input                [9:0]   cmd0_addr,
    input               [31:0]   cmd0_data,
// automatic command port1 , filled by the PL, 32w 32r, used for actual page R/W
    input                        cmd1_clk,
    input                        cmd1_we,
    input                [9:0]   cmd1_addr,
    input               [31:0]   cmd1_data,
// Controller run interface, posedge mclk
    input               [10:0]   run_addr, // controller sequencer start address (0..11'h3ff - cmd0, 11'h400..11'h7ff - cmd1)
    input                [3:0]   run_chn,  // data channel to use
    input                        run_seq,  // start controller sequence 
    output                       run_done, // controller sequence finished   
// inteface to control I/O delays and mmcm
    input                  [7:0] dly_data, // delay value (3 LSB - fine delay)
    input                  [6:0] dly_addr, // select which delay to program
    input                        ld_delay, // load delay data to selected iodelayl (clk_div synchronous)
    input                        set,       // clk_div synchronous set all delays from previously loaded values
    output                       locked,
    output                       ps_rdy,
    output     [PHASE_WIDTH-1:0] ps_out, 
// read port 0
    input                        port0_clk,
    input                        port0_re,
    input                        port0_regen, 
    input                [1:0]   port0_page,
    input                [1:0]   port0_int_page,
    input                [7:0]   port0_addr,
    output              [31:0]   port0_data,
// write port 1
    input                        port1_clk,
    input                        port1_we,
    input                [1:0]   port1_page,
    input                [1:0]   port1_int_page,
    input                [7:0]   port1_addr,
    input               [31:0]   port1_data,
    // extras
    input                        cmda_tri, // tristate command and address lines // not likely to be used
    input                        inv_clk_div,
    input                 [7:0]  dqs_pattern, // 8'h55
    input                 [7:0]  dqm_pattern  // 8'h00
    
);
    localparam ADDRESS_NUMBER = 15;
    
    
//    wire                 [35:0]  phy_cmd; // input[35:0] 
    wire                 [31:0]  phy_cmd_word;  // selected output from eithe cmd0 buffer or cmd1 buffer 
    wire                 [31:0]  phy_cmd0_word; // cmd0 buffer output
    wire                 [31:0]  phy_cmd1_word; // cmd1 buffer output
    reg                  [ 8:0]  buf_raddr;
    reg                  [ 8:0]  buf_waddr_negedge;
    reg                          buf_wr_negedge; 
    wire                 [63:0]  buf_wdata; // output[63:0]
    reg                  [63:0]  buf_wdata_negedge; // output[63:0]
    wire                 [63:0]  buf_rdata; // multiplexed input from one of the write channels buffer
    wire                 [63:0]  buf1_rdata;
    wire                         buf_wr; // output
    wire                         buf_rd; // read next 64 bytes from the buffer, need one extra pre-read
    
    wire                         rst=rst_in;
  
//    wire                 [ 9:0]  next_cmd_addr;
    reg                  [ 9:0]  cmd_addr;      // command word adderss  
    reg                          cmd_sel;
    reg                  [ 2:0]  cmd_busy;      // bit 0 - immediately,
    wire                         phy_cmd_nop;   // decoded command (ras, cas, we) was NOP
    wire                         sequence_done;
    wire   [CMD_PAUSE_BITS-1:0]  pause_len;
    reg                          cmd_fetch;     // previous cycle command was read from the command memory, current: command valid
    wire                         pause;         // do not register new data from the command memory
    reg    [CMD_PAUSE_BITS-1:0]  pause_cntr;
    
    reg                   [1:0]  buf_page;      // one of 4 pages in the channel buffer to use for R/W
    reg                  [15:0]  buf_sel_1hot; // 1 hot channel buffer select
    
    reg                   [3:0]  run_chn_d;
    reg                          run_seq_d; 
    
    assign run_done=sequence_done;
    
    assign  pause=cmd_fetch? (phy_cmd_nop && (pause_len != 0)): (cmd_busy[2] && (pause_cntr[CMD_PAUSE_BITS-1:1]!=0));
    assign phy_cmd_word = phy_cmd_word?phy_cmd1_word:phy_cmd0_word;
     
    assign buf_rdata[63:0] = ({64{buf_sel_1hot[1]}} & buf1_rdata[63:0]); // ORR with other read channels terms   
    
    always @ (posedge mclk or posedge rst) begin
        if (rst)                cmd_busy <= 0;
        else if (sequence_done) cmd_busy <= 0;
        else cmd_busy <= {cmd_busy[1:0],run_seq}; 
        // Pause counter
        if (rst)                           pause_cntr <= 0;
        else if (!cmd_busy[1])             pause_cntr <= 0; // not needed?
        else if (cmd_fetch && phy_cmd_nop) pause_cntr <= pause_len;
        else if (pause_cntr!=0)            pause_cntr <= pause_cntr-1;
        // Fetch - command data valid
        if (rst) cmd_fetch <= 0;
        else     cmd_fetch <= cmd_busy[0] && !pause;
        // Command read adderss
        if (rst)                        cmd_addr <= 0;
        else  if (run_seq)              cmd_addr <= run_addr[9:0];
        else if (cmd_busy[0] && !pause) cmd_addr <= cmd_addr + 1;
        // command bank select (0 - "manual" (software programmed sequences), 1 - "auto" (normal block r/w)
        if (rst)            cmd_sel <= 0;
        else  if (run_seq)  cmd_sel <= run_addr[10];
        
        if (rst)            buf_page <= 0;
        else  if (run_seq)  case (run_chn)
            4'h0:    buf_page <= port0_int_page;
            4'h1:    buf_page <= port1_int_page;
            // Add other channles later
            default: buf_page <= 2'bxx; 
        endcase
        
        if (rst)            buf_sel_1hot <= 0;
        else buf_sel_1hot <= {
            (run_chn_d==4'hf)?1'b1:1'b0,
            (run_chn_d==4'he)?1'b1:1'b0,
            (run_chn_d==4'hd)?1'b1:1'b0,
            (run_chn_d==4'hc)?1'b1:1'b0,
            (run_chn_d==4'hb)?1'b1:1'b0,
            (run_chn_d==4'ha)?1'b1:1'b0,
            (run_chn_d==4'h9)?1'b1:1'b0,
            (run_chn_d==4'h8)?1'b1:1'b0,
            (run_chn_d==4'h7)?1'b1:1'b0,
            (run_chn_d==4'h6)?1'b1:1'b0,
            (run_chn_d==4'h5)?1'b1:1'b0,
            (run_chn_d==4'h4)?1'b1:1'b0,
            (run_chn_d==4'h3)?1'b1:1'b0,
            (run_chn_d==4'h2)?1'b1:1'b0,
            (run_chn_d==4'h1)?1'b1:1'b0,
            (run_chn_d==4'h0)?1'b1:1'b0 };
        if (rst)                   buf_raddr <= 9'h0;
        else if (run_seq_d)        buf_raddr <= {buf_page,7'h0};
        else if (buf_wr || buf_rd) buf_raddr <= buf_raddr +1; // Separate read/write address? read address re-registered @ negedge
    end
    // re-register buffer write address to match DDR3 data
    always @ (negedge mclk) begin
        buf_waddr_negedge <= buf_raddr;
        buf_wr_negedge <= buf_wr;
        buf_wdata_negedge <= buf_wdata;
    end

    always @ (posedge mclk) begin
        run_chn_d <= run_chn;
        run_seq_d <= run_seq;
    end
    
// Command sequence memories:
// Command sequence memory 0 ("manual"):
    ram_1kx32_1kx32 #(
        .REGISTERS(1) // register output
    ) cmd0_buf_i (
        .rclk     (mclk), // input
        .raddr    (cmd_addr), // input[9:0] 
        .ren      (!cmd_sel && cmd_busy && !pause), // input
        .regen    (!cmd_sel && cmd_busy && !pause), // input
        .data_out (phy_cmd0_word), // output[31:0] 
        .wclk     (cmd0_clk), // input
        .waddr    (cmd0_addr), // input[9:0] 
        .we       (cmd0_we), // input
        .web      (4'hf), // input[3:0] 
        .data_in  (cmd0_data) // input[31:0] 
    );

// Command sequence memory 0 ("manual"):
    ram_1kx32_1kx32 #(
        .REGISTERS(1) // register output
    ) cmd1_buf_i (
        .rclk     (mclk), // input
        .raddr    (cmd_addr), // input[9:0] 
        .ren      ( cmd_sel && cmd_busy && !pause), // input
        .regen    ( cmd_sel && cmd_busy && !pause), // input
        .data_out (phy_cmd1_word), // output[31:0] 
        .wclk     (cmd1_clk), // input
        .waddr    (cmd1_addr), // input[9:0] 
        .we       (cmd1_we), // input
        .web      (4'hf), // input[3:0] 
        .data_in  (cmd1_data) // input[31:0] 
    );
// Port memory buffer (4 pages each, R/W fixed, port 0 - AXI read from DDR, port 1 - AXI write to DDR
// Port 0 (read DDR to AXI) buffer
    ram_512x64w_1kx32r #(
        .REGISTERS(1)
    ) port0_buf_i (
        .rclk     (port0_clk), // input
        .raddr    ({port0_page,port0_addr}), // input[9:0] 
        .ren      (port0_re), // input
        .regen    (port0_regen), // input
        .data_out (port0_data), // output[31:0] 
        .wclk     (!mclk), // input
        .waddr    (buf_waddr_negedge), // input[8:0] 
        .we       (buf_sel_1hot[0] && buf_wr_negedge), // input
        .web      (8'hff), // input[7:0] 
        .data_in  (buf_wdata_negedge) // input[63:0] 
    );
    
// Port 1 (write DDR from AXI) buffer
    ram_1kx32w_512x64r #(
        .REGISTERS(1)
    ) port1_buf_i (
        .rclk(mclk), // input
        .raddr(buf_raddr), // input[8:0] 
        .ren(buf_sel_1hot[1] && buf_rd), // input
        .regen(buf_sel_1hot[1] && buf_rd), // input
        .data_out(buf1_rdata), // output[63:0] 
        .wclk(port1_clk), // input
        .waddr({port1_page,port1_addr}), // input[9:0] 
        .we(port1_we), // input
        .web(4'hf), // input[3:0] 
        .data_in(port1_data) // input[31:0] 
    );
    
    
    
    phy_cmd #(
        .ADDRESS_NUMBER        (ADDRESS_NUMBER),
        .PHASE_WIDTH           (PHASE_WIDTH),
        .SLEW_DQ               (SLEW_DQ),
        .SLEW_DQS              (SLEW_DQS),
        .SLEW_CMDA             (SLEW_CMDA),
        .SLEW_CLK              (SLEW_CLK),
        .IBUF_LOW_PWR          (IBUF_LOW_PWR),
        .REFCLK_FREQUENCY      (REFCLK_FREQUENCY),
        .HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE),
        .CLKIN_PERIOD          (CLKIN_PERIOD),
        .CLKFBOUT_MULT         (CLKFBOUT_MULT),
        .CLKFBOUT_MULT_REF     (CLKFBOUT_MULT_REF),
        .CLKFBOUT_DIV_REF      (CLKFBOUT_DIV_REF),
        .DIVCLK_DIVIDE         (DIVCLK_DIVIDE),
        .CLKFBOUT_PHASE        (CLKFBOUT_PHASE),
        .ICLK_PHASE            (ICLK_PHASE),
        .CLK_PHASE             (CLK_PHASE),
        .CLK_DIV_PHASE         (CLK_DIV_PHASE),
        .MCLK_PHASE            (MCLK_PHASE),
        .REF_JITTER1           (REF_JITTER1),
        .SS_EN                 (SS_EN),
        .SS_MODE               (SS_MODE),
        .SS_MOD_PERIOD         (SS_MOD_PERIOD),
        .CMD_PAUSE_BITS        (CMD_PAUSE_BITS), // numer of (address) bits to encode pause
        .CMD_DONE_BIT          (CMD_DONE_BIT)    // bit number (address) to signal sequence done
        
    ) phy_cmd_i (
        .SDCLK               (SDCLK), // output
        .SDNCLK              (SDNCLK), // output
        .SDA                 (SDA[ADDRESS_NUMBER-1:0]), // output[14:0] 
        .SDBA                (SDBA[2:0]), // output[2:0] 
        .SDWE                (SDWE), // output
        .SDRAS               (SDRAS), // output
        .SDCAS               (SDCAS), // output
        .SDCKE               (SDCKE), // output
        .SDODT               (SDODT), // output
        .SDD                 (SDD[15:0]), // inout[15:0] 
        .SDDML               (SDDML), // inout
        .DQSL                (DQSL), // inout
        .NDQSL               (NDQSL), // inout
        .SDDMU               (SDDMU), // inout
        .DQSU                (DQSU), // inout
        .NDQSU               (NDQSU), // inout
        .clk_in              (clk_in), // input
        .rst_in              (rst_in), // input
        .mclk                (mclk), // output
        .dly_data            (dly_data[7:0]), // input[7:0] 
        .dly_addr            (dly_addr[6:0]), // input[6:0] 
        .ld_delay            (ld_delay), // input
        .set                 (set), // input
        .locked              (locked), // output
        .ps_rdy              (ps_rdy), // output
        .ps_out              (ps_out[7:0]), // output[7:0] 
        .phy_cmd_word        (phy_cmd_word[31:0]), // input[35:0]
        .phy_cmd_nop         (phy_cmd_nop), // output
        .pause_len           (pause_len),     // output  [CMD_PAUSE_BITS-1:0]
        .sequence_done       (sequence_done), // output
//        .buf_addr            (buf_addr[6:0]), // output[6:0] 
        .buf_wdata           (buf_wdata[63:0]), // output[63:0] 
        .buf_rdata           (buf_rdata[63:0]), // input[63:0] 
        .buf_wr              (buf_wr), // output
        .buf_rd              (buf_rd), // output
        .cmda_tri            (cmda_tri), // input
        .inv_clk_div         (inv_clk_div), // input
        .dqs_pattern         (dqs_pattern), // input[7:0] 
        .dqm_pattern         (dqm_pattern) // input[7:0] 
    );



endmodule

