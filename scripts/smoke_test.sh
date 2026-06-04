#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${UPLOAD_URL_ENDPOINT:-}" ]]; then
  echo "Set UPLOAD_URL_ENDPOINT first. Example: export UPLOAD_URL_ENDPOINT=https://abc.execute-api.eu-west-2.amazonaws.com/upload-url"
  exit 1
fi

curl -s -X POST "$UPLOAD_URL_ENDPOINT" \
  -H "content-type: application/json" \
  -d '{"fileName":"sample.pdf","contentType":"application/pdf"}' | python -m json.tool
