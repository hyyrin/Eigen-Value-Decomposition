#!/usr/bin/env python3
"""Verify eigenvalue/eigenvector RMSE for Matrix(:,:,8) from Vivado output.

Usage:
    python scripts/verify_rmse_matrix8.py hw_output_matrix8_q6_14.txt
"""
import sys
import math
from pathlib import Path
import numpy as np

FRAC_BITS = 14
SCALE = 1 << FRAC_BITS

REF_LAMBDA = np.array([0.000152791938, 1.297172421890, 7.246852714000], dtype=float)
REF_V = np.array([
    [ 0.81704031,  0.56856005, -0.09583639],
    [-0.54359096,  0.81499421,  0.20073193],
    [ 0.19223426, -0.11191029,  0.97494722],
], dtype=float)


def parse_output(path: Path):
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if parts[0] in {"eigenvalues", "vrow0", "vrow1", "vrow2"}:
            values[parts[0]] = [int(x) for x in parts[1:4]]
    required = ["eigenvalues", "vrow0", "vrow1", "vrow2"]
    missing = [k for k in required if k not in values]
    if missing:
        raise ValueError(f"Missing rows in {path}: {missing}")
    lam = np.array(values["eigenvalues"], dtype=float) / SCALE
    V = np.array([values["vrow0"], values["vrow1"], values["vrow2"]], dtype=float) / SCALE
    return lam, V


def align_vector_signs(V_hw: np.ndarray, V_ref: np.ndarray) -> np.ndarray:
    V = V_hw.copy()
    for i in range(3):
        if np.dot(V[:, i], V_ref[:, i]) < 0:
            V[:, i] *= -1.0
    return V


def main():
    if len(sys.argv) >= 2:
        path = Path(sys.argv[1])
    else:
        path = Path("hw_output_matrix8_q6_14.txt")
    if not path.exists():
        raise SystemExit(f"Cannot find output file: {path}")

    lam_hw, V_hw = parse_output(path)
    V_hw_aligned = align_vector_signs(V_hw, REF_V)

    rmse_lam = math.sqrt(np.mean((lam_hw - REF_LAMBDA) ** 2))
    rmse_vec = math.sqrt(np.mean((V_hw_aligned - REF_V) ** 2))

    print("=== Matrix(:,:,8) RMSE verification ===")
    print(f"Output file: {path}")
    print("Hardware eigenvalues:", lam_hw)
    print("Reference eigenvalues:", REF_LAMBDA)
    print("Hardware eigenvectors after sign alignment:")
    print(V_hw_aligned)
    print("Reference eigenvectors:")
    print(REF_V)
    print(f"Eigenvalue RMSE = {rmse_lam:.6e}")
    print(f"Eigenvector RMSE = {rmse_vec:.6e}")
    print("Pass eigenvalue criterion:", rmse_lam < 1e-2)
    print("Pass eigenvector criterion:", rmse_vec < 1e-2)


if __name__ == "__main__":
    main()
