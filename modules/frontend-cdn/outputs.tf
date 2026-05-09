output "bucket_name" {
  description = "S3 bucket name (cho aws s3 sync)"
  value       = aws_s3_bucket.frontend.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.frontend.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID (cho aws cloudfront create-invalidation)"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_domain" {
  description = "CloudFront default domain (vd: dxxxx.cloudfront.net)"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}
