# Clinical Trial Explorer

[![Tests](https://github.com/Eniola-Ajayi/clinical-trial-explorer/actions/workflows/tests.yml/badge.svg)](https://github.com/Eniola-Ajayi/clinical-trial-explorer/actions/workflows/tests.yml)

Clinical trial programming in **R**: an interactive **R Shiny** app for
exploring a study's demographics, adverse events and time-to-event endpoints,
plus a [`pharmaverse/`](pharmaverse/README.md) folder with an R package and
SDTM, ADaM and TLG programs built with pharmaverse packages. All data is
**synthetic** CDISC data; there are no real patients.

**Live app:** <https://eniolaajayi.shinyapps.io/trial-explorer/>

| Folder | What it contains |
|---|---|
| repository root | The Shiny app (`app.R`, `R/`) and its checks (`tests/`) |
| [`pharmaverse/`](pharmaverse/README.md) | `descriptiveStats` R package with tests; SDTM DS domain with `{sdtm.oak}`; ADSL with `{admiral}` and independent QC; AE summary table, figures and listing |

## The app

| Part of the page | What it shows |
|---|---|
| **Sidebar filters** | Treatment arm, sex and age group, plus "X of Y safety subjects selected" |
| **Demographics** | A TLF-style summary table by arm, with a Total column (`{gtsummary}`) |
| **Adverse Events** | Most common treatment-emergent AEs as grouped bars or a two-arm "butterfly" plot (`{plotly}`). Click a bar to filter the AE listing below it (`{DT}`). |
| **Time to Event** | Kaplan-Meier curves with number at risk and median lines (`{ggsurvfit}`), plus a table of events, median (95% CI), hazard ratio (95% CI) and log-rank p-value (`{survival}`) |

Design choices:

* **One population filter drives everything.** The sidebar filters ADSL once;
  ADAE and ADTTE are cut to the same subjects with a semi-join on USUBJID, so
  every tab always agrees on the population.
* **Correct denominators.** AE percentages use the number of subjects per arm
  from ADSL, and each subject counts once per preferred term.
* **Statistics in plain functions.** `R/km_stats.R` (medians, hazard ratios,
  log-rank tests) has no Shiny code, so it can be tested on its own.
* **`EVENT = 1 - CNSR`.** ADaM codes censoring as CNSR = 1, while
  `survival::Surv()` expects 1 for an event.
* **One colour per arm** across every tab.

### Run it

```r
source("install.R")   # first time only
shiny::runApp()
```

### Checks

```r
source("tests/check_app.R")    # or: Rscript tests/check_app.R
```

Runs each tab's real server code with `shiny::testServer()` (no browser),
including the sidebar filters and edge cases such as a single arm, and writes
a log and a KM plot per parameter to `checks/`. GitHub Actions runs it on
every push.

### Structure

```
app.R            sidebar filters, wires the tabs together
R/data.R         loads and prepares ADSL, ADAE, ADTTE
R/km_stats.R     median / hazard ratio / log-rank calculations (plain functions)
R/mod_demog.R    Demographics tab
R/mod_ae.R       Adverse Events tab: chart + listing
R/mod_km.R       Time to Event tab: Kaplan-Meier plot + summary table
tests/           testServer checks
LEARN.md         walkthrough of the code for SAS programmers
```

### Limitations

* **Exploratory, not a validated output.** Hazard ratios and p-values on a
  filtered subgroup are post-hoc subgroup analyses, for exploration only.
* **Unstratified** Cox model and log-rank tests, with no adjustment for
  multiple comparisons.
* Adverse event terms in this synthetic data are codes (e.g. "dcd D.2.1.5.3"),
  not real MedDRA terms.

## Data

Synthetic ADaM datasets (ADSL, ADAE, ADTTE) from the
[`random.cdisc.data`](https://insightsengineering.github.io/random.cdisc.data/)
package. `R/data.R` can also load
[`pharmaverseadam`](https://pharmaverse.github.io/pharmaverseadam/)
(`load_trial_data("pharmaverseadam")`), though its time-to-event data has too
few events for meaningful Kaplan-Meier curves.

## Deploy (free) to shinyapps.io

```r
install.packages("rsconnect")
# create an account at shinyapps.io, then copy the setAccountInfo() line from its dashboard
rsconnect::setAccountInfo(name = "...", token = "...", secret = "...")
rsconnect::deployApp()
```

Never commit the `setAccountInfo()` line or the `rsconnect/` folder: both are
kept out of git.
