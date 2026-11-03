# Checks: runs each tab's real server code with shiny::testServer (no browser)
# and writes the results to checks/check_log.txt, with a KM plot per parameter.
#
# Run from the repository folder:  Rscript tests/check_app.R
# Exits with an error if any step fails, so it can run in CI.
if (!file.exists("app.R")) stop("Run this from the repository folder (the one containing app.R).")
proj <- getwd()
out <- file.path(proj, "checks")
dir.create(out, showWarnings = FALSE)
n_errors <- 0
con <- file(file.path(out, "check_log.txt"), open = "wt")
sink(con, split = TRUE)

step <- function(label, expr) {
  cat("\n==== ", label, " ====\n", sep = "")
  tryCatch(
    withCallingHandlers({ res <- expr; cat("OK\n"); res },
      warning = function(w) { cat("WARNING: ", conditionMessage(w), "\n", sep = ""); invokeRestart("muffleWarning") }),
    error = function(e) { cat("ERROR: ", conditionMessage(e), "\n", sep = ""); n_errors <<- n_errors + 1; NULL })
}

pkgs <- c("shiny", "bslib", "dplyr", "tidyr", "tibble", "ggplot2", "plotly", "DT", "gtsummary", "gt",
          "survival", "ggsurvfit", "random.cdisc.data", "base64enc")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
for (p in pkgs) cat(sprintf("%-18s %s\n", p, as.character(packageVersion(p))))

library(shiny); library(bslib)
for (f in list.files("R", full.names = TRUE)) source(f)
save_plot <- function(img, name) writeBin(base64enc::base64decode(sub("^data:image/png;base64,", "", img$src)), file.path(out, name))

trial <- step("load_trial_data()", {
  trial <- load_trial_data()
  cat("subjects:", nrow(trial$adsl), " AEs:", nrow(trial$adae), " TTE rows:", nrow(trial$adtte), "\n")
  cat("arms:", paste(trial$arms, collapse = " | "), "\n")
  cat("TTE params:", paste(unique(trial$adtte$PARAMCD), collapse = ", "), "\n")
  cat("SEX:", paste(unique(trial$adsl$SEX), collapse = ", "), " AGEGR1:", paste(unique(trial$adsl$AGEGR1), collapse = ", "), "\n")
  trial
})

step("km_summary() - PFS, all arms", {
  print(as.data.frame(km_summary(dplyr::filter(trial$adtte, PARAMCD == "PFS"))))
})
step("km_summary() - single arm (edge case)", {
  print(as.data.frame(km_summary(dplyr::filter(trial$adtte, PARAMCD == "PFS", TRT01A == trial$arms[1]))))
})

step("Demographics module", {
  testServer(demogServer, args = list(adsl = reactive(trial$adsl)), {
    html <- output$table$html
    writeLines(as.character(html), file.path(out, "check_demog.html"))
    for (txt in c(trial$arms, "Total", "Mean (SD)", "Age group", "Ethnicity")) cat("  contains", sQuote(txt), ":", grepl(txt, html, fixed = TRUE), "\n")
  })
})

step("AE module", {
  testServer(aeServer, args = list(adae = reactive(trial$adae), adsl = reactive(trial$adsl), colours = trial$colours), {
    session$setInputs(view = "bars", top_n = 10, term = "", arm_left = trial$arms[1], arm_right = trial$arms[3])
    cat("  top terms:", paste(head(top_terms(), 5), collapse = ", "), "...\n")
    cat("  grouped bars json chars:", nchar(output$ae_plot), "\n")
    session$setInputs(view = "butterfly")
    cat("  butterfly json chars:", nchar(output$ae_plot), "\n")
    cat("  listing rows (all):", nrow(listing_data()), "\n")
    session$setInputs(term = top_terms()[1])
    cat("  listing rows (", top_terms()[1], "):", nrow(listing_data()),
        "- all that term:", all(listing_data()$`Preferred term` == top_terms()[1]), "\n")
    invisible(output$listing)
  })
})

step("KM module", {
  testServer(kmServer, args = list(adtte = reactive(trial$adtte), colours = trial$colours), {
    for (p in unique(trial$adtte$PARAMCD)) {
      session$setInputs(paramcd = p, show_median = TRUE)
      save_plot(output$km_plot, paste0("check_km_", p, ".png"))
      cat("  ", p, ": plot saved, table html chars", nchar(output$km_table$html), "\n")
      if (p == "PFS") writeLines(as.character(output$km_table$html), file.path(out, "check_km_table.html"))
    }
  })
})

step("Whole app: sidebar filters", {
  testServer(shinyAppDir(proj), {
    session$setInputs(arms = trial$arms, sex = unique(trial$adsl$SEX), agegr = unique(trial$adsl$AGEGR1))
    cat("  all subjects:", nrow(adsl()), " AEs:", nrow(adae()), " TTE:", nrow(adtte()), "\n")
    session$setInputs(arms = trial$arms[1:2], sex = "F")
    cat("  2 arms + female:", nrow(adsl()), " AEs:", nrow(adae()), " TTE:", nrow(adtte()), "\n")
    cat("  AE subjects all in ADSL:", all(adae()$USUBJID %in% adsl()$USUBJID), "\n")
  })
})

cat("\nDONE:", n_errors, "step(s) failed\n")
sink()
close(con)
if (n_errors > 0) quit(status = 1)
