import matplotlib.pyplot as plt

threshold = 1e-2

# Data consistent with Requirement 1 tables.
wordlengths = [16, 18, 20, 22]
wl_eig_rmse = [1.461e-1, 7.090e-3, 2.104e-3, 9.309e-4]
wl_vec_rmse = [1.882e-2, 6.598e-3, 6.706e-3, 6.739e-3]

stages = [8, 10, 12, 14]
stage_eig_rmse = [1.468e-2, 5.226e-3, 3.371e-3, 2.104e-3]
stage_vec_rmse = [3.522e-2, 6.610e-3, 6.696e-3, 6.706e-3]

def plot_wordlength():
    plt.figure(figsize=(7.2, 4.8))
    plt.semilogy(wordlengths, wl_eig_rmse, marker="o", linewidth=2,
                 label="Max eigenvalue RMSE")
    plt.semilogy(wordlengths, wl_vec_rmse, marker="s", linewidth=2,
                 label="Max eigenvector RMSE")
    plt.axhline(threshold, linestyle="--", linewidth=1.6,
                label="1e-2 criterion")
    plt.xlabel("CORDIC wordlength (bits)")
    plt.ylabel("RMSE")
    plt.title("Requirement 1: RMSE versus Wordlength")
    plt.xticks(wordlengths)
    plt.grid(True, which="both", linestyle="--", alpha=0.45)
    plt.legend()
    plt.tight_layout()
    plt.savefig("req1_rmse_vs_wordlength_clean.png", dpi=300)
    plt.savefig("req1_rmse_vs_wordlength_clean.pdf")
    plt.show()

def plot_stages():
    plt.figure(figsize=(7.2, 4.8))
    plt.semilogy(stages, stage_eig_rmse, marker="o", linewidth=2,
                 label="Max eigenvalue RMSE")
    plt.semilogy(stages, stage_vec_rmse, marker="s", linewidth=2,
                 label="Max eigenvector RMSE")
    plt.axhline(threshold, linestyle="--", linewidth=1.6,
                label="1e-2 criterion")
    plt.xlabel("Number of CORDIC micro-rotation stages")
    plt.ylabel("RMSE")
    plt.title("Requirement 1: RMSE versus CORDIC Stages")
    plt.xticks(stages)
    plt.grid(True, which="both", linestyle="--", alpha=0.45)
    plt.legend()
    plt.tight_layout()
    plt.savefig("req1_rmse_vs_stage_clean.png", dpi=300)
    plt.savefig("req1_rmse_vs_stage_clean.pdf")
    plt.show()

if __name__ == "__main__":
    plot_wordlength()
    plot_stages()
