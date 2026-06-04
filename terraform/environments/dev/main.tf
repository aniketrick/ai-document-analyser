provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_s3_bucket" "uploads" {
  bucket        = "${local.name_prefix}-uploads-${random_id.suffix.hex}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket      = aws_s3_bucket.uploads.id
  eventbridge = true
}

resource "aws_dynamodb_table" "documents" {
  name         = "${local.name_prefix}-documents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "documentId"

  attribute {
    name = "documentId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = local.common_tags
}

resource "aws_sqs_queue" "processor_dlq" {
  name                      = "${local.name_prefix}-processor-dlq"
  message_retention_seconds = 1209600
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "processor" {
  name                       = "${local.name_prefix}-processor-queue"
  visibility_timeout_seconds = var.lambda_timeout_seconds + 30
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processor_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.common_tags
}

resource "aws_sqs_queue_policy" "processor" {
  queue_url = aws_sqs_queue.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.processor.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_object_created.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${local.name_prefix}-s3-object-created"
  description = "Route uploaded S3 documents to SQS for processing."

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.uploads.bucket]
      }
      object = {
        key = [{ prefix = "uploads/" }]
      }
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "processor_queue" {
  rule = aws_cloudwatch_event_rule.s3_object_created.name
  arn  = aws_sqs_queue.processor.arn
}

data "archive_file" "upload_api" {
  type        = "zip"
  source_dir  = "${path.module}/../../../src/api"
  output_path = "${path.module}/upload-url-api.zip"
}

data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../../../src"
  output_path = "${path.module}/document-processor.zip"
}

resource "aws_iam_role" "upload_api" {
  name               = "${local.name_prefix}-upload-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role" "processor" {
  name               = "${local.name_prefix}-processor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "upload_api_basic" {
  role       = aws_iam_role.upload_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "processor_basic" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "upload_api" {
  name = "${local.name_prefix}-upload-api-policy"
  role = aws_iam_role.upload_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.uploads.arn}/uploads/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "processor" {
  name = "${local.name_prefix}-processor-policy"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.uploads.arn}/uploads/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.documents.arn
      },
      {
        Effect = "Allow"
        Action = [
          "textract:DetectDocumentText",
          "comprehend:DetectPiiEntities"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.processor.arn
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}"
      }
    ]
  })
}

resource "aws_lambda_function" "upload_api" {
  function_name    = "${local.name_prefix}-upload-url-api"
  role             = aws_iam_role.upload_api.arn
  handler          = "upload_url_handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.upload_api.output_path
  source_code_hash = data.archive_file.upload_api.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      UPLOAD_BUCKET_NAME = aws_s3_bucket.uploads.bucket
      URL_EXPIRY_SECONDS = "900"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "processor" {
  function_name    = "${local.name_prefix}-document-processor"
  role             = aws_iam_role.processor.arn
  handler          = "processor.document_processor.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = var.lambda_timeout_seconds
  memory_size      = 512

  environment {
    variables = {
      DOCUMENT_TABLE_NAME    = aws_dynamodb_table.documents.name
      ENABLE_BEDROCK_SUMMARY = tostring(var.enable_bedrock_summary)
      BEDROCK_MODEL_ID       = var.bedrock_model_id
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_event_source_mapping" "processor" {
  event_source_arn = aws_sqs_queue.processor.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 5
  enabled          = true
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type", "authorization"]
    allow_methods = ["OPTIONS", "POST"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = local.common_tags
}

resource "aws_cognito_user_pool" "users" {
  name = "${local.name_prefix}-users"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]

  tags = local.common_tags
}

resource "aws_cognito_user_pool_client" "api_client" {
  name                                 = "${local.name_prefix}-api-client"
  user_pool_id                         = aws_cognito_user_pool.users.id
  generate_secret                      = false
  explicit_auth_flows                  = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows_user_pool_client = false
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.name_prefix}-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.api_client.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
  }
}

resource "aws_apigatewayv2_integration" "upload_api" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.upload_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "POST /upload-url"
  target             = "integrations/${aws_apigatewayv2_integration.upload_api.id}"
  authorization_type = var.enable_cognito_authorizer ? "JWT" : "NONE"
  authorizer_id      = var.enable_cognito_authorizer ? aws_apigatewayv2_authorizer.cognito.id : null
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  tags = local.common_tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
