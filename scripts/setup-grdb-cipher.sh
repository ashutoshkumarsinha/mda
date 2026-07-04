#!/usr/bin/env bash
# Clone GRDB sources for the local SQLCipher-enabled package (OQ-02).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_DIR="${REPO_ROOT}/Packages/GRDBCipher"
GRDB_TAG="v7.11.1"
GRDB_REV="b83108d10f42680d78f23fe4d4d80fc88dab3212"

if [[ ! -f "${PACKAGE_DIR}/Package.swift" ]]; then
  echo "Missing ${PACKAGE_DIR}/Package.swift" >&2
  exit 1
fi

if [[ -d "${PACKAGE_DIR}/GRDB" ]]; then
  echo "GRDB sources already present at ${PACKAGE_DIR}/GRDB"
  exit 0
fi

echo "Cloning GRDB ${GRDB_TAG} into ${PACKAGE_DIR}…"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
git clone --depth 1 --branch "${GRDB_TAG}" https://github.com/groue/GRDB.swift.git "${tmpdir}/grdb"
mv "${tmpdir}/grdb/GRDB" "${PACKAGE_DIR}/GRDB"
echo "GRDB ${GRDB_REV} ready for SQLCipher build."
