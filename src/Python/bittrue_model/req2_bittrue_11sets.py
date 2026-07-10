#!/usr/bin/env python3
"""
Requirement 2:
  Use the selected setting from Requirement 1 to construct the fixed-point
  CORDIC bit-true model and draw RMSE versus pattern set index.

Usage:
  python req2_bittrue_11sets.py --mat Final11Pattern.mat

Outputs:
  results/req2_rmse_per_set.csv
  results/req2_rmse_vs_set_index.png
  results/matrix8_fixed_output.txt
"""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from fixed_cordic_model import (
    FixedConfig,
    evaluate_patterns,
    iterative_qr_evd_fixed,
    load_matrix_mat,
    rmse,
    sort_and_align,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mat", required=True, help="Path to Final11Pattern.mat")
    parser.add_argument("--outdir", default="results")
    parser.add_argument("--wl", type=int, default=20)
    parser.add_argument("--int-bits", type=int, default=6)
    parser.add_argument("--stages", type=int, default=14)
    parser.add_argument("--qr-iters", type=int, default=7)
    args = parser.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    Matrix = load_matrix_mat(args.mat)
    cfg = FixedConfig(wl=args.wl, int_bits=args.int_bits, stages=args.stages)

    rows = []
    for k in range(Matrix.shape[2]):
        A = Matrix[:, :, k].astype(float)
        ref_vals, ref_vecs = np.linalg.eigh(A)
        vals, vecs, Afinal = iterative_qr_evd_fixed(A, cfg, qr_iters=args.qr_iters)
        vals_sorted, vecs_aligned = sort_and_align(vals, vecs, ref_vals, ref_vecs)
        rows.append({
            "set_index": k + 1,
            "eigenvalue_rmse": rmse(vals_sorted, ref_vals),
            "eigenvector_rmse": rmse(vecs_aligned, ref_vecs),
            "pass_eigenvalue": rmse(vals_sorted, ref_vals) < 1e-2,
            "pass_eigenvector": rmse(vecs_aligned, ref_vecs) < 1e-2,
        })

    df = pd.DataFrame(rows)
    df.to_csv(outdir / "req2_rmse_per_set.csv", index=False)

    plt.figure()
    plt.plot(df["set_index"], df["eigenvalue_rmse"], marker="o", label="eigenvalue RMSE")
    plt.plot(df["set_index"], df["eigenvector_rmse"], marker="o", label="eigenvector RMSE")
    plt.axhline(1e-2, linestyle="--", label="1e-2 criterion")
    plt.yscale("log")
    plt.xlabel("Pattern set index")
    plt.ylabel("RMSE")
    plt.title("Requirement 2: RMSE of selected bit-true model")
    plt.grid(True, which="both")
    plt.legend()
    plt.tight_layout()
    plt.savefig(outdir / "req2_rmse_vs_set_index.png", dpi=200)
    plt.close()

    # Matrix(:,:,8) is the required hardware simulation pattern in the project handout.
    k = 7  # Python index for Matrix(:,:,8)
    A8 = Matrix[:, :, k].astype(float)
    ref_vals, ref_vecs = np.linalg.eigh(A8)
    vals, vecs, Afinal = iterative_qr_evd_fixed(A8, cfg, qr_iters=args.qr_iters)
    vals_sorted, vecs_aligned = sort_and_align(vals, vecs, ref_vals, ref_vecs)

    with open(outdir / "matrix8_fixed_output.txt", "w") as f:
        f.write("Selected fixed-point bit-true model output for Matrix(:,:,8)\n")
        f.write(f"WL={cfg.wl}, INT_BITS={cfg.int_bits}, FRAC_BITS={cfg.frac_bits}, ")
        f.write(f"CORDIC_STAGES={cfg.stages}, QR_ITERS={args.qr_iters}\n\n")
        f.write("Input Matrix(:,:,8):\n")
        f.write(np.array2string(A8, precision=9, suppress_small=False))
        f.write("\n\nReference eigenvalues from numpy.linalg.eigh:\n")
        f.write(np.array2string(ref_vals, precision=12, suppress_small=False))
        f.write("\n\nFixed-point iterative QR eigenvalues, sorted:\n")
        f.write(np.array2string(vals_sorted, precision=12, suppress_small=False))
        f.write("\n\nReference eigenvectors:\n")
        f.write(np.array2string(ref_vecs, precision=12, suppress_small=False))
        f.write("\n\nFixed-point iterative QR eigenvectors, sorted and sign-aligned:\n")
        f.write(np.array2string(vecs_aligned, precision=12, suppress_small=False))
        f.write("\n\nEigenvalue RMSE:\n")
        f.write(str(rmse(vals_sorted, ref_vals)))
        f.write("\nEigenvector RMSE:\n")
        f.write(str(rmse(vecs_aligned, ref_vecs)))
        f.write("\n\nFinal A after QR iterations:\n")
        f.write(np.array2string(Afinal, precision=12, suppress_small=False))
        f.write("\n")

    print("=== Requirement 2 bit-true model finished ===")
    print(df.to_string(index=False))
    print()
    print("Max eigenvalue RMSE :", df["eigenvalue_rmse"].max())
    print("Max eigenvector RMSE:", df["eigenvector_rmse"].max())
    print(f"All pass < 1e-2: {bool((df['eigenvalue_rmse'] < 1e-2).all() and (df['eigenvector_rmse'] < 1e-2).all())}")
    print()
    print(f"Matrix(:,:,8) output written to {outdir / 'matrix8_fixed_output.txt'}")


if __name__ == "__main__":
    main()
