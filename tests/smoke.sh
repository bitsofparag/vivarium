#!/bin/sh

set -eu

log_file="${TMPDIR:-/tmp}/vivarium-smoke.log"
expected_user="${VIVARIUM_EXPECTED_USER:-root}"
expected_uid="${VIVARIUM_EXPECTED_UID:-0}"
expected_home="${VIVARIUM_EXPECTED_HOME:-/root}"
: >"$log_file"

run_logged() {
  if ! "$@" >>"$log_file" 2>&1; then
    cat "$log_file" >&2
    exit 1
  fi
}

run_logged docker compose run --rm vivarium keeper doctor
# shellcheck disable=SC2016
run_logged docker compose run --rm \
  -e VIVARIUM_EXPECTED_USER="$expected_user" \
  -e VIVARIUM_EXPECTED_UID="$expected_uid" \
  -e VIVARIUM_EXPECTED_HOME="$expected_home" \
  vivarium sh -lc '
    set -eu
    command -v keeper >/dev/null
    test -w /workspace
    test "$(id -un)" = "$VIVARIUM_EXPECTED_USER"
    test "$(id -u)" = "$VIVARIUM_EXPECTED_UID"
    test "$HOME" = "$VIVARIUM_EXPECTED_HOME"
    test "$(awk -F: -v uid="$VIVARIUM_EXPECTED_UID" '\''$3 == uid { count++ } END { print count + 0 }'\'' /etc/passwd)" = 1
  '

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

python_packages_check='
import pypdfium2
from PIL import Image

assert pypdfium2.PdfDocument
assert Image.new("RGB", (1, 1)).getpixel((0, 0)) == (0, 0, 0)
'
run_logged docker compose run --rm vivarium python -c "$python_packages_check"
