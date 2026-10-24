# OIDC Guide — GitHub Actions ↔ AWS (không có access key dài hạn)

> Tài liệu giải thích đầy đủ kiến thức nền của GitHub OIDC ↔ AWS, các bước triển khai end-to-end, và cách dự án `3-tiers-app-infrastructure` định tuyến về đúng AWS account ở từng layer.
>
> Nguồn tham chiếu: GitHub Actions OIDC docs, AWS IAM `id_roles_providers_create_oidc`, AWS STS `AssumeRoleWithWebIdentity`, `aws-actions/configure-aws-credentials` README. Xem mục Tham khảo cuối file.

---

## 1. Vấn đề cũ: long-lived access keys

Cách truyền thống GitHub Actions truy cập AWS:

```
1. Tạo IAM user trong AWS Console
2. Tạo Access Key + Secret Key (dài hạn, không hết hạn)
3. Lưu vào GitHub Secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
4. Workflow đọc từ secrets, gọi AWS API
```

**Vấn đề:**
- Key **không bao giờ hết hạn** — leak 1 lần là vĩnh viễn cho đến khi rotate thủ công.
- Key nằm trong GitHub Secrets — repo admin (hoặc kẻ chiếm được token admin) có thể đọc/copy.
- Khó rotate (phải nhớ + automation phức tạp + sync giữa nhiều nơi).
- Audit kém — CloudTrail chỉ thấy IAM user, không phân biệt được workflow nào, branch nào, ai trigger.
- Vi phạm AWS best practice: *"use temporary credentials"*.

---

## 2. Kiến thức nền: OIDC là gì?

**OpenID Connect (OIDC)** là một lớp authentication trên OAuth 2.0, định nghĩa một identity provider (IdP) phát hành các **ID token** (chuẩn JWT) chứa thông tin định danh của một principal. Bên thứ ba (AWS) có thể trust một IdP và dùng token để cấp quyền tạm thời cho principal — không cần biết mật khẩu hay key dài hạn.

Các thành phần OIDC chuẩn:

- **Issuer URL** — URL công khai của IdP, ví dụ `https://token.actions.githubusercontent.com`. URL phải dùng HTTPS, không có port, không có query string. Path component được phép.
- **Discovery endpoint** — luôn nằm tại `<issuer>/.well-known/openid-configuration`. Trả JSON metadata: `issuer`, `jwks_uri`, `claims_supported`, `id_token_signing_alg_values_supported`, ...
- **JWKS endpoint** — chứa public key (RSA hoặc ECDSA) để verify chữ ký JWT. Tối đa 100 key RSA + 100 key EC mỗi loại.
- **Signing algorithms** — chấp nhận `RS256`, `RS384`, `RS512`, `ES256`, `ES384`, `ES512`.
- **Audience (`aud`) claim** — định danh "ai là intended recipient" của token. Khi đăng ký IdP với AWS, audience phải khớp với client ID đã đăng ký (với GitHub → AWS, mặc định là `sts.amazonaws.com`).

GitHub Actions là một OIDC IdP đầy đủ. Mọi job có thể yêu cầu một JWT ngắn hạn ký bởi GitHub, gửi cho AWS để đổi lấy temporary credentials. Không cần lưu trữ secret dài hạn ở bất cứ đâu.

---

## 3. Kiến thức nền: cấu trúc JWT

JWT (`xxxxx.yyyyy.zzzzz`) gồm 3 phần base64url-encoded:

1. **Header** — `{ "alg": "RS256", "typ": "JWT", "kid": "<key id>" }`. `kid` chỉ định key nào trong JWKS được dùng để ký.
2. **Payload** — JSON chứa các *claims* (xem mục 5).
3. **Signature** — chữ ký của `header.payload` bằng private key của IdP. AWS tải public key từ `jwks_uri` để verify.

JWT là **stateless**: AWS không cần "hỏi GitHub" mỗi lần verify; chỉ cần public key của GitHub là đủ. Vì vậy mỗi token có `exp` (thời điểm hết hạn) ngắn — token GitHub Actions thường có TTL khoảng **5–10 phút**, vừa đủ để job bắt đầu và assume role.

---

## 4. Kiến thức nền: GitHub Actions OIDC issuer

- **Issuer URL** (cố định cho github.com): `https://token.actions.githubusercontent.com`
  - GHES (GitHub Enterprise Server) có issuer khác — xem doc GHES tương ứng.
  - URL **case-sensitive**, không có trailing slash, không có port.
- **Discovery**: `https://token.actions.githubusercontent.com/.well-known/openid-configuration`
- **JWKS**: GitHub xoay key định kỳ — đó là lý do AWS không hard-code public key mà tải qua JWKS.
- **Audience mặc định**: GitHub cấp `aud = https://github.com/<owner>` nếu workflow không request audience cụ thể. Khi dùng `aws-actions/configure-aws-credentials`, action **tự request `aud = sts.amazonaws.com`** nên trust policy AWS phải khớp giá trị này.
- **Permission cần thiết** — workflow phải khai báo:
  ```yaml
  permissions:
    id-token: write   # cho phép job request OIDC JWT
    contents: read    # cần thiết cho actions/checkout
  ```
  `id-token: write` **không** cho job ghi gì cả; chỉ là quyền request token. Mặc định permission là `read` cho `contents`, không có `id-token`. Thiếu dòng này → `Error: Could not get OIDC token`.

---

## 5. JWT claims đầy đủ

Decode một JWT thực tế của GitHub Actions có dạng:

```json
{
  "jti": "<uuid>",
  "iss": "https://token.actions.githubusercontent.com",
  "aud": "sts.amazonaws.com",
  "sub": "repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/development",

  "iat": 1715000000,
  "nbf": 1714999940,
  "exp": 1715000600,

  "repository": "myorg/3-tiers-app-infrastructure",
  "repository_owner": "myorg",
  "repository_id": "123456789",
  "repository_owner_id": "987654321",
  "repository_visibility": "private",

  "actor": "alice",
  "actor_id": "11223344",

  "ref": "refs/heads/development",
  "ref_type": "branch",
  "head_ref": "",
  "base_ref": "",
  "sha": "<commit sha>",

  "workflow": "Terraform Apply",
  "workflow_ref": "myorg/3-tiers-app-infrastructure/.github/workflows/terraform-apply.yaml@refs/heads/development",
  "workflow_sha": "<commit sha>",
  "job_workflow_ref": "myorg/3-tiers-app-infrastructure/.github/workflows/terraform-apply.yaml@refs/heads/development",
  "job_workflow_sha": "<commit sha>",

  "run_id": "1234567890",
  "run_number": "42",
  "run_attempt": "1",

  "event_name": "push",
  "environment": "development",
  "runner_environment": "github-hosted",

  "enterprise": "myenterprise"
}
```

**Claim quan trọng để AWS verify:**

| Claim | Ý nghĩa | AWS dùng để |
|-------|---------|-------------|
| `iss` | Issuer của token | Khớp với URL của OIDC provider trong IAM |
| `aud` | Intended recipient | Khớp với ClientIDList của OIDC provider |
| `sub` | Định danh chính xác workflow context | Lọc trong trust policy bằng condition key |
| `exp`, `iat`, `nbf` | Thời điểm hợp lệ | Token hết hạn → từ chối |

**Format của `sub` claim** — đây là chỗ chính để hardening trust policy:

| Context | Format `sub` |
|---------|--------------|
| Push lên branch | `repo:<ORG>/<REPO>:ref:refs/heads/<BRANCH>` |
| Push lên tag | `repo:<ORG>/<REPO>:ref:refs/tags/<TAG>` |
| Pull request | `repo:<ORG>/<REPO>:pull_request` |
| Trong GitHub Environment | `repo:<ORG>/<REPO>:environment:<ENV-NAME>` |

Lưu ý:
- Bất kỳ ký tự `:` nào trong metadata sẽ được thay bằng `%3A`.
- Có thể tùy biến `sub` qua REST API `PUT /repos/{owner}/{repo}/actions/oidc/customization/sub` (`include_claim_keys`), ví dụ ép `sub` chứa `job_workflow_ref` để bắt buộc workflow phải gọi từ một reusable workflow cố định.

---

## 6. AWS validate JWT thế nào? (cập nhật 2023+)

Trước đây AWS yêu cầu khai báo **TLS thumbprint** (fingerprint của intermediate cert) khi tạo OIDC provider. Từ tháng 7/2023 AWS đổi cơ chế:

> *"AWS secures communication with OIDC identity providers (IdPs) using our library of trusted root certificate authorities (CAs) to verify the JSON Web Key Set (JWKS) endpoint's TLS certificate. If your OIDC IdP relies on a certificate that is not signed by one of these trusted CAs, only then we secure communication using the thumbprints set in the IdP's configuration."*

Hệ quả:

- Với `token.actions.githubusercontent.com` (TLS cert do CA công khai ký) → AWS dùng built-in CA library, **không cần thumbprint**.
- Thumbprint giờ chỉ là **fallback** khi CA không trusted hoặc TLS 1.3 buộc bypass.
- README của `aws-actions/configure-aws-credentials` ghi rõ: *"Prior versions of this documentation gave instructions for specifying the certificate fingerprint, but this is no longer necessary. The thumbprint, if specified, will be ignored."*

Tuy nhiên, khi tạo `AWS::IAM::OIDCProvider` trong CloudFormation/Terraform, **field `ThumbprintList` vẫn bắt buộc** (API yêu cầu ít nhất 1 thumbprint, max 5). Nên đặt giá trị thumbprint hiện tại của GitHub để hợp lệ với schema, nhưng nó sẽ không được dùng trong validation thông thường:

```
6938fd4d98bab03faadb97b34396831e3780aea1
1c58a3a8518e8759bf075b76b750d4f2df264fcd
```

**Quy trình AWS validate một AssumeRoleWithWebIdentity request:**

1. Parse JWT từ `WebIdentityToken` parameter.
2. Lấy `iss` claim → tra IAM OIDC provider có URL khớp không. Không có → `InvalidIdentityToken`.
3. Tải JWKS qua `jwks_uri`. TLS cert của endpoint được verify bằng built-in CA library (fallback: thumbprint).
4. Verify chữ ký JWT bằng public key tương ứng `kid`. Sai chữ ký → `InvalidIdentityToken`.
5. Check `exp`/`nbf`/`iat` còn hợp lệ. Hết hạn → `ExpiredToken`.
6. Check `aud` claim có nằm trong `ClientIDList` của OIDC provider không. Không khớp → `InvalidIdentityToken`.
7. Đánh giá trust policy của `RoleArn`:
   - `Principal.Federated` phải khớp ARN của OIDC provider trong account.
   - `Action` phải là `sts:AssumeRoleWithWebIdentity`.
   - `Condition` (StringEquals/StringLike trên `:aud`, `:sub`, ...) phải pass.
   - Sai → `IDPRejectedClaim` hoặc `AccessDenied`.
8. Nếu mọi bước pass → trả `Credentials` (AccessKeyId + SecretAccessKey + SessionToken + Expiration). Mặc định 3600s; có thể yêu cầu 900s–min(`MaxSessionDuration`, 43200s).

---

## 7. Token flow chi tiết

```
+-----------------+                 +------------------+                 +----------------+
|  GitHub Actions |                 |   AWS STS        |                 |  AWS Account   |
|   Workflow run  |                 |  (IAM, OIDC)     |                 |   resources    |
+--------+--------+                 +--------+---------+                 +--------+-------+
         |                                   |                                    |
         | 1. id-token: write -> request     |                                    |
         |    JWT từ GitHub OIDC issuer.     |                                    |
         |    JWT.sub = repo:ORG/REPO:       |                                    |
         |     ref:refs/heads/development    |                                    |
         |    JWT.aud = sts.amazonaws.com    |                                    |
         |                                   |                                    |
         | 2. AssumeRoleWithWebIdentity      |                                    |
         |    (RoleArn=...gha-infra-apply,   |                                    |
         |     WebIdentityToken=JWT)         |                                    |
         | --------------------------------> |                                    |
         |                                   |                                    |
         |                                   | 3. Tra OIDC provider theo iss      |
         |                                   |    -> tải JWKS, verify TLS cert    |
         |                                   |    bằng CA library                 |
         |                                   |                                    |
         |                                   | 4. Verify signature JWT bằng       |
         |                                   |    public key (theo kid)           |
         |                                   |                                    |
         |                                   | 5. Check trust policy:             |
         |                                   |    - aud match?                    |
         |                                   |    - sub match?                    |
         |                                   |    - exp/nbf hợp lệ?               |
         |                                   |                                    |
         | 6. Trả về Credentials             |                                    |
         |    (AccessKeyId,                  |                                    |
         |     SecretAccessKey,              |                                    |
         |     SessionToken,                 |                                    |
         |     Expiration: ~1h)              |                                    |
         | <-------------------------------- |                                    |
         |                                   |                                    |
         | 7. Dùng temp creds gọi AWS API    |                                    |
         | --------------------------------------------------------------------> |
         |    (terraform apply, aws s3 cp, ...)                                   |
         |                                   |                                    |
         | 8. Workflow done -> creds expire  |                                    |
         |    tự động sau Expiration         |                                    |
```

**Tóm tắt vòng đời credentials:**

| Bước | TTL | Lưu ở đâu |
|------|-----|-----------|
| GitHub OIDC JWT | ~5–10 phút | Memory của GitHub runner |
| AWS temp credentials | 900s–43200s (mặc định 3600s) | Env var `AWS_*` trong runner |
| Long-lived secret | (không có) | (không tồn tại) |

---

## 8. Các bước triển khai GitHub OIDC ↔ AWS (end-to-end)

Dưới đây là quy trình chuẩn để cấu hình GitHub OIDC vào một AWS account *từ đầu*. Áp dụng cho cả greenfield lẫn việc tự deploy `bootstrap/01-trust-anchor.yaml` của dự án này.

AWS Security Blog ([Use IAM roles to connect GitHub Actions to actions in AWS](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)) định nghĩa quy trình **5 bước chính thức**:

1. Tạo OIDC provider trong AWS account.
2. Tạo IAM role và scope trust policy về GitHub org / repo / branch cụ thể.
3. Gán quyền tối thiểu (least-privilege) cho role.
4. Tạo file workflow GitHub Actions để assume role.
5. Audit role usage qua CloudTrail.

Mục dưới đi qua đủ 5 bước, đồng thời thêm Bước 6 (Hardening) cho production-grade.

### Prerequisites

- Quyền IAM trong AWS account: tối thiểu `iam:CreateOpenIDConnectProvider`, `iam:CreateRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy`. Account root hoặc role admin một lần đầu là đủ.
- Repository GitHub đã tồn tại, biết `<ORG>/<REPO>`.
- Đã chọn AWS region để chạy workflow (ví dụ `ap-southeast-1`).

### Bước 1 — Tạo IAM OIDC identity provider trong AWS

Một AWS account chỉ cần **một** OIDC provider cho GitHub. Nó được share giữa nhiều role trong cùng account, nhưng **không cross-account** — mỗi account muốn nhận GitHub OIDC phải tạo provider riêng.

> **Case-sensitivity:** Provider URL phải được nhập **toàn bộ chữ thường** (`https://token.actions.githubusercontent.com`). AWS Security Blog đính kèm note ngày 22/5/2023: *"The IDP created in this post should be entered in lowercase through the post."* Viết hoa bất kỳ ký tự nào → AssumeRoleWithWebIdentity fail vì `iss` không match.
>
> **Một-một với IdP:** *"Each provider is a one-to-one relationship to an external IdP. If you want to add more IdPs to your account, you can repeat this process."* Trong cùng 1 account, không tạo 2 provider cùng URL được; nếu cần thêm IdP khác (GitLab, BitBucket, ...) tạo riêng mỗi cái.

**Option A — AWS Console**

1. IAM → Identity providers → Add provider.
2. Chọn OpenID Connect.
3. Provider URL: `https://token.actions.githubusercontent.com` → bấm "Get thumbprint" (Console tự lấy; có thể bỏ qua nếu không bắt buộc, nhưng API/CFN vẫn cần).
4. Audience: `sts.amazonaws.com`. Nếu cần audience khác → "Add audience" sau.
5. Add provider.

**Option B — AWS CLI**

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd
```

**Option C — CloudFormation** (chính là cách dự án này làm trong `bootstrap/01-trust-anchor.yaml`)

```yaml
GitHubOidcProvider:
  Type: AWS::IAM::OIDCProvider
  DeletionPolicy: Retain
  UpdateReplacePolicy: Retain
  Properties:
    Url: https://token.actions.githubusercontent.com
    ClientIdList:
      - sts.amazonaws.com
    ThumbprintList:
      - 6938fd4d98bab03faadb97b34396831e3780aea1
      - 1c58a3a8518e8759bf075b76b750d4f2df264fcd
```

`DeletionPolicy: Retain` quan trọng — nếu xóa stack mà chưa có replacement, mọi role trust provider này sẽ mồ côi.

**Option D — Terraform**

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}
```

Output ARN có format: `arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`.

### Bước 2 — Tạo IAM role với trust policy

Role này là cái workflow sẽ assume.

**Trust policy (tối thiểu):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:<ORG>/<REPO>:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

**StringEquals vs StringLike — chỗ dễ sai bảo mật:**

- `StringEquals` so khớp **chính xác**. Dùng khi biết rõ ref/env (ví dụ chỉ branch `main`).
- `StringLike` cho phép wildcard `*`. **Chỉ dùng khi thực sự cần** (ví dụ mọi tag bắt đầu bằng `v`):
  ```json
  "StringLike": {
    "token.actions.githubusercontent.com:sub": "repo:<ORG>/<REPO>:ref:refs/tags/v*"
  }
  ```
- **Pitfall** điển hình: dùng `StringLike` cho exact value (không có `*`) — vẫn chạy nhưng không tận dụng tính chặt chẽ; nguy hiểm hơn là viết `repo:<ORG>/<REPO>:*` → bất kỳ workflow nào của repo (bao gồm PR từ fork) đều assume được. Tránh wildcard ở đầu hoặc cuối khi không hiểu rõ tác động.

**Permissions policy** — gắn vào role theo nguyên tắc least-privilege:

```bash
aws iam create-role \
  --role-name gha-deploy \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name gha-deploy \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

Tránh `AdministratorAccess` trừ trường hợp đặc biệt (như role bootstrap của dự án này — chỉ chạy 1 lần và bị giới hạn bởi GitHub Environment "bootstrap").

**`MaxSessionDuration`** — quyết định trần `DurationSeconds` mà workflow có thể request. Mặc định 3600s; tăng lên tối đa 43200s nếu workflow chạy lâu (terraform apply lớn, build chậm, ...).

### Bước 3 — Cấu hình GitHub Actions workflow

```yaml
name: deploy

on:
  push:
    branches: [main]

permissions:
  id-token: write   # bắt buộc để request OIDC JWT
  contents: read    # cho actions/checkout

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/gha-deploy
          role-session-name: gha-${{ github.run_id }}
          aws-region: ap-southeast-1

      - name: Verify identity
        run: aws sts get-caller-identity
```

**Inputs đáng chú ý của `aws-actions/configure-aws-credentials`** (phiên bản v4 trở lên — bản mới nhất ổn định là v6.1.x):

| Input | Mặc định | Khi nào dùng |
|-------|----------|--------------|
| `role-to-assume` | (bắt buộc cho OIDC) | ARN role cần assume |
| `aws-region` | (bắt buộc) | Region cho AWS calls |
| `audience` | `sts.amazonaws.com` | Đổi nếu dùng partition khác (China, GovCloud) |
| `role-session-name` | `GitHubActions` | Đặt rõ ràng để CloudTrail log dễ trace |
| `role-duration-seconds` | `3600` | Tăng nếu job dài; phải ≤ `MaxSessionDuration` của role |
| `role-skip-session-tagging` | `false` | Bật nếu trust policy không cho phép `sts:TagSession` |
| `role-chaining` | `false` | Bật khi đã có credentials, muốn assume thêm role |

Phiên bản action — pin theo SHA hoặc tag major:
- `aws-actions/configure-aws-credentials@v4` — ổn định, đủ tính năng OIDC.
- `aws-actions/configure-aws-credentials@v6` — bản mới nhất (v6.1.x — Node.js 24, cần runner GitHub-hosted ≥ 2.327.1).
- Tránh dùng `@v1.x` (xuất hiện trong nhiều blog cũ, kể cả AWS Security Blog 2023): không hỗ trợ session tagging tốt, đã có nhiều patch security trong v4+.

### Bước 4 — Verify happy path

Push lên branch trigger workflow. Trong workflow logs cần thấy:

- Step `Configure AWS credentials` log `Authenticated as assumedRoleId AROA...:gha-<run-id>`.
- Step `aws sts get-caller-identity` trả ARN dạng `arn:aws:sts::<ACCOUNT_ID>:assumed-role/gha-deploy/gha-<run-id>` — đó là dấu hiệu OIDC đã hoạt động end-to-end.

### Bước 5 — Audit qua CloudTrail

AWS Security Blog xem đây là bước cuối chính thức (không phải tùy chọn): xác minh role được dùng đúng cách qua CloudTrail Event History. Làm ngay sau khi happy path chạy lần đầu, và lặp lại định kỳ.

**Tra theo Event source:**

1. AWS Console → CloudTrail → Event history.
2. Lookup attributes → **Event source** → giá trị `sts.amazonaws.com`.
3. Hai event quan trọng cần thấy:
   - `AssumeRoleWithWebIdentity` — xác nhận GitHub authenticate và đổi token thành credentials. Trong event details:
     - `userIdentity.identityProvider = token.actions.githubusercontent.com`
     - `requestParameters.roleArn` = ARN role workflow assume.
     - `requestParameters.webIdentityToken` đã được redact.
     - `responseElements.subjectFromWebIdentityToken` = `sub` claim (ví dụ `repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/development`).
   - `GetCallerIdentity` (hoặc bất kỳ API call nào sau đó) — xác nhận credentials hoạt động.

**Tra theo User name (lọc chính xác workflow nào):**

1. CloudTrail → Event history → Lookup attributes → **User name**.
2. Hai cách lookup:
   - Theo `role-session-name` (giá trị bạn đặt trong workflow, ví dụ `GitHub_to_AWS_via_FederatedOIDC` hoặc `gha-<run-id>`) → lọc ra mọi action mà session đó thực hiện.
   - Theo `sub` claim (ví dụ `repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/main`) → lọc ra mọi `AssumeRoleWithWebIdentity` được trigger từ context đó (branch/env cụ thể).

**Vì lý do này, đặt `role-session-name` có ý nghĩa rất quan trọng:**

```yaml
role-session-name: gha-${{ github.workflow }}-${{ github.run_id }}
```

→ CloudTrail có dòng audit dễ đọc, gắn được với workflow run cụ thể trên GitHub.

**Pattern downstream events:** mọi API call sau khi assume role có `userIdentity.principalId = AROA...:<role-session-name>`, `userIdentity.arn = arn:aws:sts::<ACCOUNT_ID>:assumed-role/<RoleName>/<role-session-name>` — trace ngược ra workflow run nào.

### Bước 6 — Hardening

Sau khi happy path chạy, siết bảo mật theo thứ tự ưu tiên:

1. **Thu hẹp `sub` condition.** Bắt đầu rộng (cho cả repo) → thu lại theo branch/environment cụ thể. Production phải có condition cứng theo branch.
2. **Dùng GitHub Environment + deployment branch restrictions** cho production. Trust policy cũng dùng `:environment:production` thay vì `:ref:refs/heads/production` để hai layer match nhau.
3. **Yêu cầu protected branch** cho `main`/`production`: required reviewers, no force-push, fast-forward only. Ngăn attacker push code độc.
4. **Tách role per workflow** — `gha-infra-plan` (read-only), `gha-infra-apply` (write), `gha-backend-deploy` (chỉ ECS), ... Một workflow hỏng không phá toàn bộ.
5. **MaxSessionDuration vừa đủ** — tăng chỉ khi cần.
6. **Customize `sub` claim qua REST API** nếu repo có nhiều reusable workflows: ép `sub` chứa `job_workflow_ref` để chỉ workflow file cụ thể assume được.
7. **Chặn `aud` mặc định** — luôn check `:aud = sts.amazonaws.com` để chối token được issue cho audience khác.
8. **CloudTrail + log aggregator** — alert mọi `AssumeRoleWithWebIdentity` failure trên role nhạy cảm.

---

## 9. `bootstrap/01-trust-anchor.yaml` của dự án này tạo gì?

File CloudFormation này **chỉ tạo 2 thứ** trong account đang login (Console upload thủ công):

### 9.1. `AWS::IAM::OIDCProvider`

```yaml
GitHubOidcProvider:
  Type: AWS::IAM::OIDCProvider
  Properties:
    Url: https://token.actions.githubusercontent.com
    ClientIdList: [sts.amazonaws.com]
    ThumbprintList:
      - 6938fd4d98bab03faadb97b34396831e3780aea1
      - 1c58a3a8518e8759bf075b76b750d4f2df264fcd
```

Đăng ký GitHub là trusted IdP cho account hiện tại. Sau bước này AWS chấp nhận token ký bởi `token.actions.githubusercontent.com` (verify qua TLS CA + JWKS public key).

**Quan trọng:** OIDC provider **per account** — phải upload trust anchor riêng cho mỗi account (development + production).

### 9.2. `AWS::IAM::Role` tên `gha-bootstrap`

```yaml
GhaBootstrapRole:
  Properties:
    RoleName: gha-bootstrap
    MaxSessionDuration: 3600
    ManagedPolicyArns:
      - arn:aws:iam::aws:policy/AdministratorAccess
    AssumeRolePolicyDocument:
      Statement:
        - Principal: { Federated: !Ref GitHubOidcProvider }
          Action: sts:AssumeRoleWithWebIdentity
          Condition:
            StringEquals:
              'token.actions.githubusercontent.com:aud': sts.amazonaws.com
            StringLike:
              'token.actions.githubusercontent.com:sub':
                !Sub "repo:${GitHubOrg}/${RepoName}:environment:bootstrap"
```

Trust policy nói:
- Principal `Federated` = JWT token từ GitHub OIDC provider trong account hiện tại.
- Action: `sts:AssumeRoleWithWebIdentity`.
- Điều kiện:
  - `aud = sts.amazonaws.com` (đúng audience).
  - `sub = repo:<org>/<repo>:environment:bootstrap` — **chỉ workflow chạy trong GitHub Environment tên `bootstrap`** mới assume được.

Lưu ý dùng `StringLike` ở đây với giá trị literal (không có wildcard) là functionally giống `StringEquals`. Nếu muốn chặt hơn nên đổi sang `StringEquals` để rõ ý định.

### 9.3. Sau khi `01-trust-anchor.yaml` deploy xong

Account đó có:
- 1 OIDC provider (trust GitHub).
- 1 role `gha-bootstrap` (chỉ workflow trong env `bootstrap` của repo cụ thể assume được, có quyền AdministratorAccess để chạy `bootstrap.yaml` deploy stacks 02 + 03).

**Đó là TẤT CẢ.** Trust anchor không tạo state bucket, không tạo các role khác. Đó là việc của workflow `bootstrap.yaml` (sau khi đã có trust anchor).

---

## 10. Where account targeting happens — 5 LAYERS

Trong dự án multi-account, có **5 layers** quyết định "workflow này được assume role ở account nào":

### Layer 1: AWS Account context (where the OIDC provider lives)

```
Account development (111111111111)            Account production (222222222222)
+-- OIDC provider                             +-- OIDC provider
|   (tạo bởi 01-trust-anchor.yaml)            |   (tạo bởi 01-trust-anchor.yaml)
|                                             |
+-- role gha-bootstrap                        +-- role gha-bootstrap
+-- role gha-infra-plan                       +-- role gha-infra-plan
+-- role gha-infra-apply                      +-- role gha-infra-apply
+-- role gha-backend-deploy                   +-- role gha-backend-deploy
+-- role gha-frontend-deploy                  +-- role gha-frontend-deploy
|                                             |
+-- S3 myorg-tfstate-111111111111             +-- S3 myorg-tfstate-222222222222
```

**Mỗi account có bộ roles riêng độc lập.** Không có role nào "cross-account" — workflow muốn truy cập account nào phải assume role NẰM TRONG account đó.

→ **Account ID trong `RoleArn`** quyết định workflow đi vào account nào.

### Layer 2: GitHub Environment (`development` vs `production`)

```yaml
# .github/workflows/terraform-apply.yaml
jobs:
  apply:
    environment: ${{ github.ref == 'refs/heads/production' && 'production' || 'development' }}
    env:
      ACCOUNT_ID: ${{ github.ref == 'refs/heads/production' && '222222222222' || '111111111111' }}
```

Logic:
- Push lên branch `development` → `environment: development` → `ACCOUNT_ID=111...`.
- Push lên branch `production` → `environment: production` → `ACCOUNT_ID=222...`.

GitHub Environment `production` có **deployment branch restriction = `production` only** + manual approval.

→ Attacker không push được trực tiếp lên `production` (bị branch protection); cũng không bypass được approval gate trong Environment.

### Layer 3: Role ARN trong workflow step

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ env.ACCOUNT_ID }}:role/gha-infra-apply
    aws-region: ap-southeast-1
```

`role-to-assume` chứa **đầy đủ 3 thông tin**:
1. **Account ID** (`111111111111` hoặc `222222222222`) — quyết định AWS account.
2. **Role name** (`gha-infra-apply`) — quyết định quyền hạn.
3. **Region** (do `aws-region`) — quyết định khu vực.

`aws-actions/configure-aws-credentials@v4` action sẽ:
1. Yêu cầu GitHub cấp JWT token (cần `id-token: write`).
2. Gọi `sts:AssumeRoleWithWebIdentity` với JWT + RoleArn.
3. AWS check trust policy → trả temp credentials.
4. Set env vars `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` cho các step sau.

### Layer 4: Trust policy của role (whitelist branches)

Trust policy của `gha-infra-apply` ở **account development**:

```yaml
Condition:
  StringEquals:
    'token.actions.githubusercontent.com:aud': sts.amazonaws.com
    'token.actions.githubusercontent.com:sub':
      "repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/development"
```

→ Role ở account development **CHỈ** assume được khi `sub = repo:...:ref:refs/heads/development`.

Trust policy của `gha-infra-apply` ở **account production**:

```yaml
Condition:
  StringEquals:
    'token.actions.githubusercontent.com:sub':
      "repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/production"
```

→ Role ở account production **CHỈ** assume được khi `sub = repo:...:ref:refs/heads/production`.

### Layer 5: Backend (state) trong Terraform code

```hcl
# envs/development/backend.tf
backend "s3" {
  bucket = "myorg-tfstate-111111111111"   # Bucket ở account development
  key    = "3-tiers-app/development/terraform.tfstate"
}
```

```hcl
# envs/production/backend.tf
backend "s3" {
  bucket = "myorg-tfstate-222222222222"   # Bucket ở account production
  key    = "3-tiers-app/production/terraform.tfstate"
}
```

→ Terraform đọc/ghi state vào bucket trong account tương ứng.

---

## 11. Tóm tắt: chỗ nào trỏ tới account nào?

| File | Dòng | Trỏ tới account |
|------|------|-----------------|
| `bootstrap/01-trust-anchor.yaml` | Toàn file | Account hiện tại (Console đang login) — bạn upload thủ công vào account nào thì nó tạo OIDC + role ở đó |
| `.github/workflows/bootstrap.yaml` | `ACCOUNT_ID: ${{ inputs.account == 'production' && '222...' || '111...' }}` | DEVELOPMENT nếu input=development, PRODUCTION nếu input=production |
| `.github/workflows/bootstrap.yaml` | `role-to-assume: arn:aws:iam::${{ env.ACCOUNT_ID }}:role/gha-bootstrap` | Account chọn ở input |
| `.github/workflows/terraform-apply.yaml` | `environment: ${{ github.ref == 'refs/heads/production' && 'production' || 'development' }}` | DEVELOPMENT nếu push vào branch development, PRODUCTION nếu push vào branch production |
| `.github/workflows/terraform-apply.yaml` | `ACCOUNT_ID: ${{ github.ref == 'refs/heads/production' && '222...' || '111...' }}` | DEVELOPMENT hoặc PRODUCTION theo branch |
| `.github/workflows/terraform-apply.yaml` | `role-to-assume: arn:aws:iam::${{ env.ACCOUNT_ID }}:role/gha-infra-apply` | Account theo branch |
| `envs/development/backend.tf` | `bucket = "myorg-tfstate-111111111111"` | DEVELOPMENT |
| `envs/production/backend.tf` | `bucket = "myorg-tfstate-222222222222"` | PRODUCTION |
| `bootstrap/03-github-oidc-roles.yaml` (parameter `AllowedBranch`) | `AllowedBranch: development` cho development, `AllowedBranch: production` cho production | Quyết định branch nào assume được apply role |

---

## 12. Defense-in-depth: 4 tầng bảo vệ

Một workflow muốn assume `gha-infra-apply` ở account production phải vượt **4 tầng**:

```
+-----------------------------------------------------------------+
| Tầng 1: BRANCH PROTECTION (GitHub)                              |
|   Branch `production` chỉ accept PR từ branch `development`,    |
|   yêu cầu reviewer, fast-forward only, no admin bypass.         |
|   -> Attacker không push trực tiếp được lên production.         |
+-----------------------------------------------------------------+
                              v
+-----------------------------------------------------------------+
| Tầng 2: GITHUB ENVIRONMENT (GitHub)                             |
|   Environment `production` có deployment branch restriction =   |
|   `production` only + manual approval + wait timer.             |
|   -> Workflow gắn `environment: production` chỉ chạy được khi   |
|      trigger từ branch `production` VÀ có approval.             |
+-----------------------------------------------------------------+
                              v
+-----------------------------------------------------------------+
| Tầng 3: WORKFLOW LOGIC (GitHub)                                 |
|   role-to-assume tính từ github.ref -> workflow chạy từ branch  |
|   khác sẽ assume role khác account, không vào production được.  |
+-----------------------------------------------------------------+
                              v
+-----------------------------------------------------------------+
| Tầng 4: IAM TRUST POLICY (AWS)                                  |
|   Role gha-infra-apply ở account production chỉ assume được khi |
|   sub claim = repo:...:ref:refs/heads/production.               |
|   -> Ngay cả khi workflow giả mạo role-to-assume, AWS từ chối   |
|      vì JWT token chứa sub khác.                                |
+-----------------------------------------------------------------+
```

Để compromise production, attacker phải vượt **CẢ 4 tầng**. Phá 1 tầng không đủ.

---

## 13. Ví dụ end-to-end: Push code lên `production`

### Bước 1: Developer mở PR
```
PR: development -> production
Reviewer 1 approve, reviewer 2 approve -> merge fast-forward
```

### Bước 2: GitHub trigger workflow `terraform-apply.yaml`
```yaml
on:
  push:
    branches: [development, production]
```
Push lên `production` match → workflow chạy.

### Bước 3: Workflow evaluate environment
```yaml
environment: ${{ github.ref == 'refs/heads/production' && 'production' || 'development' }}
```
`github.ref = refs/heads/production` → `environment: production`.

### Bước 4: GitHub Environment kiểm tra
```
- Deployment branch restriction = production OK
- Required reviewers = 1 -> workflow PAUSE, hiển thị "Waiting for review"
```

### Bước 5: 1 reviewer approve trong UI
```
- Wait timer 5 phút
- Sau 5 phút -> workflow tiếp tục
```

### Bước 6: Workflow request OIDC token
```
GitHub cấp JWT:
  iss: "https://token.actions.githubusercontent.com"
  sub: "repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/production"
  aud: "sts.amazonaws.com"
  exp: now + ~10 phút
```

### Bước 7: Workflow gọi AssumeRoleWithWebIdentity
```yaml
ACCOUNT_ID: 222222222222           # vì github.ref == production
role-to-assume: arn:aws:iam::222222222222:role/gha-infra-apply
```

### Bước 8: AWS check trust policy của role ở account production
```
Condition matched:
  - aud == "sts.amazonaws.com" OK
  - sub == "repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/production" OK
-> AWS trả temp credentials cho account production (1 giờ).
```

### Bước 9: Workflow chạy `terraform apply`
```
Terraform đọc backend "s3" trong envs/production/backend.tf:
  bucket = "myorg-tfstate-222222222222"

Dùng temp credentials -> ghi state lên bucket production.
Provision resources trong account production.
```

### Bước 10: Workflow kết thúc, credentials expire
```
Sau 1 giờ (hoặc khi job done), temp credentials hết hạn.
Không có gì còn lại trên runner.
```

---

## 14. Các trường hợp attack & lý do AWS từ chối

### Attack 1: Workflow chạy trên branch `development` cố assume role production

```yaml
# Workflow độc hại trên branch development
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::222222222222:role/gha-infra-apply
```

**JWT token có:** `sub: repo:...:ref:refs/heads/development`
**Trust policy của role production yêu cầu:** `sub: repo:...:ref:refs/heads/production`

→ AWS từ chối với `IDPRejectedClaim` / `AccessDenied`: "User is not authorized to perform sts:AssumeRoleWithWebIdentity".

### Attack 2: Workflow trong repo khác cố assume role

```yaml
# Workflow trong repo myorg/random-repo
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::222222222222:role/gha-infra-apply
```

**JWT token có:** `sub: repo:myorg/random-repo:ref:refs/heads/main`
**Trust policy yêu cầu:** `sub: repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/production`

→ AWS từ chối.

### Attack 3: Force push lên branch `production`

→ Branch protection chặn force push (Tầng 1).

### Attack 4: Tạo branch tên giống `production-evil`

**JWT có:** `sub: repo:...:ref:refs/heads/production-evil`
**Trust policy yêu cầu (StringEquals):** `sub: repo:...:ref:refs/heads/production`

→ Không match exact → AWS từ chối.

> **CRITICAL:** Phải dùng `StringEquals` (chính xác), KHÔNG dùng `StringLike` với wildcard cho `:ref:refs/heads/*`. Nếu dùng `StringLike` với pattern lỏng → attacker tạo branch `production-evil` có thể match.

### Attack 5: Token replay sau khi expire

Token hết hạn (`exp < now`) → AWS trả `ExpiredToken`. Vì AWS verify `exp` mỗi request, không có cách dùng lại token cũ.

### Attack 6: Steal token từ runner đang chạy

Token có TTL ~5–10 phút, chỉ assume được role match trust policy. Kẻ trộm chỉ có cửa sổ rất ngắn để dùng, và phải dùng đúng condition đã encode trong `sub`. Sau khi assume → temp credentials cũng chỉ sống ≤ `MaxSessionDuration`. So với access key cũ thì blast radius nhỏ hơn nhiều bậc.

---

## 15. So sánh: trước OIDC vs sau OIDC

| Tiêu chí | Access Key (cũ) | OIDC (mới) |
|----------|----------------|------------|
| Credentials lifetime | Vĩnh viễn | 900s–43200s (mặc định 3600s) |
| Lưu ở đâu | GitHub Secrets | Không lưu (in-memory runner) |
| Key rotation | Manual | Tự động mỗi run |
| Audit per workflow | Khó | CloudTrail có session metadata + sub claim |
| Compromise blast radius | Toàn bộ thời gian leak chưa phát hiện | ≤ 1 giờ (mặc định) |
| Setup phức tạp | Tạo IAM user + key + secret | Tạo OIDC provider + role |
| Cross-repo access | Cùng key dùng được mọi nơi | Bị chặn bởi `sub` condition |
| AWS recommended | Discouraged | Best practice |

---

## 16. Q&A

> **"Đâu là chỗ giúp tôi trỏ tới đúng môi trường hoặc trỏ tới đúng account?"**

**5 chỗ** (xem mục 10):
1. **AWS account context** — Phase 5/6 upload trust anchor vào account nào → OIDC + bootstrap role tạo ở đó.
2. **`bootstrap.yaml`** — input `account=development|production` → resolve ACCOUNT_ID phù hợp.
3. **`terraform-apply.yaml`** — `github.ref` (branch) → resolve ACCOUNT_ID phù hợp.
4. **Trust policy của role** (trong `03-github-oidc-roles.yaml` parameter `AllowedBranch`) — chỉ branch tương ứng assume được.
5. **`backend.tf`** — bucket name có account ID → state lưu vào account tương ứng.

> **"`bootstrap/01-trust-anchor.yaml` chính xác sẽ dùng để tạo những gì, có phải để tạo OIDC để vào được môi trường tương ứng hay không?"**

**Đúng.** Chính xác:
- Tạo `AWS::IAM::OIDCProvider` — đăng ký GitHub là trusted IdP trong account.
- Tạo `gha-bootstrap` role — role đầu tiên CI có thể assume.

**Phải upload vào CẢ 2 accounts** (development + production), mỗi account 1 lần. Mỗi lần upload → tạo OIDC + role TRONG ACCOUNT ĐÓ.

Sau khi có trust anchor ở cả 2 accounts → workflow `bootstrap.yaml` assume được `gha-bootstrap` ở account chỉ định → deploy stacks 02 + 03 → tạo các roles long-lived khác.

> **"Nói rõ hơn về CI/CD bằng GitHub Actions với OIDC (không dùng access key dài hạn)"**

Xem mục 2-8 cho chi tiết kỹ thuật và quy trình 5 bước. Một câu tóm tắt:

GitHub Actions tự cấp JWT token cho mỗi workflow run, JWT chứa metadata workflow (repo/branch/env), AWS verify JWT signature qua public key tải từ JWKS endpoint của GitHub (TLS verified bằng built-in CA library), check trust policy match `sub`/`aud`, trả temp credentials 1 giờ → workflow dùng temp creds gọi AWS API → expire tự động. Không có access key dài hạn ở bất cứ đâu.

---

## 17. Flow chi tiết end-to-end: workflow run -> JWT -> assume role -> API call

Mục này gộp toàn bộ các bước kỹ thuật xảy ra từ thời điểm GitHub trigger workflow cho tới khi job kết thúc, và đào sâu hai chỗ mà mục 7 và 13 chỉ nói tóm tắt:

- Cơ chế GitHub cấp JWT cho job (Phase C-D).
- Cơ chế AWS quyết định "role này có được làm action X trên resource Y không" cho từng API call (Phase H — IAM authorization evaluation).

Phase A đến G trả lời "ai được trở thành role". Phase H trả lời "role đã trở thành rồi thì được làm gì".

### Phase A — Pre-flight (đã setup sẵn trong AWS, không phụ thuộc workflow)

Trước khi workflow chạy, các artefact sau phải tồn tại trong account đích:

1. `AWS::IAM::OIDCProvider` với `Url = https://token.actions.githubusercontent.com` và `ClientIdList` chứa `sts.amazonaws.com`.
2. `AWS::IAM::Role` (ví dụ `gha-infra-apply`) gồm hai policy độc lập:
   - **Trust policy** (assume role policy): `Federated = <oidc-provider-arn>`, `Action = sts:AssumeRoleWithWebIdentity`, condition khớp `aud` + `sub` (trả lời: ai biến thành role được).
   - **Permissions policy** (identity-based policy): managed (`AdministratorAccess`, `ReadOnlyAccess`, ...) hoặc inline (liệt kê action / resource cụ thể) (trả lời: role được làm gì).
3. (Optional) `MaxSessionDuration` (mặc định 3600s, tối đa 43200s).

Trong dự án này, hai bước trên thực hiện qua `bootstrap/01-trust-anchor.yaml` (Console upload thủ công) và `bootstrap/03-github-oidc-roles.yaml` (CI deploy).

### Phase B — GitHub trigger workflow run

GitHub nhận event (`push`, `pull_request`, `workflow_dispatch`, `schedule`, ...). Engine match event với `on:` block trong workflow file → tạo workflow run → assign job lên runner.

Khi runner pickup job:

1. Engine đọc `permissions:` của workflow/job. **Nếu thiếu `id-token: write`**, hai biến môi trường `ACTIONS_ID_TOKEN_REQUEST_URL` và `ACTIONS_ID_TOKEN_REQUEST_TOKEN` không được inject. Mọi attempt request OIDC sau đó fail với `Error: Could not get OIDC token`.
2. Engine resolve các expression (`github.ref`, `github.sha`, `github.actor`, `github.run_id`, ...) — chính các giá trị này sẽ được encode vào JWT ở Phase C.
3. Nếu job khai báo `environment: <name>`, engine pause job để áp environment protection rules: required reviewers, wait timer, deployment branch restriction. Job chỉ tiếp tục sau khi mọi rule pass.

Đến đây runner mới chỉ có biến môi trường internal — chưa có credential AWS nào.

### Phase C — Job request JWT từ GitHub OIDC issuer

Step `aws-actions/configure-aws-credentials` (hoặc bất kỳ code nào dùng package `@actions/core` `getIDToken`) gọi:

```
POST $ACTIONS_ID_TOKEN_REQUEST_URL?audience=sts.amazonaws.com
Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN
```

Endpoint là internal của GitHub Actions, chỉ runner có biến môi trường này mới gọi được. Response:

```json
{ "value": "<JWT>", "count": 1 }
```

JWT có 3 phần (xem mục 3 và 5):

- **Header**: `{ "alg": "RS256", "kid": "<rotating>", "typ": "JWT" }`.
- **Payload**: chứa `iss`, `aud`, `sub`, `exp`, `iat`, `nbf` cùng với metadata workflow (`repository`, `repository_owner`, `ref`, `environment`, `job_workflow_ref`, `actor`, `run_id`, ...).
- **Signature**: GitHub ký bằng private key tương ứng public key publish trong JWKS (`https://token.actions.githubusercontent.com/.well-known/jwks`).

Token TTL khoảng 5-10 phút, vừa đủ để gọi STS một lần.

### Phase D — Action gọi `sts:AssumeRoleWithWebIdentity`

Action build HTTP request tới STS endpoint của region đã cấu hình (mặc định regional `https://sts.<region>.amazonaws.com`):

```
POST /
Action=AssumeRoleWithWebIdentity
&RoleArn=arn:aws:iam::222222222222:role/gha-infra-apply
&RoleSessionName=gha-Terraform-Apply-1234567890
&WebIdentityToken=<JWT từ Phase C>
&DurationSeconds=3600
&Version=2011-06-15
```

Request **không cần SigV4** — `AssumeRoleWithWebIdentity` là một trong vài STS API anonymous (cùng `AssumeRoleWithSAML`, `GetFederationToken` không trong nhóm này); identity nằm hoàn toàn trong `WebIdentityToken`.

### Phase E — AWS verify JWT (xác thực)

STS thực hiện theo thứ tự (cũng xem mục 6):

1. Decode JWT base64url, parse header và payload.
2. Tra `iss` claim trong list IAM OIDC provider của account → tìm provider có `Url` match. Không thấy → `InvalidIdentityToken`.
3. Tải JWKS từ `<iss>/.well-known/jwks` (cache nội bộ AWS). TLS cert verify bằng built-in CA library.
4. Lookup public key theo `kid` trong header → verify signature `header.payload`. Sai → `InvalidIdentityToken`.
5. Check `exp > now > nbf` (cho phép skew nhỏ). Hết hạn → `ExpiredToken`.
6. Check `aud` claim ∈ `ClientIDList` của provider. Không khớp → `InvalidIdentityToken`.

Phase E trả lời: "Token có phải do GitHub thật ký không, có còn hợp lệ không, có đúng audience không?"

### Phase F — AWS đánh giá trust policy của role (uỷ quyền nhập role)

Phase E pass mới chuyển sang Phase F. AWS load `AssumeRolePolicyDocument` của `RoleArn` được request và đánh giá:

1. Có statement nào `Effect: Allow`, `Principal.Federated` chứa ARN của OIDC provider khớp `iss`, `Action` chứa `sts:AssumeRoleWithWebIdentity` không?
2. Tất cả `Condition` trong statement đó có pass với JWT claim không?

Mapping IAM condition key ↔ JWT claim cho GitHub OIDC:

| IAM condition key | JWT claim |
|-------------------|-----------|
| `token.actions.githubusercontent.com:aud` | `aud` |
| `token.actions.githubusercontent.com:sub` | `sub` |
| `token.actions.githubusercontent.com:iss` | `iss` |
| `token.actions.githubusercontent.com:repository` | `repository` |
| `token.actions.githubusercontent.com:repository_owner` | `repository_owner` |
| `token.actions.githubusercontent.com:job_workflow_ref` | `job_workflow_ref` |
| `token.actions.githubusercontent.com:environment` | `environment` |
| `token.actions.githubusercontent.com:ref` | `ref` |
| `token.actions.githubusercontent.com:actor` | `actor` |

Không có statement Allow nào pass → `IDPRejectedClaim` (trong CloudTrail) hoặc `AccessDenied` (về phía client).

**Lưu ý:** trust policy KHÔNG quan tâm "role được làm gì" — nó chỉ trả lời "ai được biến thành role này". WHAT role được làm là Phase H.

### Phase G — STS trả về temporary credentials

Pass cả Phase E và F → STS trả response:

```json
{
  "Credentials": {
    "AccessKeyId": "ASIA...",
    "SecretAccessKey": "...",
    "SessionToken": "...",
    "Expiration": "2026-05-09T15:42:00Z"
  },
  "AssumedRoleUser": {
    "AssumedRoleId": "AROAEXAMPLEID:gha-Terraform-Apply-1234567890",
    "Arn": "arn:aws:sts::222222222222:assumed-role/gha-infra-apply/gha-Terraform-Apply-1234567890"
  },
  "SubjectFromWebIdentityToken": "repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/production",
  "Audience": "sts.amazonaws.com",
  "Provider": "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com"
}
```

Action set 4 biến môi trường để mọi step sau dùng:

```
AWS_ACCESS_KEY_ID=ASIA...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=...
AWS_DEFAULT_REGION=ap-southeast-1
```

`AccessKeyId` bắt đầu bằng `ASIA` — dấu hiệu temporary credentials (vs `AKIA` của long-lived IAM user). CloudTrail log với `userIdentity.type = AssumedRole`, `principalId = AROAEXAMPLEID:<RoleSessionName>`, `arn = arn:aws:sts::<acc>:assumed-role/<role>/<session>`.

### Phase H — Mỗi AWS API call sau đó: authorization evaluation

Đây là chỗ trả lời câu hỏi "role có được làm action X trên resource Y không". Mỗi API call (`aws ec2 RunInstances`, `aws ecs DeleteService`, `aws eks DeleteCluster`, `terraform apply` → backend gọi nhiều API, ...) đều đi qua đầy đủ pipeline sau:

#### H.1. Authentication — SigV4

AWS SDK trên runner ký request với `AccessKeyId` + `SecretAccessKey`, gắn header `X-Amz-Security-Token = <SessionToken>`. Endpoint AWS verify signature. Sai → `InvalidSignatureException` (không phải `AccessDenied`).

#### H.2. Authorization — IAM policy evaluation logic

AWS xây dựng "request context" gồm:

- `principal`: `arn:aws:sts::222...:assumed-role/gha-infra-apply/<session>`.
- `action`: ví dụ `ec2:RunInstances`, `ec2:TerminateInstances`, `ecs:DeleteService`, `eks:DeleteCluster`.
- `resource`: ARN cụ thể (vd `arn:aws:ec2:ap-southeast-1:222...:instance/i-0abc...`).
- Mọi context key (`aws:RequestTag/*`, `aws:SourceIp`, `ec2:InstanceType`, `aws:RequestedRegion`, ...).

Engine duyệt tất cả policy áp dụng cho principal theo thứ tự sau:

1. **Service Control Policies (SCP)** — chỉ có nếu account thuộc AWS Organization. SCP áp dụng ở organization root / OU. SCP là **deny-list**: action không được SCP allow → coi như Deny ngầm. SCP fail → reject ngay, không xét tiếp.
2. **Resource-based policy** — gắn trực tiếp vào resource (S3 bucket policy, KMS key policy, Lambda permission, SQS queue policy, ...). Có thể grant cross-account trực tiếp. EC2 / ECS / EKS không có resource policy ở instance/service/cluster level (riêng EKS có cluster access entries riêng).
3. **Identity-based policy của role** — managed policy + inline policy attach vào role. **Đây là chỗ permissions policy bạn viết ở mục 9.2 / file `03-github-oidc-roles.yaml`.**
4. **Permission boundary** — nếu role có boundary, action phải vừa được identity policy Allow vừa được boundary Allow (intersection).
5. **Session policy** — nếu khi assume role có truyền inline `Policy` parameter (vd `aws-actions/configure-aws-credentials` input `inline-session-policy`), session policy lọc tiếp (intersection thêm). Mặc định không có.
6. **Explicit Deny check** — duyệt lại tất cả policy ở trên xem có statement `Effect: Deny` match không. **Một Explicit Deny ở bất kỳ tầng nào sẽ thắng tất cả Allow.**

Quyết định cuối cùng (đơn giản hoá):

```
if explicit_deny_anywhere:
    return Deny
elif scp_present and not scp_allows:
    return Deny
elif identity_allows and (boundary is None or boundary_allows) \
     and (session_policy is None or session_allows):
    return Allow
elif resource_policy_allows_principal:
    return Allow
else:
    return Deny  # implicit deny (no Allow)
```

Sai một bước → API trả `AccessDenied` với message rất cụ thể, ví dụ:

```
User: arn:aws:sts::222...:assumed-role/gha-infra-apply/gha-Terraform-Apply-...
is not authorized to perform: ec2:TerminateInstances
on resource: arn:aws:ec2:ap-southeast-1:222...:instance/i-0abc...
because no identity-based policy allows the ec2:TerminateInstances action
```

hoặc

```
... with an explicit deny in identity-based policy
... with an explicit deny in service control policy
... with permissions boundary
```

Cờ thông báo lỗi của AWS định danh đúng tầng nào đã fail — luôn paste nguyên message khi debug.

#### H.3. Hai ví dụ cụ thể

Giả sử `gha-infra-apply` có inline policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEc2Create",
      "Effect": "Allow",
      "Action": ["ec2:RunInstances", "ec2:Describe*", "ec2:CreateTags"],
      "Resource": "*"
    },
    {
      "Sid": "DenyDestructive",
      "Effect": "Deny",
      "Action": [
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ecs:DeleteService",
        "ecs:DeleteCluster",
        "eks:DeleteCluster",
        "eks:DeleteNodegroup"
      ],
      "Resource": "*"
    }
  ]
}
```

**Call 1** — `ec2:RunInstances` để tạo instance mới:

- H.1: SigV4 OK.
- H.2.1: SCP (giả sử không có) → bỏ qua.
- H.2.2: resource policy (EC2 không có) → bỏ qua.
- H.2.3: identity policy có `AllowEc2Create` match `ec2:RunInstances` → tentative Allow.
- H.2.4: không có boundary.
- H.2.5: không có session policy.
- H.2.6: explicit deny check: `DenyDestructive` không bao gồm `ec2:RunInstances` → không match.
- → **Allow**, instance được tạo.

**Call 2** — `ec2:TerminateInstances` để xoá instance:

- H.2.3: identity policy `AllowEc2Create` không liệt kê `ec2:Terminate*` → no Allow ở tầng này.
- H.2.6: `DenyDestructive` match `ec2:TerminateInstances` → **Explicit Deny thắng** dù có Allow ở đâu.
- → `AccessDenied: ... with an explicit deny in identity-based policy`. Instance không bị xoá.

**Call 3** — `ecs:DeleteService`: tương tự Call 2, `DenyDestructive` chặn.
**Call 4** — `eks:DeleteCluster`: tương tự, `DenyDestructive` chặn.

Đây là pattern sản xuất khuyến nghị: Allow rộng cho tác vụ build + Explicit Deny cho mọi action huỷ diệt (ví dụ `*:Delete*`, `*:Terminate*`, `*:Destroy*`, `iam:Delete*`, `kms:ScheduleKeyDeletion`, `s3:DeleteBucket`, `rds:DeleteDBInstance`, `dynamodb:DeleteTable`, ...). Cách viết policy hoàn toàn không khác giữa "OIDC role" và "IAM user" — IAM evaluation logic chung cho mọi principal.

### Phase I — Job kết thúc

1. Workflow step cuối chạy xong → runner POST job result về GitHub.
2. Process AWS SDK kết thúc → biến môi trường `AWS_*` biến mất cùng container/runner ephemeral của GitHub-hosted.
3. Temporary credentials vẫn còn `Expiration` AWS-side, nhưng không ai biết `SecretAccessKey` nữa (không lưu xuống đâu cả).
4. Sau `Expiration` (hoặc khi role bị `aws iam put-role-policy` revoke session) credentials chính thức vô hiệu cả ở backend.
5. CloudTrail giữ event `AssumeRoleWithWebIdentity` + mọi API call sau đó với `userIdentity.sessionContext.sessionIssuer.userName = gha-infra-apply` và `principalId = AROAEXAMPLEID:<RoleSessionName>` — đủ để truy vết workflow run nào đã làm gì.

### Phase J — Diagram tổng hợp

```
+---------------------+   trigger   +-------------------+
|  GitHub event       | ----------> | Workflow run      |
|  (push to prod)     |             | + permissions:    |
+---------------------+             |   id-token: write |
                                    +---------+---------+
                                              |
              Phase B: env vars set           |
              ACTIONS_ID_TOKEN_REQUEST_URL    |
              ACTIONS_ID_TOKEN_REQUEST_TOKEN  |
                                              v
+----------------------+              +---------------------+
| GitHub OIDC issuer   |<--POST aud---| configure-aws-      |
| token.actions...     |---JWT(RS256)>| credentials@v4      |
+----------------------+              +----------+----------+
                                                 |
                              STS AssumeRoleWith |WebIdentity
                                                 v
+--------------------------------------------------------------+
|                       AWS STS                                 |
|  Phase E: verify JWT (iss, signature, exp/nbf, aud)           |
|  Phase F: evaluate trust policy                               |
|     Principal.Federated == oidc-provider-arn?                 |
|     Action == sts:AssumeRoleWithWebIdentity?                  |
|     Condition (sub, aud, ...) match JWT claims?               |
+--------------------------------------------------------------+
                                                 |
                          temp credentials (~1h, AccessKey ASIA...)
                                                 v
+----------------------+                 +---------------------+
| Workflow steps       |---SigV4 req---->| AWS service         |
| (terraform apply,    |   ec2:Run...    | (EC2 / ECS / EKS /  |
|  aws s3 cp, ...)     |<---result-------+  S3 / IAM / ...)    |
+----------------------+                 +----------+----------+
                                                    |
                                       Phase H: IAM authorization
                                          1. SCP (org)
                                          2. Resource policy
                                          3. Identity policy of role
                                          4. Permission boundary
                                          5. Session policy
                                          6. Explicit Deny check
                                                    v
                                              Allow / Deny
```

### Phase K — "Lỗi nào fail ở đâu" cheat sheet

| Bước hỏng | Lỗi user thấy | Sửa ở đâu |
|-----------|---------------|-----------|
| Workflow thiếu `id-token: write` | `Error: Could not get OIDC token` | Workflow YAML — thêm `permissions:` block |
| `aud` request không có trong `ClientIDList` provider | `InvalidIdentityToken` | Thêm audience vào OIDC provider hoặc set `audience:` input |
| Provider URL sai (vd viết hoa) | `InvalidIdentityToken: ... not in account` | Tạo lại OIDC provider, URL phải lowercase tuyệt đối |
| JWT hết hạn (job pause quá lâu trong environment approval) | `ExpiredToken` | Reduce wait timer, hoặc request lại JWT trước khi gọi STS |
| `sub` không match trust policy condition | `IDPRejectedClaim` / `AccessDenied: ... not authorized to perform sts:AssumeRoleWithWebIdentity` | Sửa branch / environment / customize sub claim qua REST API |
| Identity policy của role không có Allow cho action | `AccessDenied: ... not authorized to perform <action> ... because no identity-based policy allows ...` | Thêm Allow vào permissions policy của role (managed hoặc inline) |
| Có Explicit Deny match | `AccessDenied: ... with an explicit deny in identity-based policy` | Bỏ Deny statement hoặc thu hẹp Action/Resource |
| SCP block | `AccessDenied: ... with an explicit deny in service control policy` | Sửa SCP ở Org root account (không sửa được từ workflow account) |
| Permission boundary không Allow | `AccessDenied: ... with permissions boundary` | Sửa boundary policy (cần quyền IAM admin trong account) |
| Resource policy chặn (vd S3 bucket policy có Deny) | `AccessDenied: ... with an explicit deny in resource-based policy` | Sửa resource policy của resource đó |

Khi debug, paste nguyên error message — AWS đã chỉ rõ tầng nào fail (`identity-based policy`, `service control policy`, `permissions boundary`, `resource-based policy`).

---

## 18. Tham khảo

- [GitHub Docs — About security hardening with OpenID Connect](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [GitHub Docs — Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [GitHub Docs — OpenID Connect reference (full claim list, sub formats, customization)](https://docs.github.com/en/actions/reference/openid-connect-reference)
- [AWS IAM — Create an OpenID Connect (OIDC) identity provider](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [AWS STS — AssumeRoleWithWebIdentity API reference](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [AWS CloudFormation — AWS::IAM::OIDCProvider](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-iam-oidcprovider.html)
- [AWS Security Blog — Use IAM roles to connect GitHub Actions to actions in AWS](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)
- [aws-actions/configure-aws-credentials — Official action README](https://github.com/aws-actions/configure-aws-credentials)
- [JWT.io — Decode JWT để xem nội dung token](https://jwt.io)
