output "upload_bucket_name" {
  description = "S3 bucket used for document uploads."
  value       = aws_s3_bucket.uploads.bucket
}

output "document_table_name" {
  description = "DynamoDB table storing document analysis metadata."
  value       = aws_dynamodb_table.documents.name
}

output "processor_queue_url" {
  description = "SQS queue URL for document processing."
  value       = aws_sqs_queue.processor.url
}

output "processor_dlq_url" {
  description = "Dead-letter queue URL for failed processing events."
  value       = aws_sqs_queue.processor_dlq.url
}

output "upload_url_endpoint" {
  description = "HTTP endpoint used to request pre-signed upload URLs."
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/upload-url"
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID for JWT authentication."
  value       = aws_cognito_user_pool.users.id
}

output "cognito_app_client_id" {
  description = "Cognito app client ID for API authentication."
  value       = aws_cognito_user_pool_client.api_client.id
}
