# Policies & Licenses

> Policy compliance and exceptions, software and Microsoft licenses with their users, and Microsoft 365 groups and admin roles.

**Say this:**

```
Which of Contoso's policies are failing, and on how many devices?
```

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing: **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Review policy compliance
`Per-company` · `Read-only` · **Not yet tested**

```
Run Contoso's policy review. List the failing policies first with how many
items fail each one and the risk score, then the passing ones.
```

**What you get:** Contoso's policy picture, worst first.

### Accept a policy exception
`Per-company` · `Writes to the portal` · **Not yet tested**

```
The build server at Contoso is meant to be unencrypted. Find its exception on
the encryption policy and ignore it. Show me the exception first and only
ignore it when I confirm.
```

**What you get:** That exception no longer counts against the policy.

**Good to know:** Ignored exceptions change the compliance numbers in client reports.

### Add a policy
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Add a policy to Contoso that flags computers more than 5 years old. Copy the
settings from an existing age policy, show me the policy, and only create it
when I confirm.
```

**What you get:** A new age policy in Contoso's portal.

### Find unused licenses
`All clients` · `Read-only` · **Not yet tested**

```
Which licenses across my clients have the most unused seats? Show company,
license, seats paid for, seats used and the monthly cost of the unused ones.
```

**What you get:** A reclamation list ranked by wasted spend.

### Check who holds a license
`Per-company` · `Read-only` · **Not yet tested**

```
Who at Contoso holds a Microsoft 365 E3 license?
```

**What you get:** The users assigned that license.

### List Microsoft 365 admins
`Per-company` · `Read-only` · **Not yet tested**

```
Who holds Microsoft 365 admin roles at Contoso, and how many Global
Administrators are there?
```

**What you get:** Admin roles and their holders, from CloudRadial's last Microsoft 365 sync.

## Good to know

- **Policy risk is the opposite of assessment scores.** Higher policy risk is worse.
- **Synced licenses update themselves.** Licenses from Microsoft 365 are refreshed by the sync; only manually tracked ones should be edited.
- **Policy and license changes wait for your yes.**

## Related skills

- [Assessment & Compliance](../assessment-compliance): assessments and Microsoft Secure Score.
- [Endpoint Reporting](../endpoint-reporting): the devices behind endpoint policies.
- [Access Control](../access-control): portal roles, as opposed to Microsoft 365 admin roles.
