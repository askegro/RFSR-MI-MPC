# RFSR-MI-MPC: Ranking-Based Feasible-Set Restriction for Reconfigurable Battery Packs

This repository contains the complete simulation and postprocessing code used in:

A. Škegro, Q. Ouyang, T. Wik, C. Zou, *RFSR-MI-MPC: Ranking-Based Feasible-Set
Restriction for Real-Time Control of Reconfigurable Battery Packs*, submitted to
IEEE Transactions on Control Systems Technology.

## Repository structure

```
RFSR-MI-MPC/
├── REPRODUCE_ALL_RESULTS.m    # One-click reproduction of every reported number
├── fetch_results.m            # Downloads the archived result files into results/
├── initProjectPaths.m         # Single path-bootstrap point used by every script
├── CITATION.cff
├── LICENSE
│
├── mainSimulationRunners/     # The five simulation campaigns
│   ├── RUN_ALL_SIMULATIONS.m    runs all five in order
│   └── README_simulation.md
│
├── postProcess/               # Tables, in-text numbers, appendix checks
├── figureGeneration/          # Generators for the three manuscript figures
├── results/                   # Manuscript figures, run transcripts; the
│                              # result .mat files are downloaded into here
│
├── application/  build/  config/  control/   # Model, optimizer and controller
├── data/  plant/  solutionHandling/          # Cell data, plant, solver handling
└── state_machine/  utils/                    # Episode logic, shared helpers
```

## Quick start

The result files are archived outside this repository because they are too large
for GitHub (see [Result data](#result-data)). Download them, then reproduce every
reported number and figure:

```matlab
fetch_results
REPRODUCE_ALL_RESULTS
```

`fetch_results` downloads the five result `.mat` files into `results/`, verifying
file size and MD5 checksum, and skips any file already present. Every reported
value is then reproducible **without rerunning the simulations and without a
solver licence**. The report is organised by manuscript subsection, printed to
the Command Window, and written to
`results/textualOutputs/REPRODUCE_ALL_RESULTS_<timestamp>.txt`.

To download only what the three manuscript figures need (about 10 MB instead of
174 MB):

```matlab
fetch_results('nominal')
```

To regenerate the result files from scratch (hours; needs YALMIP and Gurobi):

```matlab
cd mainSimulationRunners
RUN_ALL_SIMULATIONS        % or RUN_ALL_SIMULATIONS(8) to set the worker count
```

## Requirements

| Component | Requirement |
| --- | --- |
| Simulation | MATLAB R2025b or later, YALMIP, Gurobi 13.0.1, Parallel Computing Toolbox (Monte Carlo and sweep campaigns only) |
| Postprocessing | MATLAB R2025b or later, Statistics and Machine Learning Toolbox |

The published results were produced with MATLAB R2025b and Gurobi 13.0.1 on an
Intel Core i7-1370P (13th Gen).


## Result data

The five result `.mat` files produced by the simulation campaigns total 174 MB,
and one of them exceeds GitHub's 100 MiB per-file limit, so they are archived on
Zenodo rather than stored in this repository:

**DOI: [10.5281/zenodo.22134357](https://doi.org/10.5281/zenodo.22134357)**

| File | Produced by | Size |
| --- | --- | --- |
| `Results_nominal_wltc_<date>.mat` | `run_nominal_wltc.m` | 10.1 MB |
| `Results_samestate_proposed_<date>.mat` | `run_samestate_proposed.m` | 5.8 MB |
| `Results_samestate_rulebased_<date>.mat` | `run_samestate_rulebased.m` | 5.8 MB |
| `Results_montecarlo_ics_<date>.mat` | `run_montecarlo_ics.m` | 110.0 MB |
| `Results_robustness_sweeps_<date>.mat` | `run_robustness_sweeps.m` | 42.5 MB |

`fetch_results` downloads them automatically. They can equally be downloaded
from the Zenodo record by hand and placed in `results/`. Which campaign feeds
which table, figure and section is documented in
[`mainSimulationRunners/README_simulation.md`](mainSimulationRunners/README_simulation.md).

The `results/` folder itself is tracked in this repository and holds the
manuscript figures and the run transcript; only the `.mat` files are fetched.


## Citation

If you use this code, please cite:

```
A. Škegro, Q. Ouyang, T. Wik, C. Zou,
RFSR-MI-MPC: Ranking-Based Feasible-Set Restriction for Real-Time Control
of Reconfigurable Battery Packs,
submitted to IEEE Transactions on Control Systems Technology.
```

Machine-readable citation metadata is in [`CITATION.cff`](CITATION.cff), which
GitHub uses to render the *Cite this repository* button.

## Licence

Source code in this repository is licensed under the MIT License; see
[`LICENSE`](LICENSE). The archived result data is licensed separately under
CC BY 4.0; see the Zenodo record linked under [Result data](#result-data).

If you use this repository, please cite the associated publication.
