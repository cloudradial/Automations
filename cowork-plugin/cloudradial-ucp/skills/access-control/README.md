# Access Control

> Security roles, role assignments, feature sets, support PINs and Signal installs, with every change previewed before it's made.

**Say this:**

```
Who has admin access in Contoso's portal?
```

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal, `Partner-wide` on your partner account's own settings. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing: **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Review who has access
`Per-company` · `Read-only` · **Not yet tested**

```
List everyone with a role in Contoso's portal: name, email, role and scope.
Flag anyone with an admin role or a partner-wide assignment.
```

**What you get:** One row per user and role, with admins and partner-wide access called out.

### Give someone a role
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Give Pat Jones the "Approver" role at Contoso. Show me the role, the user and
the scope first, and only assign it when I confirm.
```

**What you get:** The role assigned to Pat for Contoso only.

**Good to know:** Assignments can't be edited; to change the scope, the skill removes and re-adds it.

### Create a role
`Partner-wide` · `Writes to the portal` · **Not yet tested**

```
Create a "Ticket Viewer" role that can read tickets for the user's whole
company and nothing else. Copy the module codes from an existing role, show me
every permission, and only create it when I confirm.
```

**What you get:** A new client role with exactly the permissions you approved.

**Good to know:** The API won't give a client role partner-level modules or Full access, and your plan may cap the number of roles.

### Change which companies use a feature set
`All clients` · `Writes to the portal` · **Not yet tested**

```
Move Contoso and Fabrikam onto the "Essentials" feature set. Show me which
companies would be added and removed, and only save when I confirm.
```

**What you get:** The feature set's company list updated, with a before and after.

**Good to know:** The list replaces the current one. Companies taken off fall back to the default feature set.

### Set a support PIN
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Set Pat Jones's support PIN at Contoso to the one I give you. Confirm the user
first and don't repeat the PIN back.
```

**What you get:** The PIN set for help desk verification.

**Good to know:** PINs can't be read back through the API.

### Reset or revoke a Signal device
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Pat's laptop was stolen. Find its Signal install and revoke it. Show me the
device first and only revoke it when I confirm.
```

**What you get:** The install signed out for good until you unrevoke it.

## Good to know

- **Every change waits for your yes.** The tools refuse to write roles, assignments or feature sets until you've approved the exact change.
- **Protected roles stay protected.** System and protected roles can't be changed; the skill tells you why.
- **Microsoft 365 group assignments** are changed in Microsoft 365, not here.

## Related skills

- [User Management](../user-management): find the people before changing their access.
- [Company Management](../company-management): company groups used as assignment scopes.
- [Webhooks & Audit](../webhooks-audit): see who changed access and when.
