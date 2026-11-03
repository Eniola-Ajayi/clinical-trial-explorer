# ---------------------------------------------------------------------------
# Time-to-event statistics (plain functions - no Shiny, so easy to test)
#
# SAS equivalent:
#   PROC LIFETEST  -> survfit()   : N, events, median + 95% CI
#                  -> survdiff()  : log-rank test
#   PROC PHREG     -> coxph()     : hazard ratio + 95% CI
# ---------------------------------------------------------------------------

# Format "12.3 (10.1, 15.0)", with NE (not estimable) for missing values
fmt_est_ci <- function(est, lo, hi, digits = 1) {
  f <- function(x) ifelse(is.na(x), "NE", formatC(x, format = "f", digits = digits))
  paste0(f(est), " (", f(lo), ", ", f(hi), ")")
}

fmt_p <- function(p) {
  ifelse(is.na(p), "", ifelse(p < 0.001, "<0.001", formatC(p, format = "f", digits = 3)))
}

# d must contain AVAL, CNSR (1 = censored) and TRT01A (factor, reference arm first).
km_summary <- function(d) {
  d <- d |>
    dplyr::mutate(EVENT = 1 - CNSR, TRT01A = droplevels(TRT01A))
  arms <- levels(d$TRT01A)
  ref  <- arms[1]                                   # first level = reference (Placebo)

  # --- Medians: survfit() is PROC LIFETEST -----------------------------------
  fit <- survival::survfit(survival::Surv(AVAL, EVENT) ~ TRT01A, data = d)
  tab <- summary(fit)$table
  if (is.null(dim(tab))) tab <- t(as.matrix(tab))  # one arm -> make it a 1-row matrix
  medians <- tibble::tibble(
    TRT01A  = arms,
    N       = as.integer(tab[, "records"]),
    events  = as.integer(tab[, "events"]),
    median  = tab[, "median"],
    lcl     = tab[, "0.95LCL"],
    ucl     = tab[, "0.95UCL"]
  )

  # --- Hazard ratios: coxph() is PROC PHREG ----------------------------------
  hr <- tibble::tibble(TRT01A = arms, hr = NA_real_, hr_lcl = NA_real_, hr_ucl = NA_real_, p = NA_real_)
  if (length(arms) > 1) {
    ci <- summary(survival::coxph(survival::Surv(AVAL, EVENT) ~ TRT01A, data = d))$conf.int
    idx <- match(sub("^TRT01A", "", rownames(ci)), arms)
    hr$hr[idx]     <- ci[, "exp(coef)"]
    hr$hr_lcl[idx] <- ci[, "lower .95"]
    hr$hr_ucl[idx] <- ci[, "upper .95"]

    # Log-rank p-value for each arm vs the reference arm
    for (a in arms[-1]) {
      pair <- dplyr::filter(d, TRT01A %in% c(ref, a)) |> dplyr::mutate(TRT01A = droplevels(TRT01A))
      lr <- survival::survdiff(survival::Surv(AVAL, EVENT) ~ TRT01A, data = pair)
      hr$p[hr$TRT01A == a] <- stats::pchisq(lr$chisq, df = 1, lower.tail = FALSE)
    }
  }

  # Final display columns (like the columns of a PROC REPORT)
  dplyr::left_join(medians, hr, by = "TRT01A") |>
    dplyr::transmute(
      `Treatment`             = TRT01A,
      `N`                     = N,
      `Events, n (%)`         = paste0(events, " (", formatC(100 * events / N, format = "f", digits = 1), "%)"),
      `Censored, n`           = N - events,
      `Median (95% CI)`       = fmt_est_ci(median, lcl, ucl),
      `Hazard ratio (95% CI)` = ifelse(TRT01A == ref, "Reference", fmt_est_ci(hr, hr_lcl, hr_ucl, digits = 2)),
      `Log-rank p-value`      = ifelse(TRT01A == ref, "", fmt_p(p))
    )
}
