# ---------------------------------------------------------------------------
# Tab 3: Time to event (ADTTE)
#
# Kaplan-Meier plot with medians marked, number at risk underneath,
# and a TLF-style summary table (median, HR, log-rank p) from R/km_stats.R.
# ---------------------------------------------------------------------------

kmUI <- function(id, params) {
  ns <- NS(id)
  default <- if ("PFS" %in% params) "PFS" else params[[1]]
  tagList(
    card(
      card_header(
        class = "d-flex flex-wrap gap-3 align-items-end",
        tags$strong("Kaplan-Meier Plot", class = "me-auto"),
        selectInput(ns("paramcd"), "Parameter", choices = params, selected = default, width = "300px"),
        checkboxInput(ns("show_median"), "Show medians", value = TRUE)
      ),
      plotOutput(ns("km_plot"), height = "560px"),
      card_footer("Source: ADTTE. Event = CNSR 0; censored = CNSR 1 (tick marks). Dashed lines mark median time to event.")
    ),
    card(
      card_header(textOutput(ns("table_title"), inline = TRUE)),
      gt::gt_output(ns("km_table")),
      card_footer(
        "HR from an unstratified Cox proportional hazards model; HR < 1 favours the treatment arm. ",
        "p-values from unstratified log-rank tests vs the reference arm. NE = not estimable."
      )
    )
  )
}

kmServer <- function(id, adtte, colours) {
  moduleServer(id, function(input, output, session) {

    km_data <- reactive({
      req(input$paramcd)
      d <- dplyr::filter(adtte(), PARAMCD == input$paramcd)
      req(nrow(d) > 0)
      dplyr::mutate(d, EVENT = 1 - CNSR, TRT01A = droplevels(TRT01A))   # ADaM CNSR is 1 = censored
    })

    time_label <- reactive(paste0("Time (", tolower(km_data()$AVALU[1]), ")"))

    output$km_plot <- renderPlot({
      p <- ggsurvfit::survfit2(survival::Surv(AVAL, EVENT) ~ TRT01A, data = km_data()) |>
        ggsurvfit::ggsurvfit(linewidth = 0.8) +
        ggsurvfit::add_censor_mark(size = 2) +
        ggsurvfit::add_risktable(risktable_stats = "n.risk", risktable_height = 0.2) +
        ggsurvfit::add_risktable_strata_symbol(symbol = "\u25CF", size = 12) +
        ggsurvfit::scale_ggsurvfit() +                        # 0-100% y-axis, starts at 0
        ggplot2::scale_colour_manual(values = colours) +
        ggplot2::labs(
          title = km_data()$PARAM[1],
          x = time_label(), y = "Probability of no event"
        ) +
        ggplot2::theme(legend.position = "top", plot.title = ggplot2::element_text(face = "bold"))

      if (isTRUE(input$show_median)) {
        p <- p + ggsurvfit::add_quantile(y_value = 0.5, linetype = "dashed", colour = "grey50")
      }
      p
    }, res = 96)

    output$table_title <- renderText(paste("Summary of", km_data()$PARAM[1]))

    output$km_table <- gt::render_gt({
      km_summary(km_data()) |>
        gt::gt() |>
        gt::cols_label(`Median (95% CI)` = paste0("Median (95% CI), ", tolower(km_data()$AVALU[1]))) |>
        gt::cols_align("center", columns = -`Treatment`) |>
        gt::tab_options(table.width = gt::pct(100))
    })
  })
}
