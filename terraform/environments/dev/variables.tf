variable "aws_region" {
  description = "AWS region for deployment."
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Project name used in resource names."
  type        = string
  default     = "ai-document-analyser"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "enable_bedrock_summary" {
  description = "Enable real Bedrock summary generation. Keep false for cheaper testing."
  type        = bool
  default     = false
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for summarisation. Requires account model access."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "lambda_timeout_seconds" {
  description = "Processor Lambda timeout."
  type        = number
  default     = 60
}

variable "enable_cognito_authorizer" {
  description = "Require Cognito JWT authentication on the upload URL endpoint."
  type        = bool
  default     = false
}
