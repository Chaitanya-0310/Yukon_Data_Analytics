# ============================================================================
# 01_exploration.R — Exploratory Data Analysis
# ============================================================================
# Purpose: Load the linked health dataset (output from Python pipeline),
#          explore structure, distributions, and Yukon-specific patterns.
#
# Input:   data/processed/linked_health.parquet
# Output:  outputs/figures/exploration_*.png
#
# Packages needed: arrow, tidyverse, ggplot2
# Install once: install.packages(c("arrow", "tidyverse"))
# ============================================================================

library(arrow)
library(tidyverse)

# --- Load the linked dataset from the Python pipeline ---
data_path <- file.path("..", "data", "processed", "linked_health.parquet")
health <- read_parquet(data_path)

cat("Dataset loaded:", nrow(health), "rows,", ncol(health), "columns\n")
cat("Columns:", paste(names(health), collapse = ", "), "\n\n")

# --- Basic structure inspection ---
str(health)
summary(health)

# --- Check which provinces and years we have ---
cat("\nProvinces in dataset:\n")
print(table(health$prov_code))

cat("\nYears in dataset:\n")
print(table(health$fiscal_year))

cat("\nIndicators in dataset:\n")
print(table(health$indicator))

# --- Filter to Yukon specifically ---
yukon <- health %>%
  filter(prov_code == "YT")

cat("\nYukon data:", nrow(yukon), "rows\n")
cat("Yukon years:", paste(sort(unique(yukon$fiscal_year)), collapse = ", "), "\n")

# --- Create output directory ---
fig_dir <- file.path("..", "outputs", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# --- Plot 1: Data coverage heatmap (province × year) ---
# Shows which province-year combinations have data
coverage <- health %>%
  distinct(prov_code, fiscal_year) %>%
  mutate(has_data = 1)

p1 <- ggplot(coverage, aes(x = fiscal_year, y = prov_code, fill = factor(has_data))) +
  geom_tile(color = "white", linewidth = 0.5) +
  scale_fill_manual(values = c("1" = "#2563EB"), guide = "none") +
  labs(
    title = "Data Coverage by Province/Territory and Year",
    subtitle = "Blue cells indicate available data",
    x = "Fiscal Year",
    y = "Province/Territory"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid = element_blank()
  )

ggsave(file.path(fig_dir, "exploration_coverage.png"), p1, width = 10, height = 6, dpi = 150)
cat("Saved: exploration_coverage.png\n")

# --- Plot 2: Yukon vs National overview ---
# If we have rate columns, compare Yukon to Canada
rate_cols <- names(health)[grepl("rate_per", names(health))]

if (length(rate_cols) > 0) {
  rate_col <- rate_cols[1]  # Use the first rate column found

  comparison <- health %>%
    filter(prov_code %in% c("YT", "CA")) %>%
    select(prov_code, fiscal_year, indicator, all_of(rate_col)) %>%
    drop_na()

  if (nrow(comparison) > 0) {
    p2 <- ggplot(comparison, aes(x = fiscal_year, y = .data[[rate_col]],
                                  color = prov_code, group = prov_code)) +
      geom_line(linewidth = 1) +
      geom_point(size = 2) +
      scale_color_manual(
        values = c("YT" = "#DC2626", "CA" = "#6B7280"),
        labels = c("YT" = "Yukon", "CA" = "Canada")
      ) +
      labs(
        title = "Yukon vs National Rate Comparison",
        subtitle = paste("Indicator:", rate_col),
        x = "Fiscal Year",
        y = "Rate per 100,000 population",
        color = "Jurisdiction"
      ) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom")

    ggsave(file.path(fig_dir, "exploration_yukon_vs_national.png"),
           p2, width = 10, height = 6, dpi = 150)
    cat("Saved: exploration_yukon_vs_national.png\n")
  }
}

# --- Plot 3: Distribution of values by territory ---
# Compare the three territories: Yukon, NWT, Nunavut
territories <- health %>%
  filter(prov_code %in% c("YT", "NT", "NU"))

if (nrow(territories) > 0 && length(rate_cols) > 0) {
  p3 <- ggplot(territories, aes(x = prov_code, y = .data[[rate_cols[1]]],
                                  fill = prov_code)) +
    geom_boxplot(alpha = 0.7) +
    scale_fill_manual(
      values = c("YT" = "#DC2626", "NT" = "#2563EB", "NU" = "#059669"),
      guide = "none"
    ) +
    labs(
      title = "Health Indicator Distribution Across Northern Territories",
      x = "Territory",
      y = "Rate per 100,000 population"
    ) +
    theme_minimal(base_size = 12)

  ggsave(file.path(fig_dir, "exploration_territories.png"),
         p3, width = 8, height = 6, dpi = 150)
  cat("Saved: exploration_territories.png\n")
}

cat("\n--- Exploration complete ---\n")
