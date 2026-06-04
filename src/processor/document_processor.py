"""SQS-triggered Lambda for document processing."""
from __future__ import annotations

import json
import os
import tempfile
import time
import uuid
from typing import Any
from urllib.parse import unquote_plus

import boto3

from shared.text_utils import redact_entities, truncate

s3 = boto3.client("s3")
textract = boto3.client("textract")
comprehend = boto3.client("comprehend")
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["DOCUMENT_TABLE_NAME"]
ENABLE_BEDROCK_SUMMARY = os.environ.get("ENABLE_BEDROCK_SUMMARY", "false").lower() == "true"
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")

bedrock_runtime = boto3.client("bedrock-runtime") if ENABLE_BEDROCK_SUMMARY else None

table = dynamodb.Table(TABLE_NAME)


def put_status(document_id: str, status: str, **extra: Any) -> None:
    item = {
        "documentId": document_id,
        "status": status,
        "updatedAt": int(time.time()),
        **extra,
    }
    table.put_item(Item=item)


def extract_s3_records(event: dict[str, Any]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for sqs_record in event.get("Records", []):
        body = json.loads(sqs_record.get("body", "{}"))
        detail = body.get("detail", {})
        bucket = detail.get("bucket", {}).get("name")
        key = detail.get("object", {}).get("key")
        if bucket and key:
            records.append({"bucket": bucket, "key": unquote_plus(key)})
    return records


def download_to_tmp(bucket: str, key: str) -> str:
    suffix = os.path.splitext(key)[1] or ".bin"
    destination = os.path.join(tempfile.gettempdir(), f"{uuid.uuid4()}{suffix}")
    s3.download_file(bucket, key, destination)
    return destination


def extract_text_with_textract(bucket: str, key: str) -> str:
    response = textract.detect_document_text(
        Document={"S3Object": {"Bucket": bucket, "Name": key}}
    )
    lines = [
        block.get("Text", "")
        for block in response.get("Blocks", [])
        if block.get("BlockType") == "LINE" and block.get("Text")
    ]
    return "\n".join(lines)


def detect_pii(text: str) -> list[dict[str, Any]]:
    if not text.strip():
        return []
    # Comprehend has request size limits, so analyse a practical preview.
    preview = text[:4500]
    response = comprehend.detect_pii_entities(Text=preview, LanguageCode="en")
    return response.get("Entities", [])


def summarise_with_bedrock(redacted_text: str) -> str:
    if not ENABLE_BEDROCK_SUMMARY or bedrock_runtime is None:
        return "Bedrock summarisation disabled. Enable with Terraform variable enable_bedrock_summary=true."

    prompt = (
        "Summarise this enterprise document in 5 concise bullet points. "
        "Avoid exposing any sensitive personal information.\n\n"
        f"Document text:\n{redacted_text[:6000]}"
    )

    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 500,
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": prompt}],
            }
        ],
    }

    response = bedrock_runtime.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        body=json.dumps(payload),
        contentType="application/json",
        accept="application/json",
    )
    body = json.loads(response["body"].read())
    content = body.get("content", [])
    if content and isinstance(content, list):
        return content[0].get("text", "")
    return "No summary returned by Bedrock."


def process_document(bucket: str, key: str) -> None:
    document_id = str(uuid.uuid4())
    put_status(document_id, "PROCESSING", sourceBucket=bucket, sourceKey=key)

    try:
        extracted_text = extract_text_with_textract(bucket, key)
        pii_entities = detect_pii(extracted_text)
        redacted_text = redact_entities(extracted_text, pii_entities)
        summary = summarise_with_bedrock(redacted_text)

        pii_types = sorted({entity.get("Type", "UNKNOWN") for entity in pii_entities})

        put_status(
            document_id,
            "COMPLETED",
            sourceBucket=bucket,
            sourceKey=key,
            extractedTextPreview=truncate(extracted_text, 1200),
            redactedTextPreview=truncate(redacted_text, 1200),
            piiEntityTypes=pii_types,
            piiEntityCount=len(pii_entities),
            summary=truncate(summary, 1800),
        )
    except Exception as exc:  # noqa: BLE001 - Lambda should log and persist failures.
        put_status(
            document_id,
            "FAILED",
            sourceBucket=bucket,
            sourceKey=key,
            errorMessage=str(exc)[:1000],
        )
        raise


def handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    records = extract_s3_records(event)
    for record in records:
        process_document(record["bucket"], record["key"])
    return {"processed": len(records)}
