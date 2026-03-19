#!/usr/bin/env python3
"""Generate plots for library search space reduction analysis.

Usage:
    python generate_plots.py <library.parquet> <report.parquet>

Data source (ttht-biognosys tuned library, 6 LFQB runs):
    kraken:/srv/data1/karlssoc/projects/tt/lfqb_v2/results/2.2_tune_ttht-biognosys/tuned_library/lfqb_tuned_ttht-biognosys_tuned.predicted.parquet
    kraken:/srv/data1/karlssoc/projects/tt/lfqb_v2/results/2.2_tune_ttht-biognosys/quant/tuned/ttht-biognosys/report.parquet

Dependencies:
    pip install duckdb matplotlib seaborn numpy pandas pyarrow
"""

import sys
from pathlib import Path

import duckdb
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
import seaborn as sns
from matplotlib.patches import Rectangle

# --- Argument parsing ---
if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <library.parquet> <report.parquet>")
    sys.exit(1)

LIB = sys.argv[1]
REPORT = sys.argv[2]

for p in (LIB, REPORT):
    if not Path(p).exists():
        print(f"ERROR: File not found: {p}")
        sys.exit(1)

OUT_DIR = Path(__file__).parent / 'figures'
OUT_DIR.mkdir(exist_ok=True)

# --- Setup ---
sns.set_theme(style='whitegrid', font_scale=1.1)
con = duckdb.connect()

C_LIB = '#4C72B0'
C_ID = '#DD8452'
C_HIT = '#55A868'

# ============================================================
# FIGURE 1: Charge Distribution — Library vs Identified
# ============================================================
print("Figure 1: Charge distribution...")

df_charge = con.execute(f"""
WITH lib AS (
    SELECT DISTINCT "Precursor.Id", "Precursor.Charge"
    FROM read_parquet('{LIB}') WHERE "Decoy" = 0
),
report AS (
    SELECT DISTINCT "Precursor.Id", "Precursor.Charge"
    FROM read_parquet('{REPORT}') WHERE "Decoy" = 0
)
SELECT
    l."Precursor.Charge" as charge,
    COUNT(DISTINCT l."Precursor.Id") as lib_count,
    COUNT(DISTINCT r."Precursor.Id") as id_count,
    ROUND(100.0 * COUNT(DISTINCT r."Precursor.Id") / NULLIF(COUNT(DISTINCT l."Precursor.Id"), 0), 2) as hit_rate
FROM lib l LEFT JOIN report r ON l."Precursor.Id" = r."Precursor.Id"
GROUP BY l."Precursor.Charge"
ORDER BY l."Precursor.Charge"
""").fetchdf()

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

x = np.arange(len(df_charge))
w = 0.35
ax1.bar(x - w/2, df_charge['lib_count'] / 1e6, w, label='Library', color=C_LIB, alpha=0.85)
ax1.bar(x + w/2, df_charge['id_count'] / 1e3, w, label='Identified (×1000)', color=C_ID, alpha=0.85)
ax1.set_xticks(x)
ax1.set_xticklabels([f'+{c}' for c in df_charge['charge']])
ax1.set_xlabel('Precursor Charge')
ax1.set_ylabel('Count (millions / thousands)')
ax1.set_title('Library vs Identified Precursors')
ax1.legend()

for i, row in df_charge.iterrows():
    lib_pct = 100 * row['lib_count'] / df_charge['lib_count'].sum()
    id_pct = 100 * row['id_count'] / df_charge['id_count'].sum()
    ax1.text(i - w/2, row['lib_count']/1e6 + 0.02, f'{lib_pct:.0f}%', ha='center', va='bottom', fontsize=9, color=C_LIB)
    ax1.text(i + w/2, row['id_count']/1e3 + 0.02, f'{id_pct:.0f}%', ha='center', va='bottom', fontsize=9, color=C_ID)

ax2.bar(x, df_charge['hit_rate'], color=[C_HIT if c in [2,3] else '#999999' for c in df_charge['charge']], alpha=0.85)
ax2.set_xticks(x)
ax2.set_xticklabels([f'+{c}' for c in df_charge['charge']])
ax2.set_xlabel('Precursor Charge')
ax2.set_ylabel('Hit Rate (%)')
ax2.set_title('Identification Hit Rate by Charge')
for i, row in df_charge.iterrows():
    ax2.text(i, row['hit_rate'] + 0.1, f"{row['hit_rate']:.1f}%", ha='center', va='bottom', fontsize=10)

fig.suptitle('Charge State Analysis', fontsize=14, fontweight='bold', y=1.02)
fig.tight_layout()
fig.savefig(OUT_DIR / 'fig1_charge_distribution.png', dpi=150, bbox_inches='tight')
plt.close()

# ============================================================
# FIGURE 2: 2D Heatmap — Hit Rate by Length Group × RT Bin
# ============================================================
print("Figure 2: Hit rate heatmap...")

df_heatmap = con.execute(f"""
WITH lib AS (
    SELECT DISTINCT "Precursor.Id", LENGTH("Stripped.Sequence") as pep_len, "RT" as lib_rt
    FROM read_parquet('{LIB}')
    WHERE "Decoy" = 0 AND "Precursor.Charge" BETWEEN 2 AND 3
),
report AS (
    SELECT DISTINCT "Precursor.Id"
    FROM read_parquet('{REPORT}') WHERE "Decoy" = 0
)
SELECT
    CASE
        WHEN pep_len BETWEEN 7 AND 10 THEN '07-10'
        WHEN pep_len BETWEEN 11 AND 15 THEN '11-15'
        WHEN pep_len BETWEEN 16 AND 20 THEN '16-20'
        WHEN pep_len BETWEEN 21 AND 25 THEN '21-25'
        WHEN pep_len BETWEEN 26 AND 30 THEN '26-30'
    END as len_group,
    CASE
        WHEN lib_rt < -30 THEN '<-30'
        WHEN lib_rt BETWEEN -30 AND 0 THEN '-30..0'
        WHEN lib_rt BETWEEN 0 AND 30 THEN '0..30'
        WHEN lib_rt BETWEEN 30 AND 60 THEN '30..60'
        WHEN lib_rt BETWEEN 60 AND 90 THEN '60..90'
        WHEN lib_rt BETWEEN 90 AND 112 THEN '90..112'
        WHEN lib_rt > 112 THEN '>112'
    END as rt_group,
    COUNT(DISTINCT l."Precursor.Id") as lib_entries,
    COUNT(DISTINCT r."Precursor.Id") as id_entries,
    ROUND(100.0 * COUNT(DISTINCT r."Precursor.Id") / NULLIF(COUNT(DISTINCT l."Precursor.Id"), 0), 2) as hit_rate
FROM lib l LEFT JOIN report r ON l."Precursor.Id" = r."Precursor.Id"
WHERE len_group IS NOT NULL AND lib_rt BETWEEN -60 AND 175
GROUP BY len_group, rt_group
ORDER BY len_group, rt_group
""").fetchdf()

len_order = ['07-10', '11-15', '16-20', '21-25', '26-30']
rt_order = ['<-30', '-30..0', '0..30', '30..60', '60..90', '90..112', '>112']

pivot_hit = df_heatmap.pivot(index='len_group', columns='rt_group', values='hit_rate')
pivot_hit = pivot_hit.reindex(index=len_order, columns=rt_order)

pivot_lib = df_heatmap.pivot(index='len_group', columns='rt_group', values='lib_entries')
pivot_lib = pivot_lib.reindex(index=len_order, columns=rt_order)

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 5))

sns.heatmap(pivot_hit, annot=True, fmt='.1f', cmap='YlOrRd', ax=ax1,
            cbar_kws={'label': 'Hit Rate (%)'}, linewidths=0.5)
ax1.set_xlabel('Library Predicted RT')
ax1.set_ylabel('Peptide Length')
ax1.set_title('Identification Hit Rate (%) — Charge 2-3')

rect = Rectangle((1, 0), 5, 4, linewidth=2.5, edgecolor='blue', facecolor='none', linestyle='--')
ax1.add_patch(rect)
ax1.text(3.5, -0.3, 'Global filter zone', ha='center', color='blue', fontsize=9, fontweight='bold')

sns.heatmap(pivot_lib / 1e3, annot=True, fmt='.0f', cmap='Blues', ax=ax2,
            cbar_kws={'label': 'Library Entries (×1000)'}, linewidths=0.5)
ax2.set_xlabel('Library Predicted RT')
ax2.set_ylabel('Peptide Length')
ax2.set_title('Library Size (×1000) — Charge 2-3')

fig.suptitle('Search Space Heatmap: Peptide Length × Predicted RT', fontsize=14, fontweight='bold', y=1.02)
fig.tight_layout()
fig.savefig(OUT_DIR / 'fig2_heatmap_length_rt.png', dpi=150, bbox_inches='tight')
plt.close()

# ============================================================
# FIGURE 3: Diagonal Band — Per-RT m/z and Length Windows
# ============================================================
print("Figure 3: Diagonal band...")

df_band = con.execute(f"""
WITH lib AS (
    SELECT DISTINCT "Precursor.Id", LENGTH("Stripped.Sequence") as pep_len,
           "Precursor.Mz", "RT" as lib_rt
    FROM read_parquet('{LIB}')
    WHERE "Decoy" = 0 AND "Precursor.Charge" BETWEEN 2 AND 3
),
report_ids AS (
    SELECT DISTINCT r."Precursor.Id", l.lib_rt, l.pep_len, l."Precursor.Mz"
    FROM read_parquet('{REPORT}') r
    JOIN lib l ON r."Precursor.Id" = l."Precursor.Id"
    WHERE r."Decoy" = 0
)
SELECT
    FLOOR(lib_rt / 20) * 20 as rt_start,
    COUNT(*) as n_ids,
    PERCENTILE_CONT(0.025) WITHIN GROUP (ORDER BY "Precursor.Mz") as mz_lo,
    PERCENTILE_CONT(0.975) WITHIN GROUP (ORDER BY "Precursor.Mz") as mz_hi,
    PERCENTILE_CONT(0.025) WITHIN GROUP (ORDER BY pep_len) as len_lo,
    PERCENTILE_CONT(0.975) WITHIN GROUP (ORDER BY pep_len) as len_hi,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY "Precursor.Mz") as mz_med,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY pep_len) as len_med
FROM report_ids
WHERE lib_rt BETWEEN -40 AND 140
GROUP BY FLOOR(lib_rt / 20)
HAVING COUNT(*) > 50
ORDER BY FLOOR(lib_rt / 20)
""").fetchdf()

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

rt_centers = df_band['rt_start'] + 10
ax1.fill_between(rt_centers, df_band['mz_lo'], df_band['mz_hi'], alpha=0.3, color=C_ID, label='p2.5–p97.5 of IDs')
ax1.plot(rt_centers, df_band['mz_med'], 'o-', color=C_ID, linewidth=2, label='Median')
ax1.axhline(380, color='gray', linestyle='--', alpha=0.5)
ax1.axhline(1150, color='gray', linestyle='--', alpha=0.5)
ax1.text(120, 395, 'Global min m/z = 380', fontsize=8, color='gray')
ax1.text(120, 1135, 'Global max m/z = 1150', fontsize=8, color='gray', va='top')
ax1.set_xlabel('Library Predicted RT')
ax1.set_ylabel('Precursor m/z')
ax1.set_title('m/z Window per RT Slice')
ax1.legend(loc='upper left')
ax1.set_xlim(-50, 150)

ax2.fill_between(rt_centers, df_band['len_lo'], df_band['len_hi'], alpha=0.3, color=C_HIT, label='p2.5–p97.5 of IDs')
ax2.plot(rt_centers, df_band['len_med'], 'o-', color=C_HIT, linewidth=2, label='Median')
ax2.axhline(7, color='gray', linestyle='--', alpha=0.5)
ax2.axhline(25, color='gray', linestyle='--', alpha=0.5)
ax2.text(120, 7.5, 'Global min len = 7', fontsize=8, color='gray')
ax2.text(120, 24.5, 'Global max len = 25', fontsize=8, color='gray', va='top')
ax2.set_xlabel('Library Predicted RT')
ax2.set_ylabel('Peptide Length')
ax2.set_title('Length Window per RT Slice')
ax2.legend(loc='upper left')
ax2.set_xlim(-50, 150)

fig.suptitle('The Diagonal Band: RT-Dependent Search Space', fontsize=14, fontweight='bold', y=1.02)
fig.tight_layout()
fig.savefig(OUT_DIR / 'fig3_diagonal_band.png', dpi=150, bbox_inches='tight')
plt.close()

# ============================================================
# FIGURE 4: Waterfall — Incremental Filter Reduction
# ============================================================
print("Figure 4: Waterfall chart...")

labels = ['Full\nlibrary', '+ Charge\n2-3', '+ Length\n7-25', '+ m/z\n380-1150', '+ RT\n-40..120', 'Final']
lib_sizes = [3776186, 2387561, 2270201, 2033741, 1842123, 1842123]
pgs_lost = [0, 8, 14, 15, 17, 17]

fig, ax1 = plt.subplots(figsize=(10, 6))

colors = [C_LIB] + ['#E8A87C'] * 4 + [C_HIT]
bars = ax1.bar(range(len(labels)), [s/1e6 for s in lib_sizes], color=colors, alpha=0.85, edgecolor='white', linewidth=1.5)

for i in range(1, len(labels)-1):
    reduction = lib_sizes[i-1] - lib_sizes[i]
    pct = 100 * reduction / 3776186
    ax1.annotate(f'−{reduction/1e3:.0f}K\n({pct:.1f}%)',
                xy=(i, lib_sizes[i]/1e6),
                xytext=(i, (lib_sizes[i-1]+lib_sizes[i])/2/1e6),
                ha='center', fontsize=9, color='#8B0000',
                arrowprops=dict(arrowstyle='->', color='#8B0000', lw=1.2))

for i, (s, pg) in enumerate(zip(lib_sizes, pgs_lost)):
    ax1.text(i, s/1e6 + 0.05, f'{s/1e6:.2f}M', ha='center', va='bottom', fontsize=10, fontweight='bold')

ax2 = ax1.twinx()
ax2.plot(range(len(labels)), pgs_lost, 's-', color='red', markersize=8, linewidth=2, label='PGs lost')
ax2.set_ylabel('Protein Groups Lost', color='red')
ax2.tick_params(axis='y', labelcolor='red')
ax2.set_ylim(-2, 50)
ax2.legend(loc='upper right')

ax1.set_xticks(range(len(labels)))
ax1.set_xticklabels(labels)
ax1.set_ylabel('Library Precursors (millions)')
ax1.set_title('Incremental Library Reduction — 51% Reduction, 17 PGs Lost (0.17%)', fontsize=13, fontweight='bold')

fig.tight_layout()
fig.savefig(OUT_DIR / 'fig4_waterfall.png', dpi=150, bbox_inches='tight')
plt.close()

# ============================================================
# FIGURE 5: Hit Rate by RT Slice
# ============================================================
print("Figure 5: Hit rate by RT slice...")

df_rt = con.execute(f"""
WITH lib AS (
    SELECT DISTINCT "Precursor.Id", "RT" as lib_rt
    FROM read_parquet('{LIB}')
    WHERE "Decoy" = 0 AND "Precursor.Charge" BETWEEN 2 AND 3
    AND LENGTH("Stripped.Sequence") BETWEEN 7 AND 25
    AND "Precursor.Mz" BETWEEN 380 AND 1150
),
report AS (
    SELECT DISTINCT "Precursor.Id"
    FROM read_parquet('{REPORT}') WHERE "Decoy" = 0
)
SELECT
    FLOOR(l.lib_rt / 10) * 10 + 5 as rt_center,
    COUNT(DISTINCT l."Precursor.Id") as lib_entries,
    COUNT(DISTINCT r."Precursor.Id") as ids,
    ROUND(100.0 * COUNT(DISTINCT r."Precursor.Id") / COUNT(DISTINCT l."Precursor.Id"), 2) as hit_rate
FROM lib l LEFT JOIN report r ON l."Precursor.Id" = r."Precursor.Id"
WHERE l.lib_rt BETWEEN -50 AND 150
GROUP BY FLOOR(l.lib_rt / 10)
ORDER BY FLOOR(l.lib_rt / 10)
""").fetchdf()

fig, ax1 = plt.subplots(figsize=(12, 5))

ax1.bar(df_rt['rt_center'], df_rt['lib_entries'] / 1e3, width=9, alpha=0.4, color=C_LIB, label='Library (×1000)')
ax2 = ax1.twinx()
ax2.plot(df_rt['rt_center'], df_rt['hit_rate'], 'o-', color=C_HIT, linewidth=2.5, markersize=5, label='Hit Rate (%)')
ax2.fill_between(df_rt['rt_center'], df_rt['hit_rate'], alpha=0.15, color=C_HIT)

for rt_bound, label in [(-40, 'RT min = -40'), (120, 'RT max = 120')]:
    ax1.axvline(rt_bound, color='red', linestyle='--', linewidth=1.5, alpha=0.7)
    ax1.text(rt_bound + 2, ax1.get_ylim()[1] * 0.95, label, fontsize=9, color='red', va='top')

ax1.set_xlabel('Library Predicted RT')
ax1.set_ylabel('Library Entries (×1000)', color=C_LIB)
ax2.set_ylabel('Hit Rate (%)', color=C_HIT)
ax1.set_title('Library Size and Hit Rate by RT Slice — Charge 2-3, Len 7-25, m/z 380-1150', fontsize=12, fontweight='bold')

lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc='upper left')

fig.tight_layout()
fig.savefig(OUT_DIR / 'fig5_rt_hitrate.png', dpi=150, bbox_inches='tight')
plt.close()

# ============================================================
# FIGURE 6: 1-Peptide Protein Vulnerability
# ============================================================
print("Figure 6: 1-peptide protein vulnerability...")

df_vuln = con.execute(f"""
WITH pg_peptides AS (
    SELECT "Protein.Group",
        COUNT(DISTINCT "Stripped.Sequence") as n_peptides
    FROM read_parquet('{REPORT}')
    WHERE "Decoy" = 0 AND "PG.Q.Value" <= 0.01
    GROUP BY "Protein.Group"
),
lib_peptides AS (
    SELECT "Protein.Group",
        COUNT(DISTINCT "Stripped.Sequence") as n_lib_peptides
    FROM read_parquet('{LIB}') WHERE "Decoy" = 0
    GROUP BY "Protein.Group"
)
SELECT pg.n_peptides as id_peptides, lp.n_lib_peptides as lib_peptides
FROM pg_peptides pg
JOIN lib_peptides lp ON pg."Protein.Group" = lp."Protein.Group"
""").fetchdf()

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))

bins = [0.5, 1.5, 2.5, 3.5, 5.5, 10.5, 20.5, 50.5, 100.5]
labels_hist = ['1', '2', '3', '4-5', '6-10', '11-20', '21-50', '50+']
counts, _ = np.histogram(df_vuln['id_peptides'], bins=bins)
ax1.bar(range(len(counts)), counts, color=[
    '#D32F2F' if i == 0 else '#FF8A65' if i <= 1 else C_LIB for i in range(len(counts))
], alpha=0.85, edgecolor='white')
ax1.set_xticks(range(len(counts)))
ax1.set_xticklabels(labels_hist)
ax1.set_xlabel('Identified Peptides per Protein Group')
ax1.set_ylabel('Number of Protein Groups')
ax1.set_title('Peptide Coverage Distribution')
for i, c in enumerate(counts):
    ax1.text(i, c + 20, str(c), ha='center', fontsize=9)

one_pep = df_vuln[df_vuln['id_peptides'] == 1]['lib_peptides']
ax2.hist(one_pep, bins=30, color='#D32F2F', alpha=0.7, edgecolor='white')
ax2.axvline(5, color='black', linestyle='--', linewidth=1.5)
ax2.text(6, ax2.get_ylim()[1] * 0.9 if ax2.get_ylim()[1] > 0 else 50,
         f'Small proteins\n(≤5 lib peptides)\n= {(one_pep <= 5).sum()} ({100*(one_pep<=5).mean():.0f}%)',
         fontsize=9, va='top')
ax2.text(40, ax2.get_ylim()[1] * 0.7 if ax2.get_ylim()[1] > 0 else 35,
         f'Low abundance\n(>5 lib peptides)\n= {(one_pep > 5).sum()} ({100*(one_pep>5).mean():.0f}%)',
         fontsize=9, va='top', color='#D32F2F')
ax2.set_xlabel('Theoretical Library Peptides')
ax2.set_ylabel('Number of 1-Peptide PGs')
ax2.set_title('1-Peptide PGs: Small vs Low Abundance')

fig.suptitle('Protein Vulnerability Analysis', fontsize=14, fontweight='bold', y=1.02)
fig.tight_layout()
fig.savefig(OUT_DIR / 'fig6_protein_vulnerability.png', dpi=150, bbox_inches='tight')
plt.close()

# ============================================================
# FIGURE 7: Marginal Contribution Pie Chart
# ============================================================
print("Figure 7: Marginal contributions...")

fig, ax = plt.subplots(figsize=(8, 6))

labels_pie = ['Charge\n(20.5%)', 'RT\n(8.8%)', 'm/z\n(4.7%)', 'Length\n(1.7%)', 'Overlap\n(19.2%)', 'Retained\n(45.1%)']
sizes = [20.5, 8.8, 4.7, 1.7, 19.2, 45.1]
colors_pie = ['#E74C3C', '#F39C12', '#3498DB', '#9B59B6', '#95A5A6', C_HIT]
explode = (0.05, 0.05, 0.05, 0.05, 0, 0)

wedges, texts, autotexts = ax.pie(sizes, labels=labels_pie, colors=colors_pie, explode=explode,
                                   autopct='', startangle=90, pctdistance=0.85)
for t in texts:
    t.set_fontsize(10)

ax.set_title('Marginal Contribution of Each Filter Dimension\n(% of Full Library)', fontsize=13, fontweight='bold')
fig.tight_layout()
fig.savefig(OUT_DIR / 'fig7_marginal_contributions.png', dpi=150, bbox_inches='tight')
plt.close()

print(f"\nAll figures saved to {OUT_DIR}/")
print("Done!")
