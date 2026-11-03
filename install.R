# Run once to install everything the app needs.
install.packages(c(
  "shiny", "bslib",          # app + layout
  "dplyr", "tidyr",          # data wrangling
  "ggplot2", "plotly",       # charts
  "DT",                      # interactive listing
  "gtsummary", "gt",         # demographics table
  "survival", "ggsurvfit",   # Kaplan-Meier
  "tibble",
  "random.cdisc.data",       # synthetic ADaM data (default)
  "pharmaverseadam"          # alternative example ADaM data
))
