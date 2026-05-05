# Yukon Population Health Analytics Dashboard

An end-to-end population health analytics platform built as a portfolio project for the Government of Yukon **Data Scientist — PPHEE Branch** position (#15512).

Transforms raw federal health data from three agencies into a Streamlit dashboard with 7 analytical pages, 53+ derived KPIs, statistical outbreak detection, ML forecasting, and a fully automated dbt data pipeline.

---

## Live Demo

> Run locally — see [Setup](#setup) below.

---

## Tech Stack

| Layer              | Technology                               |
| ------------------ | ---------------------------------------- |
| **Storage**        | PostgreSQL via Supabase                  |
| **Transformation** | dbt-core (17 models, 73 automated tests) |
| **Dashboard**      | Streamlit + Plotly                       |
| **Forecasting**    | statsmodels (ETS / Holt-Winters)         |
| **Language**       | Python 3.8+                              |
| **Data Sources**   | CIHI, PHAC, Statistics Canada            |

---

## Architecture

```
Raw CSVs (federal agencies)
    │
    ▼
Supabase PostgreSQL (raw schema)
    │
    ▼
dbt Staging (6 models)          — clean, standardize, map province codes
    │
    ▼
dbt Intermediate (6 models)     — YoY change, rolling averages, national gap, CI, rankings
    │
    ▼
dbt Marts (5 models)            — dashboard-ready, one mart per page
    │
    ▼
Streamlit Dashboard (7 pages)   — interactive analytics
```

**17 models | 78 automated tests (73 schema + 5 singular) | 5 indicator domains | 53+ KPIs**

---

## Dashboard Pages

### 1. Yukon at a Glance
Headline KPIs across all 5 indicator domains. Metric cards with YoY change, confidence interval badges, national comparison, and traffic light trend indicators.

### 2. Provincial Comparison
Bar chart rankings across all 13 provinces/territories for ACSC, Mental Health, and Diabetes indicators. Yukon highlighted, burden category classification (High/Moderate/Low), region group comparisons.

### 3. Substance Use Harms
Opioid and stimulant harm monitoring with emergency period context (Yukon declared Substance Use Health Emergency: January 20, 2022). Area charts, severity ratio bars, pre/post-emergency comparison, and provincial heatmap.

### 4. Communicable Disease
Statistical outbreak detection dashboard for 5 diseases (Chlamydia, Gonorrhea, Infectious Syphilis, Giardiasis, Salmonellosis). National time series with z-score alarm, Canadian choropleth map, outbreak status panel, disease burden rankings.

### 5. Trend Analysis
Time series for Yukon vs Northwest Territories vs Nunavut vs Canada for ACSC and Mental Health indicators. 95% CI error bands, convergence analysis, and **ML forecast** (ETS / Holt-Winters with 80% and 95% prediction intervals).

### 6. Executive Summary
Auto-generated findings from live data across all 5 domains. Traffic light status table, key alert banners, and data source/methodology notes.

### 7. Data Quality & Methodology
Pipeline architecture, data source provenance, automated test summary, data handling notes (suppression rules, CI methodology, year-type handling), and reproducibility commands.

---

## Data Sources

| Agency                | Dataset             | Indicator                                    | Coverage                           |
| --------------------- | ------------------- | -------------------------------------------- | ---------------------------------- |
| **CIHI**              | Your Health System  | ACSC Hospitalizations (age-standardized)     | 2013–2024, all P/T                 |
| **CIHI**              | Your Health System  | 30-Day MH Readmissions (risk-adjusted)       | 2015–2025, all P/T                 |
| **PHAC**              | CCDSS Data Tool     | Diabetes Incidence (age-standardized)        | 2000–2024, all P/T                 |
| **PHAC**              | Health Infobase     | Opioid & Stimulant Harms (crude)             | 2016–2025, all P/T                 |
| **PHAC**              | CNDSS               | Communicable Disease — STI & Enteric (crude) | 2000–2023, national + PT snapshots |
| **Statistics Canada** | Table 17-10-0005-01 | Population Estimates                         | 1971–2024, all P/T                 |

All data released under Open Government licences (CIHI, Government of Canada, Statistics Canada).

---

## Key Features

### Statistical Rigour
- **CI-based national comparison** — Yukon is flagged as "Significantly Above National" only when its rate falls outside the source agency's published 95% CI bounds (not just a point-to-point comparison)
- **Tiwari modified gamma CIs** for age-standardized rates (CIHI methodology)
- **Wilson score CIs** for proportions (MH readmissions)
- **5-year central moving average** matching Yukon Health Status Report (2022–2024) methodology

### Outbreak Detection
Statistical process control (SPC) alarm for communicable diseases:
```
Z-score = (current rate − 5yr central mean) ÷ 5yr central SD
Z ≥ 2.0  →  Outbreak Detected
Z ≥ 3.0  →  Severe Outbreak
```
Implemented as a reusable dbt macro (`outbreak_signal`).

### ML Forecasting
3-year forecast on Trend Analysis page with cascading fallback:
1. **ETS** (Holt-Winters, additive trend) — primary model
2. **ARIMA(1,1,0)** — fallback if ETS fails
3. **Linear extrapolation** — fallback of last resort

Outputs 80% and 95% prediction intervals displayed as shaded bands.

### Data Integrity
- **Unified suppression flag** (`is_suppressed`) across all models — CIHI suppresses counts < 5 PHAC suppresses counts < 10 or CV > 33.3%
- **Year-type tracking** — CIHI uses fiscal years (Apr–Mar) PHAC uses calendar years (Jan–Dec) mismatch is explicitly flagged with `cross_year_type_join_flag`
- **Remote access caveat** on Yukon diabetes data — CCDSS relies on physician billing underdiagnosis in remote communities means the rate is a floor estimate, not confirmed lower burden
- **78 automated dbt tests** (73 schema + 5 singular) including domain range checks, uniqueness assertions, and `assert_yukon_present_in_all_marts`

---

## dbt Model Inventory

Data Lineage 

<img width="1845" height="930" alt="image" src="https://github.com/user-attachments/assets/6aa312b4-e046-4340-8f6b-77a03a64d953" />


```
staging/ (6 models)
├── stg_cihi__acsc
├── stg_cihi__mental_health_readmissions
├── stg_phac__ccdss_diabetes
├── stg_phac__substance_harms
├── stg_phac__cndss
└── stg_statscan__population

intermediate/ (6 models)
├── int_health__indicators_with_population
├── int_health__year_over_year
├── int_mental_health__enriched
├── int_diabetes__enriched
├── int_substance__enriched
└── int_communicable__enriched

marts/ (5 models)
├── mart_dashboard__yukon_overview
├── mart_dashboard__provincial_comparison
├── mart_dashboard__trend_analysis
├── mart_dashboard__substance_harms
└── mart_dashboard__communicable_disease

macros/ (1 custom)
└── outbreak_signal.sql

tests/ (5 singular)
├── assert_yukon_present_in_all_marts
├── assert_acsc_rate_in_valid_range
├── assert_mh_readmission_rate_is_percentage
├── assert_substance_rate_not_negative
└── assert_is_latest_is_unique
```

---

## Setup

### Prerequisites
- Python 3.8+
- A Supabase project (PostgreSQL)
- dbt-postgres

### 1. Clone and install dependencies

```bash
git clone <repo-url>
cd DataProject
pip install -r requirements.txt
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env with your Supabase credentials:
# SUPABASE_HOST, SUPABASE_PORT, SUPABASE_DB, SUPABASE_USER, SUPABASE_PASSWORD
```

### 3. Load raw data to Supabase

```bash
python pipeline/load_to_supabase.py
```

### 4. Build the dbt pipeline

```bash
# Run all 17 models
python run_dbt.py run

# Run all 73 tests
python run_dbt.py test

# (Optional) Generate dbt docs
python run_dbt.py docs generate
```

### 5. Launch the dashboard

```bash
streamlit run dashboard/app.py
```

The dashboard will open at `http://localhost:8501`.

---

## Project Structure

```
DataProject/
├── dashboard/
│   └── app.py                  # Streamlit dashboard (7 pages)
├── dbt_project/
│   ├── models/
│   │   ├── staging/            # 6 staging models
│   │   ├── intermediate/       # 6 intermediate models
│   │   └── marts/              # 5 mart models
│   ├── macros/
│   │   └── outbreak_signal.sql # Reusable SPC macro
│   └── tests/                  # Singular tests
├── pipeline/
│   └── load_to_supabase.py     # Raw data loader
├── docs/
│   └── INTERVIEW_KPI_PREP.md   # KPI documentation
├── data/                       # Raw CSV files
├── requirements.txt
├── run_dbt.py                  # dbt runner wrapper
└── KPI_CATALOG.md              # Full KPI reference
```

---

## Key Analytical Decisions

**Why age-standardized rates?**
Yukon has a different age distribution than Ontario. Raw counts would make territories with younger populations look healthier. Age standardization (reference: 2011 Canadian population) makes all jurisdictions comparable.

**Why CI-based national comparison instead of percentage thresholds?**
A hardcoded ±50 per 100k threshold treats a 50-unit gap identically whether it's in Ontario (15M people, small uncertainty) or Yukon (43k people, large uncertainty). Using the source agency's confidence interval means we only flag statistically meaningful differences.

**Why a 3-year trailing average for substance harms (vs 5-year central for others)?**
Substance harms data only goes back to ~2016 (~9 years). A 5-year central window would lose the 2 most recent years — unacceptable for monitoring an active health emergency. The 3-year trailing average preserves current data while still smoothing year-to-year volatility.

---

## Yukon Context

- **Population:** ~43,000 (2023 Statistics Canada)
- **Health Authority:** Yukon Health and Social Services
- **Substance Use Health Emergency declared:** January 20, 2022
- **Geographic challenge:** 22 communities, many accessible only by air and low physician-to-population ratio
- **Data note:** Small population means individual-year rates are volatile, confidence intervals are wide and some values are suppressed for privacy

---

## Author

**Chaitanya Panchal**
Data Engineer | Python · SQL · dbt · Streamlit · Plotly · PostgreSQL(Supabase)


