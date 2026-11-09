# See Exactly What a Portal Form Sends to AutomationAI

Attach this test tool to a service request form, submit the form, and get an email listing every value that reached AutomationAI, with anything that went wrong flagged.

## What happens

This is a testing aid for the CloudRadial UCP to AutomationAI integration. When a form runs it, you get one email that shows:

- **Every value AutomationAI received,** each with its name (the field key), so you can see what each question sent.
- **What needs a look:** tokens CloudRadial didn't fill in (a literal `@Token`), empty answers, and a body that isn't valid JSON.
- **The form's questions by Id,** when the form sends them as a list.
- **The raw input,** exactly as the runner passed it.

The run in AutomationAI keeps the same details, so a run is still useful when the email can't be sent.

## What it protects

- **It changes nothing.** It only reads what arrived and sends one email. No tickets, notes, PSA, Microsoft 365 or portal changes.
- **Broken JSON doesn't stop it.** CloudRadial pastes token values in unescaped, so an answer with a quote or a line break can break the JSON. It still reads the values, and the email names the answers that broke it.
- **It only emails the tester.** The email goes to the address in a `toEmail` question, or else to the person who submitted the form.

## Works with

CloudRadial UCP service request forms (the new **Action** question, or the old Automation with a Webhook activity), and Postmark for the email. No PSA is needed.

## What you need

- AutomationAI, with a runner
- A Postmark server and a verified sender address

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/ucp-webhook-echo/v1.0.0).
2. In AutomationAI, go to **Workflows > Import** and upload it.
3. Add the Postmark details to the runner (see the [technical details](https://github.com/cloudradial/Automations/tree/main/ucp-webhook-echo#install)).
4. **Publish** and **Deploy** it. An Action question doesn't need the webhook. Turn it on (**Properties > Webhook**) only if you test with an old Automation that uses a Webhook activity.
5. In a test service request form, add an **Action** question and pick **UCP Webhook Echo**. Optionally add a short-text question with the field key `toEmail` so the tester chooses where the email goes.

**Test it.** Run it from **Test** in AutomationAI with its built-in test input, with `toEmail` changed to your address. The email should flag one value, `@SomeFieldId`, which is deliberately left unreplaced.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/ucp-webhook-echo#technical-details) cover what the step reads, how it picks the recipient, both ways to trigger it, and how to build and test it.

---

## Technical details

**Marketplace ID:** Not listed (test tool) | **Type:** Workflow (PowerShell, no AI) | **Version:** 1.0.0

## Files

Each version is published as a release, with `ucp-webhook-echo.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/ucp-webhook-echo/v1.0.0).

| What | Link |
|---|---|
| Download `ucp-webhook-echo.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/ucp-webhook-echo/v1.0.0) |
| View the current source | [`ucp-webhook-echo.yml`](https://github.com/cloudradial/Automations/blob/main/ucp-webhook-echo/ucp-webhook-echo.yml) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/ucp-webhook-echo/src) |
| All files in this automation | [ucp-webhook-echo](https://github.com/cloudradial/Automations/tree/main/ucp-webhook-echo) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/ucp-webhook-echo) |

## How it works

`Start → Email what arrived → End`

One PowerShell step reads whatever the trigger delivered:

1. **Unwraps it.** It takes the body out of the step parameter, and out of a `{body, headers}` wrapper if there is one. A body that arrives as JSON text is parsed. When the text isn't valid JSON because a token value with a line break, double quote or backslash was pasted in unescaped, it reads the body one `"key": value` at a time instead, and names the values that broke it.
2. **Lists every value** by its path (for example `user.email` or `Ticket.Questions[1].Value`), with its type and a check:
   - `ok`
   - `empty` or `null`
   - `token not replaced`: the value is a literal `@Token`, so CloudRadial didn't fill it in
   - `may contain an unreplaced token`
   - `broke the JSON (repaired)`: this value made the body invalid JSON
   - `not JSON`
3. **Lists form questions by Id** when the body uses the CloudRadial `{Ticket:{Questions:[...]}}` shape.
4. **Emails it all through Postmark** ([`_shared/postmark.ps1`](https://github.com/cloudradial/Automations/blob/main/_shared/postmark.ps1)): a summary, a "Check these" list, the value table, and the raw step input. The run output carries the same data.

**Recipient**, in order:

1. A `toEmail` value anywhere in the payload: a form question with the field key `toEmail`, or a Questions entry with that Id. It can be one address or a comma list.
2. The submitting user's email (`user.email`, `UserEmail` or `requestedBy`).

If neither is found, the run ends `incomplete` and the reason is in the output.

## Install

1. Import `ucp-webhook-echo.yml` on **Workflows → Import**.
2. Add the Postmark secrets to the runner Key Vault. These are the same names the Postmark extension and [Deliver Result](https://github.com/cloudradial/Automations/tree/main/deliver-result) use:

   | Secret | Required | What it is |
   |---|---|---|
   | `Postmark-ServerToken` | Yes | Postmark server API token |
   | `Postmark-FromEmail` | Yes | A verified Postmark sender |
   | `Postmark-ApiUrl` | No | Defaults to `https://api.postmarkapp.com` |

3. **Publish** and **Deploy** to that runner. The webhook ships off, and an Action question doesn't need it. Enable it (**Properties → Webhook**) only for the old Webhook activity below.

## Trigger it from UCP

**Action question (the new integration):**

1. In the service request form, add a question of type **Action** and pick **UCP Webhook Echo** from the actions catalog.
2. Optional: add a short-text question with the field key `toEmail`. Without it, the email goes to whoever submitted the form.
3. Add whatever other questions you want to test.
4. Submit the form, then run the action from the ticket.

**Old Automation with a Webhook activity:**

- Enable the workflow's webhook first, then publish and redeploy.
- POST to `https://automationai.cloudradial.com/api/hooks/<tenantId>/<hookId>`.
- Content Type: `application/json`.
- Headers: `{"X-Crauto-Webhook-Secret": "<secret>"}`.
- Content: any JSON you like, for example:

  ```json
  {"toEmail": "tester@examplemsp.com", "ticketId": "@TicketId", "companyName": "@CompanyName", "UserEmail": "@UserEmail", "firstName": "@firstName"}
  ```

## Developing

Edit `src/echo.ps1` (or `_shared/postmark.ps1`), then run `node build.js` in `src/`. Run the strict-mode mock harness before pushing:

```
npm test
```

`npm test` runs `node build.js --check` and then the harness. Both need js-yaml, from `npm install` in `_shared` or from `JS_YAML_PATH`.

## What an Action sends

Captured from live Action runs on the DV tenant in November 2026 (run trigger type `integration`). The body arrives as the Start step's output, already parsed. The values below are placeholders:

```json
{
  "subject": "Request a new laptop",
  "toEmail": null,
  "laptopModel": "Standard",
  "accessGroups": [
    {"id": "f22a3a55-...", "displayName": "Account Management"}
  ],
  "ticket": {
    "id": 12345,
    "reference": "...",
    "subject": "Request a new laptop",
    "description": "...",
    "estimatedTime": 0,
    "checklist": []
  },
  "company": {
    "id": 9,
    "name": "Contoso Ltd",
    "psaId": 250,
    "psaIdentifier": "Contoso",
    "tenantId": "00000000-0000-0000-0000-000000000000"
  },
  "user": {
    "id": "...",
    "email": "pat.lee@contoso.com",
    "name": "Pat Lee",
    "psaId": 101,
    "psaSiteId": 1
  }
}
```

- **Form answers** sit at the top level, one per question, named by the question's field key. There's no `Ticket.Questions` list, and no `@tokens` are left to replace.
- **An unanswered question** arrives as `null`, and the email lists it as empty.
- **A multi-select question**, such as a group picker, arrives as a list of `{id, displayName}`.
- **`ticket`, `company` and `user`** are always added. `user.email` is the submitter, so the email goes to them when there's no `toEmail` answer.

## Webhook and Actions

An Action question runs the deployed version directly, so it doesn't need the workflow's webhook. On the DV tenant in October 2026, Add CC to Ticket, Password Reset and New User Onboarding (Direct) all ran successfully from Action questions on versions with the webhook off. Only the old Webhook activity uses the webhook URL.
