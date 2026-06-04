#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

python -m py_compile \
  "$ROOT_DIR/src/api/upload_url_handler.py" \
  "$ROOT_DIR/src/processor/document_processor.py" \
  "$ROOT_DIR/src/shared/text_utils.py"

(cd "$ROOT_DIR/src/api" && zip -qr "$BUILD_DIR/upload-url-api.zip" .)
(cd "$ROOT_DIR/src" && zip -qr "$BUILD_DIR/document-processor.zip" .)

echo "Lambda packages created in $BUILD_DIR"
