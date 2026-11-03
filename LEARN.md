# Learning guide: this app for a SAS programmer

Read this alongside the code. It goes file by file in the order the app runs,
and maps each R idea to the SAS you already know.

---

## 1. The five R ideas you need

| R | What it is | SAS equivalent |
|---|---|---|
| `x <- value` | Assign a value to a name | `%let x = value;` / creating a dataset |
| **data frame / tibble** | A table held in memory | A SAS dataset (in WORK) |
| `pkg::fun()` | Call `fun` from package `pkg` without loading it all | Calling a macro from a specific library |
| `\|>` (the pipe) | "Take the result on the left and feed it into the next step" | One DATA step feeding the next, without writing temporary datasets |
| `function(a, b) { ... }` | A reusable block with arguments | A `%macro` with parameters |

**The pipe in practice**

```r
adsl |>
  dplyr::filter(SAFFL == "Y") |>
  dplyr::count(TRT01A)
```
reads as: *take ADSL, keep the safety population, count by arm*. In SAS:
```sas
proc freq data=adsl(where=(saffl="Y")); tables trt01a; run;
```

## 2. dplyr cheat sheet (you'll see these everywhere)

| dplyr | SAS |
|---|---|
| `filter(SAFFL == "Y")` | `where saffl = "Y";` |
| `select(USUBJID, AGE)` | `keep usubjid age;` |
| `mutate(EVENT = 1 - CNSR)` | `event = 1 - cnsr;` in a DATA step |
| `arrange(TRT01A, USUBJID)` | `proc sort; by trt01a usubjid;` |
| `group_by(TRT01A) \|> summarise(n = n())` | `proc means ... class trt01a;` |
| `count(TRT01A, AEDECOD)` | `proc freq; tables trt01a*aedecod / out=...;` |
| `distinct(USUBJID, AEDECOD)` | `proc sort nodupkey; by usubjid aedecod;` |
| `left_join(a, b, by = "USUBJID")` | `merge a(in=ina) b; by usubjid; if ina;` |
| `inner_join(...)` | `merge ...; if ina and inb;` |
| `semi_join(adae, adsl, by = "USUBJID")` | Keep ADAE rows whose subject is in ADSL (no ADSL columns added) |

**Factors**: `TRT01A` is a *factor*, a character variable with a fixed order
(Placebo first). Think of it as having `TRT01AN` baked in. `droplevels()` removes
arms that have been filtered out.

---

## 3. How a Shiny app works (the only genuinely new idea)

A Shiny app has two halves:

- **UI**: what the page looks like (inputs like checkboxes, and empty slots for outputs).
- **Server**: R code that fills those slots, and **re-runs automatically when an input changes**.

That automatic re-running is called **reactivity**:

```r
adsl <- reactive({
  dplyr::filter(trial$adsl, TRT01A %in% input$arms)
})
```

`reactive()` is like a SAS view that recalculates itself: whenever the
`input$arms` checkboxes change, `adsl()` is recomputed, and every table/plot that
uses `adsl()` redraws. You call it with brackets, `adsl()`, because it's a
function that returns the current data.

Other building blocks you'll see:

| Code | Meaning |
|---|---|
| `input$top_n` | Current value of the input with ID `top_n` |
| `output$ae_plot <- renderPlotly({...})` | Code that draws the output with ID `ae_plot` |
| `req(x)` | "Stop here quietly if x is missing/empty" (avoids error messages while loading) |
| `observe({...})` / `observeEvent(x, {...})` | Run code for its side effects (e.g. update a dropdown) when something changes |
| `updateSelectInput(...)` | Change a dropdown's choices from the server side |

## 4. Modules: macros for Shiny

Each tab is a **module**: a pair of functions, `xxxUI(id)` and `xxxServer(id, ...)`.
It's the same idea as a well-written SAS macro: parameters in, output out, and no
reliance on global variables. `NS(id)` prefixes every input ID inside the module
(e.g. `ae-top_n`) so two modules can both have an input called `top_n` without clashing.

The data flows **one way**:

```
R/data.R   load_trial_data()          (runs once at start-up)
    |
app.R      sidebar filters -> adsl(), adae(), adtte()   (filtered once, centrally)
    |
    +--> demogServer("demog", adsl)
    +--> aeServer("ae", adae, adsl, colours)
    +--> kmServer("km", adtte, colours)
```

---

## 5. File by file

### `R/data.R`: data preparation
- `get_raw()` picks the source package. `random.cdisc.data` is a synthetic oncology-style study.
- `pick()` uses whichever column exists (e.g. `TRT01A`, else `ACTARM`). This is defensive
  programming, like checking `%sysfunc(varnum(...))` before using a variable.
- `plain()` strips SAS-style labels/attributes that some packages attach.
- ADAE and ADTTE get `TRT01A` **from ADSL** via `inner_join`, so every tab uses identical arm labels.
- `order_arms()` / `arm_palette()`: display order and one fixed colour per arm.

### `R/mod_demog.R`: Table 14.1.1
`gtsummary::tbl_summary()` is PROC MEANS + PROC FREQ + PROC REPORT in one call:
- `by = TRT01A`: one column per arm
- `type = AGE ~ "continuous2"`: continuous stats on separate rows
- `statistic = ...`: which stats (n, mean (SD), median, min/max; n (%) for categorical)
- `add_overall()`: the Total column. `as_gt()` turns it into a formatted table.

### `R/mod_ae.R`: AE chart + listing
1. **Summary**: `distinct(USUBJID, TRT01A, AEDECOD)` counts each subject once per term,
   then divides by the big N from ADSL. It's exactly how you'd do it for an AE table.
2. **Top terms**: `slice_max(total, n = input$top_n)`.
3. **Chart**: built with `ggplot2`, then `plotly::ggplotly()` makes it interactive.
   *Butterfly*: the left arm's percentages are made negative so the bars point left;
   the axis labels use `abs()` so they still read as positive.
4. **Click to filter**: `event_data("plotly_click")` returns the clicked bar. Its `key`
   is the preferred term, which updates the dropdown, which filters the listing.
5. **Listing**: `DT::datatable()` gives a sortable, searchable table.

### `R/km_stats.R`: the statistics (no Shiny)
| R | SAS |
|---|---|
| `survfit(Surv(AVAL, EVENT) ~ TRT01A)` | `proc lifetest; time aval*cnsr(1); strata trt01a;` |
| `summary(fit)$table` | the Quartile Estimates / Summary tables (median + 95% CI) |
| `coxph(Surv(AVAL, EVENT) ~ TRT01A)` | `proc phreg; class trt01a(ref="Placebo"); model aval*cnsr(1) = trt01a / rl;` |
| `survdiff(...)` | the log-rank test in PROC LIFETEST |

Note `EVENT = 1 - CNSR`: R's `Surv()` wants **1 = event**, but ADaM `CNSR` is **1 = censored**.
Getting this backwards is the classic mistake.

Because these are plain functions, you can run them in the console on their own:
```r
source("R/data.R"); source("R/km_stats.R")
trial <- load_trial_data()
km_summary(subset(trial$adtte, PARAMCD == "PFS"))
```

### `R/mod_km.R`: KM plot + summary table
`ggsurvfit` builds the plot in layers (the `+` signs), like adding statements to PROC SGPLOT:
curves, censor ticks, risk table, 0-100% axis, arm colours, dashed median lines.

### `app.R`: putting it together
Sidebar filters are applied **once** to ADSL; `semi_join()` then keeps only those subjects
in ADAE and ADTTE. That's why every tab always agrees on the population.

---

## 6. Try these to learn it

1. **Run pieces in the console.** Highlight a pipeline in `R/mod_ae.R` (replace `adae()`
   with `trial$adae`) and run it with Ctrl+Enter. Seeing the intermediate tibbles is the
   fastest way to learn.
2. **Add a statistic**: add `"{q1}, {q3}"` to the AGE statistics (and a digit + label for it).
3. **Add a filter**: put a `RACE` checkbox in the sidebar and add it to the `filter()` in `app.R`.
4. **Add a value box**: `bslib::value_box(title = "Subjects", value = textOutput("n_subj"))`
   at the top of the Demographics tab.
5. **Change the data**: `load_trial_data("pharmaverseadam")` and see what changes (and why the
   KM tab is less useful with that data).

## 7. Useful references
- R for Data Science (free online): dplyr, ggplot2 basics
- Mastering Shiny (free online, by Hadley Wickham): reactivity and modules
- pharmaverse.org: R packages for clinical reporting (admiral for ADaM, rtables/tern for TLFs)
