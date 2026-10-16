# Ticket routing table

The routing table tells the workflow which engineers can take which kind of ticket, and how to choose between them. It has three parts: **settings**, an **engineers** table and a **skills** table. By default all three are pasted into the workflow's **Routing table (edit me)** step. `$TableSource` at the top of that step can move the skills to AutomationAI Knowledge, or the whole table to CloudRadial KB articles (see [Where it lives](#where-it-lives)).

## How the workflow uses it

1. ServiceAI triages the ticket and sets the board, type and priority, then runs the **Assign Engineer** Action.
2. An AI step reads the ticket and picks one **Skill** and one **Role** from your table. It only sees the skill names, descriptions and roles, never the engineers' PSA ids. (With `knowledge`, it reads the skills CSV and also lists the engineers on that skill and role.)
3. A script step finds every engineer listed for that skill and role, then uses your **tieBreak** setting to choose one.
4. The script assigns the ticket in your PSA and adds an internal note saying who was chosen and why.

If the AI isn't confident enough, or no engineer matches, the **noMatch** setting decides what happens.

## Files

| File | What it is |
|---|---|
| [`kb-articles/ticket-routing-engineers-and-settings.txt`](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/kb-articles/ticket-routing-engineers-and-settings.txt) | The **Ticket Routing: Engineers and Settings** article, ready to paste: settings, then the engineers table. |
| [`kb-articles/ticket-routing-skills.txt`](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/kb-articles/ticket-routing-skills.txt) | The **Ticket Routing: Skills** article, ready to paste. |
| [`skills-template.csv`](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/skills-template.csv) | Which engineer does which skill and role. One row per skill, role and engineer. |
| [`engineers-template.csv`](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/engineers-template.csv) | One row per engineer, with the ids your PSA uses for them. |
| [`Test-RoutingTable.ps1`](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-routing/Test-RoutingTable.ps1) | Checks your table before you publish it. It's generated from the workflow's own parser, so it reads the table exactly the way the workflow does. |

## Skills table

| Column | Required | What to put in it |
|---|---|---|
| Skill | Yes | The kind of work, for example `Network Firewall Fortinet` or `Network Firewall Basic L1 (General)`. Keep names stable, because the AI picks from this list. |
| Role | Yes | The kind of task within the skill, for example `Install`, `Migrate` or `Tickets`. |
| Engineer | Yes | The engineer's name, written exactly as in the engineers table. `Last, First` is fine; keep the quotes around it in CSV. |
| Skill Description | Strongly recommended | What the skill covers. The AI uses it to pick the right skill, so be specific. Use the same description on every row for a skill. |

- Repeat a skill on as many rows as you have engineers for it.
- Rows with `Role only` in the Skill column (leadership roles with no skill) are kept for reference but never matched to a ticket.
- `#N/A` and blank cells are treated as empty.
- If the AI picks a role that isn't listed for its skill, every engineer with that skill is considered, and the run says so in its warnings.

## Engineers table

| Column | Required | What to put in it |
|---|---|---|
| Engineer | Yes | Exactly as in the skills table. Extra spaces around the comma are tidied, so `Hildebrand , Caleb` matches `Hildebrand, Caleb`. |
| Email | Recommended | Shown in the run output. |
| PSA User Id | Yes | The engineer's id in your PSA. See the table below. |
| PSA Role Id | Autotask only | Autotask assigns a resource and a role together, and rejects a resource sent on its own. |
| Active | No | `No` takes the engineer out of routing without deleting their rows. Default `Yes`. |
| Max Open Tickets | No | With `respectMaxOpen: yes`, an engineer at this many open tickets is skipped. Blank means no limit. |

Which id goes in **PSA User Id**:

| PSA | PSA User Id | PSA Role Id | Where to find it |
|---|---|---|---|
| ConnectWise PSA | Member identifier (for example `jlee`) or member id | | System > Members |
| Autotask | Resource id (number) | Role id (number) that the resource holds in a Service Desk queue | Admin > Resources; the role must be one of that resource's roles |
| HaloPSA | Agent id (number) | | Configuration > Teams & Agents |
| Kaseya BMS | Employee (assignee) id (number) | | `GET /v2/hr/assignees` |
| Syncro | User id (number) | | Admin > Users |
| Zendesk | User id (number) of the agent | | Admin Center > Team members |

## Settings

Put these one per line in the step's `$Settings` block (or, for `ucp`, at the top of the engineers article under a `[Settings]` line). Anything you leave out uses the default.

| Setting | Default | Options |
|---|---|---|
| `tieBreak` | `least-open-tickets` | `least-open-tickets`: whoever has the fewest open tickets in the PSA. `least-recently-assigned`: whoever was given a ticket longest ago (a round robin that doesn't need the workflow to remember anything; see the note below). `listed-order`: the first engineer listed for that skill. `random`. |
| `respectMaxOpen` | `yes` | `yes` skips engineers at their Max Open Tickets. `no` ignores it. |
| `noMatch` | `leave-unassigned` | `leave-unassigned`: assign nobody and add a note. `assign-fallback`: assign to `fallbackEngineer`. `recommend-only`: add a note naming up to three candidates, but don't assign. |
| `fallbackEngineer` | blank | An engineer name from the engineers table. Required when `noMatch` is `assign-fallback`. |
| `minConfidence` | `0.7` | 0 to 1. Below this, the AI's pick is treated as no match. |
| `liveAssign` | `no` | `no`: every run is a preview that writes nothing. `yes`: Triage runs assign the ticket and add the note. A `confirm` sent in the Action body overrides this. |

**About the tie-breaks:**
- **`least-recently-assigned`** looks at the newest ticket currently assigned to each engineer, because no PSA API records when a ticket was assigned. A ticket reassigned away from someone no longer counts for them.
- **Kaseya BMS** can't count open tickets or read the last assignment by assignee id, so on Kaseya BMS both of those tie-breaks fall back to `listed-order`, and Max Open Tickets isn't enforced. Each run says so in its warnings.
- Ties are always broken by listed order.

## Where it lives

`$TableSource` at the top of the **Routing table (edit me)** step decides:

| `TableSource` | Settings | Engineers | Skills |
|---|---|---|---|
| `inline` (default) | `$Settings` block | `$Engineers` block | `$Skills` block |
| `knowledge` | `$Settings` block | `$Engineers` block | A CSV in AutomationAI Knowledge |
| `ucp` | Engineers article | Engineers article | Skills article |

### inline (default): paste it into the step

Open the workflow in the Designer, select **Routing table (edit me)** and replace the sample lines between each `@'` and `'@` with your own: the settings, then your engineers CSV, then your skills CSV, header row included. Keep each `'@` at the very start of its line. Then Publish and redeploy. Every change to the table is a step edit and a redeploy.

### knowledge: skills in AutomationAI Knowledge

1. Paste your settings and engineers into the step as for `inline`, set `$TableSource = 'knowledge'`, and leave `$Skills` as it is (it's ignored).
2. Upload your skills CSV to a folder in AutomationAI **Knowledge**, and wait until it shows as embedded.
3. Select the **Pick the skill** node and ground it on that folder. Grounding is never part of an import, so do this after every import.

The agent searches the CSV, picks the skill and role, and lists the engineers on those rows. The script only assigns someone who is also in the step's engineers table, so a misread or invented name is skipped, never assigned. The trade-off is that the skill itself can't be checked against a table, and an engineer the search doesn't return isn't considered for that ticket. Check a few previews before you set `liveAssign: yes`.

Workflow scripts can't read AutomationAI Knowledge, which is why the engineers and settings stay in the step.

### ucp: publish it as KB articles

For CloudRadial UCP partners. Set `$TableSource = 'ucp'`, add the `CloudRadial-*` and `Routing-CompanyId` secrets, then create two KB articles in **your own (MSP) company** in CloudRadial. The quickest start is to paste the two files in [`kb-articles/`](https://github.com/cloudradial/Automations/tree/main/ticket-routing/kb-articles) and edit them. They look like this:

**Ticket Routing: Engineers and Settings**

```
[Settings]
tieBreak: least-open-tickets
respectMaxOpen: yes
noMatch: leave-unassigned
minConfidence: 0.7
liveAssign: no

[Engineers]
Engineer,Email,PSA User Id,PSA Role Id,Active,Max Open Tickets
"Lee, Jordan",jordan.lee@example.com,jlee,,Yes,25
```

**Ticket Routing: Skills**

```
[Skills]
Skill,Role,Engineer,Skill Description
Network Firewall Fortinet,Tickets,"Patel, Riya","FortiGate policy, VPN and SD-WAN changes"
```

- Paste the CSV as plain text, one row per line. A table works too. Titles and notes above a section are ignored.
- The workflow finds the articles by subject, so keep the subjects exactly as above, or send your own subjects in `skillsArticle` and `engineersArticle`.
- 1,200 rows is fine. The workflow reads the whole table, but the AI only receives the list of skills (about 2,700 tokens for 66 skills with their roles).
- If the table has an error, the workflow assigns nothing and puts the list of errors in its `internal_note`.

> **Keep these articles internal.** They list your engineers and their emails. Publish them only in your own company, never in a client company or in a content package that clients subscribe to.

## Check before publishing

```
./Test-RoutingTable.ps1 -SkillsPath skills.csv -EngineersPath engineers.csv -Psa autotask
```

To check what you actually published, save each article's HTML from the portal and run:

```
./Test-RoutingTable.ps1 -ArticleHtmlPath engineers.html,skills.html -Psa autotask
```

It lists the errors that would stop the workflow (missing PSA ids, names that don't match between the tables, invalid settings) and the warnings, and shows how much of the table the AI sees per ticket. It runs on Windows PowerShell 5.1 and PowerShell 7.
