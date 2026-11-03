# ---------------------------------------------------------------------------
# Data preparation
# Loads example ADaM datasets and keeps just what the app needs.
#
# source = "random.cdisc.data" : synthetic study with realistic OS/PFS       [default]
# source = "pharmaverseadam"   : CDISC pilot based data (poor time-to-event data)
# ---------------------------------------------------------------------------

# Arms in display order (placebo first, then the rest), like a TLF.
order_arms <- function(arms) {
  arms <- unique(as.character(arms))
  placebo <- arms[grepl("placebo", arms, ignore.case = TRUE)]
  low     <- arms[grepl("low", arms, ignore.case = TRUE)]
  high    <- arms[grepl("high", arms, ignore.case = TRUE)]
  ordered <- c(placebo, low, high)
  c(ordered, sort(setdiff(arms, ordered)))
}

# One colour per arm, used by every tab so the arms always match.
arm_palette <- function(arms) {
  base <- c("#7F7F7F", "#1F77B4", "#D62728", "#2CA02C", "#9467BD", "#FF7F0E")
  setNames(base[seq_along(arms)], arms)
}

# Use the first of `candidates` that exists in `data`.
pick <- function(data, candidates) {
  hit <- intersect(candidates, names(data))
  if (!length(hit)) stop("None of these columns found: ", paste(candidates, collapse = ", "))
  data[[hit[1]]]
}

# Strip SAS-style labels/attributes so dplyr and ggplot treat columns as plain vectors.
plain <- function(x) { attributes(x) <- NULL; x }

get_raw <- function(source) {
  switch(source,
    "random.cdisc.data" = list(
      adsl  = random.cdisc.data::cadsl,
      adae  = random.cdisc.data::cadae,
      adtte = random.cdisc.data::cadtte
    ),
    "pharmaverseadam" = list(
      adsl  = pharmaverseadam::adsl,
      adae  = pharmaverseadam::adae,
      adtte = pharmaverseadam::adtte_onco
    ),
    stop("Unknown data source: ", source)
  )
}

load_trial_data <- function(source = "random.cdisc.data", min_tte_records = 20) {
  raw <- get_raw(source)

  adsl <- tibble::tibble(
    USUBJID = plain(as.character(raw$adsl$USUBJID)),
    TRT01A  = plain(as.character(pick(raw$adsl, c("TRT01A", "ACTARM", "ARM")))),
    SAFFL   = plain(as.character(pick(raw$adsl, c("SAFFL")))),
    AGE     = plain(as.numeric(raw$adsl$AGE)),
    SEX     = plain(as.character(raw$adsl$SEX)),
    RACE    = plain(as.character(raw$adsl$RACE)),
    ETHNIC  = plain(as.character(pick(raw$adsl, c("ETHNIC"))))
  ) |>
    dplyr::filter(SAFFL == "Y") |>
    # Age groups chosen to suit this study's age range (20-69 years)
    dplyr::mutate(
      AGEGR1 = dplyr::case_when(AGE < 40 ~ "18-39", AGE < 65 ~ "40-64", TRUE ~ ">=65"),
      .after = AGE
    ) |>
    dplyr::select(-SAFFL)

  arms <- order_arms(adsl$TRT01A)
  adsl$TRT01A <- factor(adsl$TRT01A, levels = arms)
  arm_lookup <- dplyr::select(adsl, USUBJID, TRT01A)

  # Treatment-emergent AEs (all AEs if the dataset has no TRTEMFL flag).
  ae <- raw$adae
  adae <- tibble::tibble(
    USUBJID  = plain(as.character(ae$USUBJID)),
    AEBODSYS = plain(as.character(ae$AEBODSYS)),
    AEDECOD  = plain(as.character(ae$AEDECOD)),
    AESEV    = plain(as.character(ae$AESEV)),
    AESER    = plain(as.character(ae$AESER)),
    TRTEMFL  = if ("TRTEMFL" %in% names(ae)) plain(as.character(ae$TRTEMFL)) else "Y"
  ) |>
    dplyr::filter(TRTEMFL == "Y") |>
    dplyr::select(-TRTEMFL) |>
    dplyr::inner_join(arm_lookup, by = "USUBJID")

  # Time to event: keep time-based parameters (not counts like TNE) with enough records to plot.
  tte <- raw$adtte
  adtte <- tibble::tibble(
    USUBJID = plain(as.character(tte$USUBJID)),
    PARAMCD = plain(as.character(tte$PARAMCD)),
    PARAM   = plain(as.character(tte$PARAM)),
    AVAL    = plain(as.numeric(tte$AVAL)),
    AVALU   = if ("AVALU" %in% names(tte)) plain(as.character(tte$AVALU)) else "DAYS",
    CNSR    = plain(as.numeric(tte$CNSR))
  ) |>
    dplyr::filter(is.na(AVALU) | tolower(AVALU) %in% c("days", "weeks", "months", "years")) |>  # time-based only
    dplyr::inner_join(arm_lookup, by = "USUBJID") |>
    dplyr::add_count(PARAMCD, name = "n_records") |>
    dplyr::filter(n_records >= min_tte_records) |>
    dplyr::select(-n_records)

  list(
    source  = source,
    adsl    = adsl,
    adae    = adae,
    adtte   = adtte,
    arms    = arms,
    colours = arm_palette(arms)
  )
}
