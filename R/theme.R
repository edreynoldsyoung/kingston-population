# theme.R
# Colors and ggplot themes shared by every chart in the report.

# Okabe & Ito (2008) colour-blind-safe palette
okabe_ito <- c(
  orange     = "#E69F00",
  skyblue    = "#56B4E9",
  green      = "#009E73",
  yellow     = "#F0E442",
  blue       = "#0072B2",
  vermillion = "#D55E00",
  purple     = "#CC79A7",
  black      = "#000000"
)

theme_kingston <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background    = element_rect(fill = "linen", colour = NA),
      panel.background   = element_rect(fill = "linen", colour = NA),
      legend.background  = element_rect(fill = "linen", colour = NA),
      plot.title         = element_text(face = "bold", size = rel(1.3)),
      plot.title.position = "plot",
      plot.caption       = element_text(colour = "grey35", hjust = 0),
      plot.caption.position = "plot",
      panel.grid.minor   = element_blank(),
      strip.text         = element_text(face = "bold", hjust = 0),
      legend.position    = "bottom"
    )
}

theme_kingston_map <- function(base_size = 11) {
  theme_kingston(base_size) +
    theme(
      axis.text  = element_blank(),
      axis.title = element_blank(),
      panel.grid = element_blank()
    )
}

# Label helpers for tables
fmt_count <- function(x) ifelse(is.na(x), "", scales::comma(x, accuracy = 1))
fmt_rate  <- function(x, digits = 2) ifelse(is.na(x), "", sprintf(paste0("%+.", digits, "f%%"), x))
fmt_share <- function(x) ifelse(is.na(x), "", scales::percent(x, accuracy = 0.1))
fmt_money <- function(x) ifelse(is.na(x), "", scales::dollar(x, accuracy = 1))

# "2020-2024" style label for an ACS 5-year period ending in end_year
period_label <- function(end_year) paste0(end_year - 4, "-", end_year)
