#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/MenuBarLG.xcodeproj"
SCHEME="MenuBarLG"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${ROOT_DIR}/build/DerivedDataRelease"
PRODUCTS_DIR="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}"
APP_PATH="${PRODUCTS_DIR}/MenuBarLG.app"
DIST_DIR="${ROOT_DIR}/dist"

VERSION="${1:-local}"
ARCHIVE_NAME="MenuBarLG-${VERSION}.zip"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"

echo "Building ${SCHEME} (${CONFIGURATION})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Error: Built app not found at ${APP_PATH}" >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"
rm -f "${ARCHIVE_PATH}"

echo "Packaging ${ARCHIVE_NAME}..."
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"

echo "Created release artifact:"
echo "${ARCHIVE_PATH}"
