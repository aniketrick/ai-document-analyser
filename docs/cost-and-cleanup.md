# Cost and Cleanup Guide

This project creates AWS resources. Use it carefully and destroy resources when done.

## Potential Cost Sources

- S3 storage and requests
- Lambda invocations and duration
- SQS requests
- DynamoDB read/write capacity or on-demand requests
- API Gateway requests
- CloudWatch log storage
- Textract document analysis
- Comprehend PII detection
- Bedrock model invocation

## Reduce Cost

- Test with small text or PDF files.
- Keep `enable_bedrock_summary = false` unless you specifically want to test Bedrock.
- Destroy resources after screenshots are taken.
- Delete uploaded test documents.

## Cleanup

```bash
cd terraform/environments/dev
terraform destroy
```

Type `yes` when prompted.
