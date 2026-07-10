#!/usr/bin/env python3
"""
Generate Requirement 5 figure:
errors between hardware output and bit-true fixed-point simulation output.

This version keeps zero-error points visible but does not annotate each point with "0".
"""

import argparse
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

FRAC_BITS = 14
SCALE = 1 << FRAC_BITS

LABELS = [
    "lambda1", "lambda2", "lambda3",
    "v00", "v01", "v02",
    "v10", "v11", "v12",
    "v20", "v21", "v22",
]

REQUIRED_KEYS = ["eigenvalues", "vrow0", "vrow1", "vrow2"]

def parse_output(path: Path) -> np.ndarray:
    values = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        key = parts[0]
        if key in REQUIRED_KEYS:
            values[key] = [int(x) for x in parts[1:4]]

    missing = [k for k in REQUIRED_KEYS if k not in values]
    if missing:
        raise ValueError(f"Missing rows in {path}: {missing}")

    flat = values["eigenvalues"] + values["vrow0"] + values["vrow1"] + values["vrow2"]
    return np.array(flat, dtype=np.int64)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hw", type=Path, required=True)
    parser.add_argument("--bittrue", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path("req5_hw_vs_bittrue_error_clean_zero.png"))
    parser.add_argument("--out-pdf", type=Path, default=None)
    args = parser.parse_args()

    hw_q = parse_output(args.hw)
    bit_q = parse_output(args.bittrue)

    diff_q = hw_q - bit_q
    abs_err = np.abs(diff_q) / SCALE
    max_abs_err = np.max(abs_err)
    rmse_err = np.sqrt(np.mean((diff_q / SCALE) ** 2))

    print("=== Requirement 5: hardware vs bit-true fixed-point simulation ===")
    print("Hardware Q values :", hw_q.tolist())
    print("Bit-true Q values :", bit_q.tolist())
    print("Difference Q      :", diff_q.tolist())
    print(f"Max absolute error = {max_abs_err:.6e}")
    print(f"RMSE error         = {rmse_err:.6e}")

    x = np.arange(len(LABELS))

    plt.figure(figsize=(9.2, 4.8))

    if max_abs_err == 0:
        plt.scatter(x, abs_err, s=55, zorder=3, label="Absolute error")
        plt.axhline(0, linewidth=1.4, label="Zero error baseline")
        plt.ylim(-0.10e-6, 0.50e-6)
    else:
        plt.bar(LABELS, abs_err, label="Absolute error")
        plt.ylim(0, max_abs_err * 1.25)

    plt.xticks(x, LABELS, rotation=45, ha="right")
    plt.xlabel("Output component")
    plt.ylabel("Absolute error")
    plt.title("Errors between Hardware Output and Bit-True Fixed-Point Simulation")
    plt.grid(True, axis="y", linestyle="--", alpha=0.45)
    plt.legend(loc="upper right")
    plt.tight_layout()

    plt.savefig(args.out, dpi=300)
    if args.out_pdf is not None:
        plt.savefig(args.out_pdf)
    plt.show()

if __name__ == "__main__":
    main()
