import matplotlib.pyplot as plt

# Requirement 2 result with selected setting:
# Q6.14, 20-bit datapath, 10 CORDIC stages, 7 QR iterations
set_index = list(range(1, 12))

eigenvalue_rmse = [
    5.226e-3, 1.589e-3, 1.599e-3, 2.942e-3, 2.100e-3,
    2.534e-3, 3.892e-3, 3.463e-3, 3.165e-3, 3.226e-3,
    4.296e-3
]

eigenvector_rmse = [
    3.785e-3, 2.071e-3, 4.525e-3, 4.241e-3, 4.478e-3,
    3.823e-3, 3.157e-3, 3.766e-3, 6.610e-3, 5.471e-3,
    4.177e-3
]

threshold = 1e-2

plt.figure(figsize=(8, 5.2))

plt.plot(
    set_index,
    eigenvalue_rmse,
    marker="o",
    linewidth=2,
    label="Eigenvalue RMSE"
)

plt.plot(
    set_index,
    eigenvector_rmse,
    marker="s",
    linewidth=2,
    label="Eigenvector RMSE"
)

plt.axhline(
    threshold,
    linestyle="--",
    linewidth=1.8,
    label="Threshold = 1e-2"
)

plt.xlabel("Set Index", fontsize=12)
plt.ylabel("RMSE", fontsize=12)
plt.title("Eigenvalue and Eigenvector RMSEs versus Test Set Index", fontsize=14)
plt.xticks(set_index)
plt.ylim(0.0, 0.011)
plt.grid(True, linestyle="--", alpha=0.45)
plt.legend(loc="upper right")
plt.tight_layout()

plt.savefig("req2_rmse_vs_set_index.png", dpi=300)
plt.savefig("req2_rmse_vs_set_index.pdf")
plt.show()
