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

The main thread and every agent are forbidden from running any git operation that writes to the user's repository or remote without an explicit, in-turn user instruction for that specific operation.

Forbidden without explicit user permission:

- `git commit` (in any form: `commit`, `commit --amend`, `commit -a`, etc.).
- `git push` (in any form: `push`, `push -u`, `push --force`, `push --tags`, etc.).
- `git merge`, `git rebase`, `git cherry-pick`, `git revert` that produce new commits.
- `git tag` that creates or pushes a tag.
- `git reset --hard`, `git restore --staged`, or any destructive index/working-tree operation.
- `gh pr create`, `gh pr merge`, `gh pr close`, `gh release create`, or any `gh` subcommand that writes to GitHub (issues, PRs, releases, comments, reviews).
- Any other command that writes to the local git history, the working tree in a destructive way, or the remote.

Explicitly allowed (read-only or local-only, safe to run autonomously when needed for a task):

- `git status`, `git log`, `git diff`, `git show`, `git branch` (list only), `git remote -v`, `git rev-parse`, `git fetch` (read-only sync).
- `git add` and `git restore` against the working tree (staging only, no history change). Staging is OK because the next step (`git commit`) is still gated.
- `git checkout <branch>` and `git checkout -b <branch>` locally - branch switching only, no remote write. Pushing the new branch still needs user permission.
- Reading `gh` data (`gh pr view`, `gh pr list`, `gh run view`, `gh api` GET, etc.).

Workflow when changes need to land on a branch or be pushed:

1. The main thread (or an agent) edits the files in the working tree.
2. The main thread reports the diff to the user and stops.
3. The user runs `git commit` and `git push` themselves, or explicitly instructs the main thread to do so in the current turn ("commit and push", "push this up", "open a PR for this").
4. Permission is scoped to the operation and the turn. "Commit this" does not authorize a future commit; the next commit requires its own permission.

Rationale: commits and pushes mutate the user's authoritative history and trigger downstream automation (GitHub Actions workflows, deploy pipelines, branch protection checks). The user is the gatekeeper for what enters that history and when.

This rule overrides any inferred convenience. Even if a task feels "obviously complete" or the user has previously approved similar commits, do not commit or push without a fresh instruction in the current turn.

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
