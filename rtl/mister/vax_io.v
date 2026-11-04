//============================================================================
//  vax_io.v - the VAX 8600 MBox's view of the physical address space: the
//  physical address memory map (PAMM), the memory arrays, I/O adapter 0
//  (SBIA 0, vax_sbi.v) with the nexus on its SBI, and non-existent memory;
//  and the MBox's DMA port, which SBIA 0 uses for the SBI's DMA.
//
//        MMU ---+--- PAMM code 00-07: memory array slot 0-7 (the cache and
//               |    SDRAM, or the test bench's memory array)
//               +--- PAMM code 18: SBIA 0 --- SBI --- TR 3 DW780, TR 8 RH780
//               +--- anything else: non-existent memory (machine check)
//
//        SBIA 0 DMA ---- PAMM ---- memory arrays (or aborted: not memory)
//
//  The PAMM (VAX 8600/8650 System Fault Isolation Manual EK-8600S-MM-004,
//  M-03) holds a five-bit code for every megabyte of the 1 GB physical
//  address space, addressed by PA<29:20>: 00-07 array slot, 18-1B ABus
//  adapter 0-3, 1F non-existent. Software reaches it with the IPRs PAMLOC
//  (the megabyte, <29:20>) and PAMACC (its code, <4:0>). Processor
//  initialization loads it as the console does when it sizes the system:
//  32 MB as eight 4 MB arrays in slots 0-7, SBIA 0 at 2000 0000 - 21FF FFFF,
//  everything else 1F. A memory reference goes to its slot's array at the
//  offset PA<21:0>; with the console's map that is the physical address
//  itself.
//
//  A CPU reference the PAMM gives any code other than an array slot or
//  adapter 0 is aborted: the MBox reports an MBox fatal error (non-existent
//  memory, MSTAT2<03>, the code in MSTAT2<20:16>) and the EBox takes a
//  machine check, for reads and writes alike. A reference SBIA 0 cannot
//  complete ends the same way with a CP I/O buffer error (MSTAT2<02>); read
//  data it marks bad, with the ABus bad data code (MSTAT2<14>). MSTAT2 and
//  MEAR (the physical address) go to the CPU for the machine check frame.
//
//  Every reference carries a byte mask (sel): a write writes only those
//  bytes, a read to an I/O adapter asks for a word or a longword.
//
//  DMA. SBIA 0's receiver sends the MBox the SBI's DMA one longword at a
//  time (dma_*). The PAMM is looked up for it too: a DMA reference whose
//  code is not a memory array is aborted (dma_nxm; the Fault Isolation
//  Manual's M-03, "DMA requests which result in a PAMM code of 1X"). The
//  memory port is shared between the CPU and DMA a reference at a time, the
//  CPU and DMA taking turns when both want it, so that neither waits for
//  more than one of the other's references. DMA goes through the cache
//  like the CPU's references, so the two always see the same memory.
//
//  On the SBI: the DW780 Unibus adapter at TR 3 (vax_uba.v, Unibus 0 at
//  2010 0000, its own interrupts on BR4), its Unibus on the ub_*/dv_*
//  ports (nothing on it in the core yet; the CPU bench puts a test device
//  there);
//  the RH780 Massbus adapter at TR 8 (vax_mba.v, interrupts on BR5) with two
//  RP07 drives, units 0 and 1 (vax_rp07.v), whose disks are the images the
//  HPS serves. Both adapters are SBI masters: the SBI's arbitration gives
//  the lower TR the bus first, so the DW780 goes before the RH780.
//
//  Used by vax_core.v and by the CPU test bench (sim/cpu_tb/tb_cpu.v), so
//  that both see the same machine.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_io #(
	parameter CLK_HZ = 50000000,
	parameter MEMMB  = 32,           // installed memory, megabytes (4 MB arrays)
	parameter TSCALE = 1             // the disks' mechanical times divided by
	                                 // this (simulation)
) (
	input             clk,
	input             rst,           // processor initialization

	// physical bus from the MMU (the MBox's CPU port)
	input             stb,
	input             we,
	input      [31:0] adr,
	input      [31:0] wdat,
	input       [3:0] sel,           // byte mask
	output     [31:0] rdat,
	output            ack,

	// IPR writes (MTPR PAMLOC, PAMACC) and the code at PAMLOC (MFPR PAMACC)
	input             ipr_we,
	input       [6:0] ipr_adr,
	input      [31:0] ipr_dat,
	output reg  [4:0] pamm_rd,

	// memory port: m_adr is the array address, {slot, PA<21:0>}
	output            m_stb,
	output            m_we,
	output     [31:0] m_adr,
	output     [31:0] m_wdat,
	output      [3:0] m_sel,
	input      [31:0] m_rdat,
	input             m_ack,

	// to the CPU
	output            io_err,        // the reference failed: machine check
	output reg [31:0] io_mstat2,     // MBox status 2 of the error
	output reg [31:0] io_mear,       // MBox error address register
	output      [4:0] io_ipl,        // highest adapter interrupt request

	// disk images (hps_io block devices): RP07 units 0 and 1 on the RH780
	output     [31:0] sd_lba0,
	output     [31:0] sd_lba1,
	output      [1:0] sd_rd,
	output      [1:0] sd_wr,
	input       [1:0] sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	input             sd_buff_wr,
	output      [7:0] sd_buff_din0,
	output      [7:0] sd_buff_din1,
	input       [1:0] img_mounted,
	input             img_readonly,
	input      [63:0] img_size,
	output            disk_active,

	// the DW780's Unibus (see vax_uba.v): devices attach here
	output     [17:0] ub_a,
	output      [1:0] ub_c,
	output     [15:0] ub_d,
	output            ub_msyn,
	input             ub_ssyn,
	input      [15:0] ub_rd,
	input             dv_npr,
	output            dv_npg,
	input      [17:0] dv_a,
	input       [1:0] dv_c,
	input      [15:0] dv_d,
	input             dv_msyn,
	output            dv_ssyn,
	output     [15:0] dv_rd,
	input       [3:0] ub_br,
	output      [3:0] ub_bg,
	input             ub_intr,
	input      [15:0] ub_vec,
	output            ub_init
);

	localparam [6:0] IPR_PAMACC = 7'h40, IPR_PAMLOC = 7'h41;

	/* ----------------------------------------------------------- PAMM */
	// the console's map: MEMMB megabytes of 4 MB arrays, then SBIA 0
	function [4:0] pamm_std(input [9:0] mb);
		pamm_std = (mb < MEMMB)          ? {2'b00, mb[4:2]} :
		           (mb[9:5] == 5'b10000) ? 5'h18 : 5'h1F;
	endfunction

	// three copies, written together: one is read for every CPU reference,
	// one for every DMA reference, one at PAMLOC for MFPR PAMACC
	(* ramstyle = "M10K" *) reg [4:0] pamm  [0:1023];
	(* ramstyle = "M10K" *) reg [4:0] pamm2 [0:1023];
	(* ramstyle = "M10K" *) reg [4:0] pamm3 [0:1023];
	integer k;
	initial
		for (k = 0; k < 1024; k = k + 1) begin
			pamm[k]  = (k < MEMMB) ? k / 4 : (k >= 512 && k < 544) ? 5'h18 : 5'h1F;
			pamm2[k] = (k < MEMMB) ? k / 4 : (k >= 512 && k < 544) ? 5'h18 : 5'h1F;
			pamm3[k] = (k < MEMMB) ? k / 4 : (k >= 512 && k < 544) ? 5'h18 : 5'h1F;
		end

	reg   [9:0] pamloc;
	reg  [10:0] walk;               // initialization: rewrite every entry
	wire        walking = ~walk[10];
	reg         pw;
	reg   [9:0] pw_a;
	reg   [4:0] pw_d;

	always @* begin
		pw   = 1'b0;
		pw_a = pamloc;
		pw_d = ipr_dat[4:0];
		if (walking) begin
			pw   = 1'b1;
			pw_a = walk[9:0];
			pw_d = pamm_std(walk[9:0]);
		end else if (ipr_we && ipr_adr == IPR_PAMACC)
			pw = 1'b1;
	end

	// the DMA port (SBIA 0's receiver)
	wire        dma_stb, dma_we;
	wire [31:0] dma_adr, dma_wdat;
	wire  [3:0] dma_sel;

	reg   [4:0] code_q;             // pamm[PA<29:20>], one clock later
	reg   [9:0] mb_q;
	reg         mb_ok;              // not written while it was read
	reg   [4:0] dcode_q;            // the same for the DMA address
	reg   [9:0] dmb_q;
	reg         dmb_ok;
	always @(posedge clk) begin
		if (pw) begin
			pamm[pw_a]  <= pw_d;
			pamm2[pw_a] <= pw_d;
			pamm3[pw_a] <= pw_d;
		end
		code_q  <= pamm[adr[29:20]];
		mb_q    <= adr[29:20];
		mb_ok   <= !(pw && pw_a == adr[29:20]);
		dcode_q <= pamm3[dma_adr[29:20]];
		dmb_q   <= dma_adr[29:20];
		dmb_ok  <= !(pw && pw_a == dma_adr[29:20]);
		pamm_rd <= pamm2[pamloc];
	end

	initial begin
		walk   = 11'h400;
		pamloc = 10'd0;
	end
	always @(posedge clk)
		if (rst) begin
			walk   <= 11'd0;
			pamloc <= 10'd0;
		end else begin
			if (walking)
				walk <= walk + 11'd1;
			if (ipr_we && ipr_adr == IPR_PAMLOC)
				pamloc <= ipr_dat[29:20];
		end

	// the code is known one clock after the address (as the cache's tags)
	wire look   = stb && !walking && mb_ok && (mb_q == adr[29:20]);
	wire is_mem = look && (code_q[4:3] == 2'b00);
	wire is_ioa = look && (code_q == 5'h18);
	wire is_nxm = look && !is_mem && !is_ioa;

	wire dlook  = dma_stb && !walking && dmb_ok && (dmb_q == dma_adr[29:20]);
	wire d_mem  = dlook && (dcode_q[4:3] == 2'b00);
	wire d_nxm  = dlook && !d_mem;

	/* ---------------------------------------------- memory: CPU or DMA */
	// gnt: the memory port is DMA's. It changes hands only between
	// references, and when both want it they take turns.
	reg  gnt;
	initial gnt = 1'b0;
	wire c_stb = gnt ? d_mem : is_mem;
	always @(posedge clk)
		if (rst)
			gnt <= 1'b0;
		else if (!c_stb && !m_ack)
			gnt <= gnt ? (d_mem && !is_mem) : d_mem;

	assign m_stb  = c_stb;
	assign m_we   = gnt ? dma_we : we;
	assign m_adr  = gnt ? (d_mem ? {7'd0, dcode_q[2:0], dma_adr[21:0]} : dma_adr) :
	                      (is_mem ? {7'd0, code_q[2:0], adr[21:0]} : adr);
	assign m_wdat = gnt ? dma_wdat : wdat;
	assign m_sel  = gnt ? dma_sel : sel;

	wire cpu_mack = !gnt && is_mem && m_ack;
	wire dma_mack = gnt && d_mem && m_ack;

	reg  d_nxm_q;
	initial d_nxm_q = 1'b0;
	always @(posedge clk)
		d_nxm_q <= d_nxm && !d_nxm_q;

	/* ------------------------------------------------- SBIA 0 and SBI */
	wire        sb_cmd, sb_ack, sb_err, sb_bad;
	wire  [3:0] sb_fn, sb_msk;
	wire [27:0] sb_adr;
	wire [31:0] sb_wdat, sb_rdat;
	wire        nx_ack, nx_busy, nx_err, nx_rds;
	wire [31:0] nx_rdat;
	wire        dm_done, dm_nr, dm_busy, dm_rds, dm_idle;
	wire [63:0] dm_rdat;
	wire        sb_unjam;
	wire        dm_req;
	wire  [3:0] dm_fn, dm_msk, dm_msk2;
	wire [27:0] dm_adr;
	wire [63:0] dm_wdat;
	wire  [4:0] dm_id;
	wire        mba_req;
	wire  [3:0] uba_req;            // REQ4-REQ7 from the DW780

	vax_sbi #(.CLK_HZ(CLK_HZ), .MEMMB(MEMMB)) sbia0 (
		.clk      (clk),
		.rst      (rst),
		.stb      (is_ioa),
		.we       (we),
		.adr      (adr),
		.wdat     (wdat),
		.sel      (sel),
		.rdat     (sb_rdat),
		.ack      (sb_ack),
		.err      (sb_err),
		.bad      (sb_bad),
		.ipl      (io_ipl),
		.sbi_cmd  (sb_cmd),
		.sbi_fn   (sb_fn),
		.sbi_adr  (sb_adr),
		.sbi_msk  (sb_msk),
		.sbi_wdat (sb_wdat),
		.sbi_unjam(sb_unjam),
		.nx_ack   (nx_ack),
		.nx_busy  (nx_busy),
		.nx_err   (nx_err),
		.nx_rds   (nx_rds),
		.nx_rdat  (nx_rdat),
		.dm_req   (dm_req),
		.dm_fn    (dm_fn),
		.dm_adr   (dm_adr),
		.dm_msk   (dm_msk),
		.dm_msk2  (dm_msk2),
		.dm_wdat  (dm_wdat),
		.dm_id    (dm_id),
		.dm_done  (dm_done),
		.dm_nr    (dm_nr),
		.dm_busy  (dm_busy),
		.dm_rds   (dm_rds),
		.dm_rdat  (dm_rdat),
		.dm_idle  (dm_idle),
		.dma_stb  (dma_stb),
		.dma_we   (dma_we),
		.dma_adr  (dma_adr),
		.dma_wdat (dma_wdat),
		.dma_sel  (dma_sel),
		.dma_rdat (m_rdat),
		.dma_ack  (dma_mack),
		.dma_nxm  (d_nxm_q),
		.req4     ({12'd0, uba_req[0], 3'd0}),
		.req5     ({7'd0, mba_req, 4'd0, uba_req[1], 3'd0}),
		.req6     ({12'd0, uba_req[2], 3'd0}),
		.req7     ({12'd0, uba_req[3], 3'd0})
	);

	/* --------------------------------- SBI arbitration among masters */
	// The masters are the DW780 (TR 3) and the RH780 (TR 8); the lower TR
	// wins. A master keeps the SBI from its request to the receiver's
	// answer (done, no response or busy); a request withdrawn before the
	// receiver took it gives the SBI back at once.
	wire        uba_dm_req, mba_dm_req;
	wire  [3:0] uba_dm_fn, uba_dm_msk, uba_dm_msk2;
	wire  [3:0] mba_dm_fn, mba_dm_msk, mba_dm_msk2;
	wire [27:0] uba_dm_adr, mba_dm_adr;
	wire [63:0] uba_dm_wdat, mba_dm_wdat;
	wire  [4:0] uba_dm_id, mba_dm_id;
	reg   [1:0] dmo;                // 0 none, 1 DW780, 2 RH780
	initial dmo = 2'd0;
	wire        own_req = (dmo == 2'd1) ? uba_dm_req :
	                      (dmo == 2'd2) ? mba_dm_req : 1'b0;
	always @(posedge clk)
		if (rst)
			dmo <= 2'd0;
		else if (dmo == 2'd0)
			dmo <= uba_dm_req ? 2'd1 : mba_dm_req ? 2'd2 : 2'd0;
		else if (dm_done || dm_nr || dm_busy || (!own_req && dm_idle))
			dmo <= 2'd0;

	assign dm_req  = own_req;
	assign dm_fn   = (dmo == 2'd1) ? uba_dm_fn   : mba_dm_fn;
	assign dm_adr  = (dmo == 2'd1) ? uba_dm_adr  : mba_dm_adr;
	assign dm_msk  = (dmo == 2'd1) ? uba_dm_msk  : mba_dm_msk;
	assign dm_msk2 = (dmo == 2'd1) ? uba_dm_msk2 : mba_dm_msk2;
	assign dm_wdat = (dmo == 2'd1) ? uba_dm_wdat : mba_dm_wdat;
	assign dm_id   = (dmo == 2'd1) ? uba_dm_id   : mba_dm_id;

	/* ------------------------------------- TR 3: the DW780 and its Unibus */
	wire        uba_ack, uba_busy, uba_err, uba_rds;
	wire [31:0] uba_rdat;

	vax_uba #(.CLK_HZ(CLK_HZ), .TR(4'd3), .UBN(2'd0), .ILV(2'd0)) uba0 (
		.clk      (clk),
		.rst      (rst),
		.sbi_cmd  (sb_cmd),
		.sbi_fn   (sb_fn),
		.sbi_adr  (sb_adr),
		.sbi_msk  (sb_msk),
		.sbi_wdat (sb_wdat),
		.nx_ack   (uba_ack),
		.nx_busy  (uba_busy),
		.nx_err   (uba_err),
		.nx_rds   (uba_rds),
		.nx_rdat  (uba_rdat),
		.sbi_unjam(sb_unjam),
		.dm_req   (uba_dm_req),
		.dm_fn    (uba_dm_fn),
		.dm_adr   (uba_dm_adr),
		.dm_msk   (uba_dm_msk),
		.dm_msk2  (uba_dm_msk2),
		.dm_wdat  (uba_dm_wdat),
		.dm_id    (uba_dm_id),
		.dm_done  (dm_done && dmo == 2'd1),
		.dm_nr    (dm_nr && dmo == 2'd1),
		.dm_busy  (dm_busy && dmo == 2'd1),
		.dm_rds   (dm_rds),
		.dm_rdat  (dm_rdat),
		.req      (uba_req),
		.ub_a     (ub_a),
		.ub_c     (ub_c),
		.ub_d     (ub_d),
		.ub_msyn  (ub_msyn),
		.ub_ssyn  (ub_ssyn),
		.ub_rd    (ub_rd),
		.dv_npr   (dv_npr),
		.dv_npg   (dv_npg),
		.dv_a     (dv_a),
		.dv_c     (dv_c),
		.dv_d     (dv_d),
		.dv_msyn  (dv_msyn),
		.dv_ssyn  (dv_ssyn),
		.dv_rd    (dv_rd),
		.ub_br    (ub_br),
		.ub_bg    (ub_bg),
		.ub_intr  (ub_intr),
		.ub_vec   (ub_vec),
		.ub_init  (ub_init)
	);

	// TR 8: the RH780 and its Massbus
	wire        mba_ack, mba_busy, mba_err;
	wire [31:0] mba_rdat;
	wire        mb_dem, mb_ctod, mb_init, mb_run, mb_exco, mb_wclk;
	wire  [2:0] mb_ds;
	wire  [4:0] mb_rs;
	wire [15:0] mb_cw, mb_dw;
	wire  [1:0] d_tra, d_attn, d_occ, d_sclk, d_ebl, d_exc, d_act;
	wire [15:0] d_cr0, d_cr1, d_dr0, d_dr1;

	vax_mba #(.CLK_HZ(CLK_HZ), .TR(4'd8)) mba0 (
		.clk      (clk),
		.rst      (rst),
		.sbi_cmd  (sb_cmd),
		.sbi_fn   (sb_fn),
		.sbi_adr  (sb_adr),
		.sbi_msk  (sb_msk),
		.sbi_wdat (sb_wdat),
		.nx_ack   (mba_ack),
		.nx_busy  (mba_busy),
		.nx_err   (mba_err),
		.nx_rdat  (mba_rdat),
		.sbi_unjam(sb_unjam),
		.dm_req   (mba_dm_req),
		.dm_fn    (mba_dm_fn),
		.dm_adr   (mba_dm_adr),
		.dm_msk   (mba_dm_msk),
		.dm_msk2  (mba_dm_msk2),
		.dm_wdat  (mba_dm_wdat),
		.dm_id    (mba_dm_id),
		.dm_done  (dm_done && dmo == 2'd2),
		.dm_nr    (dm_nr && dmo == 2'd2),
		.dm_busy  (dm_busy && dmo == 2'd2),
		.dm_rds   (dm_rds),
		.dm_rdat  (dm_rdat),
		.req      (mba_req),
		.mb_dem   (mb_dem),
		.mb_ctod  (mb_ctod),
		.mb_ds    (mb_ds),
		.mb_rs    (mb_rs),
		.mb_cw    (mb_cw),
		.mb_init  (mb_init),
		.mb_tra   (|d_tra),
		.mb_cr    (d_cr0 | d_cr1),
		.mb_attn  (|d_attn),
		.mb_run   (mb_run),
		.mb_exco  (mb_exco),
		.mb_wclk  (mb_wclk),
		.mb_dw    (mb_dw),
		.mb_occ   (|d_occ),
		.mb_sclk  (|d_sclk),
		.mb_dr    (d_dr0 | d_dr1),
		.mb_ebl   (|d_ebl),
		.mb_exc   (|d_exc)
	);

	// the drives see RUN, WCLK and EXC only while they hold the data bus
	vax_rp07 #(.CLK_HZ(CLK_HZ), .UNIT(3'd0), .SN(16'h1001), .TSCALE(TSCALE)) rp0 (
		.clk          (clk),
		.rst          (rst),
		.mb_dem       (mb_dem),
		.mb_ctod      (mb_ctod),
		.mb_ds        (mb_ds),
		.mb_rs        (mb_rs),
		.mb_cw        (mb_cw),
		.mb_init      (mb_init),
		.mb_tra       (d_tra[0]),
		.mb_cr        (d_cr0),
		.mb_attn      (d_attn[0]),
		.mb_run       (mb_run & d_occ[0]),
		.mb_exci      (mb_exco & d_occ[0]),
		.mb_wclk      (mb_wclk & d_occ[0]),
		.mb_dw        (mb_dw),
		.mb_occ       (d_occ[0]),
		.mb_sclk      (d_sclk[0]),
		.mb_dr        (d_dr0),
		.mb_ebl       (d_ebl[0]),
		.mb_exc       (d_exc[0]),
		.sd_lba       (sd_lba0),
		.sd_rd        (sd_rd[0]),
		.sd_wr        (sd_wr[0]),
		.sd_ack       (sd_ack[0]),
		.sd_buff_addr (sd_buff_addr),
		.sd_buff_dout (sd_buff_dout),
		.sd_buff_wr   (sd_buff_wr),
		.sd_buff_din  (sd_buff_din0),
		.img_mounted  (img_mounted[0]),
		.img_readonly (img_readonly),
		.img_size     (img_size),
		.active       (d_act[0])
	);

	vax_rp07 #(.CLK_HZ(CLK_HZ), .UNIT(3'd1), .SN(16'h1002), .TSCALE(TSCALE)) rp1 (
		.clk          (clk),
		.rst          (rst),
		.mb_dem       (mb_dem),
		.mb_ctod      (mb_ctod),
		.mb_ds        (mb_ds),
		.mb_rs        (mb_rs),
		.mb_cw        (mb_cw),
		.mb_init      (mb_init),
		.mb_tra       (d_tra[1]),
		.mb_cr        (d_cr1),
		.mb_attn      (d_attn[1]),
		.mb_run       (mb_run & d_occ[1]),
		.mb_exci      (mb_exco & d_occ[1]),
		.mb_wclk      (mb_wclk & d_occ[1]),
		.mb_dw        (mb_dw),
		.mb_occ       (d_occ[1]),
		.mb_sclk      (d_sclk[1]),
		.mb_dr        (d_dr1),
		.mb_ebl       (d_ebl[1]),
		.mb_exc       (d_exc[1]),
		.sd_lba       (sd_lba1),
		.sd_rd        (sd_rd[1]),
		.sd_wr        (sd_wr[1]),
		.sd_ack       (sd_ack[1]),
		.sd_buff_addr (sd_buff_addr),
		.sd_buff_dout (sd_buff_dout),
		.sd_buff_wr   (sd_buff_wr),
		.sd_buff_din  (sd_buff_din1),
		.img_mounted  (img_mounted[1]),
		.img_readonly (img_readonly),
		.img_size     (img_size),
		.active       (d_act[1])
	);

	assign disk_active = |d_act;

	assign nx_ack  = uba_ack | mba_ack;
	assign nx_busy = uba_busy | mba_busy;
	assign nx_err  = uba_err | mba_err;
	assign nx_rds  = uba_ack & uba_rds;
	assign nx_rdat = uba_ack ? uba_rdat : mba_rdat;

	/* ---------------------------------------------- non-existent memory */
	reg nxm_q;
	initial nxm_q = 1'b0;
	always @(posedge clk)
		nxm_q <= is_nxm;

	// MSTAT2 <20:16> PAMM code, <14> ABus bad data, <03> non-existent
	// memory, <02> CP I/O buffer error; MEAR the longword's physical address
	always @(posedge clk)
		if (is_nxm && !nxm_q) begin
			io_mstat2 <= {11'd0, code_q, 12'd0, 4'b1000};
			io_mear   <= {2'b00, adr[29:2], 2'b00};
		end else if (sb_err) begin
			io_mstat2 <= {11'd0, 5'h18, 12'd0, 4'b0100};
			io_mear   <= {2'b00, adr[29:2], 2'b00};
		end else if (sb_bad) begin
			io_mstat2 <= {11'd0, 5'h18, 2'b01, 14'd0};
			io_mear   <= {2'b00, adr[29:2], 2'b00};
		end

	assign io_err = (stb & nxm_q & is_nxm) | sb_err | sb_bad;

	assign rdat = (cpu_mack ? m_rdat : 32'd0) | sb_rdat;
	assign ack  = cpu_mack | (sb_ack & ~sb_bad);

endmodule

`default_nettype wire
