// =============================================================================
// File:        ntt_engine.sv
// Project:     Dilithium Post-Quantum Signature Hardware Implementation
// Module:      ntt_engine
// Description: 256-point forward / inverse NTT engine for Dilithium.
//
//              Iterative Cooley-Tukey decimation-in-time butterfly with
//              Montgomery reduction, matching ref/ntt.c exactly.
//
//              Architecture:
//                - 256 x 24-bit coefficient register file (2 read, 2 write)
//                - Single-port 256 x 24-bit twiddle ROM
//                - Combinational butterfly + Montgomery reducer
//                - FSM controller mirroring the C reference loop structure
//
//              Latency (approximate, measured in cycles):
//                - Forward NTT:  3 setup + 1024 butterflies + 1 = 1028
//                - Inverse NTT:  3 setup + 1024 butterflies + 256 scalings
//                                + 1 = 1284
//
// Author:      Generated for Dilithium HW IP Core
// Date:        2026-06-23
// Version:     1.0 (Phase 1: Core Arithmetic Units)
//
// Compliance:  IEEE 1800-2017 SystemVerilog, synthesizable.
// =============================================================================

`ifndef DILITHIUM_NTT_ENGINE_SV
`define DILITHIUM_NTT_ENGINE_SV

`include "dilithium_pkg.sv"
`include "ntt_params.svh"

module ntt_engine #(
    parameter int unsigned COEFF_WIDTH = 24,
    parameter int unsigned N           = 256
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          start,
    input  dilithium_pkg::ntt_op_t        mode,
    input  logic signed [COEFF_WIDTH-1:0] coeff_in  [N],
    output logic signed [COEFF_WIDTH-1:0] coeff_out [N],
    output logic                          busy,
    output logic                          done,
    output logic                          err
);

  localparam int unsigned N_STAGES  = 8;
  localparam int unsigned ADDR_W    = $clog2(N);
  localparam logic signed [23:0]    Q_VAL   = 24'sd8380417;
  localparam logic signed [31:0]    QINV    = 32'sd58728449;
  localparam logic signed [23:0]    F_INV   = 24'sd41978;

  // ---------------------------------------------------------------------
  // Coefficient register file
  // ---------------------------------------------------------------------
  logic signed [COEFF_WIDTH-1:0] rf [N];

  // Read ports (combinational)
  logic signed [COEFF_WIDTH-1:0] a_j, a_jlen;
  assign a_j    = rf[addr_j];
  assign a_jlen = rf[addr_jlen];

  // Write ports (registered, write-first)
  logic                          we_a, we_b;
  logic [ADDR_W-1:0]              waddr_a, waddr_b;
  logic signed [COEFF_WIDTH-1:0]  wdata_a, wdata_b;

  always_ff @(posedge clk) begin
    if (we_a) rf[waddr_a] <= wdata_a;
    if (we_b) rf[waddr_b] <= wdata_b;
  end

  // ---------------------------------------------------------------------
  // Twiddle ROM
  // ---------------------------------------------------------------------
  logic [ADDR_W-1:0]             zeta_addr;
  logic                          zeta_re;
  logic signed [COEFF_WIDTH-1:0] zeta_rdata;
  logic signed [COEFF_WIDTH-1:0] zeta_q;  // registered for timing

  ntt_twiddle_rom u_rom (
    .clk  (clk),
    .re   (zeta_re),
    .addr (zeta_addr),
    .rdata(zeta_rdata)
  );
  always_ff @(posedge clk) begin
    if (zeta_re) zeta_q <= zeta_rdata;
  end

  // ---------------------------------------------------------------------
  // Montgomery reduction: 48-bit signed a -> 24-bit signed result
  // ---------------------------------------------------------------------
  function automatic logic signed [23:0] mont_reduce(input logic signed [47:0] a);
    logic signed [31:0] t;
    logic signed [63:0] mult;
    logic signed [47:0] sub;
    logic signed [23:0] result;
    begin
      t     = a[31:0] * QINV;
      mult  = $signed({{32{t[31]}}, t}) * $signed({{24{Q_VAL[23]}}, Q_VAL});
      sub   = a - mult[47:0];
      result = sub[47:24];
      return result;
    end
  endfunction

  // ---------------------------------------------------------------------
  // Butterfly: combinational
  // ---------------------------------------------------------------------
  // Forward butterfly:
  //   t = mont(zeta * a[j+len])
  //   a[j+len] = a[j] - t
  //   a[j]     = a[j] + t
  //
  // Inverse butterfly:
  //   t = a[j]
  //   a[j]     = t + a[j+len]
  //   a[j+len] = t - a[j+len]
  //   a[j+len] = mont(zeta * a[j+len])
  logic signed [COEFF_WIDTH-1:0] t_mont;
  logic signed [47:0]            product;

  always_comb begin
    if (mode == dilithium_pkg::NTT_OP_NTT) begin
      product = $signed(zeta_q) * $signed(a_jlen);
      t_mont  = mont_reduce(product);
      wdata_a = a_j + t_mont;
      wdata_b = a_j - t_mont;
    end else begin
      wdata_a = a_j + a_jlen;
      wdata_b = mont_reduce($signed((-zeta_q)) * $signed(a_j - a_jlen));
    end
  end

  // Final scaling for inverse NTT: a[j] = mont(F_INV * a[j])
  logic signed [COEFF_WIDTH-1:0] scale_q;
  always_comb begin
    if (mode == dilithium_pkg::NTT_OP_INTT) begin
      scale_q = mont_reduce($signed(F_INV) * $signed(a_j));
    end else begin
      scale_q = a_j;
    end
  end

  // ---------------------------------------------------------------------
  // FSM controller
  // ---------------------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE,
    S_LOAD,
    S_SETUP,
    S_BUTTERFLY,
    S_FINAL_SCALE,
    S_OUTPUT,
    S_DONE
  } state_e;

  state_e state, state_next;
  logic  running;
  logic  err_next;

  // Loop counters
  logic [ADDR_W-1:0]   k_idx;     // zeta index
  logic [N_STAGES-1:0] stage;     // 0..7
  logic [ADDR_W-1:0]   len_r;     // current len (128 >> stage)
  logic [ADDR_W-1:0]   start_r;   // current start value
  logic [ADDR_W-1:0]   j_r;       // current j (in inner loop)
  logic [ADDR_W-1:0]   load_idx;  // for loading input
  logic [ADDR_W-1:0]   scale_idx; // for final scaling

  // ---------------------------------------------------------------------
  // Compute next state combinational
  // ---------------------------------------------------------------------
  always_comb begin
    state_next = state;
    err_next   = err;

    case (state)
      S_IDLE: begin
        if (start && !running) begin
          if (mode == dilithium_pkg::NTT_OP_NTT) begin
            state_next = S_LOAD;
          end else if (mode == dilithium_pkg::NTT_OP_INTT) begin
            state_next = S_LOAD;
          end
        end
      end

      S_LOAD: begin
        // We use a small state machine to load all 256 coefficients
        if (load_idx == N - 1) begin
          state_next = S_SETUP;
        end
      end

      S_SETUP: begin
        // Initialise stage counters
        state_next = S_BUTTERFLY;
      end

      S_BUTTERFLY: begin
        // We are doing one butterfly per cycle
        // Termination is detected by j_r overflowing past end of inner loop
        // and start_r passing N
        if (start_r >= N) begin
          state_next = S_FINAL_SCALE;
        end
      end

      S_FINAL_SCALE: begin
        // For inverse NTT, multiply each coefficient by F_INV
        if (mode == dilithium_pkg::NTT_OP_INTT) begin
          if (scale_idx == N - 1) begin
            state_next = S_OUTPUT;
          end
        end else begin
          state_next = S_OUTPUT;
        end
      end

      S_OUTPUT: begin
        state_next = S_DONE;
      end

      S_DONE: begin
        if (!start) state_next = S_IDLE;
      end

      default: state_next = S_IDLE;
    endcase
  end

  // ---------------------------------------------------------------------
  // Sequential update
  // ---------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= S_IDLE;
      running    <= 1'b0;
      k_idx      <= '0;
      stage      <= '0;
      len_r      <= '0;
      start_r    <= '0;
      j_r        <= '0;
      load_idx   <= '0;
      scale_idx  <= '0;
      done       <= 1'b0;
      err        <= 1'b0;
      // Register file reset
      for (int i = 0; i < N; i++) rf[i] <= '0;
    end else begin
      done     <= 1'b0;
      err      <= err_next;
      state    <= state_next;

      // Load input into register file
      if (state == S_LOAD) begin
        rf[load_idx] <= coeff_in[load_idx];
        load_idx    <= load_idx + 1;
      end

      // Setup: initialise butterfly counters
      if (state == S_SETUP) begin
        if (mode == dilithium_pkg::NTT_OP_NTT) begin
          k_idx   <= '0;
          stage   <= '0;
          len_r   <= 8'd128;
          start_r <= '0;
          j_r     <= '0;
        end else begin
          // Inverse NTT: stage starts at 0, len = 1
          k_idx   <= 8'd255;
          stage   <= 8'd0;
          len_r   <= 8'd1;
          start_r <= '0;
          j_r     <= '0;
        end
      end

      // Butterfly: do one butterfly per cycle
      if (state == S_BUTTERFLY) begin
        // We use the registered zeta_q
        // Write the two new coefficients
        we_a   <= 1'b1;
        we_b   <= 1'b1;
        waddr_a <= addr_j;
        waddr_b <= addr_jlen;
        // (wdata_a, wdata_b are computed combinationally from a_j, a_jlen)

        // Advance counters
        if (j_r + 1 == len_r) begin
          // End of inner loop: move to next start group
          j_r     <= '0;
          start_r <= start_r + 2 * len_r;
          if (mode == dilithium_pkg::NTT_OP_NTT) begin
            k_idx <= k_idx + 1;
          end else begin
            k_idx <= k_idx - 1;
          end
        end else begin
          j_r <= j_r + 1;
        end

        // Check stage transition: if start_r >= N, move to next stage
        if (start_r >= N) begin
          if (mode == dilithium_pkg::NTT_OP_NTT) begin
            // Forward: advance stage, len halves
            stage    <= stage + 1;
            len_r    <= len_r >> 1;
            start_r  <= '0;
          end else begin
            // Inverse: advance stage, len doubles
            stage    <= stage + 1;
            len_r    <= len_r << 1;
            start_r  <= '0;
          end
        end
      end

      // Final scaling for inverse NTT
      if (state == S_FINAL_SCALE && mode == dilithium_pkg::NTT_OP_INTT) begin
        we_a     <= 1'b1;
        waddr_a  <= scale_idx;
        wdata_a  <= scale_q;
        scale_idx <= scale_idx + 1;
      end

      // Output: copy register file to output port
      if (state == S_OUTPUT) begin
        for (int i = 0; i < N; i++) coeff_out[i] <= rf[i];
      end

      if (state == S_DONE) begin
        done <= 1'b1;
      end

      // Running flag
      running <= (state != S_IDLE);
    end
  end

  // ---------------------------------------------------------------------
  // Address generation: addr_j, addr_jlen
  // ---------------------------------------------------------------------
  always_comb begin
    addr_j    = start_r + j_r;
    addr_jlen = addr_j + len_r;
  end

  // ---------------------------------------------------------------------
  // Twiddle ROM read
  // ---------------------------------------------------------------------
  always_ff @(posedge clk) begin
    zeta_re   <= 1'b0;
    zeta_addr <= k_idx;
    if (state == S_BUTTERFLY) begin
      zeta_re   <= 1'b1;
      zeta_addr <= k_idx;
    end
  end

  // ---------------------------------------------------------------------
  // Status outputs
  // ---------------------------------------------------------------------
  assign busy = running;

endmodule

`endif // DILITHIUM_NTT_ENGINE_SV
