# ============================================================================
# 03_forecasting.R — Time Series Forecasting
# ============================================================================
# Purpose: Build a time series forecast for Yukon's health indicator rate,
#          projecting 2-3 years forward with confidence intervals.
#
# Input:   data/processed/linked_health.parquet
# Output:  outputs/figures/forecast_*.png
#          outputs/figures/forecast_data.csv
#
# Packages: arrow, tidyverse, forecast
# Install once: install.packages(c("arrow", "tidyverse", "forecast"))
# ============================================================================

library(arrow)
library(tidyverse)
library(forecast)

# --- Load data ---
health <- read_parquet(file.path("..", "data", "processed", "linked_health.parquet"))
fig_dir <- file.path("..", "outputs", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

rate_cols <- names(health)[grepl("rate_per", names(health))]
rate_col <- rate_cols[1]
cat("Forecasting column:", rate_col, "\n")

# --- Prepare Yukon time series ---
yukon_ts <- health %>%
  filter(prov_code == "YT") %>%
  select(fiscal_year, all_of(rate_col)) %>%
  drop_na() %>%
  arrange(fiscal_year) %>%
  # If multiple rows per year (multiple indicators), take the mean
  group_by(fiscal_year) %>%
  summarise(rate = mean(.data[[rate_col]], na.rm = TRUE), .groups = "drop")

cat("Yukon time series:", nrow(yukon_ts), "data points\n")
cat("Years:", paste(yukon_ts$fiscal_year, collapse = ", "), "\n")
cat("Rates:", paste(round(yukon_ts$rate, 1), collapse = ", "), "\n\n")

if (nrow(yukon_ts) < 5) {
  cat("WARNING: Fewer than 5 data points — forecast will have wide intervals.\n")
  cat("This is expected for small jurisdictions like Yukon.\n\n")
}

# --- Also get national trend for comparison ---
national_ts <- health %>%
  filter(prov_code == "CA") %>%
  select(fiscal_year, all_of(rate_col)) %>%
  drop_na() %>%
  arrange(fiscal_year) %>%
  group_by(fiscal_year) %>%
  summarise(rate = mean(.data[[rate_col]], na.rm = TRUE), .groups = "drop")

# --- Convert to ts object ---
start_year <- min(yukon_ts$fiscal_year)
yt_ts <- ts(yukon_ts$rate, start = start_year, frequency = 1)

# --- Fit ETS (Exponential Smoothing) model ---
# ETS works well with short time series and annual data.
# For a series this short, simple methods outperform complex ones.
fit_ets <- ets(yt_ts)
cat("ETS model selected:", fit_ets$method, "\n")
print(summary(fit_ets))

# --- Forecast 3 years ahead ---
h <- 3  # forecast horizon
fc_ets <- forecast(fit_ets, h = h)

cat("\nForecast (ETS):\n")
print(fc_ets)

# --- Also fit a simple linear trend for comparison ---
yukon_ts$year_idx <- yukon_ts$fiscal_year - start_year
fit_lm <- lm(rate ~ year_idx, data = yukon_ts)

cat("\nLinear trend model:\n")
print(summary(fit_lm))

future_years <- data.frame(
  year_idx = (max(yukon_ts$year_idx) + 1):(max(yukon_ts$year_idx) + h)
)
lm_pred <- predict(fit_lm, newdata = future_years, interval = "prediction", level = 0.95)

# --- Build forecast data frame ---
forecast_years <- (max(yukon_ts$fiscal_year) + 1):(max(yukon_ts$fiscal_year) + h)

forecast_df <- data.frame(
  fiscal_year = forecast_years,
  ets_forecast = as.numeric(fc_ets$mean),
  ets_lower_80 = as.numeric(fc_ets$lower[, 1]),
  ets_upper_80 = as.numeric(fc_ets$upper[, 1]),
  ets_lower_95 = as.numeric(fc_ets$lower[, 2]),
  ets_upper_95 = as.numeric(fc_ets$upper[, 2]),
  linear_forecast = lm_pred[, "fit"],
  linear_lower_95 = lm_pred[, "lwr"],
  linear_upper_95 = lm_pred[, "upr"]
)

cat("\nForecast data:\n")
print(forecast_df)

write_csv(forecast_df, file.path(fig_dir, "forecast_data.csv"))
cat("Saved: forecast_data.csv\n")

# ============================================================================
# PLOT 1: ETS Forecast with confidence intervals
# ============================================================================

# Combine historical and forecast for plotting
historical <- data.frame(
  fiscal_year = yukon_ts$fiscal_year,
  rate = yukon_ts$rate,
  type = "Historical"
)

forecast_plot <- data.frame(
  fiscal_year = forecast_years,
  rate = forecast_df$ets_forecast,
  type = "Forecast"
)

all_points <- bind_rows(historical, forecast_plot)

p1 <- ggplot() +
  # 95% CI band
  geom_ribbon(
    data = forecast_df,
    aes(x = fiscal_year, ymin = ets_lower_95, ymax = ets_upper_95),
    fill = "#DC2626", alpha = 0.1
  ) +
  # 80% CI band
  geom_ribbon(
    data = forecast_df,
    aes(x = fiscal_year, ymin = ets_lower_80, ymax = ets_upper_80),
    fill = "#DC2626", alpha = 0.2
  ) +
  # Historical line
  geom_line(
    data = historical,
    aes(x = fiscal_year, y = rate),
    color = "#DC2626", linewidth = 1.2
  ) +
  geom_point(
    data = historical,
    aes(x = fiscal_year, y = rate),
    color = "#DC2626", size = 2.5
  ) +
  # Forecast line
  geom_line(
    data = forecast_plot,
    aes(x = fiscal_year, y = rate),
    color = "#DC2626", linewidth = 1.2, linetype = "dashed"
  ) +
  geom_point(
    data = forecast_plot,
    aes(x = fiscal_year, y = rate),
    color = "#DC2626", size = 2.5, shape = 17
  ) +
  # National average for context
  geom_line(
    data = national_ts,
    aes(x = fiscal_year, y = rate),
    color = "#6B7280", linewidth = 0.8, alpha = 0.7
  ) +
  # Dividing line between historical and forecast
  geom_vline(
    xintercept = max(yukon_ts$fiscal_year) + 0.5,
    linetype = "dotted", color = "#9CA3AF"
  ) +
  annotate("text",
    x = max(yukon_ts$fiscal_year) + 0.6, y = max(yukon_ts$rate, na.rm = TRUE),
    label = "Forecast →", hjust = 0, size = 3.5, color = "#9CA3AF"
  ) +
  labs(
    title = "Yukon Health Indicator Forecast",
    subtitle = paste0(
      fit_ets$method, " model — ",
      h, "-year projection with 80% and 95% confidence intervals\n",
      "Grey line: national average for context"
    ),
    x = "Fiscal Year",
    y = "Rate per 100,000 population"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

ggsave(file.path(fig_dir, "forecast_yukon.png"),
       p1, width = 11, height = 6, dpi = 150)
cat("Saved: forecast_yukon.png\n")

# ============================================================================
# PLOT 2: Model comparison (ETS vs Linear)
# ============================================================================

p2 <- ggplot() +
  geom_point(
    data = historical,
    aes(x = fiscal_year, y = rate),
    color = "#374151", size = 2.5
  ) +
  # ETS forecast
  geom_line(
    data = forecast_df,
    aes(x = fiscal_year, y = ets_forecast),
    color = "#DC2626", linewidth = 1, linetype = "dashed"
  ) +
  geom_ribbon(
    data = forecast_df,
    aes(x = fiscal_year, ymin = ets_lower_95, ymax = ets_upper_95),
    fill = "#DC2626", alpha = 0.1
  ) +
  # Linear forecast
  geom_line(
    data = forecast_df,
    aes(x = fiscal_year, y = linear_forecast),
    color = "#2563EB", linewidth = 1, linetype = "dashed"
  ) +
  geom_ribbon(
    data = forecast_df,
    aes(x = fiscal_year, ymin = linear_lower_95, ymax = linear_upper_95),
    fill = "#2563EB", alpha = 0.1
  ) +
  geom_vline(
    xintercept = max(yukon_ts$fiscal_year) + 0.5,
    linetype = "dotted", color = "#9CA3AF"
  ) +
  labs(
    title = "Forecast Model Comparison",
    subtitle = "Red: ETS (exponential smoothing)  |  Blue: Linear trend",
    x = "Fiscal Year",
    y = "Rate per 100,000 population"
  ) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(fig_dir, "forecast_comparison.png"),
       p2, width = 11, height = 6, dpi = 150)
cat("Saved: forecast_comparison.png\n")

# ============================================================================
# Summary statistics for README / email
# ============================================================================

cat("\n============================================\n")
cat("KEY FINDINGS FOR README / EMAIL\n")
cat("============================================\n")

yt_latest <- tail(yukon_ts, 1)
ca_latest <- tail(national_ts, 1)

if (nrow(ca_latest) > 0) {
  cat(sprintf(
    "Latest year (%d): Yukon rate = %.1f, National rate = %.1f (gap: %.1f)\n",
    yt_latest$fiscal_year, yt_latest$rate, ca_latest$rate,
    yt_latest$rate - ca_latest$rate
  ))
}

cat(sprintf(
  "Forecast (%d): %.1f [95%% CI: %.1f–%.1f]\n",
  max(forecast_years), tail(forecast_df$ets_forecast, 1),
  tail(forecast_df$ets_lower_95, 1), tail(forecast_df$ets_upper_95, 1)
))

trend_direction <- ifelse(coef(fit_lm)["year_idx"] > 0, "increasing", "decreasing")
cat(sprintf(
  "Linear trend: %s at %.2f per year (p = %.4f)\n",
  trend_direction, coef(fit_lm)["year_idx"],
  summary(fit_lm)$coefficients["year_idx", "Pr(>|t|)"]
))

cat("\n--- Forecasting complete ---\n")
