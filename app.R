# ---------------------------------------------------------------------------
# Clinical Trial Explorer
# Interactive demographics, adverse events and time-to-event outputs
# built on synthetic CDISC ADaM data.
#
# Run:  shiny::runApp()   (from this folder)
#
# How it fits together:
#   R/data.R      loads ADSL / ADAE / ADTTE once, when the app starts
#   app.R         sidebar filters -> filtered datasets -> passed to each tab
#   R/mod_*.R     one "module" per tab (its own UI + server code)
#   R/km_stats.R  plain functions for medians / HR / log-rank
# ---------------------------------------------------------------------------

library(shiny)
library(bslib)

# Shiny loads files in R/ automatically, but sourcing keeps it explicit.
for (f in list.files("R", full.names = TRUE)) source(f)

trial <- load_trial_data()
tte_params  <- unique(trial$adtte[, c("PARAMCD", "PARAM")])
tte_choices <- setNames(tte_params$PARAMCD, tte_params$PARAM)

# ---- UI: what the page looks like -----------------------------------------
ui <- page_navbar(
  title = "Clinical Trial Explorer",
  theme = bs_theme(bootswatch = "flatly"),

  sidebar = sidebar(
    width = 260,
    checkboxGroupInput("arms", "Treatment arm", choices = trial$arms, selected = trial$arms),
    checkboxGroupInput("sex", "Sex", choices = sort(unique(trial$adsl$SEX)), selected = unique(trial$adsl$SEX)),
    checkboxGroupInput("agegr", "Age group", choices = sort(unique(trial$adsl$AGEGR1)), selected = unique(trial$adsl$AGEGR1)),
    hr(),
    uiOutput("population"),
    helpText(paste0("Data: {", trial$source, "} synthetic ADaM datasets. No real patient data."))
  ),

  nav_panel("Demographics", demogUI("demog")),
  nav_panel("Adverse Events", aeUI("ae")),
  nav_panel("Time to Event", kmUI("km", tte_choices)),

  nav_spacer(),
  nav_item(tags$a("GitHub", href = "https://github.com/Eniola-Ajayi", target = "_blank"))
)

# ---- Server: what happens when inputs change --------------------------------
server <- function(input, output, session) {

  # Filters are applied ONCE, to ADSL. ADAE and ADTTE then keep only the
  # selected subjects - like merging on USUBJID in SAS - so every tab agrees.
  adsl <- reactive({
    dplyr::filter(
      trial$adsl,
      TRT01A %in% input$arms,
      SEX    %in% input$sex,
      AGEGR1 %in% input$agegr
    )
  })
  adae  <- reactive(dplyr::semi_join(trial$adae,  adsl(), by = "USUBJID"))
  adtte <- reactive(dplyr::semi_join(trial$adtte, adsl(), by = "USUBJID"))

  output$population <- renderUI({
    tags$p(tags$strong(nrow(adsl())), " of ", nrow(trial$adsl), " safety subjects selected")
  })

  demogServer("demog", adsl)
  aeServer("ae", adae, adsl, trial$colours)
  kmServer("km", adtte, trial$colours)
}

shinyApp(ui, server)
