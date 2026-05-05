# ============================================================================
# 02_trend_analysis.R — Trend Analysis & Regression
# ============================================================================
# Purpose: Analyze Yukon's PAH rate trend vs national average,
#          run comparative analysis across jurisdictions,
#          and fit regression models for demographic predictors.
#
# Input:   data/processed/linked_health.parquet
# Output:  outputs/figures/trend_*.png
#
# Packages: arrow, tidyverse, broom (for tidy model output)
# Install once: install.packages(c("arrow", "tidyverse", "broom"))
# ============================================================================

library(arrow)
library(tidyverse)
library(broom)

# --- Load data ---
health <- read_parquet(file.path("..", "data", "processed", "linked_health.parquet"))
fig_dir <- file.path("..", "outputs", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

rate_cols <- names(health)[grepl("rate_per", names(health))]

if (length(rate_cols) == 0) {
  stop("No rate columns found — check that the Python pipeline calculated rates.")
}

rate_col <- rate_cols[1]
cat("Using rate column:", rate_col, "\n")

# ============================================================================
# ANALYSIS 1: Yukon PAH trend over time vs national average
# ============================================================================

trend_data <- health %>%
  filter(prov_code %in% c("YT", "CA")) %>%
  select(prov_code, prov_name, fiscal_year, all_of(rate_col)) %>%
  drop_na() %>%
  arrange(prov_code, fiscal_year)

cat("\nTrend data points:\n")
print(trend_data %>% count(prov_code))

# Calculate the gap between Yukon and national rate
if (nrow(trend_data) > 0) {
  gap_data <- trend_data %>%
    select(prov_code, fiscal_year, all_of(rate_col)) %>%
    pivot_wider(names_from = prov_code, values_from = all_of(rate_col)) %>%
    mutate(gap = YT - CA)

  cat("\nYukon-National gap over time:\n")
  print(gap_data)

  # Trend plot with gap shading
  p1 <- ggplot(trend_data, aes(x = fiscal_year, y = .data[[rate_col]],
                                color = prov_code)) +
    geom_line(linewidth = 1.2) +
    geom_point(size = 2.5) +
    geom_ribbon(
      data = gap_data,
      aes(x = fiscal_year, ymin = CA, ymax = YT),
      inherit.aes = FALSE,
      fill = "#DC2626", alpha = 0.1
    ) +
    scale_color_manual(
      values = c("YT" = "#DC2626", "CA" = "#374151"),
      labels = c("YT" = "Yukon", "CA" = "Canada (national)")
    ) +
    labs(
      title = "Yukon vs National Health Indicator Trend",
      subtitle = "Shaded area shows the Yukon-national gap",
      x = "Fiscal Year",
      y = "Rate per 100,000 population",
      color = "Jurisdiction"
    ) +
    theme_minimal(base_size = 13) +
    theme(
      legend.position = "bottom",
      plot.title = element_text(face = "bold"),
      panel.grid.minor = element_blank()
    )

  ggsave(file.path(fig_dir, "trend_yukon_vs_national.png"),
         p1, width = 10, height = 6, dpi = 150)
  cat("Saved: trend_yukon_vs_national.png\n")
}

# ============================================================================
# ANALYSIS 2: Territorial comparison — Yukon vs NWT vs Nunavut
# ============================================================================

territories <- health %>%
  filter(prov_code %in% c("YT", "NT", "NU")) %>%
  select(prov_code, prov_name, fiscal_year, all_of(rate_col)) %>%
  drop_na()

if (nrow(territories) > 0) {
  p2 <- ggplot(territories, aes(x = fiscal_year, y = .data[[rate_col]],
                                  color = prov_code)) +
    geom_line(linewidth = 1) +
    geom_point(size = 2) +
    scale_color_manual(
      values = c("YT" = "#DC2626", "NT" = "#2563EB", "NU" = "#059669"),
      labels = c("YT" = "Yukon", "NT" = "NWT", "NU" = "Nunavut")
    ) +
    labs(
      title = "Northern Territories Health Indicator Comparison",
      subtitle = "Yukon, Northwest Territories, and Nunavut",
      x = "Fiscal Year",
      y = "Rate per 100,000 population",
      color = "Territory"
    ) +
    theme_minimal(base_size = 13) +
    theme(legend.position = "bottom", plot.title = element_text(face = "bold"))

  ggsave(file.path(fig_dir, "trend_territories.png"),
         p2, width = 10, height = 6, dpi = 150)
  cat("Saved: trend_territories.png\n")
}

# ============================================================================
# ANALYSIS 3: National ranking — where does Yukon sit?
# ============================================================================

latest_year <- max(health$fiscal_year, na.rm = TRUE)

ranking <- health %>%
  filter(fiscal_year == latest_year, prov_code != "CA") %>%
  select(prov_code, prov_name, all_of(rate_col)) %>%
  drop_na() %>%
  arrange(desc(.data[[rate_col]])) %>%
  mutate(
    rank = row_number(),
    is_yukon = prov_code == "YT"
  )

cat("\nNational ranking (latest year:", latest_year, "):\n")
print(ranking)

if (nrow(ranking) > 0) {
  p3 <- ggplot(ranking, aes(x = reorder(prov_code, .data[[rate_col]]),
                              y = .data[[rate_col]],
                              fill = is_yukon)) +
    geom_col(width = 0.7) +
    geom_text(aes(label = round(.data[[rate_col]], 1)),
              hjust = -0.1, size = 3.5) +
    coord_flip() +
    scale_fill_manual(values = c("TRUE" = "#DC2626", "FALSE" = "#D1D5DB"), guide = "none") +
    labs(
      title = paste("Provincial/Territorial Ranking —", latest_year),
      subtitle = "Yukon highlighted in red",
      x = "",
      y = "Rate per 100,000 population"
    ) +
    theme_minimal(base_size = 13) +
    theme(
      plot.title = element_text(face = "bold"),
      panel.grid.major.y = element_blank()
    ) +
    expand_limits(y = max(ranking[[rate_col]], na.rm = TRUE) * 1.15)

  ggsave(file.path(fig_dir, "trend_ranking.png"),
         p3, width = 10, height = 7, dpi = 150)
  cat("Saved: trend_ranking.png\n")
}

# ============================================================================
# ANALYSIS 4: Linear regression — what predicts the rate?
# ============================================================================

# Fit a simple model: rate ~ population + fiscal_year + territory_flag
model_data <- health %>%
  filter(prov_code != "CA") %>%
  select(prov_code, fiscal_year, all_of(rate_col), population) %>%
  drop_na() %>%
  mutate(
    is_territory = prov_code %in% c("YT", "NT", "NU"),
    is_yukon = prov_code == "YT"
  )

if (nrow(model_data) > 10) {
  model <- lm(
    as.formula(paste(rate_col, "~ fiscal_year + population + is_territory")),
    data = model_data
  )

  cat("\n--- Regression Results ---\n")
  print(summary(model))

  tidy_results <- tidy(model, conf.int = TRUE)
  cat("\nTidy coefficients:\n")
  print(tidy_results)

  # Save regression summary
  write_csv(tidy_results, file.path(fig_dir, "regression_coefficients.csv"))
  cat("Saved: regression_coefficients.csv\n")

  # Coefficient plot
  p4 <- ggplot(
    tidy_results %>% filter(term != "(Intercept)"),
    aes(x = term, y = estimate, ymin = conf.low, ymax = conf.high)
  ) +
    geom_pointrange(color = "#2563EB", linewidth = 0.8) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "#9CA3AF") +
    coord_flip() +
    labs(
      title = "Regression Coefficients — Predictors of Health Rate",
      subtitle = "95% confidence intervals shown; dashed line = zero effect",
      x = "",
      y = "Coefficient Estimate"
    ) +
    theme_minimal(base_size = 13) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(fig_dir, "trend_regression.png"),
         p4, width = 10, height = 5, dpi = 150)
  cat("Saved: trend_regression.png\n")
}

cat("\n--- Trend analysis complete ---\n")
