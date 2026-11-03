# ---------------------------------------------------------------------------
# Tab 2: Adverse events (ADAE)
#
# Two views of the most common treatment-emergent AEs:
#   - "Grouped bars": every selected arm side by side
#   - "Butterfly":    two arms back to back, for a direct comparison
# Clicking a bar (or using the dropdown) filters the listing underneath.
#
# SAS equivalent: PROC FREQ on distinct USUBJID*AEDECOD, divide by the ADSL
# N per arm (the "big N"), then SGPLOT HBAR + a PROC REPORT listing.
# ---------------------------------------------------------------------------

aeUI <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header(
        class = "d-flex flex-wrap gap-3 align-items-end",
        tags$strong("Most Common Treatment-Emergent Adverse Events", class = "me-auto"),
        radioButtons(ns("view"), NULL, c("Grouped bars" = "bars", "Butterfly" = "butterfly"), inline = TRUE),
        sliderInput(ns("top_n"), "Top", min = 5, max = 25, value = 10, width = "180px")
      ),
      # Only shown in butterfly view: which two arms to compare
      conditionalPanel(
        condition = "input.view == 'butterfly'", ns = ns,
        layout_columns(
          selectInput(ns("arm_left"), "Left arm", choices = NULL),
          selectInput(ns("arm_right"), "Right arm", choices = NULL)
        )
      ),
      plotly::plotlyOutput(ns("ae_plot"), height = "520px"),
      card_footer("Source: ADAE (TRTEMFL = 'Y'). Subjects counted once per preferred term. Percentages use N per arm from ADSL.")
    ),
    card(
      card_header(
        class = "d-flex flex-wrap gap-3 align-items-end",
        tags$strong("Listing of Treatment-Emergent Adverse Events", class = "me-auto"),
        selectInput(ns("term"), "Preferred term", choices = c("All terms" = ""), width = "320px"),
        actionButton(ns("clear"), "Show all", class = "btn-sm btn-outline-secondary")
      ),
      DT::DTOutput(ns("listing"))
    )
  )
}

aeServer <- function(id, adae, adsl, colours) {
  moduleServer(id, function(input, output, session) {
    plot_source <- session$ns("ae_plot")   # lets us listen for clicks on *this* plot

    # --- 1. Summary: subjects with each term, as % of the arm's N -------------
    ae_summary <- reactive({
      big_n <- dplyr::count(adsl(), TRT01A, name = "N")   # "big N" per arm

      adae() |>
        dplyr::distinct(USUBJID, TRT01A, AEDECOD) |>       # a subject counts once per term
        dplyr::count(TRT01A, AEDECOD, name = "n") |>
        dplyr::left_join(big_n, by = "TRT01A") |>
        dplyr::mutate(pct = 100 * n / N)
    })

    # Most frequent terms overall (across whichever arms are selected)
    top_terms <- reactive({
      req(input$top_n)
      ae_summary() |>
        dplyr::group_by(AEDECOD) |>
        dplyr::summarise(total = sum(n), .groups = "drop") |>
        dplyr::slice_max(total, n = input$top_n, with_ties = FALSE) |>
        dplyr::pull(AEDECOD)
    })

    # --- 2. Keep dropdowns in sync with the data ----------------------------
    observe({
      arms <- as.character(unique(adsl()$TRT01A))
      arms <- intersect(names(colours), arms)              # keep display order
      cur_left  <- isolate(input$arm_left)                 # isolate(): read without re-triggering
      cur_right <- isolate(input$arm_right)
      left  <- if (isTruthy(cur_left)  && cur_left  %in% arms) cur_left  else arms[1]
      right <- if (isTruthy(cur_right) && cur_right %in% arms) cur_right else arms[length(arms)]
      updateSelectInput(session, "arm_left",  choices = arms, selected = left)
      updateSelectInput(session, "arm_right", choices = arms, selected = right)
    })

    observe({
      terms <- sort(unique(adae()$AEDECOD))
      current <- isolate(input$term)
      keep <- if (isTruthy(current) && current %in% terms) current else ""   # isTruthy: not NULL/""
      updateSelectInput(session, "term", choices = c("All terms" = "", terms), selected = keep)
    })

    # --- 3. The chart --------------------------------------------------------
    output$ae_plot <- plotly::renderPlotly({
      req(nrow(ae_summary()) > 0)
      d <- dplyr::filter(ae_summary(), AEDECOD %in% top_terms())

      if (input$view == "butterfly") {
        req(input$arm_left, input$arm_right, input$arm_left != input$arm_right)
        d <- d |>
          dplyr::filter(TRT01A %in% c(input$arm_left, input$arm_right)) |>
          dplyr::mutate(x = ifelse(TRT01A == input$arm_left, -pct, pct))   # left arm goes negative
        req(nrow(d) > 0)
        lim <- max(abs(d$x)) * 1.1

        p <- ggplot2::ggplot(d, ggplot2::aes(
          x = x, y = stats::reorder(AEDECOD, pct, FUN = sum), fill = TRT01A, key = AEDECOD,
          text = paste0(AEDECOD, "<br>", TRT01A, ": ", n, "/", N, " (", round(pct, 1), "%)")
        )) +
          ggplot2::geom_col(width = 0.7) +
          ggplot2::geom_vline(xintercept = 0, colour = "grey40") +
          ggplot2::scale_x_continuous(limits = c(-lim, lim), labels = function(v) paste0(abs(v), "%")) +
          ggplot2::labs(x = paste0("\u2190 ", input$arm_left, "   |   ", input$arm_right, " \u2192"))
      } else {
        p <- ggplot2::ggplot(d, ggplot2::aes(
          x = pct, y = stats::reorder(AEDECOD, pct, FUN = sum), fill = TRT01A, key = AEDECOD,
          text = paste0(AEDECOD, "<br>", TRT01A, ": ", n, "/", N, " (", round(pct, 1), "%)")
        )) +
          ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.8), width = 0.75) +
          ggplot2::scale_x_continuous(labels = function(v) paste0(v, "%")) +
          ggplot2::labs(x = "Subjects with event (%)")
      }

      p <- p +
        ggplot2::scale_fill_manual(values = colours, drop = TRUE) +
        ggplot2::labs(y = NULL, fill = NULL) +
        ggplot2::theme_minimal(base_size = 12) +
        ggplot2::theme(legend.position = "top")

      plotly::ggplotly(p, tooltip = "text", source = plot_source) |>
        plotly::layout(legend = list(orientation = "h", y = 1.08)) |>
        plotly::event_register("plotly_click")
    })

    # --- 4. Click a bar -> filter the listing -------------------------------
    # (suppressWarnings: plotly warns if we listen before the plot has been drawn)
    clicked <- reactive(suppressWarnings(plotly::event_data("plotly_click", source = plot_source)))
    observeEvent(clicked(), {
      click <- clicked()
      if (!is.null(click$key)) updateSelectInput(session, "term", selected = click$key[[1]])
    })
    observeEvent(input$clear, updateSelectInput(session, "term", selected = ""))

    # --- 5. The listing ------------------------------------------------------
    listing_data <- reactive({
      d <- adae()
      if (isTruthy(input$term)) d <- dplyr::filter(d, AEDECOD == input$term)
      d |>
        dplyr::arrange(TRT01A, USUBJID, AEBODSYS, AEDECOD) |>
        dplyr::select(
          `Subject` = USUBJID, `Treatment` = TRT01A, `System organ class` = AEBODSYS,
          `Preferred term` = AEDECOD, `Severity` = AESEV, `Serious` = AESER
        )
    })

    output$listing <- DT::renderDT({
      DT::datatable(
        listing_data(), rownames = FALSE, filter = "top",
        options = list(pageLength = 10, scrollX = TRUE)
      )
    })
  })
}
