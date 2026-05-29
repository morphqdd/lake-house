#!/usr/bin/env bash
# Integration test for `house build` — basic build + the manifest
# `env` / `flag` passthrough (#97).
#
# Builds the `house` binary from src/main.lake, then drives it over a
# throwaway fixture project and asserts:
#   1. a bare project builds and the produced binary runs;
#   2. a manifest `flag "<arg>"` reaches lakec (a bogus flag is rejected,
#      a real `--release` flag changes the build mode);
#   3. a manifest `env "K" "V"` line does not break the build.
#
# Env:
#   LAKEC      path to the lakec binary  (default: ../lake-native-compiler/target/release/lakec)
#   LAKE_PATH  path to the Lake stdlib   (default: ../lake-stdlib)
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$here/.." && pwd)"
LAKEC="${LAKEC:-$root/lake-native-compiler/target/release/lakec}"
export LAKE_PATH="${LAKE_PATH:-$root/lake-stdlib}"
# house reads these to locate the toolchain (resolve_lakec / resolve_stdlib);
# exporting them keeps the spawned lakec on the same stdlib as this script.
export LAKEC
export LAKE_STDLIB="${LAKE_STDLIB:-$LAKE_PATH}"

[ -x "$LAKEC" ] || { echo "FAIL: lakec not found at $LAKEC"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Build the house binary.
house="$work/house"
"$LAKEC" "$here/src/main.lake" -o "$work/house-out" >/dev/null
cp "$work/house-out/main" "$house"

# Fixture project.
proj="$work/proj"
mkdir -p "$proj/src"
cat > "$proj/src/main.lake" <<'LAKE'
+std.io.{ println }
main is { _ -> { println("fixture ok") } }
LAKE

run_house() { ( cd "$proj" && "$house" "$@" ); }

pass() { echo "ok - $1"; }
fail() { echo "FAIL - $1"; exit 1; }

# ── 1. bare build + run ──────────────────────────────────────────
cat > "$proj/lake.house" <<'HOUSE'
project "fixture" "0.1.0"
entry "src/main.lake"
HOUSE
run_house build >/dev/null 2>&1 || fail "bare build failed"
out="$("$proj/src/build/main")"
[ "$out" = "fixture ok" ] || fail "bare build binary output: '$out'"
pass "bare project builds and runs"

# ── 2a. bogus flag is forwarded to lakec (and rejected) ──────────
cat > "$proj/lake.house" <<'HOUSE'
project "fixture" "0.1.0"
entry "src/main.lake"
flag "--bogus-flag-xyz"
HOUSE
log="$(run_house build 2>&1 || true)"
echo "$log" | grep -q "bogus-flag-xyz" || fail "bogus flag not forwarded to lakec: $log"
pass "manifest flag reaches lakec argv"

# ── 2b. real --release flag changes build mode ───────────────────
cat > "$proj/lake.house" <<'HOUSE'
project "fixture" "0.1.0"
entry "src/main.lake"
flag "--release"
HOUSE
log="$(run_house build 2>&1)"
echo "$log" | grep -q "\[release\]" || fail "--release flag not applied: $log"
"$proj/src/build/main" | grep -q "fixture ok" || fail "release binary did not run"
pass "manifest flag --release applied"

# ── 3. env line does not break the build ─────────────────────────
cat > "$proj/lake.house" <<'HOUSE'
project "fixture" "0.1.0"
entry "src/main.lake"
env "HOUSE_TEST_ENV" "xyz"
HOUSE
run_house build >/dev/null 2>&1 || fail "build with env line failed"
"$proj/src/build/main" | grep -q "fixture ok" || fail "env-build binary did not run"
pass "manifest env line builds cleanly"

# ── 4. house test — passing + failing ────────────────────────────
cat > "$proj/lake.house" <<'HOUSE'
project "fixture" "0.1.0"
entry "src/main.lake"
HOUSE
mkdir -p "$proj/tests"
cat > "$proj/tests/main.lake" <<'LAKE'
+std.io.{ println }
+std.panic.{ assert }
main is {
  _ -> {
    pin assert(1 + 1 == 2 "math works")
    println("[ok] tests passed")
  }
}
LAKE
run_house test >/dev/null 2>&1 || fail "house test (passing) should exit 0"
pass "house test — passing suite exits 0"

cat > "$proj/tests/main.lake" <<'LAKE'
+std.io.{ println }
+std.panic.{ assert }
main is {
  _ -> {
    pin assert(1 + 1 == 3 "math is broken")
    println("[ok] unreachable")
  }
}
LAKE
if run_house test >/dev/null 2>&1; then
  fail "house test (failing) should exit non-zero"
fi
pass "house test — failing suite exits non-zero"

echo "ALL PASS"
