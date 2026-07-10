## Requirement 1 Draft Text

The input matrices are 3x3 real symmetric positive semi-definite matrices. The eigenvalue decomposition was first verified by a floating-point iterative QR model, and then a fixed-point CORDIC bit-true model was constructed. In the bit-true model, QR decomposition is performed by three Givens rotations for each 3x3 matrix. For each Givens rotation, the CORDIC module first operates in vectoring mode to generate the micro-rotation direction bits. The same direction bits are then reused in rotation mode to update the remaining matrix elements and the accumulated eigenvector matrix.

The selected fixed-point format is Q6.14, i.e., the total wordlength is 20 bits, including 6 integer bits and 14 fractional bits. The 6 integer bits are used because the largest eigenvalue among the 11 test patterns is about 10.59, while Q6.14 provides a signed dynamic range of approximately [-32, 32). Therefore, overflow can be avoided while keeping enough fractional precision.

The selected number of CORDIC micro-rotation stages is 14. The CORDIC gain for 14 stages is

```text
K = product_{i=0}^{13} sqrt(1 + 2^{-2i}) = 1.6467602540
```

Therefore, the scaling factor used after the CORDIC operation is

```text
K^{-1} = 0.6072529365
```

In Q6.14 format, this scaling factor is quantized as

```text
round(K^{-1} * 2^14) = 9949
```

To determine the wordlength, the CORDIC stage number was fixed to 14 and the wordlength was swept. The RMSE criterion is satisfied from 20 bits. To determine the number of stages, the wordlength was fixed to 20 bits and the number of CORDIC stages was swept. The RMSE criterion is satisfied from 10 stages, but 14 stages was selected because it gives a smaller eigenvalue RMSE while keeping the hardware complexity moderate.

The final selected configuration is:

```text
wordlength = 20 bits
integer bits = 6 bits
fractional bits = 14 bits
CORDIC stages = 14
QR iterations = 7
```

Under this setting, the maximum eigenvalue RMSE over the 11 sets is about 2.10e-3, and the maximum eigenvector RMSE is about 6.71e-3, both smaller than 1e-2.

## Requirement 2 Draft Text

Using the selected Q6.14 fixed-point CORDIC setting, the bit-true model was applied to all 11 input matrices. For each set, the eigenvalues were sorted before comparison because the ordering of eigenvalues may differ between algorithms. The eigenvectors were reordered according to the sorted eigenvalues and sign-aligned with the reference eigenvectors before computing RMSE, because both v and -v are valid eigenvectors.

The result shows that all 11 sets satisfy the 1e-2 RMSE criterion for both eigenvalues and eigenvectors. Therefore, the selected fixed-point model is used as the reference bit-true model for the following hardware implementation.
