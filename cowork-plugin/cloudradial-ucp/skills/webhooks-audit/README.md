# Webhooks & Audit

> Set up, test and troubleshoot webhook actions, and find out who changed what, when, and whether a sync ran.

**Say this:**

```
Who changed Contoso's portal settings this week?
```

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal, `Partner-wide` on your partner account's own settings. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing: **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Create a webhook
`Partner-wide` · `Writes to the portal` · **Not yet tested**

```
Create a webhook called "PSA intake" that POSTs to https://hooks.example.com/cr.
The Authorization header value is in C:\Users\me\cr-headers.json. Show me the
webhook first, only create it when I confirm, and tell me where the signing
secret was saved.
```

**What you get:** A new webhook action, with its signing secret saved to a private file on your computer instead of the chat.

**Good to know:** Keep header values in a local file. Pasting tokens into chat isn't needed.

### Test a webhook
`Partner-wide` · `Read-only` · **Not yet tested**

```
Send a test to the "PSA intake" webhook and tell me what the endpoint answered.
```

**What you get:** One signed test delivery and the receiver's response.

**Good to know:** The test has a 10-second limit and isn't retried.

### Find out why a webhook failed
`Partner-wide` · `Read-only` · **Not yet tested**

```
The "PSA intake" webhook stopped working. Check its recent runs, open the last
failed one, and tell me the likely cause.
```

**What you get:** The failing deliveries and a suggested fix to approve.

### Rotate a signing secret
`Partner-wide` · `Writes to the portal` · **Not yet tested**

```
Rotate the signing secret on the "PSA intake" webhook. Warn me first and only
rotate it when I confirm.
```

**What you get:** A new signing secret saved to a private file on your computer.

**Good to know:** The old secret stops working at once, so update the receiving system right away.

### See who changed what
`Per-company` · `Read-only` · **Not yet tested**

```
Who changed anything in Contoso's portal in the last 7 days? Group it by person
and show what they changed.
```

**What you get:** A dated list of changes by person.

### Check a sync
`Per-company` · `Read-only` · **Not yet tested**

```
Did Contoso's PSA ticket sync run successfully today? Show the last run's
status and any errors.
```

**What you get:** The latest ticket sync run with its counts and log entries.

## Good to know

- **Secrets stay out of chat.** Signing secrets go to a file on your computer, and header values come from a file.
- **Every webhook change waits for your yes.**
- **The audit log is read-only.** Nothing here changes your portal.

## Related skills

- [Access Control](../access-control): change the access the audit log shows.
- [Content Management](../content-management): the catalog forms that trigger webhooks.
