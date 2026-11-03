# ---------------------------------------------------------------------------
# Tab 1: Demographics (ADSL)
#
# SAS equivalent: PROC MEANS / PROC FREQ by TRT01A, then PROC REPORT.
# In R, {gtsummary} does the counting AND the layout in one pipeline.
# ---------------------------------------------------------------------------

demogUI <- function(id) {
  ns <- NS(id)                       # ns() prefixes IDs so modules never clash
  card(
    card_header("Table 14.1.1 Summary of Demographics - Safety Population"),
    gt::gt_output(ns("table")),
    card_footer("Source: ADSL. Population: Safety (SAFFL = 'Y'). Percentages use N per treatment arm.")
  )
}

demogServer <- function(id, adsl) {
  moduleServer(id, function(input, output, session) {

    output$table <- gt::render_gt({
      req(nrow(adsl()) > 0)          # stop quietly if the filters leave no subjects

      adsl() |>
        # droplevels(): arms removed by the sidebar filter disappear from the columns
        dplyr::mutate(TRT01A = droplevels(TRT01A)) |>
        dplyr::select(TRT01A, AGE, AGEGR1, SEX, RACE, ETHNIC) |>
        gtsummary::tbl_summary(
          by = TRT01A,
          type = list(AGE ~ "continuous2"),                 # continuous2 = one stat per row
          statistic = list(
            AGE ~ c("{N_nonmiss}", "{mean} ({sd})", "{median}", "{min}, {max}"),
            gtsummary::all_categorical() ~ "{n} ({p}%)"
          ),
          digits = list(
            AGE ~ c(0, 1, 2, 1, 0, 0),                      # n, mean, sd, median, min, max
            gtsummary::all_categorical() ~ c(0, 1)          # n (%) with 1 decimal place
          ),
          label = list(
            AGE ~ "Age (years)", AGEGR1 ~ "Age group", SEX ~ "Sex",
            RACE ~ "Race", ETHNIC ~ "Ethnicity"
          ),
          missing = "no"
        ) |>
        # add_overall() must come straight after tbl_summary(): it re-runs the summary
        gtsummary::add_overall(last = TRUE, col_label = "**Total**  \nN = {N}") |>
        gtsummary::add_stat_label(
          label = AGE ~ c("n", "Mean (SD)", "Median", "Min, Max")
        ) |>
        gtsummary::modify_header(label = "**Characteristic**") |>
        gtsummary::bold_labels() |>
        gtsummary::as_gt() |>
        gt::tab_options(table.width = gt::pct(100))
    })
  })
}
