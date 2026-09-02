#!/usr/bin/env bash
# tests/test-install-meslo-fonts.sh — TAP-13 suite for setup_terminal_fonts().

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_sh="$repo_root/install.sh"

tmp_dir="$(mktemp -d -t install-meslo-fonts-test.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

plan_count=5
echo "1..$plan_count"
echo "# repo_root=$repo_root"

n=0
fail=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=$((fail+1)); echo "not ok $n - $1"; [[ -n "${2:-}" ]] && echo "# $2"; }

source_install() {
  # shellcheck disable=SC1090
  source "$install_sh"
}

# T1: Linux skip
test_T1() {
  local out
  out="$(bash -c '
    install_sh="$1"
    source "$install_sh"
    OS=linux
    DRY_RUN=0
    install_meslo_fonts 2>&1
  ' _ "$install_sh")"
  if printf '%s' "$out" | grep -q 'skip Meslo fonts'; then
    ok "install_meslo_fonts skips on Linux"
  else
    nok "install_meslo_fonts skips on Linux" "$out"
  fi
}

# T2: macOS dry-run prints curl for missing fonts
test_T2() {
  local out
  out="$(HOME="$tmp_dir/home" bash -c '
    install_sh="$1"
    source "$install_sh"
    OS=macos
    DRY_RUN=1
    install_meslo_fonts 2>&1
  ' _ "$install_sh")"
  if printf '%s' "$out" | grep -Fq 'MesloLGS%20NF%20Regular.ttf'; then
    ok "install_meslo_fonts dry-run prints curl for missing fonts"
  else
    nok "install_meslo_fonts dry-run prints curl for missing fonts" "$out"
  fi
}

# T3: macOS installs Regular variant to isolated HOME
test_T3() {
  local home="$tmp_dir/install-home"
  mkdir -p "$home/Library/Fonts"
  HOME="$home" bash -c '
    install_sh="$1"
    source "$install_sh"
    OS=macos
    DRY_RUN=0
    MESLO_FONT_VARIANTS=(Regular)
    install_meslo_fonts >/dev/null 2>&1
  ' _ "$install_sh"
  if [[ -f "$home/Library/Fonts/MesloLGS NF Regular.ttf" ]]; then
    ok "install_meslo_fonts downloads Regular to isolated HOME"
  else
    nok "install_meslo_fonts downloads Regular to isolated HOME"
  fi
}

# T4: configure_iterm2_meslo_font updates Monaco profile
test_T4() {
  local home="$tmp_dir/iterm-home"
  mkdir -p "$home/Library/Preferences"
  python3 - "$home/Library/Preferences/com.googlecode.iterm2.plist" <<'PY'
import plistlib, pathlib, sys
path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
data = {"New Bookmarks": [{"Normal Font": "Monaco 14", "Non Ascii Font": "Monaco 12"}]}
with path.open("wb") as f:
    plistlib.dump(data, f)
PY
  HOME="$home" bash -c '
    install_sh="$1"
    source "$install_sh"
    OS=macos
    DRY_RUN=0
    configure_iterm2_meslo_font >/dev/null 2>&1
  ' _ "$install_sh"
  local font
  font="$(python3 - "$home/Library/Preferences/com.googlecode.iterm2.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    d = plistlib.load(f)
print(d["New Bookmarks"][0]["Normal Font"])
PY
)"
  if [[ "$font" == "MesloLGSNF-Regular 14" ]]; then
    ok "configure_iterm2_meslo_font updates Monaco profile"
  else
    nok "configure_iterm2_meslo_font updates Monaco profile" "got: $font"
  fi
}

# T5: configure_iterm2 skips when already Meslo
test_T5() {
  local home="$tmp_dir/iterm-meslo"
  mkdir -p "$home/Library/Preferences"
  python3 - "$home/Library/Preferences/com.googlecode.iterm2.plist" <<'PY'
import plistlib, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = {"New Bookmarks": [{"Normal Font": "MesloLGSNF-Regular 14"}]}
with path.open("wb") as f:
    plistlib.dump(data, f)
PY
  local out
  out="$(HOME="$home" bash -c '
    install_sh="$1"
    source "$install_sh"
    OS=macos
    DRY_RUN=0
    configure_iterm2_meslo_font 2>&1
  ' _ "$install_sh")"
  if printf '%s' "$out" | grep -q 'skip iTerm2 font (already Meslo'; then
    ok "configure_iterm2_meslo_font skips when already Meslo"
  else
    nok "configure_iterm2_meslo_font skips when already Meslo" "$out"
  fi
}

test_T1
test_T2
test_T3
test_T4
test_T5

exit "$fail"
