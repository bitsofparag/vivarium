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
