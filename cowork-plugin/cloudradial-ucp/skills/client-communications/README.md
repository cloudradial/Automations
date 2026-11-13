# Client Communications

> Signal desktop notices, portal banners and portal messages, written and sent from a chat prompt.

**Say this:**

```
Remind Pat Jones at Contoso that their password expires Friday
```

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing: **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Send a personal reminder
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Send Pat Jones at Contoso a Signal reminder that their password expires on
Friday, with a Change Password button to
https://passwordreset.microsoftonline.com/ and ask them to acknowledge it.
Show me who it reaches and the exact message, and only send when I confirm.
```

**What you get:** One important Signal notice on Pat's desktop, and the message id to check on it later.

**Good to know:** Important and urgent notices need an expiry date; the skill sets one for you.

### Announce planned maintenance
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Let everyone at Contoso know the file server will be down for maintenance on
Saturday from 8pm to 11pm. Draft a Signal notice and a portal banner, show me
both and who sees them, and only publish when I confirm.
```

**What you get:** A Signal notice for Contoso's users and an amber banner that takes itself down after the window.

**Good to know:** Banners are shown by company group, so the skill checks Contoso is in a group that will see it.

### Send an outage notice
`All clients` · `Writes to the portal` · **Not yet tested**

```
Email is down for clients in the "Microsoft 365" company group. Send them an
urgent Signal notice that expires in 4 hours. Show me the audience count and
the message first, and only send when I confirm.
```

**What you get:** An urgent notice on every affected desktop, plus the id to resolve it when service is back.

### Check who read it
`Per-company` · `Read-only` · **Not yet tested**

```
How many people have read and acknowledged the password reminder we sent Pat
Jones? List anyone who hasn't acknowledged yet.
```

**What you get:** Read, acknowledged and button-click counts, with names where the company allows per-user receipts.

**Good to know:** Some companies only report totals. The skill tells you when names are hidden.

### Retract a notice
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Retract the outage notice we sent this morning. Show me the message and its
current status first, and only retract when I confirm.
```

**What you get:** The notice withdrawn and cleared from users' Signal clients.

### Add a portal banner
`All clients` · `Writes to the portal` · **Not yet tested**

```
Add a blue banner across the top of the portal for the "Managed Plus" company
group announcing our new after-hours support line, from today until the end of
the month. Show me the banner and which companies will see it, and only save
when I confirm.
```

**What you get:** A dated banner on the home, report and request pages of every company in that group.

**Good to know:** A banner with no company groups isn't shown on any company's pages.

### Post a portal message
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Post an important message to Contoso's portal about the new password policy
starting next month, and include it in the digest. Show me the message first
and only post it when I confirm.
```

**What you get:** A highlighted message in Contoso's portal message list.

**Good to know:** Attachments on portal messages still have to be added in the portal.

## Good to know

- **Signal must be enabled for your partner account.** If it isn't, the skill tells you instead of retrying.
- **Nothing goes out without your yes.** The skill always shows the audience estimate and the exact message before sending.
- **Retries are safe.** A repeated send of the same message on the same day returns the first one instead of sending twice.
- **Test sends aren't available through the API.** Send a first test to your own user in your own company.

## Related skills

- [User Management](../user-management): find the people to target.
- [Company Management](../company-management): set up the company groups banners and notices use.
- [Report Archive](../report-archive): upload a report, then tell the client it's ready.
