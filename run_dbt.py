"""
Helper to run dbt commands with .env loaded.
Usage:
  python run_dbt.py run
  python run_dbt.py test
  python run_dbt.py docs generate
"""
from __future__ import annotations

import subprocess
import sys
import os
from pathlib import Path
from dotenv import load_dotenv

PROJECT_DIR = Path(__file__).resolve().parent
DBT_DIR = PROJECT_DIR / "dbt_project"

load_dotenv(PROJECT_DIR / ".env")

args = sys.argv[1:] if len(sys.argv) > 1 else ["run"]

cmd = ["python", "-m", "dbt.cli.main"] + args + ["--profiles-dir", str(DBT_DIR)]

result = subprocess.run(cmd, cwd=str(DBT_DIR), env={**os.environ})
sys.exit(result.returncode)
