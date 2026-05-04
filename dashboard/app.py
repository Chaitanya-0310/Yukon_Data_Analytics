"""
Streamlit dashboard — Yukon Health System Performance Analytics

Reads from Supabase (PostgreSQL) mart tables built by dbt:
  - mart_dashboard__yukon_overview  (3 indicators for Yukon)
  - mart_dashboard__provincial_comparison  (all provinces, 3 indicators)
  - mart_dashboard__trend_analysis  (time series, 3 indicators)
  - mart_dashboard__substance_harms  (opioid/stimulant harms, all provinces)
  - mart_dashboard__communicable_disease  (STI & enteric disease surveillance)

Indicators:
  1. ACSC Hospitalizations (CIHI) — avoidable hospitalizations per 100k
  2. Mental Health Readmissions (CIHI) — 30-day readmission rate %
  3. Diabetes Incidence (PHAC CCDSS) — new cases per 100k
  4. Substance Use Harms (PHAC) — opioid/stimulant deaths, ED visits
  5. Communicable Disease (PHAC CNDSS) — STI & enteric disease surveillance

Pages:
  1. Yukon at a Glance — headline KPIs across all indicators
  2. Provincial Comparison — rankings by indicator
  3. Trend Analysis — time series with confidence intervals
  4. Substance Use Harms — opioid/stimulant emergency monitoring
  5. Communicable Disease — outbreak detection & STI surveillance
  6. Data Quality & Methodology — pipeline info and data notes
"""
from __future__ import annotations

import os
from pathlib import Path

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st
from dotenv import load_dotenv
from sqlalchemy import create_engine

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

st.set_page_config(
    page_title="Yukon Health Analytics",
    page_icon="🏥",
    layout="wide",
    initial_sidebar_state="expanded",
)

SCHEMA = "analytics_analytics"

COLOR_YUKON = "#DC2626"
COLOR_NATIONAL = "#374151"
COLOR_NT = "#2563EB"
COLOR_NU = "#059669"
COLOR_MAP = {
    "YT": COLOR_YUKON, "CA": COLOR_NATIONAL, "NT": COLOR_NT, "NU": COLOR_NU,
    "BC": "#7C3AED", "AB": "#D97706", "SK": "#0891B2", "MB": "#BE185D",
    "ON": "#F59E0B", "QC": "#6366F1", "NB": "#10B981", "NS": "#EC4899",
    "PE": "#8B5CF6", "NL": "#14B8A6",
}

INDICATOR_COLORS = {
    "ACSC Hospitalizations": "#DC2626",
    "Mental Health Readmissions": "#2563EB",
    "Diabetes Incidence": "#059669",
}


def get_engine():
    from urllib.parse import quote_plus
    password = quote_plus(os.environ["SUPABASE_PASSWORD"])
    user = os.environ["SUPABASE_USER"]
    host = os.environ["SUPABASE_HOST"]
    port = os.environ["SUPABASE_PORT"]
    db = os.environ["SUPABASE_DB"]
    url = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}?sslmode=require"
    return create_engine(url, connect_args={"connect_timeout": 30})


@st.cache_data(ttl=300)
def load_table(table_name: str) -> pd.DataFrame:
    engine = get_engine()
    return pd.read_sql(f"SELECT * FROM {SCHEMA}.{table_name}", engine)


@st.cache_data(ttl=300)
def load_all_data():
    overview = load_table("mart_dashboard__yukon_overview")
    comparison = load_table("mart_dashboard__provincial_comparison")
    trends = load_table("mart_dashboard__trend_analysis")
    substance = load_table("mart_dashboard__substance_harms")
    communicable = load_table("mart_dashboard__communicable_disease")
    return overview, comparison, trends, substance, communicable


@st.cache_data(ttl=86400, show_spinner=False)
def load_canada_geojson():
    """
    Fetch Canada provinces/territories GeoJSON and set each feature's `id`
    to the 2-letter province code so Plotly's geojson-id locationmode works.
    Cached for 24 hours. Returns None if the fetch fails.
    """
    import json
    import unicodedata
    import urllib.request

    url = (
        "https://raw.githubusercontent.com/codeforamerica/"
        "click_that_hood/master/public/data/canada.geojson"
    )
    try:
        with urllib.request.urlopen(url, timeout=12) as resp:
            geojson = json.loads(resp.read().decode())
    except Exception:
        return None

    # Maps English province/territory name → 2-letter code
    name_to_code = {
        "Alberta": "AB",
        "British Columbia": "BC",
        "Manitoba": "MB",
        "New Brunswick": "NB",
        "Newfoundland and Labrador": "NL",
        "Newfoundland": "NL",
        "Nova Scotia": "NS",
        "Northwest Territories": "NT",
        "Nunavut": "NU",
        "Ontario": "ON",
        "Prince Edward Island": "PE",
        "Quebec": "QC",
        "Québec": "QC",
        "Saskatchewan": "SK",
        "Yukon": "YT",
        "Yukon Territory": "YT",
    }

    matched = 0
    for feat in geojson.get("features", []):
        raw_name = feat.get("properties", {}).get("name", "")
        # Strip accents for fallback matching
        stripped = "".join(
            c for c in unicodedata.normalize("NFD", raw_name)
            if unicodedata.category(c) != "Mn"
        )
        code = name_to_code.get(raw_name) or name_to_code.get(stripped)
        if code:
            feat["id"] = code
            matched += 1

    # Need at least 10 of 13 provinces/territories to be usable
    if matched < 10:
        return None

    return geojson


try:
    overview_df, comparison_df, trends_df, substance_df, communicable_df = load_all_data()
except Exception as e:
    st.error(
        f"Could not connect to Supabase: {e}\n\n"
        "Make sure your `.env` file has the correct credentials and "
        "run `python run_dbt.py run` to build the mart tables."
    )
    st.stop()


# --- Sidebar ---
st.sidebar.title("Yukon Health Analytics")
st.sidebar.markdown("**Population & Public Health Evidence**")
st.sidebar.markdown("---")

page = st.sidebar.radio(
    "Navigate",
    [
        "Yukon at a Glance",
        "Provincial Comparison",
        "Trend Analysis",
        "Substance Use Harms",
        "Communicable Disease",
        "Data Quality & Methodology",
    ],
)

st.sidebar.markdown("---")
st.sidebar.caption(
    "Built by Chaitanya Panchal\n\n"
    "Data: CIHI + PHAC + Statistics Canada\n\n"
    "Pipeline: dbt + PostgreSQL (Supabase) | Dashboard: Streamlit"
)


# ============================================================================
# PAGE 1: Yukon at a Glance
# ============================================================================
if page == "Yukon at a Glance":
    st.title("Yukon Health System at a Glance")
    st.markdown(
        "Key performance indicators across three health dimensions: hospital avoidable admissions (ACSC), "
        "mental health system capacity (readmissions), and chronic disease burden (diabetes). "
        "Data sourced from **CIHI**, **PHAC**, and **Statistics Canada**."
    )

    latest = overview_df[overview_df["is_latest"] == True]
    if latest.empty:
        st.warning("No data available.")
        st.stop()

    row = latest.iloc[0]

    # --- KPI cards: 3 indicators ---
    st.subheader("Latest Indicators")
    col1, col2, col3 = st.columns(3)

    with col1:
        st.markdown("**ACSC Hospitalizations** *(CIHI)*")
        st.metric(
            label=f"Rate per 100k ({int(row['fiscal_year'])})",
            value=f"{row['acsc_rate']:.1f}" if pd.notna(row['acsc_rate']) else "N/A",
            delta=f"{row['acsc_gap_to_national']:+.1f} vs national" if pd.notna(row['acsc_gap_to_national']) else None,
            delta_color="inverse",
        )
        if pd.notna(row.get('acsc_national_rank')):
            st.caption(f"Rank: #{int(row['acsc_national_rank'])} of 13 | Trend: {row['acsc_trend_direction']}")

    with col2:
        st.markdown("**Mental Health Readmissions** *(CIHI)*")
        st.metric(
            label=f"30-Day Readmission % ({int(row['fiscal_year'])})",
            value=f"{row['mh_readmission_rate']:.1f}%" if pd.notna(row['mh_readmission_rate']) else "N/A",
            delta=f"{row['mh_gap_to_national']:+.1f}pp vs national" if pd.notna(row['mh_gap_to_national']) else None,
            delta_color="inverse",
        )
        if pd.notna(row.get('mh_national_rank')):
            st.caption(f"Rank: #{int(row['mh_national_rank'])} of 13 | Trend: {row['mh_trend_direction']}")

    with col3:
        st.markdown("**Diabetes Incidence** *(PHAC CCDSS)*")
        # Diabetes may not have data for the latest ACSC year — find latest available
        diab_data = overview_df[overview_df['diabetes_incidence_rate'].notna()]
        if not diab_data.empty:
            diab_row = diab_data.iloc[-1]
            st.metric(
                label=f"Rate per 100k ({int(diab_row['fiscal_year'])})",
                value=f"{diab_row['diabetes_incidence_rate']:.0f}",
                delta=f"{diab_row['diabetes_gap_to_national']:+.0f} vs national" if pd.notna(diab_row['diabetes_gap_to_national']) else None,
                delta_color="inverse",
            )
            if pd.notna(diab_row.get('diabetes_national_rank')):
                st.caption(f"Rank: #{int(diab_row['diabetes_national_rank'])} of 13 | Trend: {diab_row['diabetes_trend_direction']}")
        else:
            st.metric(label="Rate per 100k", value="N/A")

    st.markdown("---")

    # --- ACSC Trend chart ---
    col_chart, col_stats = st.columns([3, 1])

    with col_chart:
        st.subheader("ACSC Rate Trend — Yukon vs National")
        fig = go.Figure()

        fig.add_trace(go.Scatter(
            x=overview_df["fiscal_year"],
            y=overview_df["acsc_rate"],
            mode="lines+markers",
            name="Yukon",
            line=dict(color=COLOR_YUKON, width=3),
            marker=dict(size=8),
        ))

        fig.add_trace(go.Scatter(
            x=overview_df["fiscal_year"],
            y=overview_df["acsc_national_rate"],
            mode="lines+markers",
            name="National Average",
            line=dict(color=COLOR_NATIONAL, width=2, dash="dash"),
            marker=dict(size=6),
        ))

        fig.add_trace(go.Scatter(
            x=overview_df["fiscal_year"],
            y=overview_df["acsc_rolling_avg_5yr"],
            mode="lines",
            name="5-Year Central Avg",
            line=dict(color=COLOR_YUKON, width=1.5, dash="dot"),
            opacity=0.6,
        ))

        fig.update_layout(
            height=400,
            yaxis_title="Rate per 100,000 population",
            xaxis_title="Fiscal Year",
            legend=dict(orientation="h", yanchor="bottom", y=-0.25),
            xaxis=dict(dtick=1),
            margin=dict(l=40, r=20, t=20, b=60),
        )
        st.plotly_chart(fig, use_container_width=True)

    with col_stats:
        st.subheader("Summary")
        st.markdown(f"**Latest Year:** {int(row['fiscal_year'])}")
        st.markdown(f"**Status:** {row['acsc_national_comparison']}")
        st.markdown(f"**ACSC Gap:** {row['acsc_gap_to_national']:+.1f} per 100k")
        if pd.notna(row.get("acsc_rolling_avg_5yr")):
            st.markdown(f"**5-Year Central Avg:** {row['acsc_rolling_avg_5yr']:.1f}")
        if pd.notna(row.get("population")):
            st.markdown(f"**Population:** {int(row['population']):,}")

        st.markdown("---")
        st.markdown("**Interpretation:**")
        if row["acsc_gap_to_national"] > 100:
            st.markdown(
                "Yukon's ACSC rate is **substantially above** the national average, "
                "indicating potential gaps in primary care access or chronic disease management."
            )
        elif row["acsc_gap_to_national"] > 0:
            st.markdown(
                "Yukon's ACSC rate is **above** the national average. "
                "Targeted primary care improvements may help close this gap."
            )
        else:
            st.markdown("Yukon's ACSC rate is **at or below** the national average.")

    # --- Multi-indicator mini-charts ---
    st.subheader("All Indicators Over Time")
    col_mh, col_diab = st.columns(2)

    with col_mh:
        mh_data = overview_df[overview_df["mh_readmission_rate"].notna()]
        if not mh_data.empty:
            fig_mh = go.Figure()
            fig_mh.add_trace(go.Scatter(
                x=mh_data["fiscal_year"], y=mh_data["mh_readmission_rate"],
                mode="lines+markers", name="Yukon",
                line=dict(color=INDICATOR_COLORS["Mental Health Readmissions"], width=2.5),
                marker=dict(size=7),
            ))
            mh_nat = mh_data[mh_data["mh_national_rate"].notna()]
            if not mh_nat.empty:
                fig_mh.add_trace(go.Scatter(
                    x=mh_nat["fiscal_year"], y=mh_nat["mh_national_rate"],
                    mode="lines+markers", name="National",
                    line=dict(color=COLOR_NATIONAL, width=2, dash="dash"),
                    marker=dict(size=5),
                ))
            fig_mh.update_layout(
                title="Mental Health 30-Day Readmission Rate (%)",
                height=300, xaxis=dict(dtick=1),
                legend=dict(orientation="h", yanchor="bottom", y=-0.3),
                margin=dict(l=40, r=20, t=40, b=60),
            )
            st.plotly_chart(fig_mh, use_container_width=True)

    with col_diab:
        diab_data = overview_df[overview_df["diabetes_incidence_rate"].notna()]
        if not diab_data.empty:
            fig_diab = go.Figure()
            fig_diab.add_trace(go.Scatter(
                x=diab_data["fiscal_year"], y=diab_data["diabetes_incidence_rate"],
                mode="lines+markers", name="Yukon",
                line=dict(color=INDICATOR_COLORS["Diabetes Incidence"], width=2.5),
                marker=dict(size=7),
            ))
            diab_nat = diab_data[diab_data["diabetes_national_rate"].notna()]
            if not diab_nat.empty:
                fig_diab.add_trace(go.Scatter(
                    x=diab_nat["fiscal_year"], y=diab_nat["diabetes_national_rate"],
                    mode="lines+markers", name="National",
                    line=dict(color=COLOR_NATIONAL, width=2, dash="dash"),
                    marker=dict(size=5),
                ))
            fig_diab.update_layout(
                title="Diabetes Incidence Rate (per 100k)",
                height=300, xaxis=dict(dtick=1),
                legend=dict(orientation="h", yanchor="bottom", y=-0.3),
                margin=dict(l=40, r=20, t=40, b=60),
            )
            st.plotly_chart(fig_diab, use_container_width=True)


# ============================================================================
# PAGE 2: Provincial Comparison
# Answers: "Where does Yukon rank compared to all provinces THIS year?"
# Cross-sectional snapshot — who is highest/lowest, burden classification,
# gap to national, regional patterns. NOT about trend over time.
# ============================================================================
elif page == "Provincial Comparison":
    st.title("Provincial & Territorial Ranking")
    st.markdown(
        "**Cross-sectional snapshot** — where does Yukon rank against all 13 provinces and "
        "territories for a chosen year? Use the selectors to change indicator and year. "
        "Bars are coloured by burden level. *(For time trends, see → Trend Analysis)*"
    )

    # Indicator and year selectors
    col_ind, col_yr = st.columns(2)
    with col_ind:
        indicators = sorted(comparison_df["indicator_name"].unique())
        selected_indicator = st.selectbox("Select indicator", indicators)

    ind_data = comparison_df[comparison_df["indicator_name"] == selected_indicator]
    with col_yr:
        years = sorted(ind_data["fiscal_year"].unique())
        selected_year = st.select_slider("Select year", options=years, value=max(years))

    rate_unit = ind_data["rate_unit"].iloc[0] if not ind_data.empty else ""

    year_data = ind_data[
        (ind_data["fiscal_year"] == selected_year) &
        (ind_data["prov_code"] != "CA")
    ].copy().sort_values("rate_value", ascending=True)

    if year_data.empty:
        st.warning("No data for this selection.")
    else:
        national_rate = year_data["national_rate"].dropna()
        national_rate_val = national_rate.iloc[0] if not national_rate.empty else None

        # --- YUKON SPOTLIGHT — top of page ---
        yk_row = year_data[year_data["prov_code"] == "YT"]
        if not yk_row.empty:
            yk = yk_row.iloc[0]
            burden_colors = {"High Burden": "#DC2626", "Moderate Burden": "#F59E0B", "Low Burden": "#059669"}
            burden_cat = yk.get("burden_category", "Moderate Burden")
            nat_cmp = yk.get("national_comparison", "")
            outcome_rank = yk.get("outcome_rank")
            nat_rank = yk.get("national_rank")

            st.markdown(f"""
<div style='background:#FEF2F2; border-left:5px solid {burden_colors.get(burden_cat,"#374151")};
     padding:16px 20px; border-radius:6px; margin-bottom:16px'>
<span style='font-size:1.1rem; font-weight:600; color:{burden_colors.get(burden_cat,"#374151")}'>
  Yukon — {burden_cat}
</span>
&nbsp;&nbsp;|&nbsp;&nbsp;
<span style='color:#374151; font-size:0.95rem'>{nat_cmp}</span>
&nbsp;&nbsp;|&nbsp;&nbsp;
<span style='color:#374151; font-size:0.95rem'>
  Rate: <b>{yk['rate_value']:.1f} {rate_unit}</b> &nbsp;·&nbsp;
  Burden rank: <b>#{int(nat_rank) if pd.notna(nat_rank) else "N/A"} of 13</b>
  (1=highest burden) &nbsp;·&nbsp;
  Outcome rank: <b>#{int(outcome_rank) if pd.notna(outcome_rank) else "N/A"} of 13</b>
  (1=best outcome) &nbsp;·&nbsp;
  Gap to national: <b>{yk["gap_to_national"]:+.1f} {rate_unit}</b>
</span>
</div>
""", unsafe_allow_html=True)

        # --- Bar chart: coloured by burden category ---
        st.subheader(f"{selected_indicator} — All Provinces ({int(selected_year)})")
        st.caption("Bars coloured by burden level: 🔴 High Burden (top 3) · 🟡 Moderate · 🟢 Low Burden (bottom 3). Yukon always outlined in red.")

        burden_bar_colors = {
            "High Burden": "#FCA5A5",
            "Moderate Burden": "#FDE68A",
            "Low Burden": "#A7F3D0",
        }
        bar_colors = []
        bar_outlines = []
        for _, row in year_data.iterrows():
            cat = row.get("burden_category", "Moderate Burden")
            if row["prov_code"] == "YT":
                bar_colors.append(COLOR_YUKON)
                bar_outlines.append("#991B1B")
            else:
                bar_colors.append(burden_bar_colors.get(cat, "#E5E7EB"))
                bar_outlines.append("#9CA3AF")

        fig = go.Figure()
        fig.add_trace(go.Bar(
            x=year_data["prov_code"],
            y=year_data["rate_value"],
            marker=dict(
                color=bar_colors,
                line=dict(color=bar_outlines, width=1.5),
            ),
            text=year_data["rate_value"].apply(
                lambda x: f"{x:.1f}" if rate_unit == "%" else f"{x:.0f}"
            ),
            textposition="outside",
            customdata=year_data[["national_comparison", "burden_category", "outcome_rank"]].values,
            hovertemplate=(
                "<b>%{x}</b><br>"
                "Rate: %{y:.1f}<br>"
                "Burden: %{customdata[1]}<br>"
                "vs National: %{customdata[0]}<br>"
                "Outcome rank: #%{customdata[2]:.0f} of 13"
                "<extra></extra>"
            ),
        ))

        if national_rate_val and pd.notna(national_rate_val):
            fig.add_hline(
                y=national_rate_val, line_dash="dash", line_color=COLOR_NATIONAL,
                annotation_text=f"National avg: {national_rate_val:.1f} {rate_unit}",
                annotation_position="top right",
            )

        fig.update_layout(
            height=430,
            yaxis_title=f"Rate ({rate_unit})",
            xaxis_title="Province / Territory",
            margin=dict(l=40, r=20, t=30, b=40),
        )
        st.plotly_chart(fig, use_container_width=True)

        st.markdown("---")

        # --- Rankings table + Regional averages side by side ---
        col1, col2 = st.columns([3, 2])

        with col1:
            st.subheader("Full Rankings Table")
            ranking = year_data[[
                "prov_code", "province_name", "rate_value",
                "national_rank", "outcome_rank", "burden_category",
                "national_comparison", "gap_to_national"
            ]].copy().sort_values("national_rank")

            def fmt_rate(x):
                return f"{x:.1f}" if rate_unit == "%" else f"{x:.0f}"

            ranking["rate_value"] = ranking["rate_value"].apply(fmt_rate)
            ranking["gap_to_national"] = ranking["gap_to_national"].apply(
                lambda x: f"{x:+.1f}" if pd.notna(x) else "N/A"
            )
            ranking["national_rank"] = ranking["national_rank"].apply(
                lambda x: int(x) if pd.notna(x) else ""
            )
            ranking["outcome_rank"] = ranking["outcome_rank"].apply(
                lambda x: int(x) if pd.notna(x) else ""
            )
            ranking.columns = [
                "Code", "Province/Territory", f"Rate ({rate_unit})",
                "Burden Rank ↓", "Outcome Rank ↑", "Burden",
                "vs National", "Gap"
            ]
            st.caption("Burden Rank: 1=highest rate (worst) · Outcome Rank: 1=best health outcome")
            st.dataframe(
                ranking.set_index("Code"),
                use_container_width=True,
                height=420,
            )

        with col2:
            st.subheader("Burden by Region")
            st.caption("Average rate by Canadian region — shows whether the burden pattern is geographic")
            region_avg = year_data.groupby("region_group")["rate_value"].mean().reset_index()
            region_avg = region_avg.sort_values("rate_value", ascending=False)
            fig_region = px.bar(
                region_avg, x="rate_value", y="region_group",
                orientation="h",
                color="region_group",
                labels={"region_group": "", "rate_value": f"Avg Rate ({rate_unit})"},
                color_discrete_map={
                    "Territories": COLOR_YUKON, "Western": "#7C3AED",
                    "Central": "#F59E0B", "Atlantic": "#10B981",
                },
                text=region_avg["rate_value"].apply(fmt_rate),
            )
            fig_region.update_traces(textposition="outside")
            fig_region.update_layout(
                height=300, showlegend=False,
                margin=dict(l=20, r=40, t=10, b=40),
            )
            st.plotly_chart(fig_region, use_container_width=True)

            # --- Gap to national dot plot ---
            st.subheader("Gap to National Average")
            st.caption("How far each province sits above (+) or below (–) the national rate")
            gap_data = year_data[year_data["gap_to_national"].notna()].sort_values("gap_to_national")
            gap_colors = [COLOR_YUKON if p == "YT" else ("#DC2626" if g > 0 else "#059669")
                          for p, g in zip(gap_data["prov_code"], gap_data["gap_to_national"])]
            fig_gap = go.Figure()
            fig_gap.add_trace(go.Bar(
                x=gap_data["gap_to_national"],
                y=gap_data["prov_code"],
                orientation="h",
                marker_color=gap_colors,
                text=gap_data["gap_to_national"].apply(lambda x: f"{x:+.1f}"),
                textposition="outside",
            ))
            fig_gap.add_vline(x=0, line_dash="solid", line_color=COLOR_NATIONAL, line_width=1.5)
            fig_gap.update_layout(
                height=360,
                xaxis_title=f"Gap ({rate_unit})",
                margin=dict(l=10, r=50, t=10, b=30),
            )
            st.plotly_chart(fig_gap, use_container_width=True)


# ============================================================================
# PAGE 3: Trend Analysis
# Answers: "Is Yukon's rate improving or worsening over time? Is the gap
# to the national average narrowing or widening?"
# Longitudinal time series — trajectory, convergence, CI uncertainty bands.
# NOT about ranking across provinces at one point in time.
# ============================================================================
elif page == "Trend Analysis":
    st.title("Trend Analysis & Trajectory")
    st.markdown(
        "**Longitudinal time series** — how has Yukon's rate changed over available years, "
        "and is the gap to the national benchmark **converging** (improving) or **diverging** (worsening)? "
        "Shaded bands show 95% confidence intervals. *(For cross-province rankings, see → Provincial Comparison)*"
    )

    # Indicator selector + display options
    col_sel, col_opt = st.columns([2, 1])
    with col_sel:
        indicators = sorted(trends_df["indicator_name"].unique())
        selected_indicator = st.selectbox("Select indicator", indicators)
    with col_opt:
        show_rolling = st.checkbox("Show 5-year rolling average", value=True)
        show_ci = st.checkbox("Show 95% CI bands", value=True)

    ind_trends = trends_df[trends_df["indicator_name"] == selected_indicator]
    rate_unit = ind_trends["rate_unit"].iloc[0] if not ind_trends.empty else ""

    available_series = sorted(ind_trends["series_name"].unique())
    selected_series = st.multiselect(
        "Select series to display",
        available_series,
        default=available_series,
    )

    filtered = ind_trends[ind_trends["series_name"].isin(selected_series)]

    if filtered.empty:
        st.info("Select at least one series.")
    else:
        # --- TRAJECTORY KPI CARDS for Yukon ---
        yk_trend = filtered[filtered["prov_code"] == "YT"].sort_values("fiscal_year")
        nat_trend = filtered[filtered["prov_code"] == "CA"].sort_values("fiscal_year")

        if not yk_trend.empty:
            yk_first = yk_trend.iloc[0]
            yk_last = yk_trend.iloc[-1]
            total_change = yk_last["rate_value"] - yk_first["rate_value"]
            total_pct = (total_change / yk_first["rate_value"]) * 100 if yk_first["rate_value"] else 0

            # Convergence: is the gap to national narrowing over time?
            yk_nat_merged = yk_trend.merge(
                nat_trend[["fiscal_year", "rate_value"]].rename(columns={"rate_value": "nat_rate"}),
                on="fiscal_year", how="inner"
            )
            if not yk_nat_merged.empty and len(yk_nat_merged) >= 2:
                gap_first = yk_nat_merged.iloc[0]["rate_value"] - yk_nat_merged.iloc[0]["nat_rate"]
                gap_last = yk_nat_merged.iloc[-1]["rate_value"] - yk_nat_merged.iloc[-1]["nat_rate"]
                gap_change = gap_last - gap_first
                converging = gap_change < 0  # gap shrinking = converging toward national
                conv_label = "Converging ↘" if converging else "Diverging ↗"
                conv_color = "#059669" if converging else "#DC2626"
            else:
                gap_first = gap_last = gap_change = None
                conv_label = "N/A"
                conv_color = "#374151"

            st.subheader(f"Yukon — {selected_indicator} Trajectory")
            kc1, kc2, kc3, kc4 = st.columns(4)

            with kc1:
                trend_icon = "📈" if total_change > 0 else ("📉" if total_change < 0 else "➡️")
                st.metric(
                    label=f"Total change ({int(yk_first['fiscal_year'])}→{int(yk_last['fiscal_year'])})",
                    value=f"{total_change:+.1f} {rate_unit}",
                    delta=f"{total_pct:+.1f}%",
                    delta_color="inverse",
                )
                st.caption(trend_icon + " from first to latest year")

            with kc2:
                st.metric(
                    label=f"First year ({int(yk_first['fiscal_year'])})",
                    value=f"{yk_first['rate_value']:.1f} {rate_unit}",
                )

            with kc3:
                st.metric(
                    label=f"Latest year ({int(yk_last['fiscal_year'])})",
                    value=f"{yk_last['rate_value']:.1f} {rate_unit}",
                )

            with kc4:
                st.markdown(f"**Gap to national: {conv_label}**")
                if gap_first is not None:
                    st.markdown(
                        f"<span style='color:{conv_color}; font-size:1.5rem; font-weight:bold'>"
                        f"{conv_label}</span>",
                        unsafe_allow_html=True,
                    )
                    st.caption(
                        f"Gap: {gap_first:+.1f} → {gap_last:+.1f} {rate_unit} "
                        f"({'–' if converging else '+'}{abs(gap_change):.1f} pp)"
                    )
                else:
                    st.markdown("N/A")

        st.markdown("---")

        # --- Main time series chart ---
        st.subheader("Time Series with 95% Confidence Intervals")
        fig = go.Figure()

        for series in selected_series:
            sdata = filtered[filtered["series_name"] == series].sort_values("fiscal_year")
            if sdata.empty:
                continue
            prov = sdata["prov_code"].iloc[0]
            color = COLOR_MAP.get(prov, "#94A3B8")
            is_yukon = prov == "YT"
            is_national = prov == "CA"

            # CI band (toggled)
            if show_ci and sdata["ci_lower"].notna().any() and sdata["ci_upper"].notna().any():
                ci_data = sdata[sdata["ci_lower"].notna() & sdata["ci_upper"].notna()]
                r = int(color.lstrip("#")[0:2], 16)
                g_val = int(color.lstrip("#")[2:4], 16)
                b_val = int(color.lstrip("#")[4:6], 16)
                fig.add_trace(go.Scatter(
                    x=list(ci_data["fiscal_year"]) + list(ci_data["fiscal_year"][::-1]),
                    y=list(ci_data["ci_upper"]) + list(ci_data["ci_lower"][::-1]),
                    fill="toself",
                    fillcolor=f"rgba({r},{g_val},{b_val},0.12)",
                    line=dict(color="rgba(255,255,255,0)"),
                    showlegend=False,
                    name=f"{series} 95% CI",
                    hoverinfo="skip",
                ))

            # Rolling average line (toggled)
            if show_rolling and "rolling_avg_5yr" in sdata.columns and sdata["rolling_avg_5yr"].notna().any():
                fig.add_trace(go.Scatter(
                    x=sdata["fiscal_year"],
                    y=sdata["rolling_avg_5yr"],
                    mode="lines",
                    name=f"{series} (5yr avg)",
                    line=dict(color=color, width=1.5, dash="dot"),
                    opacity=0.55,
                    showlegend=False,
                ))

            # Main line
            fig.add_trace(go.Scatter(
                x=sdata["fiscal_year"],
                y=sdata["rate_value"],
                mode="lines+markers",
                name=series,
                line=dict(
                    color=color,
                    width=3.5 if is_yukon else (2 if is_national else 1.8),
                    dash="solid" if (is_yukon or is_national) else "dot",
                ),
                marker=dict(size=8 if is_yukon else 5),
            ))

        fig.update_layout(
            height=520,
            yaxis_title=f"Rate ({rate_unit})",
            xaxis_title="Year",
            legend=dict(orientation="h", yanchor="bottom", y=-0.22),
            xaxis=dict(dtick=1),
            margin=dict(l=40, r=20, t=20, b=60),
        )
        st.plotly_chart(fig, use_container_width=True)

        st.caption(
            "**How to read:** Solid bold line = Yukon. Solid thin line = National. Dotted = peer territories. "
            "Shaded bands = 95% confidence interval (wider bands = smaller population, more uncertainty). "
            "Dotted line overlaid = 5-year central moving average."
        )

        st.markdown("---")

        # --- Convergence analysis ---
        if not yk_trend.empty and not nat_trend.empty and len(yk_nat_merged) >= 2:
            st.subheader("Gap to National — Convergence Analysis")
            st.caption(
                "How many units above or below the national average is Yukon each year? "
                "A shrinking gap means Yukon is converging toward the national rate."
            )

            gap_series = yk_nat_merged.copy()
            gap_series["gap"] = gap_series["rate_value"] - gap_series["nat_rate"]
            gap_colors = [COLOR_YUKON if g > 0 else "#059669" for g in gap_series["gap"]]

            fig_gap = go.Figure()
            fig_gap.add_trace(go.Bar(
                x=gap_series["fiscal_year"],
                y=gap_series["gap"],
                marker_color=gap_colors,
                text=gap_series["gap"].apply(lambda x: f"{x:+.1f}"),
                textposition="outside",
            ))
            fig_gap.add_hline(y=0, line_color=COLOR_NATIONAL, line_width=1.5,
                              annotation_text="National parity", annotation_position="top left")
            fig_gap.update_layout(
                height=350,
                yaxis_title=f"Gap to national ({rate_unit})",
                xaxis_title="Year",
                xaxis=dict(dtick=1),
                margin=dict(l=40, r=20, t=20, b=40),
            )
            st.plotly_chart(fig_gap, use_container_width=True)

        st.markdown("---")

        # --- Summary statistics (no ranking columns — that's Provincial Comparison) ---
        st.subheader("Historical Statistics by Series")
        stats_df = filtered.copy()
        stats_rows = []
        for series in selected_series:
            s = stats_df[stats_df["series_name"] == series].sort_values("fiscal_year")
            if s.empty:
                continue
            first_yr = int(s.iloc[0]["fiscal_year"])
            last_yr = int(s.iloc[-1]["fiscal_year"])
            chg = s.iloc[-1]["rate_value"] - s.iloc[0]["rate_value"]
            chg_pct = (chg / s.iloc[0]["rate_value"]) * 100 if s.iloc[0]["rate_value"] else 0
            stats_rows.append({
                "Series": series,
                f"Mean ({rate_unit})": f"{s['rate_value'].mean():.1f}",
                f"Min → Max ({rate_unit})": f"{s['rate_value'].min():.1f} → {s['rate_value'].max():.1f}",
                f"Change {first_yr}→{last_yr}": f"{chg:+.1f} ({chg_pct:+.1f}%)",
                "Years": len(s),
            })
        if stats_rows:
            st.dataframe(pd.DataFrame(stats_rows).set_index("Series"), use_container_width=True)

        # --- Raw data download ---
            
            pivot = filtered.pivot_table(
                index="fiscal_year", columns="series_name", values="rate_value"
            )
            st.dataframe(pivot)
            csv = pivot.to_csv()
            st.download_button(
                "Download CSV", csv,
                file_name=f"yukon_{selected_indicator.lower().replace(' ', '_')}_trends.csv",
                mime="text/csv",
            )


# ============================================================================
# PAGE 4: Substance Use Harms
# ============================================================================
elif page == "Substance Use Harms":
    st.title("Substance Use Harms — Yukon Emergency Monitoring")
    st.markdown(
        "Yukon declared a **Substance Use Health Emergency** on January 20, 2022. "
        "This page tracks opioid and stimulant-related harms using PHAC Health Infobase data. "
        "Terminology follows PHAC/Yukon Coroner convention: *apparent toxicity death* (not 'overdose')."
    )

    # --- Filter data for Yukon and Canada ---
    yk_sub = substance_df[substance_df["prov_code"] == "YT"].copy()
    ca_sub = substance_df[substance_df["prov_code"] == "YT"].copy()  # placeholder

    # --- KPI Cards: Latest Yukon Opioid & Stimulant Deaths ---
    st.subheader("Latest Yukon Indicators")

    yk_opioid_deaths = yk_sub[
        (yk_sub["substance"] == "Opioids") & (yk_sub["harm_type"] == "Deaths")
    ].sort_values("ref_year")

    yk_stimulant_deaths = yk_sub[
        (yk_sub["substance"] == "Stimulants") & (yk_sub["harm_type"] == "Deaths")
    ].sort_values("ref_year")

    yk_opioid_ed = yk_sub[
        (yk_sub["substance"] == "Opioids") & (yk_sub["harm_type"] == "Emergency Department (ED) Visits")
    ].sort_values("ref_year")

    yk_stimulant_ed = yk_sub[
        (yk_sub["substance"] == "Stimulants") & (yk_sub["harm_type"] == "Emergency Department (ED) Visits")
    ].sort_values("ref_year")

    col1, col2, col3, col4 = st.columns(4)

    def _kpi_card(col, title, source_label, df_indicator):
        with col:
            st.markdown(f"**{title}**")
            if not df_indicator.empty:
                latest = df_indicator.iloc[-1]
                st.metric(
                    label=f"per 100k ({int(latest['ref_year'])})",
                    value=f"{latest['crude_rate_per_100k']:.1f}",
                    delta=f"{latest['yoy_change']:+.1f} vs prior year" if pd.notna(latest.get('yoy_change')) else None,
                    delta_color="inverse",
                )
                sev = latest.get("severity_vs_national", "")
                rank = latest.get("national_rank", "")
                rank_str = f"Rank #{int(rank)}" if pd.notna(rank) else ""
                st.caption(f"{sev} | {rank_str}")
            else:
                st.metric(label="per 100k", value="N/A")

    _kpi_card(col1, "Opioid Deaths", "PHAC", yk_opioid_deaths)
    _kpi_card(col2, "Stimulant Deaths", "PHAC", yk_stimulant_deaths)
    _kpi_card(col3, "Opioid ED Visits", "PHAC", yk_opioid_ed)
    _kpi_card(col4, "Stimulant ED Visits", "PHAC", yk_stimulant_ed)

    st.markdown("---")

    # ---- CHART 1: Area chart — Opioid Deaths with Emergency Period Shading ----
    st.subheader("Opioid Apparent Toxicity Deaths — Yukon vs Canada")

    all_opioid_deaths = substance_df[
        (substance_df["substance"] == "Opioids") &
        (substance_df["harm_type"] == "Deaths") &
        (substance_df["prov_code"].isin(["YT", "BC", "AB"]))
    ].sort_values("ref_year")

    fig_area = go.Figure()

    # Emergency period shading
    fig_area.add_vrect(
        x0=2022, x1=2025, fillcolor="rgba(220,38,38,0.08)",
        layer="below", line_width=0,
        annotation_text="Emergency Declared", annotation_position="top left",
        annotation_font_size=10, annotation_font_color="#DC2626",
    )

    # Yukon line (bold)
    if not yk_opioid_deaths.empty:
        fig_area.add_trace(go.Scatter(
            x=yk_opioid_deaths["ref_year"],
            y=yk_opioid_deaths["crude_rate_per_100k"],
            mode="lines+markers",
            name="Yukon",
            line=dict(color=COLOR_YUKON, width=3.5),
            marker=dict(size=9),
            fill="tozeroy",
            fillcolor="rgba(220,38,38,0.12)",
        ))

    # National benchmark
    nat_opioid = substance_df[
        (substance_df["substance"] == "Opioids") &
        (substance_df["harm_type"] == "Deaths") &
        (substance_df["prov_code"] == "YT")
    ].sort_values("ref_year")
    if not nat_opioid.empty and nat_opioid["national_rate"].notna().any():
        fig_area.add_trace(go.Scatter(
            x=nat_opioid["ref_year"],
            y=nat_opioid["national_rate"],
            mode="lines+markers",
            name="Canada (National)",
            line=dict(color=COLOR_NATIONAL, width=2, dash="dash"),
            marker=dict(size=6),
        ))

    fig_area.update_layout(
        height=420,
        yaxis_title="Crude Rate per 100,000",
        xaxis_title="Year",
        legend=dict(orientation="h", yanchor="bottom", y=-0.22),
        xaxis=dict(dtick=1),
        margin=dict(l=40, r=20, t=20, b=60),
    )
    st.plotly_chart(fig_area, use_container_width=True)

    st.markdown("---")

    # ---- CHART 2: Grouped Bar — Yukon vs Canada Death Rates by Year ----
    col_left, col_right = st.columns(2)

    with col_left:
        st.subheader("Yukon vs Canada — Death Rates by Substance")

        yk_deaths = yk_sub[yk_sub["harm_type"] == "Deaths"].copy()
        if not yk_deaths.empty:
            fig_grouped = go.Figure()

            for sub, color in [("Opioids", COLOR_YUKON), ("Stimulants", "#F59E0B")]:
                sub_data = yk_deaths[yk_deaths["substance"] == sub]
                if not sub_data.empty:
                    fig_grouped.add_trace(go.Bar(
                        x=sub_data["ref_year"],
                        y=sub_data["crude_rate_per_100k"],
                        name=f"Yukon — {sub}",
                        marker_color=color,
                        opacity=0.9,
                    ))

            # Add national opioid line for reference
            if not nat_opioid.empty:
                nat_vals = nat_opioid[nat_opioid["national_rate"].notna()]
                fig_grouped.add_trace(go.Scatter(
                    x=nat_vals["ref_year"],
                    y=nat_vals["national_rate"],
                    mode="lines+markers",
                    name="Canada — Opioids",
                    line=dict(color=COLOR_NATIONAL, width=2, dash="dash"),
                    marker=dict(size=5),
                ))

            fig_grouped.update_layout(
                height=380,
                barmode="group",
                yaxis_title="Rate per 100,000",
                xaxis=dict(dtick=1),
                legend=dict(orientation="h", yanchor="bottom", y=-0.3),
                margin=dict(l=40, r=20, t=20, b=60),
            )
            st.plotly_chart(fig_grouped, use_container_width=True)

    # ---- CHART 3: Yukon-to-Canada Ratio Trend (Bullet/Line) ----
    with col_right:
        st.subheader("Yukon-to-Canada Ratio — Opioid Deaths")

        ratio_data = yk_opioid_deaths[yk_opioid_deaths["yukon_vs_canada_ratio"].notna()].copy()
        if not ratio_data.empty:
            fig_ratio = go.Figure()

            # Color bars by severity
            bar_colors = []
            for _, r in ratio_data.iterrows():
                ratio = r["yukon_vs_canada_ratio"]
                if ratio >= 2.0:
                    bar_colors.append("#DC2626")  # Crisis
                elif ratio >= 1.5:
                    bar_colors.append("#F59E0B")  # Severely Elevated
                elif ratio >= 1.0:
                    bar_colors.append("#F97316")  # Above National
                else:
                    bar_colors.append("#059669")  # Below National

            fig_ratio.add_trace(go.Bar(
                x=ratio_data["ref_year"],
                y=ratio_data["yukon_vs_canada_ratio"],
                marker_color=bar_colors,
                text=ratio_data["yukon_vs_canada_ratio"].apply(lambda x: f"{x:.1f}x"),
                textposition="outside",
                showlegend=False,
            ))

            # Parity line at 1.0
            fig_ratio.add_hline(
                y=1.0, line_dash="dash", line_color=COLOR_NATIONAL, line_width=1.5,
                annotation_text="National parity (1.0x)",
                annotation_position="bottom right",
                annotation_font_size=10,
            )

            # Crisis threshold line at 2.0
            fig_ratio.add_hline(
                y=2.0, line_dash="dot", line_color="#DC2626", line_width=1,
                annotation_text="Crisis threshold (2.0x)",
                annotation_position="top right",
                annotation_font_size=10,
            )

            fig_ratio.update_layout(
                height=380,
                yaxis_title="Ratio (Yukon ÷ Canada)",
                xaxis=dict(dtick=1),
                margin=dict(l=40, r=20, t=20, b=40),
            )
            st.plotly_chart(fig_ratio, use_container_width=True)

    st.markdown("---")

    # ---- CHART 4: Heatmap — All Provinces, Opioid Death Rates ----
    st.subheader("Provincial Heatmap — Opioid Apparent Toxicity Death Rate")

    opioid_deaths_all = substance_df[
        (substance_df["substance"] == "Opioids") &
        (substance_df["harm_type"] == "Deaths")
    ].copy()

    if not opioid_deaths_all.empty:
        heatmap_data = opioid_deaths_all.pivot_table(
            index="prov_code", columns="ref_year", values="crude_rate_per_100k"
        )
        # Sort by latest year rate descending
        latest_col = heatmap_data.columns.max()
        heatmap_data = heatmap_data.sort_values(by=latest_col, ascending=True)

        # Build text labels compatible with all pandas versions (map() is 2.1+ only)
        heat_text = [
            ["{:.1f}".format(v) if pd.notna(v) else "—" for v in row]
            for row in heatmap_data.values
        ]

        fig_heat = go.Figure(data=go.Heatmap(
            z=heatmap_data.values,
            x=[str(int(c)) for c in heatmap_data.columns],
            y=heatmap_data.index.tolist(),
            colorscale=[
                [0, "#F0FDF4"],      # Low: green tint
                [0.25, "#FEF3C7"],   # Moderate: yellow
                [0.5, "#FED7AA"],    # Elevated: orange
                [0.75, "#FECACA"],   # High: red light
                [1.0, "#991B1B"],    # Crisis: dark red
            ],
            text=heat_text,
            texttemplate="%{text}",
            textfont=dict(size=10),
            colorbar=dict(title="Rate<br>per 100k"),
            hovertemplate="Province: %{y}<br>Year: %{x}<br>Rate: %{z:.1f} per 100k<extra></extra>",
        ))

        fig_heat.update_layout(
            height=450,
            xaxis_title="Year",
            yaxis_title="Province / Territory",
            margin=dict(l=40, r=20, t=20, b=40),
        )
        st.plotly_chart(fig_heat, use_container_width=True)

    st.markdown("---")

    # ---- CHART 5: ED Visits Trend — Multi-substance Line Chart ----
    col_ed_left, col_ed_right = st.columns(2)

    with col_ed_left:
        st.subheader("Yukon ED Visits — Opioids vs Stimulants")

        yk_ed = yk_sub[
            yk_sub["harm_type"] == "Emergency Department (ED) Visits"
        ].sort_values("ref_year")

        if not yk_ed.empty:
            fig_ed = go.Figure()
            for sub, color, dash in [("Opioids", COLOR_YUKON, "solid"), ("Stimulants", "#F59E0B", "dash")]:
                sub_data = yk_ed[yk_ed["substance"] == sub]
                if not sub_data.empty:
                    fig_ed.add_trace(go.Scatter(
                        x=sub_data["ref_year"],
                        y=sub_data["crude_rate_per_100k"],
                        mode="lines+markers",
                        name=sub,
                        line=dict(color=color, width=2.5, dash=dash),
                        marker=dict(size=7),
                    ))

            fig_ed.add_vrect(
                x0=2022, x1=2025, fillcolor="rgba(220,38,38,0.06)",
                layer="below", line_width=0,
            )

            fig_ed.update_layout(
                height=380,
                yaxis_title="ED Visit Rate per 100,000",
                xaxis=dict(dtick=1),
                legend=dict(orientation="h", yanchor="bottom", y=-0.25),
                margin=dict(l=40, r=20, t=20, b=60),
            )
            st.plotly_chart(fig_ed, use_container_width=True)

    # ---- CHART 6: Pre vs Post Emergency Comparison ----
    with col_ed_right:
        st.subheader("Pre vs Post Emergency — Yukon Opioid Deaths")

        yk_emergency = yk_opioid_deaths[yk_opioid_deaths["emergency_period_label"].isin(
            ["Pre-Emergency", "Post-Emergency"]
        )].copy()

        if not yk_emergency.empty:
            period_avg = yk_emergency.groupby("emergency_period_label").agg(
                avg_rate=("crude_rate_per_100k", "mean"),
                avg_rank=("national_rank", "mean"),
                years=("ref_year", "count"),
            ).reset_index()

            period_avg = period_avg.sort_values("emergency_period_label")

            fig_prepost = go.Figure()

            colors_period = {"Pre-Emergency": "#F59E0B", "Post-Emergency": "#DC2626"}
            for _, period_row in period_avg.iterrows():
                label = period_row["emergency_period_label"]
                fig_prepost.add_trace(go.Bar(
                    x=[label],
                    y=[period_row["avg_rate"]],
                    name=label,
                    marker_color=colors_period.get(label, "#94A3B8"),
                    text=[f"{period_row['avg_rate']:.1f}"],
                    textposition="outside",
                    width=0.5,
                ))

            fig_prepost.update_layout(
                height=380,
                yaxis_title="Avg Death Rate per 100,000",
                showlegend=False,
                margin=dict(l=40, r=20, t=20, b=40),
            )
            st.plotly_chart(fig_prepost, use_container_width=True)

            # Text summary
            pre = period_avg[period_avg["emergency_period_label"] == "Pre-Emergency"]
            post = period_avg[period_avg["emergency_period_label"] == "Post-Emergency"]
            if not pre.empty and not post.empty:
                pre_rate = pre.iloc[0]["avg_rate"]
                post_rate = post.iloc[0]["avg_rate"]
                change = ((post_rate - pre_rate) / pre_rate) * 100
                st.caption(
                    f"Pre-emergency avg: **{pre_rate:.1f}** per 100k | "
                    f"Post-emergency avg: **{post_rate:.1f}** per 100k | "
                    f"Change: **{change:+.0f}%**"
                )

    st.markdown("---")

    # ---- Data Table ----
    with st.expander("View Yukon Substance Harms Data"):
        display_cols = [
            "ref_year", "indicator_label", "crude_rate_per_100k", "national_rate",
            "yukon_vs_canada_ratio", "severity_vs_national", "trend_direction",
            "emergency_period_label", "national_rank"
        ]
        yk_display = yk_sub[display_cols].copy()
        yk_display.columns = [
            "Year", "Indicator", "Rate/100k", "National Rate",
            "YK÷CA Ratio", "Severity", "Trend", "Period", "Rank"
        ]
        yk_display = yk_display.sort_values(["Indicator", "Year"])
        st.dataframe(yk_display, use_container_width=True, hide_index=True)

        csv = yk_display.to_csv(index=False)
        st.download_button(
            "Download Yukon Substance Harms CSV", csv,
            file_name="yukon_substance_harms.csv", mime="text/csv",
        )


# ============================================================================
# PAGE 5: Communicable Disease Surveillance
# ============================================================================
elif page == "Communicable Disease":
    st.title("Communicable Disease Surveillance")
    st.markdown(
        "National and provincial surveillance for **sexually transmitted infections** (STIs) "
        "and **enteric diseases** from the PHAC Canadian Notifiable Disease Surveillance System (CNDSS). "
        "Features statistical outbreak detection (rate > mean + 2×SD) and Yukon provincial spotlight."
    )

    # --- Separate national time series and provincial snapshots ---
    national_cd = communicable_df[communicable_df["prov_code"] == "CA"].copy()
    provincial_cd = communicable_df[communicable_df["prov_code"] != "CA"].copy()

    # --- Disease category filter ---
    col_cat, col_dis = st.columns(2)
    with col_cat:
        categories = sorted(communicable_df["disease_category"].dropna().unique())
        selected_category = st.selectbox("Disease Category", ["All"] + list(categories))

    if selected_category != "All":
        national_cd = national_cd[national_cd["disease_category"] == selected_category]
        provincial_cd = provincial_cd[provincial_cd["disease_category"] == selected_category]

    with col_dis:
        diseases = sorted(national_cd["disease"].unique()) if not national_cd.empty else []
        selected_disease = st.selectbox("Select Disease", diseases if diseases else ["No data"])

    if selected_disease == "No data" or national_cd.empty:
        st.warning("No data available for this selection.")
    else:
        disease_national = national_cd[national_cd["disease"] == selected_disease].sort_values("ref_year")
        disease_provincial = provincial_cd[provincial_cd["disease"] == selected_disease]

        # --- KPI Cards: Latest National Stats ---
        st.subheader(f"{selected_disease} — National Overview")

        if not disease_national.empty:
            latest = disease_national.iloc[-1]
            prev = disease_national.iloc[-2] if len(disease_national) > 1 else None

            col1, col2, col3, col4 = st.columns(4)

            with col1:
                st.markdown("**Latest National Rate**")
                st.metric(
                    label=f"per 100k ({int(latest['ref_year'])})",
                    value=f"{latest['rate_per_100k']:.1f}",
                    delta=f"{latest['yoy_change']:+.1f} vs prior year" if pd.notna(latest.get('yoy_change')) else None,
                    delta_color="inverse",
                )

            with col2:
                st.markdown("**Outbreak Status**")
                status = latest.get("outbreak_status_label", "Normal Range")
                z_score = latest.get("outbreak_z_score", 0)
                status_colors = {
                    "Severe Outbreak": "#DC2626",
                    "Outbreak Detected": "#F59E0B",
                    "Elevated": "#F97316",
                    "Normal Range": "#059669",
                }
                status_color = status_colors.get(status, "#374151")
                st.markdown(
                    f"<div style='font-size:1.8rem; font-weight:bold; color:{status_color}'>"
                    f"{status}</div>",
                    unsafe_allow_html=True,
                )
                if pd.notna(z_score):
                    st.caption(f"Z-score: {z_score:.1f} SD above mean")

            with col3:
                st.markdown("**5-Year Rolling Average**")
                rolling = latest.get("rolling_avg_5yr_central")
                if pd.notna(rolling):
                    st.metric(label="per 100k", value=f"{rolling:.1f}")
                else:
                    st.metric(label="per 100k", value="N/A")

            with col4:
                st.markdown("**Trend (National)**")
                trend = latest.get("trend_direction", "Stable")
                pct = latest.get("yoy_pct_change")
                trend_icons = {"Increasing": "📈", "Decreasing": "📉", "Stable": "➡️"}
                st.markdown(f"### {trend_icons.get(trend, '')} {trend}")
                if pd.notna(pct):
                    st.caption(f"{pct:+.1f}% year-over-year")

        st.markdown("---")

        # ---- CHART 1: National Trend with Outbreak Detection ----
        st.subheader(f"{selected_disease} — National Trend & Outbreak Detection")

        if not disease_national.empty:
            fig_trend = go.Figure()

            # Rolling average band
            if disease_national["rolling_avg_5yr_central"].notna().any():
                rolling_data = disease_national[disease_national["rolling_avg_5yr_central"].notna()]
                fig_trend.add_trace(go.Scatter(
                    x=rolling_data["ref_year"],
                    y=rolling_data["rolling_avg_5yr_central"],
                    mode="lines",
                    name="5-Year Central Avg",
                    line=dict(color="#6B7280", width=2, dash="dot"),
                    opacity=0.7,
                ))

                # Upper threshold band (mean + 2*SD) for outbreak visualization
                if rolling_data["rolling_stddev_5yr"].notna().any():
                    threshold = rolling_data["rolling_avg_5yr_central"] + 2 * rolling_data["rolling_stddev_5yr"]
                    fig_trend.add_trace(go.Scatter(
                        x=rolling_data["ref_year"],
                        y=threshold,
                        mode="lines",
                        name="Outbreak Threshold (μ+2σ)",
                        line=dict(color="#DC2626", width=1.5, dash="dash"),
                        opacity=0.5,
                    ))

            # Main rate line
            fig_trend.add_trace(go.Scatter(
                x=disease_national["ref_year"],
                y=disease_national["rate_per_100k"],
                mode="lines+markers",
                name="National Rate",
                line=dict(color="#2563EB", width=3),
                marker=dict(size=7),
            ))

            # Highlight outbreak years
            outbreak_years = disease_national[disease_national["is_outbreak_signal"] == True]
            if not outbreak_years.empty:
                fig_trend.add_trace(go.Scatter(
                    x=outbreak_years["ref_year"],
                    y=outbreak_years["rate_per_100k"],
                    mode="markers",
                    name="Outbreak Signal",
                    marker=dict(
                        size=14, color="#DC2626", symbol="triangle-up",
                        line=dict(width=2, color="#991B1B"),
                    ),
                ))

            fig_trend.update_layout(
                height=450,
                yaxis_title="Rate per 100,000",
                xaxis_title="Year",
                legend=dict(orientation="h", yanchor="bottom", y=-0.22),
                xaxis=dict(dtick=2),
                margin=dict(l=40, r=20, t=20, b=60),
            )
            st.plotly_chart(fig_trend, use_container_width=True)

        st.markdown("---")

        # ---- CHART 2: All Diseases National Comparison ----
        col_left, col_right = st.columns(2)

        with col_left:
            st.subheader("Disease Burden Comparison (National)")

            latest_year = national_cd["ref_year"].max()
            latest_all = national_cd[national_cd["ref_year"] == latest_year].copy()

            if not latest_all.empty:
                latest_all = latest_all.sort_values("rate_per_100k", ascending=True)

                disease_colors = {
                    "Chlamydia": "#2563EB",
                    "Gonorrhea": "#7C3AED",
                    "Infectious Syphilis": "#DC2626",
                    "Giardiasis": "#059669",
                    "Salmonellosis": "#D97706",
                }

                fig_burden = go.Figure()
                fig_burden.add_trace(go.Bar(
                    y=latest_all["disease"],
                    x=latest_all["rate_per_100k"],
                    orientation="h",
                    marker_color=[disease_colors.get(d, "#94A3B8") for d in latest_all["disease"]],
                    text=latest_all["rate_per_100k"].apply(lambda x: f"{x:.1f}"),
                    textposition="outside",
                ))

                fig_burden.update_layout(
                    height=350,
                    xaxis_title=f"Rate per 100,000 ({int(latest_year)})",
                    margin=dict(l=120, r=40, t=20, b=40),
                )
                st.plotly_chart(fig_burden, use_container_width=True)

        # ---- CHART 3: Outbreak Status Dashboard ----
        with col_right:
            st.subheader(f"Outbreak Status ({int(latest_year)})")

            if not latest_all.empty:
                # Build a status table
                status_data = latest_all[["disease", "outbreak_status_label", "outbreak_z_score"]].copy()
                status_data["z_display"] = status_data["outbreak_z_score"].apply(
                    lambda x: f"{x:+.1f}" if pd.notna(x) else "N/A"
                )

                status_emoji = {
                    "Severe Outbreak": "🔴",
                    "Outbreak Detected": "🟠",
                    "Elevated": "🟡",
                    "Normal Range": "🟢",
                }

                for _, row in status_data.iterrows():
                    emoji = status_emoji.get(row["outbreak_status_label"], "⚪")
                    st.markdown(
                        "{} **{}** — {}".format(
                            emoji, row["disease"], row["outbreak_status_label"]
                        )
                    )

                with st.expander("Technical detail: Z-scores"):
                    st.caption(
                        "Z-score measures how many standard deviations the current rate "
                        "is above the 5-year central average. Z ≥ 2.0 triggers an "
                        "outbreak signal; Z ≥ 3.0 indicates a severe outbreak."
                    )
                    for _, zrow in status_data.iterrows():
                        st.text("{}: z = {}".format(
                            zrow["disease"], zrow["z_display"]
                        ))

        st.markdown("---")

        # ---- CHART 4: Provincial Comparison (STI snapshot years) ----
        st.subheader(f"{selected_disease} — Provincial Comparison")

        if not disease_provincial.empty:
            prov_years = sorted(disease_provincial["ref_year"].unique())
            selected_prov_year = st.select_slider(
                "Snapshot Year", options=prov_years, value=max(prov_years),
                key="cd_prov_year",
            )

            prov_year_data = disease_provincial[
                disease_provincial["ref_year"] == selected_prov_year
            ].sort_values("rate_per_100k", ascending=True)

            if not prov_year_data.empty:
                # Get national rate for reference line
                nat_rate_row = disease_national[
                    disease_national["ref_year"] == selected_prov_year
                ]
                nat_rate = nat_rate_row["rate_per_100k"].iloc[0] if not nat_rate_row.empty else None

                fig_prov = go.Figure()

                bar_colors = [
                    COLOR_YUKON if code == "YT" else (
                        COLOR_NT if code == "NT" else (
                            COLOR_NU if code == "NU" else "#94A3B8"
                        )
                    ) for code in prov_year_data["prov_code"]
                ]

                fig_prov.add_trace(go.Bar(
                    x=prov_year_data["prov_code"],
                    y=prov_year_data["rate_per_100k"],
                    marker_color=bar_colors,
                    text=prov_year_data["rate_per_100k"].apply(lambda x: f"{x:.1f}"),
                    textposition="outside",
                ))

                if nat_rate and pd.notna(nat_rate):
                    fig_prov.add_hline(
                        y=nat_rate, line_dash="dash", line_color=COLOR_NATIONAL,
                        annotation_text=f"National: {nat_rate:.1f}",
                        annotation_position="top right",
                    )

                fig_prov.update_layout(
                    height=420,
                    yaxis_title="Rate per 100,000",
                    xaxis_title="Province / Territory",
                    margin=dict(l=40, r=20, t=20, b=40),
                )
                st.plotly_chart(fig_prov, use_container_width=True)

                # Yukon spotlight
                yk_prov = prov_year_data[prov_year_data["prov_code"] == "YT"]
                if not yk_prov.empty:
                    yk_row = yk_prov.iloc[0]
                    sev = yk_row.get("severity_vs_national", "")
                    ratio = yk_row.get("prov_vs_national_ratio")
                    gap = yk_row.get("gap_to_national")

                    col_yk1, col_yk2, col_yk3 = st.columns(3)
                    with col_yk1:
                        st.metric(
                            label="Yukon Rate",
                            value=f"{yk_row['rate_per_100k']:.1f} per 100k",
                        )
                    with col_yk2:
                        st.metric(
                            label="vs National",
                            value=f"{ratio:.1f}x" if pd.notna(ratio) else "N/A",
                            delta=f"{gap:+.1f}" if pd.notna(gap) else None,
                            delta_color="inverse",
                        )
                    with col_yk3:
                        st.metric(label="Severity", value=sev if sev else "N/A")

                # ---- Canadian Choropleth Map (discrete bins, province labels) ----
                map_title = "{} — Rate per 100,000 by Province/Territory ({})".format(
                    selected_disease, int(selected_prov_year)
                )
                st.subheader(map_title)

                canada_geojson = load_canada_geojson()
                map_data = prov_year_data.copy()

                if not map_data.empty and canada_geojson is not None:
                    # ---------- Build discrete 5-tier bins ----------
                    max_rate = float(map_data["rate_per_100k"].max())
                    if max_rate <= 0:
                        max_rate = 1.0
                    raw_step = max_rate / 5.0
                    # Round step to a clean number (nearest 5 or 10)
                    mag = 10 ** max(0, len(str(int(raw_step))) - 1)
                    step = max(1.0, round(raw_step / mag) * mag)
                    bin_edges = [step * i for i in range(5)] + [max_rate * 1.01]

                    bin_colors = ["#FFF3CD", "#FFCC7A", "#FF9A3C", "#E05010", "#8B1800"]
                    bin_labels = [
                        "{:.0f} – {:.0f}".format(bin_edges[i], bin_edges[i + 1])
                        for i in range(5)
                    ]

                    def _get_bin(rate):
                        for idx in range(len(bin_edges) - 1):
                            if bin_edges[idx] <= rate < bin_edges[idx + 1]:
                                return float(idx)
                        return 4.0

                    map_data["bin_idx"] = map_data["rate_per_100k"].apply(_get_bin)

                    # Discrete colorscale: each step is a flat-color segment
                    n_bins = 5
                    disc_scale = []
                    for i in range(n_bins):
                        disc_scale.append([i / n_bins, bin_colors[i]])
                        disc_scale.append([(i + 1) / n_bins, bin_colors[i]])

                    fig_canada = go.Figure()

                    # --- Choropleth fill layer ---
                    fig_canada.add_trace(go.Choropleth(
                        geojson=canada_geojson,
                        locations=map_data["prov_code"],
                        z=map_data["bin_idx"],
                        locationmode="geojson-id",
                        zmin=0,
                        zmax=n_bins,
                        colorscale=disc_scale,
                        colorbar=dict(
                            title="Rate/100k",
                            tickvals=[i + 0.5 for i in range(n_bins)],
                            ticktext=bin_labels,
                            tickfont=dict(size=11),
                            len=0.50,
                            thickness=15,
                            x=1.01,
                        ),
                        marker_line_color="white",
                        marker_line_width=0.8,
                        customdata=list(
                            zip(map_data["prov_code"], map_data["rate_per_100k"])
                        ),
                        hovertemplate=(
                            "<b>%{customdata[0]}</b><br>"
                            "Rate: %{customdata[1]:.1f} per 100k"
                            "<extra></extra>"
                        ),
                    ))

                    # --- Province/territory abbreviation labels ---
                    # Centroid coordinates tuned to sit inside each polygon
                    _PROV_LABEL_COORDS = {
                        "AB": (54.5, -114.5), "BC": (54.5, -124.5),
                        "MB": (55.5, -97.5),  "NB": (46.5, -66.3),
                        "NL": (53.5, -60.5),  "NS": (45.2, -63.2),
                        "NT": (67.5, -117.0), "NU": (70.5, -86.0),
                        "ON": (50.0, -86.5),  "PE": (46.4, -63.3),
                        "QC": (53.5, -70.5),  "SK": (54.5, -105.5),
                        "YT": (63.5, -136.0),
                    }

                    label_prov = map_data[
                        map_data["prov_code"].isin(_PROV_LABEL_COORDS)
                    ].copy()
                    label_prov["lbl_lat"] = label_prov["prov_code"].apply(
                        lambda c: _PROV_LABEL_COORDS[c][0]
                    )
                    label_prov["lbl_lon"] = label_prov["prov_code"].apply(
                        lambda c: _PROV_LABEL_COORDS[c][1]
                    )

                    fig_canada.add_trace(go.Scattergeo(
                        lat=label_prov["lbl_lat"],
                        lon=label_prov["lbl_lon"],
                        text=label_prov["prov_code"],
                        mode="text",
                        textfont=dict(size=9, color="#1E293B", family="Arial Bold"),
                        hoverinfo="skip",
                        showlegend=False,
                    ))

                    fig_canada.update_geos(
                        visible=False,
                        resolution=50,
                        scope="north america",
                        showcountries=True,
                        countrycolor="#9CA3AF",
                        showsubunits=False,
                        showland=True,
                        landcolor="#EFF3F7",
                        showocean=True,
                        oceancolor="#D1E8F5",
                        showlakes=True,
                        lakecolor="#D1E8F5",
                        fitbounds="locations",
                    )
                    fig_canada.update_layout(
                        height=520,
                        margin=dict(l=0, r=0, t=0, b=0),
                        showlegend=False,
                        paper_bgcolor="#FFFFFF",
                        geo_bgcolor="#FFFFFF",
                    )
                    st.plotly_chart(fig_canada, use_container_width=True)

                elif canada_geojson is None:
                    st.info(
                        "Map could not be loaded (no internet connection or GeoJSON unavailable). "
                        "Use the bar chart above for provincial comparisons."
                    )

                # Territory spotlight caption
                if not map_data.empty:
                    territories = ["YT", "NT", "NU"]
                    terr_rows = map_data[map_data["prov_code"].isin(territories)].sort_values(
                        "rate_per_100k", ascending=False
                    )
                    if not terr_rows.empty:
                        terr_parts = []
                        for _, tr in terr_rows.iterrows():
                            terr_parts.append(
                                "{}: {:.1f}".format(tr["prov_code"], tr["rate_per_100k"])
                            )
                        st.caption(
                            "**Territory rates** — "
                            + " | ".join(terr_parts)
                            + " per 100,000"
                        )

            else:
                st.info("No provincial data available for this year.")
        else:
            st.info("No provincial comparison data available for this disease.")

        st.markdown("---")

        # ---- CHART 5: Multi-Disease National Trend (Small Multiples) ----
        st.subheader("All Diseases — National Trend Overview")

        all_diseases = sorted(national_cd["disease"].unique())

        # Create a grid of sparkline-style charts
        n_cols = min(len(all_diseases), 3)
        if n_cols > 0:
            chart_cols = st.columns(n_cols)

            for idx, disease_name in enumerate(all_diseases):
                with chart_cols[idx % n_cols]:
                    d_data = national_cd[national_cd["disease"] == disease_name].sort_values("ref_year")
                    if not d_data.empty:
                        disease_colors_map = {
                            "Chlamydia": "#2563EB",
                            "Gonorrhea": "#7C3AED",
                            "Infectious Syphilis": "#DC2626",
                            "Giardiasis": "#059669",
                            "Salmonellosis": "#D97706",
                        }
                        color = disease_colors_map.get(disease_name, "#374151")

                        fig_mini = go.Figure()
                        r = int(color.lstrip("#")[0:2], 16)
                        g = int(color.lstrip("#")[2:4], 16)
                        b = int(color.lstrip("#")[4:6], 16)
                        fill_rgba = f"rgba({r},{g},{b},0.1)"
                        fig_mini.add_trace(go.Scatter(
                            x=d_data["ref_year"],
                            y=d_data["rate_per_100k"],
                            mode="lines+markers",
                            line=dict(color=color, width=2),
                            marker=dict(size=4),
                            fill="tozeroy",
                            fillcolor=fill_rgba,
                        ))

                        # Mark outbreak years
                        outbreaks = d_data[d_data["is_outbreak_signal"] == True]
                        if not outbreaks.empty:
                            fig_mini.add_trace(go.Scatter(
                                x=outbreaks["ref_year"],
                                y=outbreaks["rate_per_100k"],
                                mode="markers",
                                marker=dict(size=10, color="#DC2626", symbol="triangle-up"),
                                showlegend=False,
                            ))

                        latest_val = d_data.iloc[-1]["rate_per_100k"]
                        peak = d_data["rate_per_100k"].max()
                        peak_yr = d_data.loc[d_data["rate_per_100k"].idxmax(), "ref_year"]

                        fig_mini.update_layout(
                            title=dict(text=disease_name, font=dict(size=14)),
                            height=220,
                            showlegend=False,
                            xaxis=dict(showticklabels=True, dtick=5),
                            yaxis=dict(showticklabels=True),
                            margin=dict(l=30, r=10, t=35, b=25),
                        )
                        st.plotly_chart(fig_mini, use_container_width=True)
                        st.caption(
                            f"Latest: **{latest_val:.1f}** | Peak: **{peak:.1f}** ({int(peak_yr)})"
                        )

        st.markdown("---")

        # ---- Data Table ----
        with st.expander("View Full Communicable Disease Data"):
            display_cd = communicable_df[communicable_df["disease"] == selected_disease][
                ["ref_year", "prov_code", "disease", "rate_per_100k", "outbreak_status_label",
                 "outbreak_z_score", "trend_direction", "severity_vs_national",
                 "disease_category", "data_source"]
            ].copy()
            display_cd.columns = [
                "Year", "Province", "Disease", "Rate/100k", "Outbreak Status",
                "Z-Score", "Trend", "Severity vs National", "Category", "Source"
            ]
            display_cd = display_cd.sort_values(["Year", "Province"])
            st.dataframe(display_cd, use_container_width=True, hide_index=True)

            csv_cd = display_cd.to_csv(index=False)
            st.download_button(
                "Download CSV", csv_cd,
                file_name=f"{selected_disease.lower().replace(' ', '_')}_surveillance.csv",
                mime="text/csv",
            )


# ============================================================================
# PAGE 6: Data Quality & Methodology
# ============================================================================
elif page == "Data Quality & Methodology":
    st.title("Data Quality & Methodology")
    st.markdown(
        "This dashboard is powered by a **dbt (data build tool)** pipeline "
        "that stages, transforms, tests, and serves data from a PostgreSQL database (Supabase)."
    )

    st.subheader("Data Sources — 3 Federal Agencies")
    st.markdown("""
| Source | Agency | Indicator | Rate Type | Coverage |
|--------|--------|-----------|-----------|----------|
| **CIHI Your Health System** | CIHI | ACSC Hospitalizations | Age-standardized per 100k | 2013–2024, all PT |
| **CIHI Your Health System** | CIHI | 30-Day Mental Health Readmissions | Risk-adjusted % | 2015–2025, all PT |
| **CCDSS Data Tool** | PHAC | Diabetes Incidence | Age-standardized per 100k | 2000–2024, all PT |
| **Health Infobase** | PHAC | Opioid & Stimulant Harms | Crude rate per 100k | 2016–2025, all PT |
| **CNDSS + PHAC Reports** | PHAC | Communicable Diseases (STI/Enteric) | Crude rate per 100k | 2000–2023, national + provincial snapshots |
| **Table 17-10-0005-01** | Statistics Canada | Population Estimates | Count | 1971–2024, all PT |
    """)

    st.subheader("Pipeline Architecture")
    st.markdown("""
```
Raw CSVs  -->  Supabase (raw)  -->  dbt staging  -->  dbt intermediate  -->  dbt marts  -->  Dashboard
                                     |                  |                     |
                                     stg_cihi__acsc     int_health__*         mart_dashboard__yukon_overview
                                     stg_cihi__mh       int_mental_health__*  mart_dashboard__provincial_comparison
                                     stg_phac__diabetes  int_diabetes__*      mart_dashboard__trend_analysis
                                     stg_phac__substance int_substance__*     mart_dashboard__substance_harms
                                     stg_phac__cndss    int_communicable__*   mart_dashboard__communicable_disease
                                     stg_statscan__pop
```

- **7 raw tables** from 3 agencies loaded via `load_to_supabase.py`
- **6 staging models** — clean, standardize, map province codes, handle suppressed values
- **6 intermediate models** — link with population, calculate YoY changes, rolling averages, national gap, rankings
- **5 mart models** — purpose-built for each dashboard page, union all indicators
    """)

    st.subheader("Automated Quality Tests")
    st.markdown(
        "The dbt pipeline runs **73 automated tests** on every build, including:"
    )
    st.markdown("""
- `not_null` — Critical columns (prov_code, fiscal_year, rates) are never null across all models
- `unique` — Fiscal year is unique per Yukon overview row
- `accepted_values` — Province codes match valid Canadian jurisdictions; indicator names match expected set; substance types are Opioids/Stimulants
- `assert_yukon_present_in_all_marts` — Singular test that Yukon is never accidentally dropped from any mart
- Cross-model consistency checks between staging, intermediate, and marts
    """)

    col1, col2 = st.columns(2)
    with col1:
        st.subheader("Data Handling Notes")
        st.markdown("""
- **Suppressed values:** CIHI suppresses counts < 5 for privacy. PHAC suppresses counts < 10 or CV > 33.3%. Set to NULL in the pipeline.
- **Confidence intervals:** 95% CIs provided by CIHI and PHAC. Wide CIs for territories reflect small populations.
- **Fiscal years:** Canadian health data uses April-March fiscal years (e.g., 2022-2023). Labeled by start year.
- **Age standardization:** CIHI uses 2011 Canadian population; PHAC CCDSS uses 2021 Canadian population.
- **COVID-19 impact:** PHAC flags 2020-2023 fiscal years with asterisks. Healthcare-seeking behaviour changes may affect estimates.
- **Yukon data availability:** PHAC diabetes data starts at 2010 for Yukon. Earlier years were not collected.
        """)

    with col2:
        st.subheader("Key Indicators")
        st.markdown("""
**ACSC Hospitalizations** *(CIHI)*
Avoidable hospitalizations for conditions manageable in primary care (diabetes, COPD, asthma, heart failure). Higher = gaps in primary care access.

**30-Day Mental Health Readmissions** *(CIHI)*
Percentage of patients readmitted within 30 days of discharge from a mental health or substance use hospitalization. Higher = inadequate community follow-up.

**Diabetes Incidence** *(PHAC CCDSS)*
New diabetes cases per 100,000 population per year, from linked administrative data. Reflects chronic disease burden and prevention effectiveness.

**Substance Use Harms** *(PHAC Health Infobase)*
Apparent opioid/stimulant toxicity deaths and ED visits per 100,000. Yukon declared a Substance Use Health Emergency on Jan 20, 2022. Terminology follows PHAC/Yukon Coroner convention.

**Communicable Disease Surveillance** *(PHAC CNDSS)*
National trends (2000–2023) and provincial snapshots for STIs (Chlamydia, Gonorrhea, Infectious Syphilis) and enteric diseases (Giardiasis, Salmonellosis). Statistical outbreak detection using mean + 2×SD alarm from epidemiological surveillance methodology.
        """)

    st.subheader("Reproducibility")
    st.markdown("""
```bash
# Load raw data to Supabase
python pipeline/load_to_supabase.py

# Build all 17 dbt models
python run_dbt.py run

# Run all 73 quality tests
python run_dbt.py test

# Generate dbt documentation
python run_dbt.py docs generate

# Launch dashboard
streamlit run dashboard/app.py
```
    """)
