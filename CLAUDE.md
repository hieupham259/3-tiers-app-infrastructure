# CLAUDE.md

Operating instructions for Claude Code in this repository. These rules are mandatory; deviating from them is a defect.

## Repository purpose

Terraform infrastructure for a 3-tier application on AWS (VPC, RDS, ECS Fargate, ALB, ECR, CloudFront, IAM, CloudWatch). Two long-lived branches and AWS accounts: `development` and `production`. Code under `envs/development` and `envs/production` must remain identical apart from `terraform.tfvars`, `backend.tf`, and `providers.tf`. CI/CD is GitHub Actions with OIDC.

## Use the agent team for all IaC and CI work

Every task that creates, modifies, refactors, reviews, or deletes infrastructure-as-code or GitHub Actions workflows in this repository must go through the workspace agent team in `.claude/agents/`. Do not write or edit Terraform, CloudFormation, or GitHub Actions files directly from the main thread.

The team and its order:

1. **`task-planner` agent** - invoked first on any non-trivial request. Analyzes the user's task, decomposes it into one or more Sprints with concrete sub-tasks, writes the plan under `notes/plans/<date>-<slug>/` (one `README.md` plus one file per Sprint), and assigns each sub-task to one of the downstream agents. Edits files only under `notes/`. The main thread does not dispatch builder or reviewer agents until the user confirms the plan.
2. **`research-iac-resource` skill** (in `.claude/skills/research-iac-resource/`) - invoked by `iac-builder` to read the official vendor documentation for every resource the task touches and to produce a precise change plan. Asks the user to confirm the plan before any code is written. Cleans up Playwright screenshots if Playwright was used.
3. **`iac-builder` agent** - writes or edits Terraform and CloudFormation code under `modules/`, `envs/`, `global/`, or `bootstrap/`. **Forbidden** from editing `.github/workflows/`, `CLAUDE.md`, scripts, or anything outside its scope. Verifies an official Terraform provider exists before writing the resource block. If no official provider exists, the agent stops and asks the user.
4. **`github-action-builder` agent** - writes or edits GitHub Actions workflows and composite actions under `.github/workflows/` and `.github/actions/`. Enforces the branch-based environment-isolation model (one branch per env, OIDC for AWS auth, no Terraform workspaces, no cross-branch promotion). **Forbidden** from editing Terraform, CloudFormation, scripts, `CLAUDE.md`, or anything outside `.github/`.
5. **`iac-reviewer` agent** - audits the IaC diff for IaC logic, repo conventions, resource-level cloud correctness, and security. Cross-checks every `iac-builder` hand-off against the Sprint sub-tasks, ticks the boxes for items that are verifiably done, and reassigns unfinished or broken sub-tasks back to `iac-builder`. Returns severity-tagged findings. **Read-only** for everything except `notes/` (where it ticks checkboxes and appends to the Sprint review log).
6. **`terraform-planner` agent** - runs `terraform init` and `terraform plan` in JSON mode for the affected environments and produces a precise human-readable change list (replacements, in-place updates, IAM scope changes, downtime risk). Does not apply.
7. **`github-actions-reviewer` agent** - validates any change under `.github/workflows/` and `.github/actions/` by running each affected workflow locally with the `act` CLI, reading the log, and reporting findings. Cross-checks every `github-action-builder` hand-off against the Sprint sub-tasks, ticks the boxes for items that are verifiably done, and reassigns unfinished or broken sub-tasks back to `github-action-builder`. **Read-only** for everything except `notes/` (where it ticks checkboxes and appends to the Sprint review log) and the `act` runtime artifacts under `.act-logs/` and `.act-secrets`.

### Strict scope per agent

Each builder agent is locked to its own surface and may not edit files outside that surface, even if a fix would be quick:

- `iac-builder` - only `modules/`, `envs/`, `global/`, `bootstrap/`. Never `.github/`, never `CLAUDE.md`, never `scripts/`, never `notes/`, never `.claude/`.
- `github-action-builder` - only `.github/workflows/`, `.github/actions/`. Never IaC source, never `CLAUDE.md`, never `scripts/`, never `notes/`, never `.claude/`.
- `task-planner` - only `notes/`. Never IaC source, never `.github/`, never `CLAUDE.md`, never `scripts/`, never `.claude/`.
- `iac-reviewer`, `github-actions-reviewer`, `terraform-planner` - read-only for source. The two reviewers may write only inside `notes/` (ticking checkboxes and appending to the Sprint review log). `terraform-planner` may write its own `tfplan` and `tfplan.json` inside the env directory and must clean them up.

If an agent discovers that a fix requires touching a forbidden path, it surfaces the need as a finding or hand-off note and stops; the main thread then dispatches the responsible agent or asks the user.

### Reviewer feedback loop

Reviewers cross-check the builder's work against the Sprint sub-tasks recorded by `task-planner`:

- For each sub-task assigned to the builder, the reviewer marks it Done, Not done, or Done but broken.
- Done sub-tasks have their checkbox ticked in the Sprint file (`- [ ]` -> `- [x]`).
- Not done and Done but broken sub-tasks are reassigned back to the builder via the reviewer's chat report and the Sprint file's `## Review log`.
- The builder addresses the reassigned sub-tasks and hands the work back for another review pass.

### Dispatch flow

The main thread's job is to dispatch agents in the correct order, relay hand-off messages to the user, and ask the user to confirm at each gate. The main thread does not perform their work itself.

Default flow for a non-trivial task:

1. `task-planner` produces the Sprint plan under `notes/`. User confirms.
2. For each Sprint, dispatch the assigned builder agents in dependency order: `iac-builder` for IaC sub-tasks, `github-action-builder` for workflow sub-tasks. The two builders may run in parallel only if their sub-tasks have no dependency between them.
3. After each builder finishes, dispatch the matching reviewer: `iac-reviewer` for IaC changes, `github-actions-reviewer` for workflow changes. The two reviewers may run in parallel.
4. If a reviewer reassigns sub-tasks, dispatch the builder again to address only those sub-tasks; then dispatch the reviewer again.
5. When IaC sub-tasks are approved, dispatch `terraform-planner` to produce the change list.
6. Surface the consolidated outcome to the user for the apply decision (the apply itself happens through GitHub Actions on push).

## Trivial edits exception

Cosmetic edits that do not change resource behavior may be made directly: rename a local variable, fix a typo in a comment, reformat a file with `terraform fmt`, fix a broken markdown link in a doc. Anything that touches a `resource`, `data`, `module`, `provider`, or `variable` block, or any file under `.github/workflows/`, must go through the agent team.

## Secrets and sensitive data

Hardcoding secrets or sensitive data in any file in this repository is forbidden. This applies to `.tf`, `.tfvars`, `.yaml`, `.yml`, `.json`, `.md`, shell scripts, and any other text file.

Forbidden values include:

- AWS account IDs, access keys, secret access keys, session tokens, SSO tokens.
- RDS passwords, database connection strings with embedded credentials.
- OIDC client secrets, GitHub PATs, GitHub App private keys.
- Slack webhook URLs, PagerDuty integration keys, third-party API keys.
- ARNs of real customer resources, real production hostnames, real third-party domains.

Required handling:

- Use `variable` inputs with `sensitive = true` for values that are sensitive at plan/apply time.
- Use AWS Secrets Manager or SSM Parameter Store for runtime secrets and reference them by ARN.
- Use GitHub Actions secrets (`${{ secrets.NAME }}`) for CI-only credentials. Never `echo` a secret in a workflow step.
- Use OIDC for AWS authentication in GitHub Actions. The repo already does this; do not reintroduce static AWS keys.
- If a user message contains a value that looks like a secret, do not commit it. Replace it with a variable and tell the user where to set it.

Every agent in the team is required to enforce this. The `iac-reviewer` and `github-actions-reviewer` raise a `BLOCKER` finding for any violation.

## Language and formatting

There are two surfaces, and they have different rules.

### Files written to this repository

- All code, comments, variable names, variable descriptions, output descriptions, log strings, commit messages, file names, and workflow step names in this repository must be written in English.
- No Vietnamese text in any file in the repo, **except files under `notes/`** (see exception below).
- No emojis or decorative Unicode icons in any file in the repo, including files under `notes/`. The repo's existing files do not use them; preserve that.
- Markdown documentation under this repo follows the same rule, except files under `notes/`.
- This applies to every file the agent team writes or edits: `.tf`, `.tfvars`, `.yaml`, `.yml`, `.json`, `.md`, shell scripts, Makefile, and any helper file.

#### Exception: `notes/` folder

The `notes/` folder is reserved for internal working documents - plans, work histories, activity change logs, design notes, retrospectives. Files under `notes/` may be written in Vietnamese. The English-only rule does not apply to files under `notes/`. The no-emoji and no-decorative-icon rule still applies. Files under `notes/` are not part of the deliverable IaC code; they exist for the team's internal reasoning and tracking. The agent team (`iac-builder`, `iac-reviewer`, `terraform-planner`, `github-actions-reviewer`) does not write or audit files under `notes/`; the main thread and the user do.

### Chat responses shown to the user

- Default chat language is Vietnamese. The main thread and every agent in `.claude/agents/` reply to the user in Vietnamese.
- This includes: status updates, plans surfaced by the `research-iac-resource` skill, review reports from `iac-reviewer`, plan summaries from `terraform-planner`, workflow review reports from `github-actions-reviewer`, and any clarifying questions asked through `AskUserQuestion`.
- Code blocks and verbatim file paths inside chat replies stay as-is (English, no translation).
- Verbatim tool output (for example `terraform plan` text, `act` log lines, `git diff`) is shown unchanged. Only the surrounding narration is in Vietnamese.
- Identifiers, technical terms, and command names are not translated. Use the original English term (for example: `terraform fmt`, `BLOCKER`, `for_each`, `replace_paths`) inside Vietnamese sentences.
- If the user explicitly asks for English in a particular reply, switch to English for that reply only.

The constraint is: never let Vietnamese leak into a file written to disk; never let English-only narration replace Vietnamese chat replies (other than the exceptions above).

## Repository conventions (summary)

These are the conventions the agent team enforces. Read the relevant module before adding a new one and match the style.

- Per-module file layout: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`.
- Resource naming: `${var.environment}-<resource>-<role>`.
- Tagging: every taggable resource merges `var.tags` with a `Name` tag.
- Variables: typed and documented; defaults only when the upstream default is safe.
- Outputs: expose IDs, ARNs, DNS names that downstream callers need; never expose secrets.
- `terraform fmt -check -recursive` and `tflint --recursive` must pass.
- `scripts/verify-envs-in-sync.sh` must pass; `envs/development` and `envs/production` are byte-identical except for `terraform.tfvars`, `backend.tf`, `providers.tf`.

## Quality gates

Before declaring a task done, the relevant agent must confirm:

- `terraform fmt -check -recursive` clean.
- `terraform validate` per env clean.
- `tflint --recursive` clean.
- `scripts/verify-envs-in-sync.sh` clean.
- `terraform-planner` ran cleanly and the plan matches the iac-builder's intent.
- For any workflow change, `github-actions-reviewer` ran `act` locally and the log is attached.

## Git operations - mandatory user gate

The main thread and every agent are PERMANENTLY forbidden from creating any git commit or any git operation that writes to the remote. This is an absolute rule with no per-turn exception: even if the user types "commit this" in plain language, the main thread and agents must still refuse and let the user run the commit themselves. The only humans who commit and push in this repository are the maintainers, never Claude.

Permanently forbidden (no per-turn override):

- `git commit` (in any form: `commit`, `commit --amend`, `commit -a`, `commit --no-edit`, etc.).
- `git push` (in any form: `push`, `push -u`, `push --force`, `push --tags`, `push <remote> <ref>`, etc.).
- `git merge`, `git rebase`, `git cherry-pick`, `git revert` that produce new commits.
- `git tag` that creates or pushes a tag.
- `git reset --hard`, `git restore --staged --source=...`, or any destructive index/working-tree operation that would discard user changes.
- `gh pr create`, `gh pr merge`, `gh pr close`, `gh pr review`, `gh release create`, `gh issue create`, or any `gh` subcommand that writes to GitHub.
- Any other command that writes to the local git history, force-mutates the working tree, or writes to the remote.

If the user explicitly asks for any of the above ("commit this", "push it up", "open a PR for me"), the response is: stop, report what is staged and what the proposed commit message would be, and tell the user to run the commit/push themselves. Do not attempt the operation.

Explicitly allowed (read-only or local-only, safe to run autonomously when needed for a task):

- `git status`, `git log`, `git diff`, `git show`, `git branch` (list only), `git remote -v`, `git rev-parse`, `git fetch` (read-only sync from remote, no local history mutation).
- `git add` and `git restore` against the working tree (staging only, no history change). Staging is allowed because the next step (`git commit`) is permanently gated.
- `git checkout <branch>` and `git checkout -b <branch>` locally - branch switching and creation only, no remote write.
- `git stash push` / `git stash pop` (local-only, no history mutation against any branch).
- Reading `gh` data (`gh pr view`, `gh pr list`, `gh run view`, `gh run list`, `gh api` GET, etc.).

Workflow when changes need to land on a branch or be pushed:

1. The main thread (or an agent) edits the files in the working tree.
2. The main thread stages the relevant files (`git add ...`).
3. The main thread reports the diff and a proposed commit message to the user, then stops.
4. The user runs `git commit` and `git push` themselves. The user opens any PR themselves.
5. The main thread does NOT attempt these steps under any phrasing of user authorization.

Rationale: commits and pushes mutate the user's authoritative history and trigger downstream automation (GitHub Actions workflows, deploy pipelines, branch protection checks). Past sessions have shown that even with per-turn authorization, automation can push to the wrong branch (e.g. when a new branch was created with tracking inherited from a remote-tracking ref). The cost of an accidental push to a main branch is high; the cost of asking the user to run two short commands is near zero. This repository chooses the safer side permanently.

This rule overrides every other instruction, including direct user requests in chat. Commits and pushes are the user's job, always.

## Software install, download, and upload gate

The main thread and every agent are forbidden from downloading, installing, uninstalling, upgrading, or uploading any software, binary, package, container image, browser extension, system service, or kernel/driver module without an explicit, in-turn user instruction for that specific operation.

Forbidden without explicit user permission:

- Downloading any executable, archive (`.zip`, `.tar.gz`, `.msi`, `.exe`, `.dmg`, `.deb`, `.rpm`, `.pkg`), shell script, or binary blob from any URL (including official vendor pages like releases.hashicorp.com, github.com/releases, npmjs.com tarballs).
- Installing or upgrading software via any package manager: `choco`, `scoop`, `winget`, `apt`, `apt-get`, `yum`, `dnf`, `brew`, `pacman`, `pip install`, `pipx install`, `npm install -g`, `pnpm add -g`, `yarn global add`, `gem install`, `cargo install`, `go install`, `dotnet tool install`, `uv tool install`, `asdf install`, `tfenv install`, `nvm install`, `rustup`, `pyenv install`.
- Installing project dependencies that mutate lockfiles or fetch new packages: `npm install`, `pnpm install`, `yarn install`, `pip install -r`, `poetry add`, `cargo add`, `go get`, `bundle install`, `composer install`, `mvn install`, `gradle build` (when it downloads new deps). Note: re-running these to restore a previously locked state may be allowed if the user has scoped it, but adding or upgrading deps always requires permission.
- Pulling Docker / OCI images (`docker pull`, `podman pull`, `nerdctl pull`, `helm pull`, `crane pull`) or running images that implicitly pull (`docker run <new-image>`).
- Installing VS Code / JetBrains / browser extensions or MCP servers from the network.
- Uploading anything to a third-party service: pastebins, diagram renderers, gists, transfer.sh, file.io, S3 buckets outside this repo's IaC, any "share" or "publish" endpoint. This includes uploading code, logs, screenshots, or config snippets for "rendering" or "analysis".
- Running install scripts piped from the network: `curl ... | sh`, `iwr ... | iex`, `wget -O- | bash`, etc. - regardless of the source.

Explicitly allowed (safe to run autonomously when needed for a task):

- Reading from the network: HTTP GET via `WebFetch`, `curl`, `Invoke-WebRequest` to inspect a page or fetch JSON / docs into the conversation (not to disk as an executable).
- Re-running a previously-installed tool already on `PATH` (running `terraform`, `tflint`, `act`, `docker`, etc. that the user has already installed).
- Reading local package metadata (`npm ls`, `pip list`, `terraform version`, `docker images`) without fetching anything.

Workflow when a task needs a tool that is not installed or is the wrong version:

1. Stop. Do not download, install, or upgrade.
2. Report to the user: which tool is missing or out of date, the exact version required, and the recommended install command (so the user can run it themselves).
3. Wait for the user to install it (or to explicitly authorize the install in the current turn).
4. Permission is scoped to the operation and the turn. "Install terraform 1.13.3" does not authorize installing other tools or other versions later.

Workaround attempts that are NOT permitted:

- Downloading a portable binary to a temp directory to "avoid touching the system install".
- Building from source after `git clone`-ing an upstream repo.
- Using a language runtime's package manager (`pip`, `npm`, `cargo`) to fetch a tool "just for this task".
- Pulling a container image to run the tool inside Docker without the user authorizing the image pull.

Rationale: software installs mutate the user's machine in ways that are hard to audit (PATH changes, system services, scheduled tasks, certificate stores), can introduce supply-chain risk, and may conflict with the user's existing toolchain (tfenv, asdf, corporate-managed installs). Uploads can leak proprietary code or secrets to third-party services that cache or index the content. The user is the gatekeeper for what enters the machine and what leaves it.

This rule overrides any inferred convenience. Even if a quality gate fails because a tool is missing, do not install the tool - report the gap and let the user decide.

## AWS CLI and AWS API call gate

The main thread and every agent are forbidden from invoking the AWS API (via the `aws` CLI, any AWS SDK, `terraform` commands that talk to AWS, or any direct HTTP call to an `*.amazonaws.com` endpoint) without an explicit, in-turn user instruction for that specific operation.

Forbidden without explicit user permission:

- Any `aws` CLI subcommand, including read-only ones: `aws sts get-caller-identity`, `aws s3 ls`, `aws iam list-roles`, `aws cloudformation describe-stacks`, `aws secretsmanager describe-secret`, `aws ec2 describe-instances`, etc.
- Any `terraform` subcommand that performs a remote operation: `terraform init` (when the backend is S3 / any remote backend), `terraform plan`, `terraform apply`, `terraform destroy`, `terraform refresh`, `terraform import`, `terraform state list/show/pull/push/mv/rm` against remote state, `terraform console`, `terraform output` against remote state.
- Any SDK call from a script that hits AWS APIs (boto3, AWS SDK for JavaScript / Go / Java, etc.).
- Reading local AWS credentials or session files (`~/.aws/credentials`, `~/.aws/config`, `~/.aws/sso/cache/`, `~/.aws/cli/cache/`, environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`) for diagnostic purposes. The agent does not need to know who the caller is; if a command fails with a credential error, stop and report.
- Triggering AWS-side workflows that exist only to run AWS API calls (e.g., dispatching a workflow that runs `aws cloudformation deploy` is forbidden the same way as running it locally).

Explicitly allowed (safe to run autonomously when needed for a task):

- Local-only `terraform` subcommands that do NOT touch AWS: `terraform fmt`, `terraform fmt -check`, `terraform validate` (against a module with a local-only fixture; if it requires `terraform init` against a remote backend, it is forbidden), `terraform version`, `terraform providers schema -json` (if init has already happened and no remote calls are needed).
- Reading repository files that describe AWS resources without calling AWS: `Read` / `Grep` / `Glob` on `.tf`, `.yaml` (CFN), `.tfvars`, `.tfstate.backup` (local copies only — do NOT pull state).
- `gh` read commands (`gh pr view`, `gh run view`, `gh api` GET) which talk to GitHub, not AWS.

Workflow when a task needs an AWS API call:

1. Stop. Do not invoke the AWS API.
2. Report to the user: what call is needed, why, the exact command, and what the expected effect is (read-only vs mutating, what permissions, what blast radius).
3. Wait for the user to either run the command themselves or to explicitly authorize the call in the current turn.
4. Permission is scoped to the operation and the turn. "Run `terraform plan` for the destroy" does not authorize a future `terraform apply` or a different `terraform plan` against another env; each call requires its own permission.

Agent-internal AWS calls and explicit dispatch:

- Dispatching an agent (e.g., `terraform-planner`, `github-actions-reviewer`) is NOT in itself authorization for that agent to call AWS. The agent must still stop, report, and ask if it cannot find pre-authorized credentials matching the user's stated intent.
- If the user dispatches an agent with an explicit instruction that involves AWS calls ("dispatch terraform-planner to run plan for dev"), that instruction IS the authorization for those specific calls. The agent may proceed.
- If credentials fail mid-run, the agent stops and reports the failure verbatim. The agent does NOT investigate credential state, does NOT read credential files, does NOT call `aws sts get-caller-identity` as a diagnostic. It just reports "credentials failed - please refresh and re-dispatch".

Workaround attempts that are NOT permitted:

- Running `aws ...` inside a `bash -c` / `pwsh -c` wrapper to obscure the call.
- Setting `AWS_PROFILE` or `AWS_ACCESS_KEY_ID` env vars from inside the agent and then running AWS commands.
- Using `curl` or `Invoke-WebRequest` to hit an `*.amazonaws.com` endpoint directly to bypass the `aws` CLI gate.
- Re-running a previously-authorized `terraform plan` to "re-confirm" - each invocation needs its own per-turn authorization.
- Reading `~/.aws/sso/cache/` to check if a session is valid before deciding whether to call AWS.

Rationale: AWS API calls (even read-only ones) cost money (rate limits, audit logging), leave a trail in CloudTrail that the user is accountable for, and can leak who is operating in the account at what time. Mutating calls can cost real money, change shared infrastructure, and cause incidents. The user is the gatekeeper for what AWS sees and when. This is stricter than the git gate (git is local-first; AWS is always remote and audited).

This rule overrides any inferred convenience. If a quality gate fails because credentials are expired, do not investigate credentials - report the gap and let the user decide. If `terraform plan` cannot run because credentials are missing, do not run `aws sts get-caller-identity` to "help diagnose" - just report `terraform plan` failed.

## Out-of-scope safety

- No `terraform apply` from the main thread or any agent. Apply only happens through the GitHub Actions pipeline.
- No `terraform destroy` from the main thread or any agent without explicit user instruction; production destroy is refused by the Makefile and must remain refused.
- No force-push, no direct pushes to `production`, no editing of `bootstrap/01-trust-anchor.yaml` without user approval (it is a manual Console upload).
- No deletion of `tfstate` buckets, KMS keys, or OIDC roles.

## Where to find things

- Skill: `.claude/skills/research-iac-resource/SKILL.md`
- Agents: `.claude/agents/task-planner.md`, `iac-builder.md`, `github-action-builder.md`, `iac-reviewer.md`, `github-actions-reviewer.md`, `terraform-planner.md`
- Workflows: `.github/workflows/`
- Modules: `modules/`
- Envs: `envs/development`, `envs/production`, `envs/_shared`
- Bootstrap (CFN): `bootstrap/`
- Quality scripts: `scripts/`
- Internal notes and Sprint plans (Vietnamese allowed): `notes/`, plans live under `notes/plans/<date>-<slug>/`
