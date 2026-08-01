#!/bin/sh

set -eu

log_file="${TMPDIR:-/tmp}/vivarium-smoke.log"
: >"$log_file"

run_logged() {
  if ! "$@" >>"$log_file" 2>&1; then
    cat "$log_file" >&2
    exit 1
  fi
}

run_logged docker compose run --rm vivarium keeper doctor
run_logged docker compose run --rm vivarium sh -lc 'command -v keeper >/dev/null; test -w /workspace'

timezone_check='
from datetime import datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

berlin = ZoneInfo("Europe/Berlin")
before = datetime(2026, 3, 29, 0, 59, tzinfo=timezone.utc).astimezone(berlin)
after = datetime(2026, 3, 29, 1, 0, tzinfo=timezone.utc).astimezone(berlin)
assert before.isoformat() == "2026-03-29T01:59:00+01:00"
assert after.isoformat() == "2026-03-29T03:00:00+02:00"

try:
    ZoneInfo("Europe/Not_A_Zone")
except ZoneInfoNotFoundError:
    pass
else:
    raise AssertionError("invalid timezone unexpectedly resolved")
'
run_logged docker compose run --rm vivarium python -c "$timezone_check"
