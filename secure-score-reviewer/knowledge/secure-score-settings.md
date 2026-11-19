# Secure Score Settings

Owner: Security Lead · Effective: 2026-11-16 · Used by: Microsoft Secure Score Reviewer

> **Example, replace with your own.** The Secure Score Reviewer reads this at every check-in. Settings here override its built-in defaults. Use the exact names and ids from your CloudRadial portal and Microsoft 365 tenant.

## Which client is this for?

| Setting | Value |
|---|---|
| Client | Contoso |
| CloudRadial companyId | 12 |

## Where do Planner cards go?

| Setting | Value |
|---|---|
| Planner product category id | 7 |
| Planner category name | Security |

Without a product category id the reviewer creates no cards: it lists them and asks.

## Which group enforces MFA?

| Setting | Value |
|---|---|
| MFA enforcement group | SG-MFA-Required |

Users who aren't MFA-capable are proposed for this group. Leave it blank to only recommend MFA on the Planner card.

## When is an account inactive?

No sign-in for **90 days**. Never propose disabling these accounts:

| Account | Why |
|---|---|
| svc-scanner@contoso.example | Service account for the office scanner |
| reception@contoso.example | Shared reception login |

## Where does the monthly report go?

Report Archives folder: **Security Reports**. If the folder doesn't exist, the reviewer skips the report and says so.

## Which controls are accepted risk?

| Control | Reason | Decided |
|---|---|---|
| Example: Turn on Microsoft Defender for Cloud Apps | Covered by a third-party CASB | 2026-11-01 |

The reviewer stops proposing these and keeps their cards closed.
