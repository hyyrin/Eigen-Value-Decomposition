# Eigen-Value Decomposition (EVD) by Iterative QR Operation

A VLSI implementation of a **CORDIC-based Givens-rotation iterative QR
algorithm** for eigenvalue decomposition (EVD) of 3×3 symmetric matrices,
including RTL design, logic synthesis (TSMC/ADFP 16nm), and gate-level
simulation verification.

> NTU "Digital Signal Processing in VLSI Design (ICDA 5003)" Final Project — Eigen-value
> Decomposition by Iterative QR Operations.

## Algorithm

Given a symmetric input matrix A (3×3), the design runs a fixed **7-iteration
QR algorithm with no Hessenberg reduction and no shift**:

```
A(0) = A
for i = 0 .. QR_ITERS-1:
    [Q(i), R(i)] = QRD(A(i))          // every Givens rotation is done by CORDIC
    A(i+1)       = R(i) Q(i)
    U(i+1)       = U(i) Q(i)          // eigenvector accumulation
After convergence: diag(A) holds the eigenvalues, and the columns of U are
the corresponding eigenvectors.
```

Every Givens rotation inside the QR decomposition is realized by CORDIC
hardware: **vectoring mode** first derives the rotation direction (angle-free,
no arctan ROM needed), and **rotation mode** then re-applies the same
direction to rotate both A and the accumulated U. Rotations are scheduled in
a two-phase ROW→COL scheme:

1. `S_ROW_A` / `S_ROW_U`: direction generation (vectoring) and the row
   rotation are evaluated in the same cycle.
2. `S_COL`: the matching column rotation is applied to A.

This scheduling shortens each QR iteration from ~9 cycles to ~6 cycles, and
lets one vectoring CORDIC plus several rotation-CORDIC datapaths be reused
across all Givens rotations and all QR iterations, avoiding a large unrolled
combinational matrix-multiply chain.

## Top-Level Module Interface (`EVD_QR`)

File: [`src/01_RTL/EVD_QR.v`](src/01_RTL/EVD_QR.v)

```verilog
module EVD_QR #(
    parameter W           = 20,   // data width (bits)
    parameter INT_BITS    = 6,    // integer bits
    parameter FRAC_BITS   = 14,   // fraction bits (Q6.14)
    parameter STAGES      = 10,   // CORDIC micro-rotation stages
    parameter QR_ITERS    = 7,    // number of QR iterations
    parameter WAIT_CYCLES = 0,
    parameter K_INV_Q     = 9949  // CORDIC gain-correction constant (Q6.14)
)(
    input                  clk,
    input                  Reset,     // active-high
    input                  InValid,
    input  signed [W-1:0]  InData1,
    input  signed [W-1:0]  InData2,
    input  signed [W-1:0]  InData3,
    output reg             OutValid,
    output signed [W-1:0]  OutData1,
    output signed [W-1:0]  OutData2,
    output signed [W-1:0]  OutData3
);
```

- **Data format**: signed 20-bit Q6.14 fixed-point.
- **Input**: `InValid` is asserted for 3 clock cycles; `InData1/2/3` carry one
  row of the input matrix per cycle.
- **Output**: `OutValid` is asserted for 4 clock cycles; the first cycle
  outputs the three eigenvalues, and the next 3 cycles output the three rows
  of the eigenvector matrix, in order.

Everything is described in a single file, `EVD_QR.v`, containing:

| Submodule | Description |
|---|---|
| `cordic_vector_comb` | Combinational CORDIC vectoring unit; unrolls `STAGES` micro-rotation stages and records the per-stage rotation directions (`dirs`) |
| `EVD_QR` (top) | 3×3 matrix register file, rotation scheduling/accumulation logic, eigenvalue sorting, output interface, and control FSM |

Control FSM (8 states):

```
S_IDLE → S_LOAD → S_INIT → (S_ROW_A → S_ROW_U → S_COL) × QR_ITERS → S_SORT → S_OUTPUT → S_IDLE
```

`S_SORT` sorts the eigenvalues (and their corresponding eigenvectors) before
output.

## Repository Structure

```
.
├── report.pdf              # Full technical report
├── spec/                   # Course-provided project specification
├── src/
│   ├── 00_TESTBED/
│   │   ├── tb_EVD_QR.v            # Testbench: reads input matrix, measures M (processing cycles), writes results
│   │   └── matrix8_input_real.txt # Test matrix Matrix(:,:,8)
│   ├── 01_RTL/
│   │   ├── EVD_QR.v               # RTL source (CORDIC + top-level EVD_QR module)
│   │   ├── file.f                 # RTL simulation file list
│   │   └── 01_run                 # Script to run RTL simulation (VCS + Verdi/FSDB)
│   ├── 02_SYN/
│   │   ├── syn.tcl                # Design Compiler synthesis script (target: N16ADFP StdCell)
│   │   ├── syn.sdc                # Timing constraints (clock period passed in from syn.tcl)
│   │   └── 01_syn                 # Script to run logic synthesis
│   ├── 03_GATESIM/
│   │   ├── file.f                 # Gate-level simulation file list (synthesized netlist + StdCell library)
│   │   └── 01_run                 # Script to run gate-level simulation
│   └── Final11Pattern.mat         # MATLAB test matrix dataset
```

## How to Run

Requires an environment with VCS / Verdi / Synopsys Design Compiler licenses
(scripts are commented for the ADFP platform; run `cb` before executing):

```bash
# 1. RTL functional simulation
cd src/01_RTL
./01_run
# Outputs: EVD_QR_rtl.fsdb, hw_output_matrix8_q6_14.txt

# 2. Logic synthesis (TSMC/ADFP 16nm)
cd src/02_SYN
./01_syn
# Outputs: Netlist/EVD_QR_syn.v, Netlist/EVD_QR_syn.sdf, Report/*

# 3. Gate-level simulation (requires step 2 to complete first)
cd src/03_GATESIM
./01_run
# Outputs: EVD_QR_gate.fsdb, hw_output_matrix8_q6_14.txt
```

## Specifications & Verification Results (Matrix(:,:,8), Ts = 1.50 ns)

| Item | Value |
|---|---|
| Matrix size | 3×3 symmetric |
| Data format | Signed 20-bit, Q6.14 (6 integer + 14 fraction bits) |
| CORDIC stages | 10 |
| QR iterations | 7 |
| Synthesis clock period *Ts* | 1.50 ns |
| Processing cycles *M* (post-synthesis) | 72.5 cycles |
| Processing time *M×Ts* | 108.75 ns |
| Post-synthesis cell area | 9715.23 (um², N16ADFP StdCell) |
| Area-Time product (AT) | 1,056,531.36 |
| Accuracy requirement | Eigenvalue / eigenvector RMSE both below 1e-2 (met in both behavioral and post-synthesis simulation) |

See [`report.pdf`](report.pdf) for full derivations, RMSE analysis, timing
diagrams, and waveforms.

## Toolchain

Verilog/SystemVerilog testbench · Synopsys VCS + Verdi (FSDB waveforms) ·
Synopsys Design Compiler (dc_shell) · N16ADFP StdCell library
