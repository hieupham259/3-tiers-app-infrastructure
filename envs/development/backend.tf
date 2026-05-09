terraform {
  required_version = ">= 1.11"

  backend "s3" {
    bucket       = "myorg-tfstate-111111111111"
    key          = "3-tiers-app/development/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "alias/tfstate"
    use_lockfile = true
  }
}
