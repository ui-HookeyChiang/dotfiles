#!/usr/bin/env bash
# entry.sh — sources its lib via a ${BASH_SOURCE[0]%/*}/ dir prefix.
set -euo pipefail
# shellcheck source=lib/helper.sh
source "${BASH_SOURCE[0]%/*}/lib/helper.sh"
do_thing
