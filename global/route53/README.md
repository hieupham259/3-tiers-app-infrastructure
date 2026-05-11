# global/route53

Primary hosted zone (e.g. `myapp.example.com`).

## Notes

- A single hosted zone serves both envs. Per-env subdomains: `development.myapp.example.com` vs `myapp.example.com`.
- After the first apply, take the nameservers and create an NS record at the registrar (GoDaddy / Cloudflare / etc.).
- The state for this module should live in a dedicated account (or the development account). Use a separate backend - do NOT share with `envs/`.

## Backend (no backend.tf yet)

Create a dedicated `backend.tf` for this folder once you decide which account hosts the state, for example:

```hcl
terraform {
  backend "s3" {
    bucket       = "3-tiers-app-infrastructure-tfstate-111111111111"
    key          = "3-tiers-app/global/route53/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "alias/tfstate"
    use_lockfile = true
  }
}
```
