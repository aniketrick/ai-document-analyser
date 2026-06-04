# AI-Powered Enterprise Document Analyser

A production-style AWS serverless project that ingests enterprise documents, processes them asynchronously, extracts text, redacts sensitive data, generates an AI summary, and stores searchable metadata.

This project is designed for Cloud Engineer / DevOps Engineer / AWS Solutions Architect portfolios. It demonstrates event-driven architecture, least-privilege IAM, asynchronous processing, serverless compute, and CI validation.

## Architecture

```text
Client
  |
  | 1. Request pre-signed upload URL
  v
API Gateway HTTP API
  |
  v
Lambda: upload-url-api
  |
  v
S3 Upload Bucket
  |
  | 2. ObjectCreated event
  v
EventBridge Rule
  |
  v
SQS Processing Queue + DLQ
  |
  v
Lambda: document-processor
  |
  |-- Textract: extract text
  |-- Comprehend: detect PII and redact sensitive entities
  |-- Bedrock: generate business summary
  v
DynamoDB Document Metadata Table
  |
  v
CloudWatch Logs and Metrics
```

## What this project proves

- Event-driven document ingestion using S3, EventBridge, SQS and Lambda
- Fault-tolerant processing using queue retries and a dead-letter queue
- Secure API upload pattern using pre-signed S3 URLs
- Serverless document analysis with Textract, Comprehend and Bedrock-ready summarisation
- Least-privilege IAM roles for Lambda functions
- DynamoDB persistence for extracted metadata, redaction results and summaries
- GitHub Actions pipeline for Terraform and Python validation

## Tech Stack

| Area | Tools |
|---|---|
| Cloud | AWS S3, Lambda, API Gateway, SQS, EventBridge, DynamoDB, CloudWatch |
| AI / ML | Amazon Textract, Amazon Comprehend, Amazon Bedrock |
| IaC | Terraform |
| Language | Python 3.12 |
| CI/CD | GitHub Actions |
| Security | IAM least privilege, S3 encryption, public access block, pre-signed URLs |

## Repository Structure

```text
.
├── .github/workflows/platform-ci.yml
├── docs/
│   ├── architecture.md
│   ├── screenshots.md
│   └── cost-and-cleanup.md
├── examples/
│   └── sample-api-event.json
├── scripts/
│   ├── package_lambdas.sh
│   └── smoke_test.sh
├── src/
│   ├── api/
│   │   └── upload_url_handler.py
│   ├── processor/
│   │   └── document_processor.py
│   └── shared/
│       └── text_utils.py
├── terraform/environments/dev/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   └── terraform.tfvars.example
└── tests/
    └── test_text_utils.py
```

## Prerequisites

- AWS CLI configured with an AWS account
- Terraform >= 1.5
- Python 3.12
- Bash shell
- Bedrock model access enabled if you want real AI summaries

## Setup

Clone the repository and package the Lambda functions:

```bash
chmod +x scripts/package_lambdas.sh
./scripts/package_lambdas.sh
```

Deploy infrastructure:

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

Type `yes` when Terraform asks for approval.

## Upload Flow

After deployment, Terraform outputs an API endpoint.

Request an upload URL:

```bash
curl -X POST "$UPLOAD_URL_ENDPOINT" \
  -H "content-type: application/json" \
  -d '{"fileName":"sample.pdf","contentType":"application/pdf"}'
```

Then upload the document using the returned `uploadUrl`.

## Local Validation

Run Python checks:

```bash
python -m py_compile src/api/upload_url_handler.py src/processor/document_processor.py src/shared/text_utils.py
python -m unittest discover -s tests
```

Run Terraform validation:

```bash
cd terraform/environments/dev
terraform init -backend=false
terraform validate
```

## Cost Warning

This project can create AWS resources. Most resources are low-cost or free-tier friendly when lightly used, but charges can occur from Lambda invocations, S3 storage, DynamoDB, SQS, CloudWatch logs, Textract, Comprehend, API Gateway and Bedrock usage.

Destroy resources when finished:

```bash
cd terraform/environments/dev
terraform destroy
```

## Resume Bullet

Built an AI-powered enterprise document analyser on AWS using S3, EventBridge, SQS, Lambda, Textract, Comprehend, Bedrock and DynamoDB, implementing asynchronous processing, PII redaction, least-privilege IAM and CloudWatch observability through Terraform-managed infrastructure.
