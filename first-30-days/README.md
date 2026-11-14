# Give a New Client a Strong First Week in One Run

Run one workflow for a new client and, in a few minutes, they have starter portal content, their Microsoft Secure Score as a portal assessment, and a card on their Planner board showing the Microsoft 365 licences they could save on. You get a one-paragraph summary of all of it.

## What happens

- **Their portal gets its starter content.** Users, replacement tokens, request forms and menu tiles are added to the client's existing CloudRadial company. Anything already there is skipped, so running it again adds nothing twice. New menu tiles are shown to Everyone.
- **They see their security score.** Their Microsoft Secure Score becomes a portal assessment, with one question per control, its status and Microsoft's recommended fix. One click on **Run** in the portal shows the score.
- **They see a saving straight away.** A card called "Reclaim unused Microsoft 365 licences" lists the paid licences nobody has used, with the monthly saving, on the client's Planner board. It's shown to the client unless you choose otherwise.
- **You get one summary.** The run ends with a short summary: the score, the saving, what was set up, and the few steps left to do by hand.

## What it protects

- **Preview first.** By default it works everything out and writes nothing: the summary lists every portal record, the assessment and the card it would add. Run it again with `mode` set to `live` when you're happy.
- **It reports only what happened.** A record is listed as added only when CloudRadial confirmed it. Anything that failed is listed with the error.
- **It never changes Microsoft 365.** It only reads the client's tenant. No licence or account is touched.
- **One client per run.** Each stage uses the client's own Microsoft 365 and CloudRadial connection, so one client's data never lands in another client's portal.
- **It never creates, changes or deletes the company or an existing record.** It only adds to a company that already exists. An existing replacement token is left as it is.
- **Bad input stops it early.** Every problem is listed at once, before any stage runs.

## Works with

CloudRadial, Microsoft 365 and AutomationAI. No PSA is needed.

## What you need

- AutomationAI, with a runner
- The client added as a company in AutomationAI **Companies**, with its Microsoft 365 connection
- The client's company in CloudRadial (create it first with [New Client Onboarding](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding) or by hand)

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/first-30-days/v1.1.0).
2. In AutomationAI, go to **Workflows > Import** and upload this file. No agent is needed.
3. Click **Publish**, then **Deploy** to your runner.
4. Choose **Run**, and enter the client's name in AutomationAI, its CloudRadial company number, and what to add to the portal.

**Test it.** Run it once in preview, check the summary, then run it again with `"mode": "live"`.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/first-30-days#technical-details) cover the run input, each stage, the summary, and how to build and test it.

---

## Technical details

**Marketplace ID:** Not listed yet | **Type:** Workflow (PowerShell) | **Version:** 1.1.0

## Files

Each version is published as a release, with `first-30-days-week-one.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/first-30-days/v1.1.0).

| What | Link |
|---|---|
| Download `first-30-days-week-one.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/first-30-days/v1.1.0) |
| View the current source | [`first-30-days-week-one.yml`](https://github.com/cloudradial/Automations/blob/main/first-30-days/first-30-days-week-one.yml) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/first-30-days/src) |
| All files in this automation | [first-30-days](https://github.com/cloudradial/Automations/tree/main/first-30-days) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/first-30-days) |
| Uses | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) (the Read the setup check from Set Up a New Company) |
| Uses | [Secure Score Assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment) |
| Uses | [License Reclamation](https://github.com/cloudradial/Automations/tree/main/license-reclamation) |

## How it works

`Start → Read the client → Check the portal setup → Add portal content → Secure Score assessment → Licence check settings → Find unused licences → Licence card for the client → Week-one summary → End`

| Step | What it does |
|---|---|
| **Read the client** | Checks the run input and stops with every problem listed. Its output feeds the other stages. |
| **Check the portal setup** | The Read the setup step of Set Up a New Company, run with `company_id`. It checks every user, token, form and tile and stops with every problem listed. |
| **Add portal content** | Plain PowerShell, no AI. It reads what the company already has, skips duplicates, and in `live` mode adds the rest: the default domain, company group membership (never a new group), users, tokens, request forms and menu tiles. In `preview` it only lists them. |
| **Secure Score assessment** | The Secure Score Assessment step, with `company`, `companyId` and `mode` bound from Read the client. |
| **Licence check settings**, **Find unused licences**, **Licence card for the client** | The three License Reclamation steps, with `company`, `company_id`, `days`, `preview` and `client_visible` bound from Read the client. |
| **Week-one summary** | Reads the four results and writes one summary. It writes nothing anywhere else. |

The reused steps are copied from those automations' built files when this one is built, so a fix there reaches this workflow on its next build.

**If a stage fails,** the run stops at that stage, and the stages before it keep what they did. For example, if the client's Microsoft 365 connection is missing, Secure Score stops the run and no licence card is written.

## Run input

| Field | Default | What it does |
|---|---|---|
| `company` | required | The client's company in AutomationAI **Companies** (name, external id or alias). Every stage uses its Microsoft 365 and CloudRadial connection. |
| `company_id` | required | The client's CloudRadial company number. |
| `mode` | `preview` | `preview` plans the portal content, the assessment and the card without writing them. `live` adds them. |
| `days` | `30` | How long a licence must go unused before it is listed (14 to 365). |
| `client_visible` | `true` | Shows the licence card to the client. `false` keeps it internal. |
| `domain`, `companyGroup`, `users`, `tokens`, `requestForms`, `menuTiles` | at least one | What to add to the portal, in the same format as [Set Up a New Company](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#technical-details): up to 5 users, 5 tokens, 3 request forms and 3 menu tiles. |

`companyName`, `accountManager`, `territory`, `psaIdentifier` and `psaKey` are refused, because this workflow never creates or changes the company.

Example:

```json
{
  "company": "Contoso Ltd",
  "company_id": 7,
  "mode": "preview",
  "users": [{"firstName": "Pat", "lastName": "Lee", "email": "pat.lee@contoso.com"}],
  "tokens": [{"token": "SupportPhone", "value": "555-0100"}],
  "requestForms": [{"subject": "Request a new laptop", "category": "Hardware", "description": "Tell us who the laptop is for and when they start."}],
  "menuTiles": [{"name": "Remote Support", "url": "https://support.examplemsp.com", "category": "Help"}]
}
```

**What counts as already there:** a domain any company has, a group membership, a user email anywhere in the portal (a user in another company is skipped with a warning, never moved), a token name, a request form subject or a menu tile name in this company. Request forms are added with self-approval off, the subject appended, sent to the PSA, and the button text REQUEST. If a portal won't take the Everyone group on a new tile, the tile is added without it and a manual step says so. A user deleted from the portal still holds their email, so adding that email again fails; the summary says so. Restore the user in CloudRadial instead.

## Output

The Week-one summary returns:

- `status`: `success` (live), `pending_confirmation` (preview), or `incomplete` when a stage gave no result or a portal record failed
- `message`: one line, for example "Week one for Contoso Ltd is done: score 87.93 / 267, 2 unused licence(s) worth about $12.00 a month."
- `summary`: that line, one line per stage, and the steps left to do by hand
- `actions`, `warnings`, `manualSteps`, `company`, `companyId`, `secureScore`, `assessmentId`, `licenceCount` and `monthlySaving`

**By hand afterwards:** choose **Run** on the new assessment in the portal (the API can't start an assessment run), review the licence card with the client, and the portal steps the summary lists: logo and theme, messaging, the PSA and Microsoft 365 links, security roles, and inviting the users.

## Secrets

None of its own. The stages use the client's Microsoft 365 and CloudRadial secrets through its AutomationAI company. See [Secure Score Assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment) and [License Reclamation](https://github.com/cloudradial/Automations/tree/main/license-reclamation#required-runner-key-vault-secrets) for the names and the Microsoft Graph permissions.

## Developing

Edit `src/plan.ps1`, `src/portal.ps1` or `src/summary.ps1`, or the reused steps in their own folders, then run `node first-30-days/src/build.js`. Never edit the `.yml`. Before pushing:

```
node first-30-days/src/build.js --check
pwsh -NoProfile -File first-30-days/src/test.ps1
```

`--check` also fails when one of the reused automations changed and this file wasn't rebuilt. The harness runs every step in strict mode, the way the runner does. It covers Read the client, Add portal content (against a stand-in CloudRadial API: preview, live, re-run, failures), the hand-offs into the reused steps and the summary. The reused steps have their own harnesses.
