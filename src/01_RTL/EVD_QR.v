`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// DSP in VLSI Final Project
// EVD by iterative QR operations, optimized similarity-rotation architecture.
//
// Key architectural difference from the previous qmac3 implementation:
//   A_{k+1} = R Q = Q_k^T A_k Q_k is implemented by CORDIC row rotations
//   followed by the matching CORDIC column rotations. Therefore the explicit
//   3x3 RQ and UQ matrix multipliers are removed.
//
// Each Givens rotation is scheduled with a low-latency row/column scheme:
//   1) ROW: vectoring direction generation and row rotation are evaluated in
//      the same cycle. This removes the separate VECTOR cycle.
//   2) COL: apply the matching column rotation to A.
//
// This reduces one QR iteration from 9 cycles to about 6 cycles. The trade-off
// is a longer ROW-state critical path, so the final AT product should be checked
// by synthesis timing.
//
// One vectoring CORDIC and six rotation CORDIC datapaths are reused across all
// Givens rotations and all QR iterations. This keeps M around O(9*QR_ITERS)
// while avoiding the very large combinational QR/matrix-multiply chain.
//
// Interface follows the project specification.
// Input and output values are signed Q6.14 fixed-point.
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Combinational CORDIC vectoring unit.
// STAGES is fixed by parameter. In the unrolled loop, each shift amount i is a
// compile-time constant, so no dynamic barrel shifter is inferred.
// -----------------------------------------------------------------------------
module cordic_vector_comb #(
    parameter W         = 20,
    parameter FRAC_BITS = 14,
    parameter STAGES    = 10,
    parameter K_INV_Q   = 9949
)(
    input  signed [W-1:0]      x,
    input  signed [W-1:0]      y,
    output reg signed [W-1:0]  xo,
    output reg signed [W-1:0]  yo,
    output reg [STAGES-1:0]    dirs
);
    localparam CACC_W = W + 4;
    localparam MACC_W = 2*W + 4;
    localparam signed [CACC_W-1:0] SAT_MAX_C = {{(CACC_W-W){1'b0}}, 1'b0, {(W-1){1'b1}}};
    localparam signed [CACC_W-1:0] SAT_MIN_C = {{(CACC_W-W){1'b1}}, 1'b1, {(W-1){1'b0}}};
    localparam signed [MACC_W-1:0] SAT_MAX_M = {{(MACC_W-W){1'b0}}, 1'b0, {(W-1){1'b1}}};
    localparam signed [MACC_W-1:0] SAT_MIN_M = {{(MACC_W-W){1'b1}}, 1'b1, {(W-1){1'b0}}};
    localparam signed [W-1:0] K_INV_W = K_INV_Q;

    reg signed [W-1:0] xi;
    reg signed [W-1:0] yi;
    reg signed [CACC_W-1:0] x_ext;
    reg signed [CACC_W-1:0] y_ext;
    reg signed [CACC_W-1:0] x_next;
    reg signed [CACC_W-1:0] y_next;
    integer i;

    function signed [W-1:0] sat_c;
        input signed [CACC_W-1:0] val;
        begin
            if (val > SAT_MAX_C)
                sat_c = {1'b0, {(W-1){1'b1}}};
            else if (val < SAT_MIN_C)
                sat_c = {1'b1, {(W-1){1'b0}}};
            else
                sat_c = val[W-1:0];
        end
    endfunction

    function signed [MACC_W-1:0] round_shift_m;
        input signed [MACC_W-1:0] val;
        input integer sh;
        reg signed [MACC_W-1:0] abs_val;
        begin
            if (sh <= 0) begin
                round_shift_m = val <<< (-sh);
            end else if (val >= 0) begin
                round_shift_m = (val + ({{(MACC_W-1){1'b0}},1'b1} <<< (sh-1))) >>> sh;
            end else begin
                abs_val = -val;
                round_shift_m = -((abs_val + ({{(MACC_W-1){1'b0}},1'b1} <<< (sh-1))) >>> sh);
            end
        end
    endfunction

    function signed [W-1:0] sat_m;
        input signed [MACC_W-1:0] val;
        begin
            if (val > SAT_MAX_M)
                sat_m = {1'b0, {(W-1){1'b1}}};
            else if (val < SAT_MIN_M)
                sat_m = {1'b1, {(W-1){1'b0}}};
            else
                sat_m = val[W-1:0];
        end
    endfunction

    function signed [W-1:0] apply_k_inv;
        input signed [W-1:0] val;
        reg signed [MACC_W-1:0] prod;
        begin
            prod = $signed(val) * $signed(K_INV_W);
            apply_k_inv = sat_m(round_shift_m(prod, FRAC_BITS));
        end
    endfunction

    always @* begin
        xi = x;
        yi = y;
        dirs = {STAGES{1'b0}};

        for (i = 0; i < STAGES; i = i + 1) begin
            x_ext = {{(CACC_W-W){xi[W-1]}}, xi};
            y_ext = {{(CACC_W-W){yi[W-1]}}, yi};
            if ($signed(yi) >= 0) begin
                dirs[i] = 1'b1;
                x_next = x_ext + (y_ext >>> i);
                y_next = y_ext - (x_ext >>> i);
            end else begin
                dirs[i] = 1'b0;
                x_next = x_ext - (y_ext >>> i);
                y_next = y_ext + (x_ext >>> i);
            end
            xi = sat_c(x_next);
            yi = sat_c(y_next);
        end

        xo = apply_k_inv(xi);
        yo = apply_k_inv(yi);
    end
endmodule

// -----------------------------------------------------------------------------
// Combinational CORDIC rotation unit.
// -----------------------------------------------------------------------------
module cordic_rotate_comb #(
    parameter W         = 20,
    parameter FRAC_BITS = 14,
    parameter STAGES    = 10,
    parameter K_INV_Q   = 9949
)(
    input  signed [W-1:0]      x,
    input  signed [W-1:0]      y,
    input  [STAGES-1:0]        dirs,
    output reg signed [W-1:0]  xo,
    output reg signed [W-1:0]  yo
);
    localparam CACC_W = W + 4;
    localparam MACC_W = 2*W + 4;
    localparam signed [CACC_W-1:0] SAT_MAX_C = {{(CACC_W-W){1'b0}}, 1'b0, {(W-1){1'b1}}};
    localparam signed [CACC_W-1:0] SAT_MIN_C = {{(CACC_W-W){1'b1}}, 1'b1, {(W-1){1'b0}}};
    localparam signed [MACC_W-1:0] SAT_MAX_M = {{(MACC_W-W){1'b0}}, 1'b0, {(W-1){1'b1}}};
    localparam signed [MACC_W-1:0] SAT_MIN_M = {{(MACC_W-W){1'b1}}, 1'b1, {(W-1){1'b0}}};
    localparam signed [W-1:0] K_INV_W = K_INV_Q;

    reg signed [W-1:0] xi;
    reg signed [W-1:0] yi;
    reg signed [CACC_W-1:0] x_ext;
    reg signed [CACC_W-1:0] y_ext;
    reg signed [CACC_W-1:0] x_next;
    reg signed [CACC_W-1:0] y_next;
    integer i;

    function signed [W-1:0] sat_c;
        input signed [CACC_W-1:0] val;
        begin
            if (val > SAT_MAX_C)
                sat_c = {1'b0, {(W-1){1'b1}}};
            else if (val < SAT_MIN_C)
                sat_c = {1'b1, {(W-1){1'b0}}};
            else
                sat_c = val[W-1:0];
        end
    endfunction

    function signed [MACC_W-1:0] round_shift_m;
        input signed [MACC_W-1:0] val;
        input integer sh;
        reg signed [MACC_W-1:0] abs_val;
        begin
            if (sh <= 0) begin
                round_shift_m = val <<< (-sh);
            end else if (val >= 0) begin
                round_shift_m = (val + ({{(MACC_W-1){1'b0}},1'b1} <<< (sh-1))) >>> sh;
            end else begin
                abs_val = -val;
                round_shift_m = -((abs_val + ({{(MACC_W-1){1'b0}},1'b1} <<< (sh-1))) >>> sh);
            end
        end
    endfunction

    function signed [W-1:0] sat_m;
        input signed [MACC_W-1:0] val;
        begin
            if (val > SAT_MAX_M)
                sat_m = {1'b0, {(W-1){1'b1}}};
            else if (val < SAT_MIN_M)
                sat_m = {1'b1, {(W-1){1'b0}}};
            else
                sat_m = val[W-1:0];
        end
    endfunction

    function signed [W-1:0] apply_k_inv;
        input signed [W-1:0] val;
        reg signed [MACC_W-1:0] prod;
        begin
            prod = $signed(val) * $signed(K_INV_W);
            apply_k_inv = sat_m(round_shift_m(prod, FRAC_BITS));
        end
    endfunction

    always @* begin
        xi = x;
        yi = y;

        for (i = 0; i < STAGES; i = i + 1) begin
            x_ext = {{(CACC_W-W){xi[W-1]}}, xi};
            y_ext = {{(CACC_W-W){yi[W-1]}}, yi};
            if (dirs[i]) begin
                x_next = x_ext + (y_ext >>> i);
                y_next = y_ext - (x_ext >>> i);
            end else begin
                x_next = x_ext - (y_ext >>> i);
                y_next = y_ext + (x_ext >>> i);
            end
            xi = sat_c(x_next);
            yi = sat_c(y_next);
        end

        xo = apply_k_inv(xi);
        yo = apply_k_inv(yi);
    end
endmodule

module EVD_QR #(
    parameter W           = 20,
    parameter INT_BITS    = 6,
    parameter FRAC_BITS   = 14,
    parameter STAGES      = 10,
    parameter QR_ITERS    = 7,
    parameter WAIT_CYCLES = 0,
    parameter K_INV_Q     = 9949
)(
    input                         clk,
    input                         Reset,
    input                         InValid,
    input signed [W-1:0]          InData1,
    input signed [W-1:0]          InData2,
    input signed [W-1:0]          InData3,
    output reg                    OutValid,
    output signed [W-1:0]         OutData1,
    output signed [W-1:0]         OutData2,
    output signed [W-1:0]         OutData3
);

    // 狀態機定義更新：將 S_ROW 拆分為 S_ROW_A 與 S_ROW_U
    localparam S_IDLE   = 4'd0;
    localparam S_LOAD   = 4'd1;
    localparam S_INIT   = 4'd2;
    localparam S_ROW_A  = 4'd3; // 負責旋轉 A 矩陣並記錄 dirs
    localparam S_ROW_U  = 4'd4; // 負責共用 CORDIC 旋轉 U 矩陣
    localparam S_COL    = 4'd5;
    localparam S_SORT   = 4'd6;
    localparam S_OUTPUT = 4'd7;

    localparam signed [W-1:0] Q_ZERO = {W{1'b0}};
    localparam signed [W-1:0] Q_ONE  = (1 <<< FRAC_BITS);

    reg signed [W-1:0] OutData1_r;
    reg signed [W-1:0] OutData2_r;
    reg signed [W-1:0] OutData3_r;

    assign OutData1 = OutValid ? OutData1_r : Q_ZERO;
    assign OutData2 = OutValid ? OutData2_r : Q_ZERO;
    assign OutData3 = OutValid ? OutData3_r : Q_ZERO;

    reg [3:0] state;
    reg [1:0] load_cnt;
    reg [1:0] givens_sel;   
    reg [3:0] iter_cnt;
    reg [2:0] out_cnt;

    reg [STAGES-1:0] dirs_reg;
    reg [STAGES-1:0] dirs0;
    reg [STAGES-1:0] dirs1;
    reg [STAGES-1:0] dirs2;

    reg signed [W-1:0] A00, A01, A02;
    reg signed [W-1:0] A10, A11, A12;
    reg signed [W-1:0] A20, A21, A22;

    reg signed [W-1:0] U00, U01, U02;
    reg signed [W-1:0] U10, U11, U12;
    reg signed [W-1:0] U20, U21, U22;

    reg signed [W-1:0] E0, E1, E2;
    reg signed [W-1:0] V00, V01, V02;
    reg signed [W-1:0] V10, V11, V12;
    reg signed [W-1:0] V20, V21, V22;

    reg signed [W-1:0] vec_x;
    reg signed [W-1:0] vec_y;
    wire signed [W-1:0] vec_xo;
    wire signed [W-1:0] vec_yo;
    wire [STAGES-1:0] vec_dirs;

    wire [STAGES-1:0] dirs_use;

    // dirs_use 根據狀態決定：S_ROW_A 吃即時的 vec_dirs，S_ROW_U 吃存下來的 dirs_reg
    assign dirs_use = (state == S_COL) ?
                      ((givens_sel == 2'd0) ? dirs0 : ((givens_sel == 2'd1) ? dirs1 : dirs2)) :
                      (state == S_ROW_U) ? dirs_reg : vec_dirs;

    // 刪除原本的 r3, r4, r5，只保留 3 個 Rotation CORDIC
    reg signed [W-1:0] r0x, r0y, r1x, r1y, r2x, r2y;
    wire signed [W-1:0] r0xo, r0yo, r1xo, r1yo, r2xo, r2yo;

    cordic_vector_comb #(.W(W), .FRAC_BITS(FRAC_BITS), .STAGES(STAGES), .K_INV_Q(K_INV_Q)) u_vec (
        .x(vec_x), .y(vec_y), .xo(vec_xo), .yo(vec_yo), .dirs(vec_dirs)
    );

    cordic_rotate_comb #(.W(W), .FRAC_BITS(FRAC_BITS), .STAGES(STAGES), .K_INV_Q(K_INV_Q)) u_rot0 (
        .x(r0x), .y(r0y), .dirs(dirs_use), .xo(r0xo), .yo(r0yo)
    );

    cordic_rotate_comb #(.W(W), .FRAC_BITS(FRAC_BITS), .STAGES(STAGES), .K_INV_Q(K_INV_Q)) u_rot1 (
        .x(r1x), .y(r1y), .dirs(dirs_use), .xo(r1xo), .yo(r1yo)
    );

    cordic_rotate_comb #(.W(W), .FRAC_BITS(FRAC_BITS), .STAGES(STAGES), .K_INV_Q(K_INV_Q)) u_rot2 (
        .x(r2x), .y(r2y), .dirs(dirs_use), .xo(r2xo), .yo(r2yo)
    );

    always @* begin
        case (givens_sel)
            2'd0: begin vec_x = A00; vec_y = A10; end
            2'd1: begin vec_x = A00; vec_y = A20; end
            default: begin vec_x = A11; vec_y = A21; end
        endcase
    end

    // MUX 重新配置：讓 A 矩陣和 U 矩陣共用 r0, r1, r2
    always @* begin
        r0x = Q_ZERO; r0y = Q_ZERO; r1x = Q_ZERO; r1y = Q_ZERO; r2x = Q_ZERO; r2y = Q_ZERO;

        if (state == S_ROW_A) begin
            case (givens_sel)
                2'd0: begin r0x = A00; r0y = A10; r1x = A01; r1y = A11; r2x = A02; r2y = A12; end
                2'd1: begin r0x = A00; r0y = A20; r1x = A01; r1y = A21; r2x = A02; r2y = A22; end
                default: begin r0x = A10; r0y = A20; r1x = A11; r1y = A21; r2x = A12; r2y = A22; end
            endcase
        end else if (state == S_ROW_U) begin
            case (givens_sel)
                2'd0: begin r0x = U00; r0y = U01; r1x = U10; r1y = U11; r2x = U20; r2y = U21; end
                2'd1: begin r0x = U00; r0y = U02; r1x = U10; r1y = U12; r2x = U20; r2y = U22; end
                default: begin r0x = U01; r0y = U02; r1x = U11; r1y = U12; r2x = U21; r2y = U22; end
            endcase
        end else if (state == S_COL) begin
            case (givens_sel)
                2'd0: begin r0x = A00; r0y = A01; r1x = A10; r1y = A11; r2x = A20; r2y = A21; end
                2'd1: begin r0x = A00; r0y = A02; r1x = A10; r1y = A12; r2x = A20; r2y = A22; end
                default: begin r0x = A01; r0y = A02; r1x = A11; r1y = A12; r2x = A21; r2y = A22; end
            endcase
        end
    end

    task automatic sort_eigenpairs;
        reg signed [W-1:0] d0;
        reg signed [W-1:0] d1;
        reg signed [W-1:0] d2;
        reg signed [W-1:0] td;
        integer idx0;
        integer idx1;
        integer idx2;
        integer ti;
        begin
            d0 = A00; idx0 = 0;
            d1 = A11; idx1 = 1;
            d2 = A22; idx2 = 2;
            if ($signed(d0) > $signed(d1)) begin
                td = d0; d0 = d1; d1 = td; ti = idx0; idx0 = idx1; idx1 = ti;
            end
            if ($signed(d1) > $signed(d2)) begin
                td = d1; d1 = d2; d2 = td; ti = idx1; idx1 = idx2; idx2 = ti;
            end
            if ($signed(d0) > $signed(d1)) begin
                td = d0; d0 = d1; d1 = td; ti = idx0; idx0 = idx1; idx1 = ti;
            end

            E0 = d0; E1 = d1; E2 = d2;

            V00 = (idx0 == 0) ? U00 : ((idx0 == 1) ? U01 : U02);
            V10 = (idx0 == 0) ? U10 : ((idx0 == 1) ? U11 : U12);
            V20 = (idx0 == 0) ? U20 : ((idx0 == 1) ? U21 : U22);
            V01 = (idx1 == 0) ? U00 : ((idx1 == 1) ? U01 : U02);
            V11 = (idx1 == 0) ? U10 : ((idx1 == 1) ? U11 : U12);
            V21 = (idx1 == 0) ? U20 : ((idx1 == 1) ? U21 : U22);
            V02 = (idx2 == 0) ? U00 : ((idx2 == 1) ? U01 : U02);
            V12 = (idx2 == 0) ? U10 : ((idx2 == 1) ? U11 : U12);
            V22 = (idx2 == 0) ? U20 : ((idx2 == 1) ? U21 : U22);
        end
    endtask

    always @(posedge clk) begin
        if (Reset) begin
            state      <= S_IDLE;
            load_cnt   <= 2'd0;
            givens_sel <= 2'd0;
            iter_cnt   <= 4'd0;
            out_cnt    <= 3'd0;
            dirs_reg   <= {STAGES{1'b0}};
            dirs0      <= {STAGES{1'b0}};
            dirs1      <= {STAGES{1'b0}};
            dirs2      <= {STAGES{1'b0}};
            OutValid   <= 1'b0;
            OutData1_r <= Q_ZERO;
            OutData2_r <= Q_ZERO;
            OutData3_r <= Q_ZERO;

            A00 <= Q_ZERO; A01 <= Q_ZERO; A02 <= Q_ZERO;
            A10 <= Q_ZERO; A11 <= Q_ZERO; A12 <= Q_ZERO;
            A20 <= Q_ZERO; A21 <= Q_ZERO; A22 <= Q_ZERO;
            
            U00 <= Q_ONE;  U01 <= Q_ZERO; U02 <= Q_ZERO;
            U10 <= Q_ZERO; U11 <= Q_ONE;  U12 <= Q_ZERO;
            U20 <= Q_ZERO; U21 <= Q_ZERO; U22 <= Q_ONE;
        end else begin
            OutValid <= 1'b0;
            case (state)
                S_IDLE: begin
                    load_cnt <= 2'd0;
                    out_cnt  <= 3'd0;
                    OutData1_r <= Q_ZERO;
                    OutData2_r <= Q_ZERO;
                    OutData3_r <= Q_ZERO;
                    if (InValid) begin
                        A00 <= InData1; A01 <= InData2; A02 <= InData3;
                        load_cnt <= 2'd1;
                        state <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    if (InValid) begin
                        if (load_cnt == 2'd1) begin
                            A10 <= InData1; A11 <= InData2; A12 <= InData3;
                            load_cnt <= 2'd2;
                        end else begin
                            A20 <= InData1; A21 <= InData2; A22 <= InData3;
                            state <= S_INIT;
                        end
                    end
                end

                S_INIT: begin
                    U00 <= Q_ONE;  U01 <= Q_ZERO; U02 <= Q_ZERO;
                    U10 <= Q_ZERO; U11 <= Q_ONE;  U12 <= Q_ZERO;
                    U20 <= Q_ZERO; U21 <= Q_ZERO; U22 <= Q_ONE;
                    iter_cnt <= 4'd0;
                    givens_sel <= 2'd0;
                    state <= S_ROW_A; // 直接進入更新 A 的狀態
                end

                S_ROW_A: begin
                    dirs_reg <= vec_dirs;
                    if (givens_sel == 2'd0)      dirs0 <= vec_dirs;
                    else if (givens_sel == 2'd1) dirs1 <= vec_dirs;
                    else                         dirs2 <= vec_dirs;

                    case (givens_sel)
                        2'd0: begin A00 <= r0xo; A10 <= Q_ZERO; A01 <= r1xo; A11 <= r1yo; A02 <= r2xo; A12 <= r2yo; end
                        2'd1: begin A00 <= r0xo; A20 <= Q_ZERO; A01 <= r1xo; A21 <= r1yo; A02 <= r2xo; A22 <= r2yo; end
                        default: begin A10 <= r0xo; A20 <= r0yo; A11 <= r1xo; A21 <= Q_ZERO; A12 <= r2xo; A22 <= r2yo; end
                    endcase
                    state <= S_ROW_U; // 下一個 Cycle 交給 U 矩陣更新
                end

                S_ROW_U: begin
                    case (givens_sel)
                        2'd0: begin U00 <= r0xo; U01 <= r0yo; U10 <= r1xo; U11 <= r1yo; U20 <= r2xo; U21 <= r2yo; end
                        2'd1: begin U00 <= r0xo; U02 <= r0yo; U10 <= r1xo; U12 <= r1yo; U20 <= r2xo; U22 <= r2yo; end
                        default: begin U01 <= r0xo; U02 <= r0yo; U11 <= r1xo; U12 <= r1yo; U21 <= r2xo; U22 <= r2yo; end
                    endcase

                    if (givens_sel == 2'd2) begin
                        givens_sel <= 2'd0;
                        state <= S_COL;
                    end else begin
                        givens_sel <= givens_sel + 2'd1;
                        state <= S_ROW_A; // 回到更新 A 矩陣，做下一個 Row Rotation
                    end
                end

                S_COL: begin
                    case (givens_sel)
                        2'd0: begin A00 <= r0xo; A01 <= r0yo; A10 <= r1xo; A11 <= r1yo; A20 <= r2xo; A21 <= r2yo; end
                        2'd1: begin A00 <= r0xo; A02 <= r0yo; A10 <= r1xo; A12 <= r1yo; A20 <= r2xo; A22 <= r2yo; end
                        default: begin A01 <= r0xo; A02 <= r0yo; A11 <= r1xo; A12 <= r1yo; A21 <= r2xo; A22 <= r2yo; end
                    endcase

                    if (givens_sel == 2'd2) begin
                        if (iter_cnt == QR_ITERS-1) begin
                            state <= S_SORT;
                        end else begin
                            iter_cnt <= iter_cnt + 4'd1;
                            givens_sel <= 2'd0;
                            state <= S_ROW_A; // 完成一個 Iteration，回到 S_ROW_A
                        end
                    end else begin
                        givens_sel <= givens_sel + 2'd1;
                        state <= S_COL;
                    end
                end

                S_SORT: begin
                    sort_eigenpairs;
                    out_cnt <= 3'd0;
                    state <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    OutValid <= 1'b1;
                    case (out_cnt)
                        3'd0: begin OutData1_r <= E0;  OutData2_r <= E1;  OutData3_r <= E2;  end
                        3'd1: begin OutData1_r <= V00; OutData2_r <= V01; OutData3_r <= V02; end
                        3'd2: begin OutData1_r <= V10; OutData2_r <= V11; OutData3_r <= V12; end
                        3'd3: begin OutData1_r <= V20; OutData2_r <= V21; OutData3_r <= V22; end
                        default: begin OutData1_r <= Q_ZERO; OutData2_r <= Q_ZERO; OutData3_r <= Q_ZERO; end
                    endcase

                    if (out_cnt == 3'd3) begin
                        state <= S_IDLE;
                        out_cnt <= 3'd0;
                    end else begin
                        out_cnt <= out_cnt + 3'd1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule