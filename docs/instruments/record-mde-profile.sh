#!/usr/bin/env bash
# Record an MDE performance trace using the repo trace template and Instruments package.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE="${SCRIPT_DIR}/MDE Performance.tracetemplate"
SCHEME="mde"
DERIVED_DATA="${DERIVED_DATA:-/tmp/mde-derived}"
OUTPUT="${1:-${REPO_ROOT}/MDE-Performance-$(date +%Y%m%d-%H%M%S).trace}"
TIME_LIMIT="${TIME_LIMIT:-30s}"

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Missing trace template: ${TEMPLATE}" >&2
  exit 1
fi

echo "Building ${SCHEME} (macOS)…"
xcodebuild \
  -project "${REPO_ROOT}/mde.xcodeproj" \
  -scheme "${SCHEME}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_ENABLE_CODE_COVERAGE=NO \
  >/dev/null

APP="${DERIVED_DATA}/Build/Products/Debug/mde.app"
EXEC="${APP}/Contents/MacOS/mde"

if [[ ! -x "${EXEC}" ]]; then
  echo "Built app not found at ${EXEC}" >&2
  exit 1
fi

echo "Recording → ${OUTPUT}"
echo "  Template: MDE Performance"
echo "  Instruments: Time Profiler, os_signpost"
echo "  Time limit: ${TIME_LIMIT}"
echo ""
echo "Tip: run install-mde-instruments-template.sh once to show this template in Instruments."
echo "Reproduce workloads in the launched app (edit, search, sync), then wait for auto-stop."

xcrun xctrace record \
  --template "${TEMPLATE}" \
  --instrument "Time Profiler" \
  --instrument "os_signpost" \
  --time-limit "${TIME_LIMIT}" \
  --launch -- "${EXEC}" -skipOnboarding \
  --output "${OUTPUT}"

echo ""
echo "Opening trace in Instruments…"
open "${OUTPUT}"
