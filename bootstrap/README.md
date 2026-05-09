# Bootstrap CloudFormation stacks

CFN templates used to provision the prerequisites Terraform needs before it can run
(state bucket, KMS, OIDC trust + roles).

## Files

| File | Provisioned via | Frequency | Purpose |
|------|-----------------|-----------|---------|
| `01-trust-anchor.yaml` | MANUAL Console | Once per account | OIDC provider + `gha-bootstrap` role |
| `02-tfstate-backend.yaml` | CI/CD `bootstrap.yaml` | Initial + on update | S3 state bucket + KMS |
| `03-github-oidc-roles.yaml` | CI/CD `bootstrap.yaml` | Initial + on update | gha-infra-{plan,apply} + app deploy roles |

## Deploy workflow

1. **Cloud admin uploads `01-trust-anchor.yaml` via the AWS Console** (see `SETUP-GUIDE.md` Phase 5 + 6)
   - Sign in to the Console with development account admin credentials -> Upload template -> Stack name `trust-anchor`
   - Repeat for the production account
2. **DevOps triggers the `bootstrap.yaml` workflow via the GitHub Actions UI** (see `SETUP-GUIDE.md` Phase 7 + 8)
   - Actions tab -> "Bootstrap" -> Run workflow -> select `account=development`
   - Reviewer approves in the `bootstrap` Environment
   - Repeat for `account=production`

> **DO NOT** run `aws cloudformation deploy` or `terraform` locally.

## DeletionPolicy

All stateful resources (KMS key, S3 bucket, IAM role, OIDC provider) carry
`DeletionPolicy: Retain` + `UpdateReplacePolicy: Retain`. If the CFN stack is
deleted by accident the critical resources are RETAINED, so the Terraform state
is preserved and the OIDC trust is not broken.

## Drift detection

The `cfn-drift-detect.yaml` workflow runs on a weekly schedule (Sunday 01:00 ICT)
and calls `aws cloudformation detect-stack-drift` for all three stacks. The step
fails and alerts if drift is detected.

## Updating the bootstrap stacks

When you need to edit a YAML file (e.g. add a new role, rotate KMS):
1. Edit the YAML file and push to the `main` branch
2. Actions tab -> "Bootstrap" -> Run workflow -> pick the account
3. Reviewer approves in the `bootstrap` Environment
4. CI redeploys the CFN stack (idempotent)
