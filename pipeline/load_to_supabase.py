"""
Load raw CSV data into Supabase Postgres (raw schema).
Creates tables and bulk-inserts from CIHI CSVs and StatsCan data.
"""
from __future__ import annotations

import os
import logging
from pathlib import Path

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"


def get_connection():
    return psycopg2.connect(
        host=os.getenv("SUPABASE_HOST"),
        port=os.getenv("SUPABASE_PORT"),
        user=os.getenv("SUPABASE_USER"),
        password=os.getenv("SUPABASE_PASSWORD"),
        dbname=os.getenv("SUPABASE_DB"),
        sslmode="require",
    )


def clean_column_name(col: str) -> str:
    return (
        col.lower()
        .replace("\xa0", "_")  # non-breaking space
        .replace(" ", "_")
        .replace("/", "_")
        .replace("-", "_")
        .replace("(", "")
        .replace(")", "")
        .replace("%", "pct")
        .replace(",", "")
        .strip("_")
    )


def load_dataframe_to_table(
    df: pd.DataFrame,
    table_name: str,
    schema: str = "raw",
):
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    df.columns = [clean_column_name(c) for c in df.columns]
    df = df.where(pd.notnull(df), None)

    full_table = f"{schema}.{table_name}"

    col_types = []
    for col in df.columns:
        dtype = df[col].dtype
        if pd.api.types.is_integer_dtype(dtype):
            col_types.append(f'"{col}" BIGINT')
        elif pd.api.types.is_float_dtype(dtype):
            col_types.append(f'"{col}" DOUBLE PRECISION')
        else:
            col_types.append(f'"{col}" TEXT')

    cur.execute(f"DROP TABLE IF EXISTS {full_table}")
    create_sql = f"CREATE TABLE {full_table} (\n  {','.join(col_types)}\n)"
    cur.execute(create_sql)
    log.info(f"Created table {full_table} ({len(df.columns)} columns)")

    cols = ", ".join(f'"{c}"' for c in df.columns)
    insert_sql = f"INSERT INTO {full_table} ({cols}) VALUES %s"

    rows = [tuple(row) for row in df.itertuples(index=False, name=None)]

    batch_size = 1000
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        execute_values(cur, insert_sql, batch)

    log.info(f"Loaded {len(rows)} rows into {full_table}")

    cur.close()
    conn.close()


def load_cihi_acsc():
    path = RAW_DIR / "Ambulatory_care_sensitive_conditions.csv"
    if not path.exists():
        log.warning(f"CIHI ACSC file not found: {path}")
        return

    df = pd.read_csv(path)
    log.info(f"CIHI ACSC: {len(df)} rows, columns: {list(df.columns)}")
    load_dataframe_to_table(df, "cihi_acsc")


def load_statscan_population():
    path = RAW_DIR / "statscan_population.csv"
    if not path.exists():
        log.warning(f"StatsCan file not found: {path}")
        return

    df = pd.read_csv(path, low_memory=False)

    # Filter to total population (both sexes, all ages) to keep table manageable
    gender_col = [c for c in df.columns if "gender" in c.lower() or "sex" in c.lower()]
    age_col = [c for c in df.columns if "age" in c.lower()]

    if gender_col:
        df = df[df[gender_col[0]].astype(str).str.strip().isin(["Both sexes", "Total - gender"])]
    if age_col:
        df = df[df[age_col[0]].astype(str).str.strip().isin(["All ages", "Total, all ages"])]

    log.info(f"StatsCan Population (filtered): {len(df)} rows")
    load_dataframe_to_table(df, "statscan_population")


def load_cihi_mental_health():
    """Load CIHI 30-Day Readmission for Mental Health and Substance Use."""
    path = RAW_DIR / "CIHI_mental_health_readmissions.csv"
    if not path.exists():
        log.warning(f"CIHI Mental Health file not found: {path}")
        return

    # Row 1 is a title row ("Table 1 30-Day Readmission..."), actual headers on row 2
    df = pd.read_csv(path, header=1)
    log.info(f"CIHI Mental Health: {len(df)} rows, columns: {list(df.columns)}")
    load_dataframe_to_table(df, "cihi_mental_health_readmissions")


def load_phac_ccdss_diabetes():
    """Load PHAC CCDSS Diabetes incidence data."""
    path = RAW_DIR / "PHAC_Infobase_CCDSS.csv"
    if not path.exists():
        log.warning(f"PHAC CCDSS file not found: {path}")
        return

    # Row 1 is a title row, skip it. File uses latin-1 encoding (non-breaking spaces).
    df = pd.read_csv(path, skiprows=1, encoding="latin-1")

    # Clean non-breaking spaces in column names
    df.columns = [c.replace("\xa0", " ") for c in df.columns]

    log.info(f"PHAC CCDSS Diabetes: {len(df)} rows, columns: {list(df.columns)}")
    load_dataframe_to_table(df, "phac_ccdss_diabetes")


def load_phac_substance_harms():
    """Load PHAC Health Infobase — Opioid- and Stimulant-related Harms."""
    path = RAW_DIR / "SubstanceHarmsData.csv"
    if not path.exists():
        log.warning(f"PHAC Substance Harms file not found: {path}")
        return

    df = pd.read_csv(path)
    log.info(f"PHAC Substance Harms: {len(df)} rows, columns: {list(df.columns)}")
    load_dataframe_to_table(df, "phac_substance_harms")


def load_phac_cndss_national():
    """Load PHAC CNDSS national disease data (1991-2023, Male/Female split)."""
    path = RAW_DIR / "Data.csv"
    if not path.exists():
        log.warning(f"PHAC CNDSS national file not found: {path}")
        return

    df = pd.read_csv(path)
    log.info(f"PHAC CNDSS National: {len(df)} rows, columns: {list(df.columns)}")
    load_dataframe_to_table(df, "phac_cndss_national")


def load_phac_cndss_provincial():
    """Load PHAC CNDSS STI provincial data (extracted from PHAC reports)."""
    path = RAW_DIR / "STI_Provincial_Data.csv"
    if not path.exists():
        log.warning(f"PHAC CNDSS provincial file not found: {path}")
        return

    df = pd.read_csv(path)
    log.info(f"PHAC CNDSS Provincial: {len(df)} rows, columns: {list(df.columns)}")
    load_dataframe_to_table(df, "phac_cndss_provincial")


def run():
    log.info("=" * 60)
    log.info("LOADING DATA TO SUPABASE")
    log.info("=" * 60)

    load_cihi_acsc()
    load_statscan_population()
    load_cihi_mental_health()
    load_phac_ccdss_diabetes()
    load_phac_substance_harms()
    load_phac_cndss_national()
    load_phac_cndss_provincial()

    log.info("=" * 60)
    log.info("LOAD COMPLETE")
    log.info("=" * 60)


if __name__ == "__main__":
    run()
