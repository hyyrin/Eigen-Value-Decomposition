#!/usr/bin/env python3
"""
Requirement 1:
  Decide wordlength and CORDIC micro-rotation stages.
  Draw RMSE versus wordlength and RMSE versus number of stages.

Usage:
  python req1_sweep_wordlength_stage.py --mat Final11Pattern.mat

Outputs:
  results/req1_wordlength_sweep.csv
  results/req1_stage_sweep.csv
  results/req1_rmse_vs_wordlength.png
  results/req1_rmse_vs_stage.png
  results/selected_config.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

from fixed_cordic_model import FixedConfig, evaluate_patterns, load_matrix_mat


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mat", required=True, help="Path to Final11Pattern.mat")
    parser.add_argument("--outdir", default="results")
    parser.add_argument("--qr-iters", type=int, default=7)
    args = parser.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    Matrix = load_matrix_mat(args.mat)

    # Keep integer bits fixed at 6 because the largest eigenvalue is about 10.6,
    # and signed Q6.(WL-6) covers roughly [-32, 32).
    int_bits = 6

    # Wordlength sweep.
    # Stage is fixed to 14 because the later stage sweep shows it satisfies the criterion.
    stage_for_wl_sweep = 14
    wl_rows = []
    for wl in [16, 18, 20, 22, 24, 26, 28, 30, 32]:
        cfg = FixedConfig(wl=wl, int_bits=int_bits, stages=stage_for_wl_sweep)
        eig_rmse, vec_rmse = evaluate_patterns(Matrix, cfg, qr_iters=args.qr_iters)
        wl_rows.append({
            "wordlength": wl,
            "int_bits": int_bits,
            "frac_bits": cfg.frac_bits,
            "stages": stage_for_wl_sweep,
            "max_eigenvalue_rmse": eig_rmse.max(),
            "max_eigenvector_rmse": vec_rmse.max(),
            "mean_eigenvalue_rmse": eig_rmse.mean(),
            "mean_eigenvector_rmse": vec_rmse.mean(),
            "pass_all_sets": bool((eig_rmse < 1e-2).all() and (vec_rmse < 1e-2).all()),
        })

    df_wl = pd.DataFrame(wl_rows)
    df_wl.to_csv(outdir / "req1_wordlength_sweep.csv", index=False)

    plt.figure()
    plt.plot(df_wl["wordlength"], df_wl["max_eigenvalue_rmse"], marker="o", label="max eigenvalue RMSE")
    plt.plot(df_wl["wordlength"], df_wl["max_eigenvector_rmse"], marker="o", label="max eigenvector RMSE")
    plt.axhline(1e-2, linestyle="--", label="1e-2 criterion")
    plt.yscale("log")
    plt.xlabel("CORDIC wordlength (bits)")
    plt.ylabel("RMSE")
    plt.title("Requirement 1: RMSE versus wordlength")
    plt.grid(True, which="both")
    plt.legend()
    plt.tight_layout()
    plt.savefig(outdir / "req1_rmse_vs_wordlength.png", dpi=200)
    plt.close()

    # Stage sweep.
    # Wordlength is fixed to the selected 20-bit setting.
    selected_wl = 20
    st_rows = []
    for stages in [6, 8, 10, 12, 14, 16, 18, 20, 22, 24]:
        cfg = FixedConfig(wl=selected_wl, int_bits=int_bits, stages=stages)
        eig_rmse, vec_rmse = evaluate_patterns(Matrix, cfg, qr_iters=args.qr_iters)
        st_rows.append({
            "wordlength": selected_wl,
            "int_bits": int_bits,
            "frac_bits": cfg.frac_bits,
            "stages": stages,
            "cordic_gain": cfg.cordic_gain,
            "scaling_factor_K_inv": cfg.cordic_k_inv,
            "scaling_factor_K_inv_q": cfg.cordic_k_inv_q,
            "max_eigenvalue_rmse": eig_rmse.max(),
            "max_eigenvector_rmse": vec_rmse.max(),
            "mean_eigenvalue_rmse": eig_rmse.mean(),
            "mean_eigenvector_rmse": vec_rmse.mean(),
            "pass_all_sets": bool((eig_rmse < 1e-2).all() and (vec_rmse < 1e-2).all()),
        })

    df_st = pd.DataFrame(st_rows)
    df_st.to_csv(outdir / "req1_stage_sweep.csv", index=False)

    plt.figure()
    plt.plot(df_st["stages"], df_st["max_eigenvalue_rmse"], marker="o", label="max eigenvalue RMSE")
    plt.plot(df_st["stages"], df_st["max_eigenvector_rmse"], marker="o", label="max eigenvector RMSE")
    plt.axhline(1e-2, linestyle="--", label="1e-2 criterion")
    plt.yscale("log")
    plt.xlabel("Number of CORDIC micro-rotation stages")
    plt.ylabel("RMSE")
    plt.title("Requirement 1: RMSE versus CORDIC stages")
    plt.grid(True, which="both")
    plt.legend()
    plt.tight_layout()
    plt.savefig(outdir / "req1_rmse_vs_stage.png", dpi=200)
    plt.close()

    selected_cfg = FixedConfig(wl=20, int_bits=6, stages=14)
    summary = {
        "selected_wordlength": selected_cfg.wl,
        "selected_int_bits": selected_cfg.int_bits,
        "selected_frac_bits": selected_cfg.frac_bits,
        "selected_cordic_stages": selected_cfg.stages,
        "selected_qr_iterations": args.qr_iters,
        "cordic_gain_K": selected_cfg.cordic_gain,
        "scaling_factor_K_inv": selected_cfg.cordic_k_inv,
        "scaling_factor_K_inv_q": selected_cfg.cordic_k_inv_q,
        "fixed_point_format": f"Q{selected_cfg.int_bits}.{selected_cfg.frac_bits}",
    }
    with open(outdir / "selected_config.json", "w") as f:
        json.dump(summary, f, indent=2)

    print("=== Requirement 1 sweep finished ===")
    print(df_wl.to_string(index=False))
    print()
    print(df_st.to_string(index=False))
    print()
    print("Selected configuration:")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
