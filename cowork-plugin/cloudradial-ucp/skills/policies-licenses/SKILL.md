---
name: policies-licenses
description: "Review and manage CloudRadial policies (endpoint, server, domain, application, user and license compliance checks), their exceptions, software and Microsoft licenses with their assigned users, and Microsoft 365 groups and admin roles. Use when the user says \"policy review\", \"policy compliance\", \"which devices fail\", \"policy exceptions\", \"ignore this exception\", \"create a policy\", \"encryption policy\", \"license list\", \"who has a license\", \"unused licenses\", \"assign a license\", \"Microsoft 365 groups\", \"global admins\", \"who are the M365 admins\", or wants a compliance or licensing picture for a client.\n"
metadata:
  version: "1.0.0"
---

# Policies & Licenses

## Before any tool call

Call `setup_status` first. If it returns `configured: false`, defer to the `setup` skill.

## Policy review (read-only)

`policy_review` with `action: "review"` and `company_id`: the company's policies by category, each with
`totalItems`, `complianceCount`, `allowance`, `isCompliant` and `riskScore`. Higher risk is worse (the
opposite of assessment scores). Present the failing policies first, with how many items fail.

- **Which items fail:** `policy_review` `action: "exceptions"` with `policy_id`: each exception's
  `objectId`, `description`, `isIgnored` and `ignoreUntil`.
- **Accept an exception** (for example a server that's meant to be unencrypted): `action: "ignore"`
  with `exception_id` and `confirmed: true` after the user agrees. `unignore` counts it again. Ignoring
  changes the compliance numbers in client reports, so say so.

## Policies (writes need confirmed)

- **List:** `list_resources` with `resource_type: "policy"` and `filter: "companyId eq 42"`. Fields:
  `companyPolicyId`, `companyId`, `name`, `description`, `recommendation`, `type`, `policy`,
  `parameters`, `scoringMethod`, `plannerCategoryId`.
- `type` (what it tests): 10 Endpoint, 20 Server, 30 Domain, 40 Application, 50 User, 60 License,
  100 Monitor. `policy` (the test): for example 10 Age, 20 Encryption, 30 Antivirus, 40 OSUpdates,
  50 CurrentOS, 60 FreeSpace. `parameters` holds the test's setting (for example a number of days).
- **Create:** `create_resource` with `data: { companyId, name, type, policy, parameters, description,
  recommendation }` and `confirmed: true`. Copy `type`, `policy`, `parameters` and the alert/PSA fields
  from an existing policy that tests the same thing rather than guessing codes.
- **Edit:** PATCH with `confirmed: true` (only the fields that change). PUT replaces the whole policy
  and takes no `company_id`.
- **Delete:** `delete_resource` with `confirmed: true`, after showing the policy and what reports lose
  it.
- New policies start with the partner's alert defaults, which can include sending to the PSA. Mention
  it when creating one.

## Licenses

- **List:** `list_resources` with `resource_type: "license"` and `filter: "companyId eq 42"`. Fields:
  `licenseId`, `companyId`, `skuId`, `name`, `friendlyName`, `vendor`, `source`, `cost`,
  `billingCycle` (10 monthly, 20 quarterly, 30 annual, 100 other), `renewalDate`, `consumedUnits`,
  `enabledUnits`, `warningUnits`.
- **Who holds a license:** `access_control` `action: "license_users"` with `license_id`, or
  `list_resources` on `user_license` (`userLicenseId`, `userId`, `licenseId`, `companyId`, `skuId`,
  `source`).
- **Unused seats:** `enabledUnits - consumedUnits`, times `cost`, is the monthly (or per-cycle) waste.
  Rank by that for a reclamation report.
- **Create / edit / delete a license** (a manually tracked one, for example a line-of-business app):
  the generic tools with `confirmed: true`. `data: { companyId, name, vendor, skuId, cost,
  billingCycle, renewalDate, enabledUnits }`. Licenses synced from Microsoft 365 (`source`) are
  refreshed by the sync; don't edit those by hand.
- **Set who holds a manual license:** `access_control` `action: "set_license_users"` with the
  **complete** list of `user_ids`. The preview shows who is added and removed.

## Microsoft 365 directory (read-only)

`m365_directory` with `company_id`: `action: "groups"` lists the company's Microsoft 365 groups;
`action: "roles"` lists Microsoft admin roles and who holds them. Pair it with `m365_secure_score` for
a security picture: too many Global Administrators is a common finding. The data is as of
CloudRadial's last daily sync.

## Report honestly

Say which numbers came from the policy review and which you calculated. Never mark a policy as
compliant or an exception as ignored without the user's yes.
