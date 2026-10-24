# AWS IAM Role & Policy

An AWS access policy can be described from several viewpoints at once: what it does, where it applies, how it is stored, who maintains it, and how it controls access.

These viewpoints overlap. A role trust policy is also a resource-based policy; an application permissions policy can be both identity-based and customer managed.

This document covers IAM and related access-control policies, then distinguishes them from other AWS policies. Documentation checked on October 24, 2026.

## 1. Start with the IAM role: trust and permissions

An IAM role is an AWS identity that a permitted person, application, or service can assume. Assuming a role provides temporary credentials for a role session.

When explaining a role, separate its trust policy from its permissions policies:

| Policy | Question it answers | Example |
| --- | --- | --- |
| Trust policy | Who is trusted to assume this role, and under what conditions? | Allow the EC2 service to assume an application role. |
| Permissions policy | What actions can this role perform, on which resources, and under what conditions? | Allow reading objects in an application S3 bucket. |

Permission to assume a role and permission to read application data are separate authorizations. A trust policy authorizes role assumption; it does not itself grant S3 object access.

The distinction above describes the function of policies associated with a role. It is not a complete classification of every AWS policy.

Source: [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html).

## 2. Classify by policy type and enforcement scope

AWS currently lists nine policy types or access-control mechanisms in its overview:

| Type | Applies to | Main purpose |
| --- | --- | --- |
| Identity-based policy | IAM user, group, or role | Define the identity's permissions. |
| Resource-based policy | A resource | Define which principals can access that resource. |
| VPC endpoint policy | A VPC endpoint | Control access through that endpoint. |
| Permissions boundary | IAM user or role | Limit permissions available from identity-based policies. |
| Service control policy (SCP) | Organizations root, OU, or account | Set permission limits for principals in member accounts. |
| Resource control policy (RCP) | Organizations root, OU, or account | Set permission limits for supported resources in member accounts. |
| Session policy | A temporary session | Restrict permissions for that session. |
| Access control list (ACL) | A resource supporting ACLs | Grant resource access using an ACL mechanism. |
| AWS RAM resource share | A collection of shared resources | Share supported resources across accounts or an organization. |

The list contains related categories rather than completely disjoint boxes. For example, AWS separately lists VPC endpoint policies, while also describing an endpoint policy as resource-based.

Sources: [AWS policy types](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html#access_policy-types), [VPC endpoint policies](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html), [permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html), [SCPs and RCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_authorization_policies.html), and [session policies in AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).

### Where the trust policy belongs

A role trust policy is a resource-based policy attached directly to the IAM role. An S3 bucket policy is another resource-based policy.

An IAM role can be viewed in two ways:

- As an identity performing actions: its attached identity-based policies define permissions.
- As a resource that another principal wants to assume: its trust policy defines the trust relationship.

Resource-based policies are stored directly on their resources. They are not standalone AWS managed or customer managed identity policies.

Source: [Resource-based policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html#policies_resource-based).

## 3. Classify by storage, reuse, and maintenance

For identity-based policies, distinguish standalone managed policies from policies embedded in one identity.

| Category | Maintained by | Reusable across identities? | Can you edit its permissions? |
| --- | --- | --- | --- |
| AWS managed policy | AWS | Yes | No, not directly |
| Customer managed policy | You or your organization | Yes | Yes |
| Inline policy | You or your organization | No shared policy object; embedded in one user, group, or role | Yes |

Both AWS managed and customer managed policies are standalone managed policies with their own ARN. An inline policy belongs to one identity and is deleted when that identity is deleted.

These are two connected viewpoints:

- Storage and reuse: managed versus inline.
- Maintenance of managed policies: AWS managed versus customer managed.

AWS can update an AWS managed policy. Updating a customer managed policy changes the shared policy used by its attached identities. Copying a policy's text into separate inline policies creates separate copies, not one shared policy.

For example, `AdministratorAccess` is an AWS managed policy. When attached as a permissions policy to an IAM user or role, it is also identity-based.

Source: [Managed policies and inline policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html).

## 4. Classify by authorization function: grants and limits

Different policies participate in an access decision in different ways.

| Function | Examples | Meaning |
| --- | --- | --- |
| Grant or deny access | Identity-based and resource-based policies | Can contain permission grants and explicit denials. |
| Authorize role assumption | Role trust policy | Controls access to assuming the role. |
| Limit identity-policy grants | Permissions boundary | Sets a maximum for permissions granted through identity-based policies. |
| Limit organizational access | SCP and RCP | Apply centralized limits to principals or supported resources. |
| Limit a temporary session | Session policy | Restricts the session rather than adding permissions. |
| Control an access path | VPC endpoint policy | Adds access control for requests traversing the endpoint. |

A permissions boundary, SCP, RCP, or session policy does not grant permissions by itself. An `Allow` in one of these limiting policies does not replace a required permission grant.

A managed policy used as a permissions boundary is performing a different job from a managed policy attached to grant permissions. Its role depends on how it is associated with the identity.

Sources: [Permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html), [organization authorization policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_authorization_policies.html), and [AssumeRole session policies](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).

An endpoint policy does not replace permissions required by the destination service. Its restrictions matter to traffic using that endpoint.

Source: [VPC endpoint policies](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html).

## 5. Classify statements by effect: Allow and Deny

Each JSON policy statement has an `Effect`:

- `Allow`: permits the specified actions when the statement applies.
- `Deny`: explicitly prohibits the specified actions when the statement applies.

A policy can contain both effects in separate statements. Therefore, "Allow policy" and "Deny policy" are informal descriptions of contents, not mutually exclusive policy types.

An applicable explicit deny overrides an allow. Requests also fail when a required allow is absent; this is an implicit deny rather than an explicit `Deny` statement.

The meaning of an `Allow` also depends on the policy's function: an allow inside a boundary defines what may be granted, rather than granting it.

Sources: [Effect](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_effect.html) and [permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html).

## 6. Classify by permission breadth and access level

Descriptions such as full access, read-only access, and custom access describe the breadth of permissions, not where the policy is attached.

AWS classifies service actions into five access levels:

| Access level | Meaning |
| --- | --- |
| List | Enumerate resources or determine whether they exist. |
| Read | Read resource contents or attributes. |
| Write | Create, modify, or delete resources. |
| Tagging | Modify resource tags through actions dedicated to tagging. |
| Permissions management | Manage access permissions. |

A policy can include several access levels, with full or limited coverage of the actions in each level. For example, `s3:GetObject` is a Read action, while `s3:PutObject` is a Write action.

These levels describe actions. They do not, by themselves, establish which resources are accessible or which conditions must be satisfied.

Source: [Access levels in policy summaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_understand-policy-summary-access-level-summaries.html).

To describe scope precisely, inspect:

- `Action`: which operations are covered.
- `Resource`: which resources are covered, where that element applies.
- `Principal`: who is covered, where that element applies.
- `Condition`: additional requirements, such as matching attributes or request context.

Not every policy type accepts every element in the same way. These are policy document elements, not additional policy categories.

Source: [IAM JSON policy elements](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements.html).

## 7. Classify by authorization design: RBAC and ABAC

| Model | Basis for permissions | Example |
| --- | --- | --- |
| Role-based access control (RBAC) | Job function or organizational responsibility | Different permission policies for developers and auditors. |
| Attribute-based access control (ABAC) | Attributes, commonly principal and resource tags | Allow access when the principal's Project tag matches the resource's Project tag. |

These are design strategies implemented with policies. They do not replace identity-based or resource-based classifications.

The "role" in RBAC means a job function or responsibility; it is not synonymous with the IAM role resource. A policy design can combine job-based permissions with attribute-based conditions.

Source: [ABAC and its comparison with RBAC](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html).

## 8. Classify by access relationship

Access policies can also be described by the relationship between the caller and the target:

- Same-account access: the principal and target are in the same AWS account.
- Cross-account access: the principal and target are in different accounts.
- AWS service access: an AWS service assumes a role to perform work.
- Federated access: an external identity provider participates in access through a role.

These are use cases rather than separate policy storage formats. They can overlap: a federated session can also access resources across accounts.

For cross-account role assumption, the target role must establish the appropriate trust relationship, and the caller must have permission to call `sts:AssumeRole`. A trust policy alone should not be treated as universal proof that a caller can assume a role.

Sources: [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html) and [AssumeRole permissions](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).

## 9. Distinguish access policies from other AWS policies

The word "policy" is broader than IAM authorization. AWS Organizations also offers policies that manage configuration or organizational behavior.

Examples include:

- Tag policies: standardize resource tags.
- Backup policies: centrally manage backup plans.
- AI services opt-out policies: manage AI-service data-collection preferences.
- Declarative policies: centrally declare and maintain supported service configurations.

AWS Organizations distinguishes authorization policies, including SCPs and RCPs, from its declarative policy category. A tag-standardization policy has a different purpose from an IAM policy granting S3 access.

Source: [Managing organization policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies.html).

## 10. Worked example: one role, several classifications

Consider an illustrative role named `ApplicationReadDataRole`:

1. Its trust policy permits the EC2 service to assume it.
2. A customer managed policy named `ApplicationReadData` is attached as a permissions policy and allows reading application objects in S3.
3. An optional permissions boundary limits the permissions its identity-based policies may grant.

The same components can be described from several viewpoints:

| Component | Function | Type or scope | Storage or maintenance |
| --- | --- | --- | --- |
| Role trust policy | Authorize role assumption | Resource-based; attached to the role | Stored directly on the role |
| ApplicationReadData policy | Grant application permissions | Identity-based; Read actions | Customer managed; standalone and reusable |
| Optional boundary | Limit identity-policy grants | Permissions boundary on the role | Uses a managed policy |

The permissions policy describes the allowed S3 operations. The trust policy describes who may use the role. The boundary limits the identity-policy grants. Applicable organizational controls, session policies, resource policies, and explicit denies can also affect a request.

This example illustrates how the classifications combine; it does not describe the current deployed configuration of this repository.

Sources: [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html), [managed and inline policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html), and [permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html).
