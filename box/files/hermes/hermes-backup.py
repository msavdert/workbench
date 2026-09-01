#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3>=1.34"]
# ///
"""Nightly encrypted hermes backup to OCI S3.

Pipeline (run as the agent user by hermes-backup.service):
  1. `hermes backup -o <tmp>.zip` - full ~/.hermes snapshot (hermes' own
     tool; excludes the codebase, node_modules, __pycache__; credentials
     included by design - which is why step 2 exists).
  2. Encrypt with age (recipients from AGE_RECIPIENTS, public keys only).
  3. Upload <label>-<UTC date>.zip.age to the S3 bucket via boto3.
  4. Delete remote objects older than RETENTION_DAYS and prune local files.

Credentials never touch disk or the repo: S3 keys and the age recipient
arrive via the environment (systemd EnvironmentFile lines may hold op://
refs, resolved by `op inject` in the bootstrap step; the manual path is
`op run --env-file=...`).  A nonzero exit anywhere aborts before upload.

Why boto3 and not the aws CLI: OCI's S3 compatibility layer rejects the
aws-chunked encoding that both AWS CLI v2 and modern botocore send by
default; boto3 accepts request_checksum_calculation="when_required" while
the CLI has no equivalent switch (verified against this endpoint on
2026-08-31).
"""

from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import boto3
from botocore.config import Config

# --- required environment (fail loudly, never guess) -----------------------
ENDPOINT = os.environ["S3_ENDPOINT"]
REGION = os.environ["S3_REGION"]
BUCKET = os.environ["S3_BUCKET"]
PREFIX = os.environ.get("S3_PREFIX", "hermes/backup/").lstrip("/")
ACCESS_KEY = os.environ["S3_ACCESS_KEY_ID"]
SECRET_KEY = os.environ["S3_SECRET_ACCESS_KEY"]
AGE_RECIPIENTS = [r.strip() for r in os.environ["AGE_RECIPIENTS"].split(",") if r.strip()]

RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "30"))
LOCAL_KEEP = int(os.environ.get("LOCAL_KEEP", "7"))
LOCAL_DIR = Path(os.environ.get("LOCAL_DIR", str(Path.home() / "backup" / "hermes")))
LABEL = os.environ.get("BACKUP_LABEL", "hermes")


def fail(msg: str) -> "NoReturn":  # type: ignore[valid-type]
    print(f"hermes-backup: FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if not AGE_RECIPIENTS:
        fail("AGE_RECIPIENTS is empty")

    s3 = boto3.client(
        "s3",
        endpoint_url=ENDPOINT,
        region_name=REGION,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        config=Config(
            signature_version="s3v4",
            # OCI compat layer: no aws-chunked, no trailing checksums.
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
        ),
    )

    # 1. hermes' own full backup (consistent while the gateway runs).
    LOCAL_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="hermes-backup.") as td:
        tmp_zip = Path(td) / "backup.zip"
        r = subprocess.run(
            ["hermes", "backup", "-o", str(tmp_zip)],
            capture_output=True, text=True, timeout=1800,
        )
        # hermes backup -q is broken (0.20.5): it writes a state-snapshots
        # entry and exits 0 without producing the zip - so always full mode.
        if r.returncode != 0 or not tmp_zip.exists():
            fail(f"hermes backup failed: {r.stdout[-500:]} {r.stderr[-500:]}")

        # 2. encrypt - age reads stdin, writes stdout; nothing lands on disk
        # in plaintext except hermes' own temp zip (mode 0600, tmpfs-adjacent
        # temp dir, deleted below).
        recipient_args: list[str] = []
        for rec in AGE_RECIPIENTS:
            recipient_args += ["-r", rec]
        enc = subprocess.run(
            ["age"] + recipient_args,
            input=tmp_zip.read_bytes(), capture_output=True, timeout=1800,
        )
        if enc.returncode != 0:
            fail(f"age encryption failed: {enc.stderr.decode()[-500:]}")
        blob = enc.stdout
        plain_size = tmp_zip.stat().st_size

    day = dt.datetime.now(dt.UTC).strftime("%Y-%m-%d")
    key = f"{PREFIX}{LABEL}-backup-{day}.zip.age"
    s3.put_object(
        Bucket=BUCKET, Key=key, Body=blob,
        ContentType="application/octet-stream",
        Metadata={"label": LABEL, "plain-size": str(plain_size)},
    )
    print(f"hermes-backup: uploaded s3://{BUCKET}/{key} ({len(blob)} bytes)")

    # 3. retention: remote objects older than RETENTION_DAYS, same prefix.
    cutoff = dt.datetime.now(dt.UTC) - dt.timedelta(days=RETENTION_DAYS)
    old = [
        o["Key"]
        for o in s3.list_objects_v2(Bucket=BUCKET, Prefix=PREFIX).get("Contents", [])
        if o["LastModified"].replace(tzinfo=dt.UTC) < cutoff
    ]
    if old:
        s3.delete_objects(
            Bucket=BUCKET, Delete={"Objects": [{"Key": k} for k in old], "Quiet": True}
        )
        print(f"hermes-backup: pruned {len(old)} remote object(s)")

    # 4. local copies: keep the newest LOCAL_KEEP, only our own label.
    local = sorted(LOCAL_DIR.glob(f"{LABEL}-backup-*.zip.age"))
    for stale in local[:-LOCAL_KEEP] if len(local) > LOCAL_KEEP else []:
        stale.unlink()
        print(f"hermes-backup: pruned local {stale.name}")

    # local copy for fast restores (metadata says which object is newest)
    (LOCAL_DIR / f"{LABEL}-backup-{day}.zip.age").write_bytes(blob)

    state = {"last_run_utc": dt.datetime.now(dt.UTC).isoformat(), "key": key}
    (LOCAL_DIR / f"{LABEL}-backup-state.json").write_text(json.dumps(state))
    print("hermes-backup: OK")


if __name__ == "__main__":
    main()
