#!/usr/bin/env python3
"""
Package Age Gate — Supply Chain Defense for agent-forge

Checks whether a package was published to its registry within a configurable
threshold (default: 7 days). Used by pip/npm wrapper scripts to block or warn
on suspiciously new packages that may be supply chain attacks.

Usage:
    python3 gate.py <pip|npm> <package> [version]

Exit codes:
    0 — package is allowed (old enough, allowlisted, or fail-open)
    1 — package is blocked (too new, enforce mode)
    2 — usage error

Environment variables:
    PACKAGE_AGE_GATE           enforce|audit|off  (default: enforce)
    PACKAGE_AGE_GATE_THRESHOLD days               (default: 7)
    PACKAGE_AGE_GATE_TIMEOUT   seconds            (default: 5)
    PACKAGE_AGE_GATE_ALLOWLIST path to allowlist   (default: /usr/local/lib/package-age-gate/allowlist.txt)
    PACKAGE_AGE_GATE_LOG       path to log file    (default: ~/.local/log/package-age-gate.log)
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VALID_MODES = {"enforce", "audit", "off"}


def _safe_int(env_var, default):
    """Parse an integer from env, falling back to default on bad input."""
    try:
        return int(os.environ.get(env_var, str(default)))
    except ValueError:
        return default


def load_config():
    """Read environment variables and return a config dict."""
    home = Path.home()
    mode = os.environ.get("PACKAGE_AGE_GATE", "enforce").lower()
    if mode not in VALID_MODES:
        print(
            f"[AGE-GATE] Invalid PACKAGE_AGE_GATE mode: {mode!r}. "
            f"Using 'enforce'. Valid: {', '.join(sorted(VALID_MODES))}",
            file=sys.stderr,
        )
        mode = "enforce"

    return {
        "mode": mode,
        "threshold_days": _safe_int("PACKAGE_AGE_GATE_THRESHOLD", 7),
        "timeout_seconds": _safe_int("PACKAGE_AGE_GATE_TIMEOUT", 5),
        "allowlist_path": os.environ.get(
            "PACKAGE_AGE_GATE_ALLOWLIST",
            "/usr/local/lib/package-age-gate/allowlist.txt",
        ),
        "log_path": os.environ.get(
            "PACKAGE_AGE_GATE_LOG",
            str(home / ".local" / "log" / "package-age-gate.log"),
        ),
    }


# ---------------------------------------------------------------------------
# Allowlist
# ---------------------------------------------------------------------------

def load_allowlist(path):
    """Load allowlist file. Returns a set of lowercase package names.
    Returns empty set if the file is missing (fail-open)."""
    try:
        with open(path) as f:
            entries = set()
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                entries.add(line.lower())
            return entries
    except (OSError, IOError):
        return set()


def is_allowlisted(package, allowlist):
    """Case-insensitive allowlist check."""
    return package.lower() in allowlist


# ---------------------------------------------------------------------------
# Registry queries
# ---------------------------------------------------------------------------

def _parse_iso_timestamp(ts):
    """Parse an ISO 8601 timestamp (with or without trailing Z) to UTC datetime."""
    if not ts:
        return None
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts)


def query_pypi(package, version, timeout):
    """Query PyPI JSON API for a package's publish date.

    Uses version-specific endpoint when version is known to reduce bandwidth.
    Returns: datetime (UTC) or None on any error.
    """
    encoded = urllib.parse.quote(package, safe="")
    if version:
        # Version-specific endpoint — returns only this version's metadata
        url = f"https://pypi.org/pypi/{encoded}/{urllib.parse.quote(version, safe='')}/json"
    else:
        url = f"https://pypi.org/pypi/{encoded}/json"

    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read())
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError):
        return None

    try:
        # Version-specific endpoint returns "urls" array directly;
        # full endpoint returns "releases" dict keyed by version.
        if version:
            file_list = data.get("urls", [])
        else:
            version = data["info"]["version"]
            file_list = data.get("releases", {}).get(version, [])

        if not file_list:
            return None

        ts = file_list[0].get("upload_time_iso_8601")
        if ts:
            return _parse_iso_timestamp(ts)

        # Fallback to upload_time (no timezone info, assume UTC)
        ts = file_list[0].get("upload_time")
        if ts:
            return datetime.fromisoformat(ts).replace(tzinfo=timezone.utc)
        return None

    except (KeyError, IndexError, ValueError):
        return None


def query_npm(package, version, timeout):
    """Query npm registry API for a package's publish date.

    Scoped packages: @scope/pkg -> @scope%2fpkg in URL.
    Returns: datetime (UTC) or None on any error.
    """
    if package.startswith("@"):
        encoded = urllib.parse.quote(package, safe="@")
    else:
        encoded = urllib.parse.quote(package, safe="")

    url = f"https://registry.npmjs.org/{encoded}"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read())
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError):
        return None

    try:
        if not version:
            version = data.get("dist-tags", {}).get("latest")
            if not version:
                return None

        ts = data.get("time", {}).get(version)
        return _parse_iso_timestamp(ts)

    except (KeyError, ValueError):
        return None


def get_publish_date(manager, package, version, timeout):
    """Dispatch to the appropriate registry query."""
    if manager == "pip":
        return query_pypi(package, version, timeout)
    elif manager == "npm":
        return query_npm(package, version, timeout)
    else:
        return None


# ---------------------------------------------------------------------------
# Decision logic
# ---------------------------------------------------------------------------

def check_age(publish_date, threshold_days):
    """Check if the package is old enough.
    Returns (is_allowed, age_in_days)."""
    now = datetime.now(timezone.utc)
    age = now - publish_date
    age_days = age.days
    return (age_days >= threshold_days, age_days)


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

def log_decision(log_path, entry):
    """Append a JSON line to the log file. Silently skip on failure."""
    try:
        log_dir = os.path.dirname(log_path)
        if log_dir:
            os.makedirs(log_dir, exist_ok=True)
        with open(log_path, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        print("Usage: gate.py <pip|npm> <package> [version]", file=sys.stderr)
        return 2

    manager = sys.argv[1].lower()
    package = sys.argv[2]
    version = sys.argv[3] if len(sys.argv) > 3 else None

    if manager not in ("pip", "npm"):
        print(f"Unknown manager: {manager}. Use 'pip' or 'npm'.", file=sys.stderr)
        return 2

    config = load_config()

    # Off mode — allow everything, no checks
    if config["mode"] == "off":
        return 0

    # Check allowlist first (no network call needed)
    allowlist = load_allowlist(config["allowlist_path"])
    if is_allowlisted(package, allowlist):
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "package": package,
            "manager": manager,
            "version": version,
            "action": "ALLOWED",
            "reason": "allowlisted",
        }
        log_decision(config["log_path"], entry)
        print(json.dumps(entry))
        return 0

    # Query registry for publish date
    publish_date = get_publish_date(
        manager, package, version, config["timeout_seconds"]
    )

    if publish_date is None:
        # Fail-open: can't determine age, allow the install
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "package": package,
            "manager": manager,
            "version": version,
            "action": "ALLOWED",
            "reason": "registry_unreachable_or_not_found",
        }
        log_decision(config["log_path"], entry)
        print(json.dumps(entry))
        return 0

    # Check age
    is_allowed, age_days = check_age(publish_date, config["threshold_days"])

    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "package": package,
        "manager": manager,
        "version": version or "latest",
        "published": publish_date.isoformat(),
        "age_days": age_days,
        "threshold_days": config["threshold_days"],
        "action": "ALLOWED" if is_allowed else "BLOCKED",
        "mode": config["mode"],
    }

    if is_allowed:
        log_decision(config["log_path"], entry)
        print(json.dumps(entry))
        return 0
    else:
        # Package is too new
        if config["mode"] == "audit":
            entry["action"] = "WARNED"
            log_decision(config["log_path"], entry)
            print(json.dumps(entry))
            print(
                f"[AGE-GATE WARNING] {package} was published {age_days} day(s) ago "
                f"(threshold: {config['threshold_days']} days). "
                f"Allowing in audit mode.",
                file=sys.stderr,
            )
            return 0
        else:
            # enforce mode — block
            log_decision(config["log_path"], entry)
            print(json.dumps(entry))
            print(
                f"[AGE-GATE BLOCKED] {package} was published {age_days} day(s) ago "
                f"(threshold: {config['threshold_days']} days). "
                f"Package rejected for supply chain safety.",
                file=sys.stderr,
            )
            return 1


if __name__ == "__main__":
    sys.exit(main())
