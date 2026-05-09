# global/

Resources that cross both envs or exist only once (e.g. the primary hosted zone, or IAM roles app repos grant to teams).

## When to use

- Create the Route53 hosted zone shared by the production domain
- Create IAM roles for app repos (an alternative to `bootstrap/03-github-oidc-roles.yaml` if you prefer Terraform management)

## When NOT to use

- A resource that belongs to a specific env -> use `envs/<env>/` instead of `global/`
- A resource you want to rebuild per-env easily -> keep it in `modules/` and call from `envs/_shared/`

## State backend

If you need one, each subfolder under `global/` has its own backend (e.g. the state for `route53/` lives in the development account or in a dedicated "shared" account). In the current 2-account project, the recommendation is to temporarily store it in the development account.
