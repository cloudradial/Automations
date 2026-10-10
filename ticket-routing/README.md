# Send Every Ticket to the Right Engineer

New tickets are assigned to an engineer who has the right skill, chosen by the rule you set (least busy, round robin, listed order or random), and every assignment leaves a note saying why.

**Formerly:** Queue / Technician Routing | **Marketplace ID:** not yet listed | **Type:** Agent + Workflow (ServiceAI Triage Action)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `ticket-routing.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ticket-routing.yml) |
| Download `ticket-routing.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/ticket-routing.yml) |
| Download `ticket-skill-classifier.agent.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/ticket-skill-classifier.agent.yml) |
| Download the **Ticket Routing: Engineers and Settings** KB article (paste into your portal) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/kb-articles/ticket-routing-engineers-and-settings.txt) |
| Download the **Ticket Routing: Skills** KB article (paste into your portal) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/kb-articles/ticket-routing-skills.txt) |
| Download `engineers-template.csv` (to build the table in Excel) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/engineers-template.csv) |
| Download `skills-template.csv` | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/skills-template.csv) |
| Download `Test-RoutingTable.ps1` (checks your table before you publish) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/Test-RoutingTable.ps1) |
| Routing table guide (columns, settings, publishing) | [ROUTING-TABLE.md](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ROUTING-TABLE.md) |
| All files in this automation | [ticket-routing](https://github.com/cloudradial/Automations/tree/main/ticket-routing) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/ticket-routing) |

## How it works

ServiceAI still replies to the requester and sets the board, type and priority. This automation only picks the person.

1. **Read the request, routing table and ticket** (script). It reads your routing table from two CloudRadial KB articles, checks it, and reads the ticket from your PSA. If the ticket already has an assignee, it stops there.
2. **Pick the skill** (the `ticket-skill-classifier` agent). The AI reads the ticket and picks one skill and role from your list of skills, with a confidence and a one-sentence reason. It never sees your engineers, and it has no tools.
3. **Find, pick, assign and note** (script).
   - Checks that the skill really is in your table. An answer that isn't counts as no match.
   - Finds every active engineer listed for that skill and role.
   - Skips anyone at their open-ticket limit.
   - Applies your tie-break, then assigns the ticket in the PSA and adds an internal note.

Matching the table is done by a script, not the AI, so a 1,200-row table costs the same as a 20-row one: the AI only receives the list of skills.

The internal note looks like this:

```
Ticket routing: assigned to Patel, Riya.
Skill: Network Firewall Fortinet, role: Tickets. Confidence 0.9.
Why: The ticket asks for a new FortiGate VPN tunnel, which is covered by Network Firewall Fortinet.
Candidates: Patel, Riya (4 open); Okafor, Chidi (7 open).
Tie-break: least-open-tickets.
```

## Pieces

| File | Type | Role |
|---|---|---|
| [`ticket-routing.yml`](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ticket-routing.yml) | `automationsWorkflow` | The workflow: Read → Pick the skill (Agent node) → Find, pick, assign and note. **Generated** from `src/`. |
| [`ticket-skill-classifier.agent.yml`](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ticket-skill-classifier.agent.yml) | `automationsAgent` | The classifier the Agent node runs (slug `ticket-skill-classifier`). No extensions. |
| [`ROUTING-TABLE.md`](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ROUTING-TABLE.md) | Guide | How to fill in and publish the routing table, and every setting. |
| [`kb-articles/`](https://github.com/cloudradial/Automations/tree/main/ticket-routing/kb-articles) | KB article templates | The two routing articles, ready to paste into your own company in the portal. **Generated** from the CSV templates. |
| [`skills-template.csv`](https://github.com/cloudradial/Automations/blob/main/ticket-routing/skills-template.csv), [`engineers-template.csv`](https://github.com/cloudradial/Automations/blob/main/ticket-routing/engineers-template.csv) | Templates | Starting points for the two tables. |
| [`Test-RoutingTable.ps1`](https://github.com/cloudradial/Automations/blob/main/ticket-routing/Test-RoutingTable.ps1) | Script | Checks your table before you publish it, with the workflow's own parser. **Generated** from `src/`. |
| [`src/`](https://github.com/cloudradial/Automations/tree/main/ticket-routing/src) | Source | The step scripts, the PSA calls, the build script and the mock test harness. Edit these, not the generated files. |

## Supported PSAs

| PSA | Assign | Internal note | Least open tickets | Least recently assigned |
|---|---|---|---|---|
| ConnectWise PSA | Ticket owner | Internal tab | Yes | Yes |
| Autotask | Resource + role | Internal Only (looked up by name) | Yes | Yes (last 90 days) |
| HaloPSA | Agent | Hidden from user | Yes | Yes |
| Kaseya BMS | Assignee | Internal | Falls back to listed order | Falls back to listed order |
| Syncro | User | Hidden, no email | Yes | Yes |
| Zendesk | Assignee | Private comment | Yes | Yes |

The workflow calls each PSA's API directly from its script steps, using the **same secret names as that PSA's catalog extension**, so you don't need the extension installed.

> **Not yet proven on a live PSA.** Each call was checked against the vendor's API docs and a mock harness, not yet against a real tenant. Run it with `confirm` false first (see [Test](#test)).

## Install

1. On **Agents → Custom → Import**, upload [`ticket-skill-classifier.agent.yml`](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ticket-skill-classifier.agent.yml).
2. On **Workflows → Import**, upload [`ticket-routing.yml`](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ticket-routing.yml).
3. Add the [secrets](#secrets) to your runner's Key Vault.
4. Publish your routing table as two KB articles in your own (MSP) company. Start from the two [KB article templates](#files-always-the-latest-version) in the Files table: create each article with the subject shown, paste the file in as plain text, and replace the sample engineers and PSA ids with yours. See [ROUTING-TABLE.md](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ROUTING-TABLE.md), and check it first with `Test-RoutingTable.ps1`.
5. **Publish** the workflow and **deploy** it to that runner.
6. Turn on the webhook under **Properties → Webhook**, which mints the URL and secret, then redeploy.
7. Wire the ServiceAI Action (below).

## ServiceAI Action

**The split:** ServiceAI triages the ticket. It replies, sets the board, type and priority, and adds its notes. Then its triage AI runs this Action, and AutomationAI picks the engineer and assigns them. ServiceAI doesn't read the webhook's response, so the workflow writes its own internal note.

In **ServiceAI → Settings → Actions**, create an Action named **Assign Engineer**:

- **Mode:** **Use in Triage**.
- **URL:** the workflow's webhook URL. **Header:** `X-Crauto-Webhook-Secret` with `{{secret.<name>}}`, a secret you add in the ServiceAI Secrets manager holding the webhook secret.
- **Body:** a template the triage AI fills in from the ticket. Use the raw-ticket sample in the editor to find the ticket id field for your PSA:

  ```json
  {"triggerSource":"serviceai-triage","ticketId":"{{<ticket id field>}}"}
  ```

  Leave `confirm` out. The routing table's `liveAssign` setting decides whether a Triage run assigns, which keeps the write switch out of an AI-filled body. The workflow also accepts the whole raw ticket, and looks for the id in `ticketId`, `id`, `ticketID`, `TicketID` and `ticket.id`.
- **Triage rules:** ServiceAI's triage can assign technicians too, so tell it not to, or the two will fight over the assignee. For example:
  - *"Never assign a technician or resource to a ticket yourself."*
  - *"After you have set the board, type and priority on a new ticket that has no assigned technician, run the **Assign Engineer** action and include the ticket id."*

**Going live:** `liveAssign` starts as `no`, so every Triage run is a preview that writes nothing. Check the picks in **Action Runs** and the AutomationAI run history. When they look right, set `liveAssign: yes` in the engineers article. You don't need to edit the Action. To stop assigning, set it back to `no`.

**Retries are safe.** A retry from Action Runs replays the same request. The ticket is already assigned by then, so the workflow leaves it alone.

**Optional, for technicians:** an Action can only be Use in Triage *or* Use in AI, so this needs a **second** Action, for example **Find Engineer (preview)**:
- **Mode:** Use in AI, with the same URL and header.
- **Parameter:** `ticketId` (required).
- **Example body:** `{"triggerSource":"serviceai-ai","ticketId":"12345","confirm":"false"}`.
- **Pod Quick Action pill (optional):** label "Find the right engineer", prompt *"Run Find Engineer (preview) for this ticket and show me who it would pick and why."*

The explicit `confirm` false keeps it a preview even when `liveAssign` is on.

## Inputs

| Field | Default | What it does |
|---|---|---|
| `ticketId` | none | Required. The PSA ticket id. |
| `confirm` | the table's `liveAssign` (default `no`) | `false` returns who it **would** assign and writes nothing, not even the note. `true` assigns and adds the note. When it's left out, as in a raw Triage body, `liveAssign` decides. |
| `reassign` | `false` | `false` leaves a ticket that already has an assignee alone. |
| `psa` | secret `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` |
| `routingCompanyId` | secret `Routing-CompanyId` | The CloudRadial company that holds the routing articles |
| `skillsArticle` | `Ticket Routing: Skills` | Subject of the skills article |
| `engineersArticle` | `Ticket Routing: Engineers and Settings` | Subject of the engineers and settings article |

Routing settings (`tieBreak`, `respectMaxOpen`, `noMatch`, `fallbackEngineer`, `minConfidence`, `liveAssign`) live in the engineers article. See [ROUTING-TABLE.md](https://github.com/cloudradial/Automations/blob/main/ticket-routing/ROUTING-TABLE.md#settings).

## Secrets

Runner Key Vault, by name:

| Secret | Required | Used for |
|---|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Yes | Reading the routing articles |
| `Routing-CompanyId` | Yes, unless sent as `routingCompanyId` | The CloudRadial company id of your own (MSP) company |
| `PSA-Type` | Yes, unless sent as `psa` | Which PSA |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | For ConnectWise | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | For Autotask | Optional: `Autotask-NotePublishId` and `Autotask-NoteTypeId` to pin the note's publish and type ids. Otherwise they're looked up by name ("Internal Only"). |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | For HaloPSA | Optional: `Halo-NoteOutcomeId`, the action outcome for the note. Default `7`. |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | For Kaseya BMS | `KaseyaBMS-NoteTypeId` is the note type id for internal notes. Kaseya requires one. |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | For Syncro | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | For Zendesk | |

## Output

The standard contract:

- `status`: `success`, `rejected`, `incomplete`, `error` or `pending_confirmation`
- `message`, `public_note` (always empty, since nothing here is for the requester), `internal_note`, `ticket_id`, `actions`, `warnings`, `chatReply`

Plus:

- `assignee` (name, PSA user id, email)
- `skill`, `role`, `confidence`, `reason`
- `candidates`: name, open count, and why each one was skipped
- `tieBreak`: the rule actually used, which may be `listed-order` after a fallback, or `fallback`
- `noMatchApplied`
- `confirm`

| Outcome | `status` |
|---|---|
| Preview (`confirm` false) | `pending_confirmation`; `internal_note` holds the note it would write |
| Assigned | `success` |
| Already assigned | `rejected` |
| No match, low confidence, everyone at their limit, or a routing table error | `incomplete` |
| A PSA call failed | `error` |

## Safety

- Until `liveAssign` is `yes` (or the body sends `confirm` true) it writes nothing: no assignment and no note.
- It never reassigns a ticket that already has an assignee unless `reassign` is true.
- It never assigns anyone who isn't in the engineers table, is marked inactive, or (with `respectMaxOpen`) is at their limit.
- It never trusts an invented skill. An AI answer that isn't in the table counts as no match.
- If the routing table fails its checks, nothing happens, and `internal_note` lists the errors.
- If the assignment fails, no note is written and the run returns `error`.
- The routing articles list engineer emails, so keep them in your own company and out of client-facing content.

## Test

1. Run `Test-RoutingTable.ps1` on your tables until it reports no errors.
2. In AutomationAI, open the workflow's **Test** run and send `{"ticketId":"<a test ticket>","confirm":"false"}`. The first step's Test Input has a sample. Check `assignee`, `candidates` and `internal_note`.
3. Send the same with `"confirm":"true"` against a test ticket, and check the assignee and the internal note in the PSA.
4. Wire the ServiceAI Triage Action with `liveAssign: no`, create a test ticket, and check **Action Runs** and the run history. After the first live assignment (`liveAssign: yes`), check the assignee is still set once ServiceAI has finished triage.

### For developers

The step scripts live in `src/`. `build.js` embeds them into `ticket-routing.yml` and generates `Test-RoutingTable.ps1` from the same parser. `test.ps1` runs the shipped step scripts under strict mode against mocked CloudRadial, all six PSAs and the classifier.

```
cd src
npm install
npm test
```
