# Automated MS-QC pipeline (OpenBIS → DIA-NN → SQLite)

Continuously picks up newly uploaded QC raw files from OpenBIS, searches each
one with DIA-NN, and accumulates QC metrics in a SQLite database for
longitudinal monitoring. Designed to run unattended on **kraken** via cron.

It is the downstream complement to `openbis-tools` (`minerva/obtools-qc.bat`),
which uploads instrument QC raws to OpenBIS every ~15 min.

## At a glance (current kraken deployment)

| | |
|---|---|
| **Location** | `/srv/data1/karlssoc/projects/ms/qc/` (scripts in `bin/`, config `qc_watch.yaml`) |
| **Watches** | OpenBIS `/DDB/CK/MINERVA_QC` (Q-Exactive HFX, Thermo `.raw`) |
| **Library/FASTA** | `data/speclib/hfx-yeast/out-lib.parquet` + `UP000002311_559292.fasta` |
| **Search** | `quantify_only` on **SLURM**, pinned to `alap759`/`work`, **10 cores** |
| **Schedule** | cron `*/30`, up to 10 new files per tick (flock-serialised) |
| **Stores** | `qc.sqlite` (ledger + metrics); kept outputs in `results/<inst>/<run>/` |
| **Publishes** | dashboard + DB → SMB `\\uw.lu.se\research\…\minerva\qc` each tick |

Deployed crontab line:

```cron
*/30 * * * * QC_CONFIG=/srv/data1/karlssoc/projects/ms/qc/qc_watch.yaml \
  QC_LOG=/srv/data1/karlssoc/projects/ms/qc/qc-watch.log \
  QC_DASHBOARD=/srv/data1/karlssoc/projects/ms/qc/qc-dashboard.html \
  QC_PUBLISH_CMD="/srv/.../qc/venv/bin/python /srv/.../qc/bin/qc-publish-smb /srv/.../qc/qc-dashboard.html /srv/.../qc/qc.sqlite" \
  /srv/data1/karlssoc/projects/ms/qc/bin/qc-watch.sh --max 10
```

## What it does, per poll

For each instrument (watch target) in the config:

1. **Enumerate** `RAW_DATA` datasets in the instrument's OpenBIS collection
   (one bulk call; file size comes from the `file_size` property set at ingest).
2. **Diff** against the SQLite ledger — datasets already `done` or `skipped` are ignored.
3. **Size filter** — datasets `< min_raw_mb` (default 100 MB; incomplete/blank/aborted
   runs) are recorded as `skipped` and never downloaded again.
4. For each remaining dataset (one at a time, so only one raw is ever on disk):
   - **Download** the raw via OpenBIS.
   - **Search** it with `nextflow run … -entry quantify_only` (config `profile:`)
     (single sample; MBR off; mass accuracy auto-set by `file_type`).
   - **Extract metrics**: every numeric column of `report.stats.tsv` (`source='stats'`)
     plus RT span / median peak width from `report.parquet` (`source='rt'`).
   - **Record** metrics + `status='done'` in the DB.
   - **Delete** the downloaded raw and the Nextflow work tree; keep only
     `report.stats.tsv` and logs (set `keep_parquet: true` to keep `report.parquet`).

The SQLite DB is both the metrics store **and** the "already processed" ledger —
there is no separate state file.

## Files

| Path | Purpose |
|------|---------|
| `bin/qc-watch` | Python orchestrator (the logic above) |
| `bin/qc-watch.sh` | cron wrapper: `flock` lock, stale `/dev/shm` cleanup, env, dashboard refresh |
| `bin/qc-dashboard` | renders a portable self-contained HTML dashboard from the DB (stdlib only) |
| `bin/qc-publish-smb` | uploads dashboard/DB to an LU SMB share (pure-Python smbprotocol) |
| `configs/qc/qc_watch.yaml` | multi-instrument config |

## One-time setup on kraken

The current kraken deployment lives at `/srv/data1/karlssoc/projects/ms/qc/`
(scripts in `bin/`, config `qc_watch.yaml`). Notes from that setup:

- **Python**: system `python3` (3.10) already has `pybis`, `duckdb`, `pyyaml`.
- **OpenBIS auth**: `qc-watch` prefers `obtools` but falls back to **pybis +
  `~/.openbis/credentials`** (already present: `OPENBIS_URL/USERNAME/PASSWORD`).
  To use obtools instead, install it where `python3` can import it:
  `pip install git+https://github.com/karlssoc/openbis-tools.git`
  (a `pipx`-only install is *not* importable; use a venv with
  `--system-site-packages` or `--user`).
- **nextflow + Java**: a non-login/cron shell has no JVM, so the config sets
  `nextflow:` to the `nf-env` binary and `java_home:` to that env (Java 23).
- **Workflow**: `repo: karlssoc/diann-wf` runs the pulled Nextflow asset
  (`nextflow pull karlssoc/diann-wf` to update it); no local checkout needed.

```bash
# 1. library + FASTA on kraken; point the config's library:/fasta: at them.
# 2. Edit qc_watch.yaml: db_path, work_dir, results_dir, repo, nextflow, java_home.
# 3. Schedule (every 30 min):
crontab -e
*/30 * * * * QC_CONFIG=/srv/data1/karlssoc/projects/ms/qc/qc_watch.yaml \
             /srv/data1/karlssoc/projects/ms/qc/bin/qc-watch.sh
```

## Manual use / testing

```bash
QC=/srv/data1/karlssoc/projects/ms/qc
python3 $QC/bin/qc-watch --config $QC/qc_watch.yaml --dry-run          # enumerate only, show process/skip
python3 $QC/bin/qc-watch --config $QC/qc_watch.yaml --only <CODE>      # force one dataset (ignores filters)
python3 $QC/bin/qc-watch --config $QC/qc_watch.yaml --instrument minerva --max 1
```

## Database

```sql
-- one row per dataset; status = pending|running|done|failed|skipped
runs(dataset_code PK, instrument, collection, run_name, size_bytes,
     acquisition_date, registration_date, status, attempts,
     diann_version, library, result_dir, searched_at, error)

-- long format: one row per (dataset, source, metric)
metrics(dataset_code, source, metric, value)   -- source = 'stats' | 'rt'
```

Inspect / plot:

```bash
sqlite3 qc.sqlite "SELECT run_name, status, searched_at FROM runs ORDER BY acquisition_date"

# longitudinal: protein IDs over time
sqlite3 qc.sqlite "
  SELECT r.acquisition_date, m.value
  FROM runs r JOIN metrics m USING (dataset_code)
  WHERE m.source='stats' AND m.metric='Proteins.Identified' AND r.status='done'
  ORDER BY r.acquisition_date"
```

Long format pivots cleanly in R (`tidyr::pivot_wider`) for ggplot QC charts.

## Dashboard

`bin/qc-dashboard` renders a **portable HTML** snapshot from the DB — data
embedded as JSON, charts via Plotly, no server, opens in any browser (copy it to
SMB/SharePoint to share). Stdlib only (no Python deps). Plotly loads from the CDN
by default (~150 KB file); set **`plotly_js:`** in the config (or `--plotly-js
<path>`) to **inline Plotly** for a fully **offline, self-contained** file
(~4.5 MB — what the kraken deployment publishes, so the SMB copy opens without
internet). Fetch the lib once: `curl -fsSL https://cdn.plot.ly/plotly-2.35.2.min.js -o plotly.min.js`.

Metrics: MS signal (MS1/MS2), precursor count, peak width (FWHM), mass accuracy
(MS1/MS2), missed cleavages, RT span. Time controls: **Last 7 / 30 / 60 days /
All time** plus a draggable range slider (anchored to the generation time). The
**y-axis auto-rescales** to the points visible in the selected window, and the
slider drives all charts together.

- **Trends (two per series)**: **LOWESS** (locally weighted regression, solid) for
  the smooth all-time trend, and **EWMA** (exponentially weighted moving average,
  dotted, `span` runs) for a responsive recent trend / drift signal. LOWESS
  robustness reweighting is intentionally off so a genuine step recovery (e.g.
  post-maintenance) is not mistaken for an outlier and erased.
- **Outlier exclusion**: failed/abnormally low runs are detected from the precursor
  count (`< abs_frac × global median` *or* `< rel_frac × local rolling median`;
  defaults 0.33 / 0.5, window 11) and removed from trends + KPIs. A *gradual*
  decline is kept (each point stays near its neighbours); only *sudden* drops are
  cut. Excluded points are **hidden by default** (so they don't inflate the
  y-axis) and revealed with the **Show excluded ✕** toggle.
- **Banner**: red if the latest run is itself flagged low; amber if **EWMA drift**
  is detected (a watched metric — precursors or MS2 signal — is down
  `> drift_thresh` from its recent 90-day peak, default 0.15) or the latest valid
  run is `< warn_frac × recent median` (default 0.75); green otherwise.
- Tunables: `--outlier-abs-frac/-rel-frac/-window --lowess-frac --ewma-span
  --warn-frac --drift-thresh`.

```bash
QC=/srv/data1/karlssoc/projects/ms/qc
$QC/bin/qc-dashboard --config $QC/qc_watch.yaml -o $QC/qc-dashboard.html
# open $QC/qc-dashboard.html in a browser
```

The cron wrapper auto-refreshes it each tick when `QC_DASHBOARD=<output.html>`
is set in the crontab line (alongside `QC_CONFIG`/`QC_LOG`).

**Publishing** (optional): also set `QC_PUBLISH` to an rsync target and the
wrapper pushes the freshly regenerated dashboard there each tick:

```cron
*/30 * * * * QC_CONFIG=…/qc_watch.yaml QC_LOG=…/qc-watch.log \
             QC_DASHBOARD=…/qc-dashboard.html \
             QC_PUBLISH=deploy@webserver:/var/www/ms-kb/qc/index.html \
             …/bin/qc-watch.sh --max 10
```

`QC_PUBLISH` can be a local dir/file (`/srv/.../shared/qc-dashboard.html`) or a
remote `user@host:/path` (needs an SSH deploy key). The dashboard is a single
static file, so a static host just serves it — or embed it in a site via
`<iframe>`. For OneDrive/SharePoint, point at a synced folder or swap the rsync
line for `rclone`.

For an arbitrary publish step, set `QC_PUBLISH_CMD` (run after each regen).
**`bin/qc-publish-smb`** uploads files to an **LU SMB share** with the pure-Python
`smbclient` (`pip install smbprotocol` — no samba CLI / sudo needed). Credentials
live in an smbclient-style auth file (default `~/.smbcredentials`, `chmod 600`):

```
username=medk-cka
password=…            # your LU password
domain=uw
```

`\\uw.lu.se\research` is a **domain-DFS namespace**, so the script forces **NTLM**
and passes credentials on every call (the DFS-referral backend server must also
authenticate); `smbprotocol`'s default `negotiate`/pre-registered-session path
fails here with `STATUS_BAD_NETWORK_NAME`. Defaults target
`\\uw.lu.se\research\LU25D1040-imp_arch\…\minerva\qc` (override via
`--server/--share/--dir/--auth-protocol` or `QC_SMB_SERVER/SHARE/DIR/PROTOCOL`).
Wire it into cron to push the dashboard **and** the SQLite DB each tick:

```cron
*/30 * * * * QC_CONFIG=$QC/qc_watch.yaml QC_LOG=$QC/qc-watch.log \
  QC_DASHBOARD=$QC/qc-dashboard.html \
  QC_PUBLISH_CMD="$QC/venv/bin/python $QC/bin/qc-publish-smb $QC/qc-dashboard.html $QC/qc.sqlite" \
  $QC/bin/qc-watch.sh --max 10
```

## Adding an instrument

Append an entry to `instruments:` with its `collection`, `file_type`
(`raw` Thermo / `d` Bruker), `library` and `fasta`. DIA-NN mass-accuracy
defaults are applied automatically by `file_type` (`modules/quantify.nf`).
Bruker `.d` datasets (stored zipped in OpenBIS) are extracted automatically; the
wrapper's `/dev/shm` cleanup guards the known Bruker shared-memory hang.

## Notes & limitations

- **Profile**: the kraken deployment uses `profile: slurm` with the SLURM jobs
  **pinned to the stable node** via `nextflow_params` (`slurm_account: karlssoc`,
  `slurm_queue: work`, `slurm_nodelist: alap759`, `parallel_mode: false`). Without
  that pinning, single-file QC jobs land on other nodes and are killed
  ("terminated by external system"); with it they run fine (matches the working
  `DT-D3mNP-pquant` project). `profile: standard` (local on alap759) also works
  and avoids the JVM/queue overhead — override per run with `--profile`.
- **Failures** are retried on later ticks up to `max_retries`; the raw is always
  deleted even on failure. `runs.error`, `results/<inst>/<run>/nextflow.log`, and
  (on failure) the kept `work/nf/<code>/` tree (`diann.log`, `.command.err`) hold
  the diagnostics.
- **Serial** processing keeps disk use to one raw at a time; QC volume is low so
  this is intentional (not a throughput pipeline). Each SLURM tick runs one search
  at a time (`parallel_mode: false`, `maxForks: 1`).
- **Sharing**: the dashboard + SQLite DB are pushed to the LU SMB share each tick
  (see *Publishing*). Uploading results back to OpenBIS as ANALYZED child datasets
  is a possible future add-on.
- The exact `report.stats.tsv` columns depend on the DIA-NN version; metric
  extraction is generic (every numeric column is stored), so it adapts.
