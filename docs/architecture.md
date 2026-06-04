# Architecture Notes

## Goal

The platform accepts document uploads, processes them asynchronously, extracts text, removes sensitive information, generates a business-friendly summary, and stores the result for later retrieval.

## Components

### API Gateway HTTP API
Exposes a lightweight endpoint for clients to request pre-signed S3 upload URLs. This avoids sending large files through Lambda and keeps uploads secure.

### Upload Lambda
Validates the request body, creates a safe object key, and returns a pre-signed S3 PUT URL.

### S3 Upload Bucket
Stores raw uploaded documents. Public access is blocked and server-side encryption is enabled.

### EventBridge
Receives S3 Object Created events and routes them to the processing queue.

### SQS Queue
Buffers document processing events. This decouples upload traffic from compute and gives retry protection during transient failures.

### Dead-Letter Queue
Stores events that fail repeatedly, allowing safe investigation without data loss.

### Processor Lambda
Triggered by SQS. It downloads the uploaded document, extracts text using Textract, redacts PII using Comprehend, optionally calls Bedrock for summarisation, and writes metadata to DynamoDB.

### DynamoDB
Stores document status, extracted text preview, redacted text preview, detected PII types, summary, timestamps and source location.

### CloudWatch
Captures Lambda logs and operational metrics.

## Reliability Design

- SQS decouples ingestion from processing.
- DLQ prevents failed records from being silently dropped.
- Lambda logs each stage for traceability.
- DynamoDB records document status transitions.

## Security Design

- S3 public access is blocked.
- Bucket encryption is enabled.
- Uploads use short-lived pre-signed URLs.
- Lambda IAM permissions are scoped to required resources.
- PII is detected and redacted before text previews are persisted.
