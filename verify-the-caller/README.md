# Verify a Caller Before You Help Them

Before a technician resets a password or changes access for someone on the phone, they can prove the caller is really the person on the ticket. A one-time code goes to the email address (or mobile number) your PSA already holds for that contact, the caller reads it back, and the result is logged on the ticket.

## What happens

**The technician sends a code.** From ServiceAI, they run the **Verify the Caller** Action, or click a Quick Action labelled **Verify caller**. A 6-digit code goes to the contact on the ticket, by email, by text, or both.

**The caller reads it back.** The technician asks for the code and runs **Verify the Caller** again with it.

**The answer is logged on the ticket** as an internal note: verified, or not verified and why (wrong code, expired, or too many tries). The technician sees the same answer in ServiceAI.

## What it protects

- **The code only goes where your PSA says.** It's sent to the email and mobile number on the ticket contact's record, never to an address the caller or the technician gives.
- **Short-lived and single-use.** A code expires after 10 minutes, works once, and allows 3 tries. Sending a new code cancels the old one.
- **Nobody can read the code from the ticket.** The note records where the code went and when it expires, plus a check value that can't be turned back into the code. The code never appears in a note or in the run's output.
- **No flooding.** At most 3 codes per ticket in 15 minutes.
- **Inactive contacts are refused,** and a ticket with no contact gets no code.
- **Nothing else changes.** It adds internal notes only. Status, owner and priority stay as they were.

## Works with

ConnectWise PSA, Autotask and HaloPSA. Kaseya BMS, Syncro and Zendesk aren't supported yet.

- **Text messages** need a Twilio account. Without one, codes go by email.
- **Mobile numbers** need to be stored in international format (for example +44 7700 900123). North American numbers without the +1 work when your Twilio number is a +1 number.

## What you need

- AutomationAI, with your PSA connected
- A Postmark account for the emails (the same one other automations use)
- Optional: a Twilio account and phone number, for texts
- ServiceAI, to run it from a ticket (it can also be run by hand in AutomationAI)

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/verify-the-caller/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Add the secrets listed in the [technical details](https://github.com/cloudradial/Automations/tree/main/verify-the-caller#secrets) to your runner, including a new random key for the check value.
4. Turn on the webhook in **Properties**, then click **Publish** and **Deploy** to your runner.

**In ServiceAI (Settings > Actions):**

1. Save the workflow's webhook secret in the ServiceAI **Secrets** manager as `aai_verify_caller`.
2. Create an Action called **Verify the Caller** (**Use in AI**) pointing at the workflow's webhook address. The body and parameters are in the [technical details](https://github.com/cloudradial/Automations/tree/main/verify-the-caller#serviceai-action).
3. Optionally, add a Pod Quick Action labelled **Verify caller** (Settings > AI Behavior > Pod Quick Actions).

**Test it.** Run it by hand on a test ticket whose contact is you, first without `confirm` (a preview: nothing is sent), then with `"confirm": true`. Read the code from your email and check it.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/verify-the-caller#technical-details) for every setting, the ServiceAI Action, the output, and how to build and test it.

---

## Technical details

**Marketplace ID:** Not listed yet | **Type:** Workflow (one PowerShell step) | **Version:** 1.0.0

## Files

Each version is published as a release, with `verify-the-caller.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/verify-the-caller/v1.0.0).

| What | Link |
|---|---|
| Download `verify-the-caller.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/verify-the-caller/v1.0.0) |
| View the current source | [`verify-the-caller.yml`](https://github.com/cloudradial/Automations/blob/main/verify-the-caller/verify-the-caller.yml) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/verify-the-caller/src) |
| All files in this automation | [verify-the-caller](https://github.com/cloudradial/Automations/tree/main/verify-the-caller) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/verify-the-caller) |

## How it works

`Start → Send or check the code → End`

**`action: send`**
1. Reads the ticket, its notes and its contact from the PSA (ConnectWise `contact.id` then `/company/contacts/{id}` communication items; Autotask `contactID` then `/Contacts/{id}`; HaloPSA `user_id` then `/Users/{id}`). The contact's email and mobile come only from that record.
2. Makes a 6-digit code from a cryptographic random generator (every code equally likely) and a random 16-hex-character nonce.
3. Sends the code by Postmark email, Twilio text, or both. For `both`, if one channel can't be used or fails, the other still goes and a warning says so.
4. Only after at least one message went, adds an internal note with the masked destination, the expiry, and `Check value: HMAC-SHA256(VerifyCaller-Key, "<nonce>|<ticket id>|<code>")` in hex, marked `[verify-caller <ticket id>-<nonce>]`.

**`action: check`**
1. Finds the newest `[verify-caller ...]` note on the ticket. Older codes no longer count.
2. Counts the result notes for that nonce. A code already used, or with 3 failed tries, is refused.
3. Checks the expiry, then recomputes the HMAC from the code given and compares it in constant time.
4. Adds an internal result note (`Result: verified`, `failed (try n of 3)`, `expired` or `locked`), marked `[verify-caller-result <ticket id>-<nonce>-a<try>]`. Each try has its own marker, so every try is logged and a retry of the same try isn't doubled.

**`confirm: false`** (the default) is a preview: a send says where the code would go, and a check says which code it would check against and how many tries are used. Nothing is sent, checked or written, so a preview can't be used to guess codes.

The code is held only in memory and in the message to the contact. Every output field, warning and note is scrubbed of it.

## Inputs

| Field | Required | What it does |
|---|---|---|
| `ticket_id` | Yes | The PSA ticket number (`ticketId` also works). Autotask numbers such as `T20261008.0001` are looked up. |
| `action` | No (default `send`) | `send` or `check`. |
| `code` | For `check` | The 6 digits the caller read back. Spaces and dashes are ignored. |
| `channel` | No (default `email`) | `email`, `sms` or `both`. |
| `confirm` | No (default `false`) | `true` sends, checks and writes. `false` is a preview. |
| `psa` | No | Overrides the `PSA-Type` secret. |

Placeholder values ServiceAI leaves unfilled (`<code>`, `{{code}}` or a literal `@code`) count as not given.

## ServiceAI Action

**Verify the Caller**, **Use in AI**, pointing at the workflow's webhook URL with the header `X-Crauto-Webhook-Secret: {{secret.aai_verify_caller}}`.

Body:

```json
{"ticket_id": "<ticket_id>", "action": "<action>", "code": "<code>", "channel": "<channel>", "confirm": true}
```

Parameters: `ticket_id` (required string), `action` (`send` or `check`), and `code` and `channel` (optional strings).

**Pod Quick Action** (Settings > AI Behavior > Pod Quick Actions): label **Verify caller**, prompt *"Run the Verify the Caller action with action send for this ticket. When I give you the code the caller read back, run it again with action check and that code, and tell me if the caller is verified."*

## Output

`status` (`success`, `pending_confirmation`, `incomplete`, `rejected`, `unsupported` or `error`), `message`, `public_note` (always empty), `internal_note` (the note written), `ticket_id`, `action`, `verified` (`true` only when a check passed), `destination_masked` (for example `by email to m***@contoso.example and by text to ***-***-1234`), `expires_utc`, `actions`, `warnings`, `counts` (`emails_sent`, `texts_sent`, `notes_written`) and `chatReply`.

A check that runs but doesn't verify is `status: success` with `verified: false`.

## Secrets

By name only.

| Secret | For |
|---|---|
| `VerifyCaller-Key` | **Required.** A random value of at least 32 characters, used only for the check value. Changing it invalidates codes already sent. |
| `Postmark-ServerToken`, `Postmark-FromEmail` | The emails. `Postmark-ApiUrl` is optional. |
| `Twilio-AccountSid`, `Twilio-AuthToken`, `Twilio-FromNumber` | Optional: the texts. The from number is in E.164 (`+15550100000`). |
| `PSA-Type` | `connectwise`, `autotask` or `halopsa` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |

**ServiceAI Secrets manager:** `aai_verify_caller`, the workflow's webhook secret.

**PSA permissions:** read tickets, notes and contacts (users in HaloPSA), and add notes.

## Not yet proven live

The contact reads (ConnectWise communication items and the Mobile type name, Autotask `mobilePhone`, HaloPSA `mobilenumber`) and the Twilio send are written from the vendors' documentation and tested against mocks only.

## Developing

Edit `src/verify.ps1`, then run `node verify-the-caller/src/build.js`. Never edit the `.yml`. Before pushing:

```
node verify-the-caller/src/build.js --check
pwsh -NoProfile -File verify-the-caller/src/test.ps1
```

The harness runs the step in strict mode, the way the runner does, against mock ConnectWise, Autotask, HaloPSA and Kaseya BMS, Postmark and Twilio (`mock-psa.ps1`). It reads each code from the captured message and checks that no code ever appears in an output or a note. Test data is placeholder only.
