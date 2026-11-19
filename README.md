# AI Document Analyser

A serverless pipeline on AWS. You ask the API for an upload link, upload a document, and the pipeline pulls out the text, removes personal data, writes a short summary and saves the result to DynamoDB. Everything is built with Terraform.

I built it to practise event-driven design: how to make each step retry on its own, and how to make sure a document that fails is kept somewhere rather than lost.

## How it works

```text
Client
  │  1. POST /upload-url
  ▼
API Gateway (HTTP API) ──► Lambda: upload-url-api ──► returns a pre-signed S3 link
  │
  │  2. Client uploads the file straight to S3
  ▼
S3 upload bucket ──► EventBridge rule (Object Created)
  ▼
SQS processing queue ──(fails 3 times)──► dead-letter queue
  ▼
Lambda: document-processor
  ├── Textract: extract the text
  ├── Comprehend: find personal data and replace it with [TYPE_REDACTED]
  └── Bedrock: write a short summary (off by default, see below)
  ▼
DynamoDB: status, redacted text and summary for each document
```

## What's in it

- **Pre-signed upload links.** Files go straight to S3, so the API never handles the file itself. Only PDF, PNG, JPEG and plain text are accepted, and the link expires.
- **A queue between S3 and the processor.** If processing fails, SQS tries again. After three failed attempts the message moves to a dead-letter queue, which keeps it for 14 days.
- **The queue's visibility timeout is set longer than the Lambda timeout**, so a message isn't picked up twice while it's still being worked on.
- **A status for each document** in DynamoDB (PROCESSING, then COMPLETED or FAILED), with point-in-time recovery switched on.
- **A separate IAM role for each Lambda**, each with only the actions it needs.
- **A locked-down S3 bucket**: encrypted, versioned and blocked from public access.
- **Optional extras, both off by default to keep costs down:**
  - Cognito sign-in on the upload endpoint (`enable_cognito_authorizer = true`)
  - Real Bedrock summaries (`enable_bedrock_summary = true`, needs model access in your account)

## CI

GitHub Actions runs on every push and pull request. It:

- compiles the Python
- runs the unit tests
- checks Terraform formatting
- runs `terraform validate`

It doesn't deploy anything yet.

## Run it yourself

You'll need the AWS CLI, Terraform 1.5 or later, and Python 3.12.

```bash
./scripts/package_lambdas.sh

cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # change the values if you need to
terraform init
terraform apply
```

Then request an upload link (or run `scripts/smoke_test.sh`):

```bash
export UPLOAD_URL_ENDPOINT=$(terraform output -raw upload_url_endpoint)
curl -X POST "$UPLOAD_URL_ENDPOINT" \
  -H "content-type: application/json" \
  -d '{"fileName":"sample.pdf","contentType":"application/pdf"}'
```

Run the checks locally:

```bash
python -m unittest discover -s tests
```

**Cost:** Textract, Comprehend and Bedrock are charged per use. Run `terraform destroy` when you've finished. There's more detail in `docs/cost-and-cleanup.md`.

## Not done yet

- There are unit tests for the text helpers only. Next I'll add tests for the two Lambda handlers, with AWS calls mocked.
- CloudWatch alarms on the dead-letter queue and on Lambda errors.
- Large PDFs. The processor uses Textract's synchronous call, which only handles single-page documents. Multi-page files need the asynchronous Textract API.
- Terraform state is local. It should move to S3 with locking.
