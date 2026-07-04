#!/usr/bin/env bash
# True cold-launch benchmark via Instruments (NFR-02).
# Launches a fresh mde process with `open -n` while xctrace records (all-processes).
# Primary metric: cold_launch_to_editor result file written by the app; trace is secondary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE="${SCRIPT_DIR}/MDE Performance.tracetemplate"
PARSER="${SCRIPT_DIR}/parse-cold-launch-trace.py"
SCHEME="mde"
DERIVED_DATA="${DERIVED_DATA:-/tmp/mde-derived}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/build/cold-launch}"
ITERATIONS="${ITERATIONS:-3}"
BUDGET_MS="${BUDGET_MS:-2000}"
TOLERANCE="${TOLERANCE:-1.10}"
TIME_LIMIT="${TIME_LIMIT:-15s}"
RESULT_TIMEOUT_SEC="${RESULT_TIMEOUT_SEC:-12}"

mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

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

# Ad-hoc sign so Instruments can sample the GUI process reliably.
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || true

BENCHMARK_VAULT="${VAULT_PATH:-${OUTPUT_DIR}/benchmark-vault.mde}"
if [[ -z "${VAULT_PATH:-}" ]]; then
  echo "Preparing benchmark vault at ${BENCHMARK_VAULT}…"
  rm -rf "${BENCHMARK_VAULT}"
  MDE_BENCHMARK_VAULT_PATH="${BENCHMARK_VAULT}" \
    "${EXEC}" -createBenchmarkVault
fi

if [[ ! -d "${BENCHMARK_VAULT}" ]]; then
  echo "Benchmark vault missing: ${BENCHMARK_VAULT}" >&2
  exit 1
fi

quit_mde() {
  osascript -e 'tell application "mde" to quit' 2>/dev/null || true
  local waited=0
  while pgrep -x mde >/dev/null && [[ "${waited}" -lt 12 ]]; do
    sleep 0.25
    waited=$((waited + 1))
  done
  if pgrep -x mde >/dev/null; then
    pkill -x mde 2>/dev/null || true
    sleep 0.5
  fi
}

RESULTS_FILE="${OUTPUT_DIR}/cold-launch-results.json"
echo "[" > "${RESULTS_FILE}"
first_result=1
declare -a SAMPLES=()

for ((i = 1; i <= ITERATIONS; i++)); do
  echo ""
  echo "=== Cold launch iteration ${i}/${ITERATIONS} ==="

  quit_mde
  sleep 0.5

  TRACE_PATH="${OUTPUT_DIR}/cold-launch-${i}.trace"
  RESULT_PATH="${OUTPUT_DIR}/cold-launch-${i}.ms"
  rm -rf "${TRACE_PATH}"
  rm -f "${RESULT_PATH}" "${BENCHMARK_VAULT}/cold-launch-result.ms"

  echo "Recording (all processes) → ${TRACE_PATH}"
  trace_status=0
  (
    cd "${OUTPUT_DIR}"
    xcrun xctrace record \
      --template "${TEMPLATE}" \
      --instrument "Time Profiler" \
      --instrument "os_signpost" \
      --time-limit "${TIME_LIMIT}" \
      --no-prompt \
      --all-processes \
      --output "${TRACE_PATH}"
  ) &
  trace_pid=$!

  # Let Instruments attach before the cold launch.
  sleep 1.0

  echo "Cold launching → ${APP}"
  open -n -g -a "${APP}" --args \
    -skipOnboarding \
    -benchmarkColdLaunch "${BENCHMARK_VAULT}" \
    -benchmarkColdLaunchResultPath "${RESULT_PATH}"

  found_result=0
  for ((waited = 0; waited < RESULT_TIMEOUT_SEC * 20; waited++)); do
    if [[ -f "${RESULT_PATH}" ]]; then
      found_result=1
      break
    fi
    if [[ -f "${BENCHMARK_VAULT}/cold-launch-result.ms" ]]; then
      cp "${BENCHMARK_VAULT}/cold-launch-result.ms" "${RESULT_PATH}"
      found_result=1
      break
    fi
    sleep 0.05
  done

  if [[ "${found_result}" -eq 1 ]]; then
    sleep 0.3
    kill -INT "${trace_pid}" 2>/dev/null || true
  fi

  quit_mde
  wait "${trace_pid}" 2>/dev/null || trace_status=$?

  ACTUAL_TRACE="${TRACE_PATH}"
  if [[ ! -d "${ACTUAL_TRACE}" ]]; then
    ACTUAL_TRACE="$(ls -td "${OUTPUT_DIR}"/Launch_mde*.trace "${REPO_ROOT}"/Launch_mde*.trace 2>/dev/null | head -1 || true)"
    if [[ -n "${ACTUAL_TRACE}" && "${ACTUAL_TRACE}" != "${TRACE_PATH}" ]]; then
      rm -rf "${TRACE_PATH}"
      mv "${ACTUAL_TRACE}" "${TRACE_PATH}"
      ACTUAL_TRACE="${TRACE_PATH}"
    fi
  fi

  if [[ ! -d "${ACTUAL_TRACE}" ]]; then
    echo "Recording finished (xctrace exit ${trace_status}); trace bundle missing." >&2
  fi

  if [[ "${found_result}" -eq 0 ]]; then
    echo "Warning: benchmark result file not written: ${RESULT_PATH}" >&2
  fi

  PARSE_OUTPUT="$("${PARSER}" "${ACTUAL_TRACE}" --result-file "${RESULT_PATH}" --budget-ms "${BUDGET_MS}" --tolerance "${TOLERANCE}" || true)"
  echo "${PARSE_OUTPUT}"

  DURATION_MS="$(echo "${PARSE_OUTPUT}" | awk -F= '/^cold_launch_to_editor_ms=/{print $2}')"
  STATUS="$(echo "${PARSE_OUTPUT}" | awk -F= '/^status=/{print $2}')"

  if [[ -z "${DURATION_MS}" ]]; then
    echo "Parser could not extract duration for iteration ${i}" >&2
    STATUS="PARSE_FAIL"
    DURATION_MS="null"
  else
    SAMPLES+=("${DURATION_MS}")
  fi

  if [[ "${first_result}" -eq 1 ]]; then
    first_result=0
  else
    echo "," >> "${RESULTS_FILE}"
  fi

  printf '  {"iteration": %d, "trace": "%s", "result_file": "%s", "cold_launch_to_editor_ms": %s, "status": "%s"}' \
    "${i}" "${ACTUAL_TRACE}" "${RESULT_PATH}" "${DURATION_MS}" "${STATUS}" >> "${RESULTS_FILE}"
done

echo "]" >> "${RESULTS_FILE}"

if [[ "${#SAMPLES[@]}" -eq 0 ]]; then
  echo ""
  echo "Cold launch benchmark failed: no parseable samples." >&2
  echo "Results: ${RESULTS_FILE}"
  exit 4
fi

export SAMPLES="$(IFS=,; echo "${SAMPLES[*]}")"
MEDIAN_MS="$(SAMPLES="${SAMPLES}" python3 -c "import os; s=sorted(float(x) for x in os.environ['SAMPLES'].split(',') if x); print(f'{s[len(s)//2]:.2f}')")"

CEILING_MS="$(python3 - <<PY
budget = float("${BUDGET_MS}")
tol = float("${TOLERANCE}")
print(f"{budget * tol:.2f}")
PY
)"

echo ""
echo "Median cold_launch_to_editor_ms: ${MEDIAN_MS}"
echo "Budget ceiling_ms: ${CEILING_MS}"
echo "Results JSON: ${RESULTS_FILE}"

python3 - <<PY
median = float("${MEDIAN_MS}")
ceiling = float("${CEILING_MS}")
raise SystemExit(0 if median <= ceiling else 1)
PY
