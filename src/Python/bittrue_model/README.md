# DSP in VLSI Final Project - Step 2 Software Model

This folder completes the software-side parts for Requirement 1 and Requirement 2.

## Files

- `fixed_cordic_model.py`  
  Fixed-point CORDIC bit-true model for 3x3 iterative QR EVD.

- `req1_sweep_wordlength_stage.py`  
  Requirement 1 sweep:
  - RMSE versus CORDIC wordlength
  - RMSE versus number of CORDIC micro-rotation stages
  - selected fixed-point setting

- `req2_bittrue_11sets.py`  
  Requirement 2:
  - eigenvalue/eigenvector RMSE versus set index 1~11
  - fixed-point output for `Matrix(:,:,8)`

## How to run

Put `Final11Pattern.mat` in the same folder, then run:

```bash
python req1_sweep_wordlength_stage.py --mat Final11Pattern.mat
python req2_bittrue_11sets.py --mat Final11Pattern.mat
```

The result figures and CSV files will be generated in `results/`.

## Selected configuration

The selected setting is:

```text
Fixed-point format : Q6.14
Wordlength         : 20 bits
Integer bits       : 6 bits
Fractional bits    : 14 bits
CORDIC stages      : 14
QR iterations      : 7
CORDIC K           : 1.6467602540312928
CORDIC K_inv       : 0.6072529365170103
K_inv quantized    : 9949
```

The selected setting passes the `1e-2` RMSE criterion for all 11 patterns in the current bit-true model.

## Notes for comparison

Eigenvalues are sorted before computing RMSE. Eigenvectors are also reordered according to the sorted eigenvalues and sign-aligned with the reference eigenvectors, because both `v` and `-v` are valid eigenvectors.
