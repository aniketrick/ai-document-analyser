"""Lambda handler that returns pre-signed S3 upload URLs."""
from __future__ import annotations

import json
import os
import re
import time
from typing import Any

import boto3

s3 = boto3.client("s3")

BUCKET_NAME = os.environ["UPLOAD_BUCKET_NAME"]
URL_EXPIRY_SECONDS = int(os.environ.get("URL_EXPIRY_SECONDS", "900"))

SAFE_FILENAME_PATTERN = re.compile(r"[^A-Za-z0-9_.-]")


def response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
            "access-control-allow-headers": "content-type,authorization",
            "access-control-allow-methods": "OPTIONS,POST",
        },
        "body": json.dumps(body),
    }


def normalise_filename(filename: str) -> str:
    cleaned = SAFE_FILENAME_PATTERN.sub("-", filename.strip())
    return cleaned[:180] or "document"


def handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return response(200, {"ok": True})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, {"message": "Invalid JSON body"})

    filename = normalise_filename(body.get("fileName", "document.pdf"))
    content_type = body.get("contentType", "application/pdf")

    if content_type not in {"application/pdf", "image/png", "image/jpeg", "text/plain"}:
        return response(400, {"message": "Unsupported contentType"})

    object_key = f"uploads/{int(time.time())}-{filename}"

    upload_url = s3.generate_presigned_url(
        ClientMethod="put_object",
        Params={
            "Bucket": BUCKET_NAME,
            "Key": object_key,
            "ContentType": content_type,
        },
        ExpiresIn=URL_EXPIRY_SECONDS,
    )

    return response(
        200,
        {
            "bucket": BUCKET_NAME,
            "objectKey": object_key,
            "uploadUrl": upload_url,
            "expiresInSeconds": URL_EXPIRY_SECONDS,
        },
    )
