---
name: research-iac-resource
description: Research the official documentation of an infrastructure resource (AWS, GCP, Azure, Kubernetes, etc.) before any IaC create/modify task. Fetches the relevant vendor docs, optionally uses Playwright MCP for JavaScript-rendered pages, summarizes the resource model, then produces a precise change plan and asks the user to confirm before code is written. Always cleans up Playwright screenshots when finished. Trigger when the user asks to create, change, refactor, or review any cloud or infra resource (e.g. "create EKS cluster", "add ALB listener", "add GCS bucket", "modify RDS parameter group", "review S3 bucket lifecycle"). Also trigger before any edit under modules/, envs/, global/, or bootstrap/.
---

# Research IaC Resource

## Purpose

Before writing or modifying any Infrastructure-as-Code, gather authoritative knowledge from the resource vendor's official documentation. The skill ends by producing a written plan and asking the user to confirm. No code is written by this skill itself; it returns a plan that downstream agents (or the main thread) execute.

## When to use

Invoke this skill at the start of every IaC task that touches a real cloud or platform resource. Examples:

- "Create an EKS cluster" -> research AWS EKS docs.
- "Add a CloudFront response headers policy" -> research AWS CloudFront docs.
- "Add a GKE node pool" -> research GCP GKE docs.
- "Switch RDS to gp3" -> research AWS RDS storage docs.
- "Review this ALB module" -> research AWS ELBv2 docs.

Skip this skill only for cosmetic edits (rename a variable, fix formatting, edit a comment, fix a typo in a string).

## Inputs

The caller should provide:

1. The resource (cloud + service + concrete type, e.g. `AWS::EKS::Cluster`, `google_container_cluster`).
2. The action (create / modify / refactor / review / delete).
3. Constraints from the user (region, env, naming, compliance, budget, deadline).

If any of these are missing, ask the user before researching.

## Procedure

### Step 1 - Identify the documentation source

Pick the most authoritative vendor source. Preferred order:

1. The vendor's own product docs (e.g. `docs.aws.amazon.com`, `cloud.google.com/docs`, `learn.microsoft.com/azure`, `kubernetes.io/docs`).
2. The vendor's API or CloudFormation reference if the resource is defined there (e.g. AWS CloudFormation Template Reference, AWS API Reference).
3. The Terraform provider documentation on `registry.terraform.io` for the exact resource type that will be used.

For an AWS resource, always read both:
- The product page (concepts, limits, lifecycle, IAM requirements).
- The Terraform `registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/<resource>` page that will actually be written.

For a GCP resource, read the GCP product page and `registry.terraform.io/providers/hashicorp/google/latest/docs/resources/<resource>`.

For Azure: vendor docs plus `hashicorp/azurerm`.

For Kubernetes: `kubernetes.io/docs` plus the Terraform `kubernetes` or `helm` provider page.

### Step 2 - Fetch the docs

Try the cheap path first:

1. Use `WebFetch` against the URLs from Step 1. Most vendor docs are server-rendered and return useful content via `WebFetch`.
2. If the page returns nothing useful, is JavaScript-rendered, or is gated behind a UI control (e.g. a tab you must click to reveal a code sample), only then escalate to Playwright MCP.

### Step 3 - Escalate to Playwright MCP only if needed

Use Playwright MCP when `WebFetch` is insufficient. Required steps:

1. `mcp__playwright__browser_navigate` to the doc URL.
2. `mcp__playwright__browser_snapshot` to read the accessibility tree (text-only, no image needed).
3. Click / expand only the controls that hide the content you need. Re-snapshot.
4. If, and only if, you cannot get the information from the snapshot text, use `mcp__playwright__browser_take_screenshot`. Always pass an explicit, predictable `filename` so cleanup can find it (see Step 6). Prefer `fullPage: true` and `type: "png"`.
5. `mcp__playwright__browser_close` when finished with the site.

Do not screenshot purely to "have a copy" of the page. Screenshots are a fallback for visual content (architecture diagrams, screenshots of console flows that change behavior). The accessibility snapshot is normally enough.

### Step 4 - Extract a structured summary

For every resource you researched, capture in your working notes:

- **Resource identity**: vendor service + concrete type (e.g. `AWS::EKS::Cluster`, `aws_eks_cluster`).
- **Required properties**: name, version, role, networking inputs, etc.
- **Update behavior**: which properties trigger replacement vs in-place update vs no interruption. For AWS, take this from the CloudFormation Template Reference. For Terraform, cross-check the "ForceNew" notes.
- **Hard limits**: quotas, naming rules, region/AZ constraints, max resource counts.
- **IAM and dependencies**: required IAM roles, service-linked roles, prerequisite resources (VPC, subnets, security groups, KMS keys).
- **Lifecycle hazards**: deletion protection, snapshot-on-delete, finalizers, cool-down windows, eventual consistency.
- **Pricing-relevant knobs**: anything that changes cost class (instance family, tier, multi-AZ, log retention).
- **Security defaults**: encryption-at-rest, TLS, public exposure defaults.

### Step 5 - Produce the change plan

Write the plan to the chat (not to a file). The plan must contain:

1. **Goal** - one-sentence restatement of the user's task.
2. **Resources affected** - bullet list of every resource that will be created, modified, or destroyed. For modifications, name the exact attribute(s).
3. **Update behavior** - for every modification, state whether Terraform will replace, update in place, or no-op, with the doc evidence.
4. **Risks and prerequisites** - downtime, replacement of a stateful resource, IAM changes, quota requests, dependencies on resources outside this repo.
5. **Files to touch** - exact file paths (modules, envs, bootstrap, .github/workflows, etc.).
6. **Out of scope** - anything the user might assume is included but is not.
7. **Open questions** - anything the docs did not resolve.

Keep the plan concrete and short. Do not paste raw doc text; cite section names or URLs.

### Step 6 - Confirm before any code is written

After presenting the plan, ask the user to confirm explicitly. Use `AskUserQuestion` with options like:

- "Proceed as planned"
- "Proceed with edits" (the user will tell you what to change)
- "Cancel"

Do not proceed to write or modify code until the user picks "Proceed as planned" or its edited form. If the user cancels, stop.

### Step 7 - Mandatory Playwright screenshot cleanup

If, and only if, Playwright was used in Step 3, you must remove every screenshot it produced before this skill returns. The Playwright MCP server stores screenshots in its own output directory. Cleanup procedure:

1. Resolve the output directory in this priority order:
   - The `--output-dir` value passed to the Playwright MCP server, if known.
   - The `outputDir` field of the project's Playwright MCP config, if present.
   - The OS default used by Playwright MCP: on Windows `%TEMP%\playwright-mcp-output\` (typically `C:\Users\<user>\AppData\Local\Temp\playwright-mcp-output\`); on macOS/Linux `$TMPDIR/playwright-mcp-output/` or `/tmp/playwright-mcp-output/`.
2. Delete every `.png`, `.jpeg`, and `.jpg` file you wrote during this skill invocation. Match by the filenames you supplied to `browser_take_screenshot`. Never blanket-delete files written by other sessions.
3. Verify the deletion by listing the directory and confirming the targeted filenames are gone.
4. State in the chat: "Playwright screenshots cleaned: <count> file(s) removed from <path>."

If Playwright was not used, skip cleanup but still state: "Playwright not used; no screenshots to clean."

### Step 8 - Return control

Hand back to the caller a single, compact message containing:

- The confirmed plan (or "user cancelled").
- The cleanup status from Step 7.
- A short list of doc URLs consulted.

## Hard rules

- Never write or edit IaC code from inside this skill. The skill researches and plans only.
- Never paste secrets from the docs (sample tokens, sample account IDs, sample ARNs that look like a real customer's) into chat.
- Never recommend a Terraform resource type without confirming it exists in the provider docs you actually read.
- If the resource has no official Terraform provider (only a community fork or a REST-only API), say so clearly in the plan and ask the user how to proceed.
- Vendor docs change. Always note the date you accessed them in the plan footer.
- Two-surface language rule. The plan and the confirmation question shown in chat are written in Vietnamese (the calling agent produces the chat output following this rule). Resource type names, attribute names, command lines, file paths, vendor service names, and URLs stay in English and are not translated. The skill never writes Vietnamese into any file in the repo. No emojis. No icons.
