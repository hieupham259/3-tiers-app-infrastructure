provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "3-tiers-app"
      ManagedBy   = "terraform"
    }
  }
}

# Provider for us-east-1 (CloudFront ACM certs, if needed)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "3-tiers-app"
      ManagedBy   = "terraform"
    }
  }
}
