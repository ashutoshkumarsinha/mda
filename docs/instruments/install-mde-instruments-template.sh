#!/usr/bin/env bash
# Install MDE Performance.tracetemplate into Instruments so it appears in the template picker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SCRIPT_DIR}/MDE Performance.tracetemplate"
DEST_DIR="${HOME}/Library/Application Support/Instruments/Templates"
DEST="${DEST_DIR}/MDE Performance.tracetemplate"

mkdir -p "${DEST_DIR}"
cp "${SOURCE}" "${DEST}"
echo "Installed: ${DEST}"
echo "Available as template name: MDE Performance"
echo "Verify: xcrun xctrace list templates | grep MDE"
