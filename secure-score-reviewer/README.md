# Keep a Client's Microsoft Secure Score Climbing

A standing security assistant for one client. Each week it reviews the client's Microsoft Secure Score, shows where the points are being lost, keeps the client's CloudRadial Planner and a Secure Score record up to date, and proposes the fixes it can make safely. You approve or deny each change, and once a kind of fix has a clean record it asks whether it can do that kind on its own.

## What your clients see in the portal

- **One Planner card per open improvement action**, for the actions worth the most points: why it matters in plain language, the points available, who it affects, the evidence and the steps to fix it. Cards close when the action reaches full points.
- **A "Microsoft Secure Score" record** with today's score, the change since last time, how the client compares with similar-size organisations, and the top 3 gaps.
- **A short monthly Secure Score report** in Report Archives (admin-only).

## What happens behind the scenes

- It reads the score and improvement actions, and only the evidence it needs: who isn't set up for MFA, high-risk users and Conditional Access policies.
- It ranks the gaps by points missing, then by how little they disrupt users, so quick wins come first.
- It proposes only three kinds of fix: adding people who aren't MFA-ready to your MFA group, signing out a high-risk user everywhere, and disabling an account nobody has used in 90 days.
- It never proposes Conditional Access changes, tenant-wide settings, licence changes, password resets, deletions or anything that affects everyone at once. Those stay as recommendations on the Planner card.
- Nothing changes until someone approves it. When you deny a fix, it remembers why and doesn't propose it that way again.

## Works with

Microsoft 365 and the CloudRadial portal. One Pulsar per client.

## What you need

- AutomationAI with Pulsars, and a runner with an AI provider
- **The Microsoft 365 Security Posture extension (`microsoft-365-security`).** This is a custom extension and isn't in the catalog yet, so it must be installed on your runner before this works. It reads the client's tenant with an app registration that has SecurityEvents.Read.All (Policy.Read.All, AuditLog.Read.All and IdentityRiskyUser.Read.All add evidence).
- The catalog extensions Microsoft Entra ID, CloudRadial v2 Services, CloudRadial v2 Compliance and CloudRadial v2 Feedback, installed and working on the same runner
- A filled-in **Secure Score Settings** document for each client: the Planner category, your MFA group and any accepted risks

## Set it up

**1. Add the agent and your settings.**

1. **Download** the agent and workflow from the [release](https://github.com/cloudradial/Automations/releases/tag/secure-score-reviewer/v0.2.0), and upload the agent on **Agents > Custom**.
2. Fill in the **Secure Score Settings** template for the client: its CloudRadial company id, your Planner product category id, your MFA enforcement group, service accounts to leave alone and any accepted-risk controls.
3. In **Knowledge**, create a folder called **Secure Score - Contoso** (use the client's name) and upload the document to it.

**2. Create the Pulsar.** Go to **Pulsars > New Pulsar** and answer the five questions:

1. **Who's doing the work?**
   - **Agent:** Microsoft Secure Score Reviewer
   - **Runner:** the runner where the extensions and the client's Microsoft 365 secrets work.
   - **Name:** Secure Score - Contoso
2. **What's the goal?** `Raise and keep Contoso's Microsoft Secure Score high (CloudRadial companyId 12): review it each week, keep its Planner cards and Secure Score record current, and propose safe fixes for the improvement actions worth the most points.` Use the client's name and company id.
   - **How will we know it's done?** Leave it blank. This Pulsar keeps running.
3. **When should it check in?** **On a schedule**, **Every week**, Monday morning.
4. **How much can it do on its own?** **Propose changes** (the default). Later, when it asks to take over a kind of fix, an Admin or Owner can switch to **Act on approved kinds** and name only that tool.
5. **Where does it keep notes?** **An existing Knowledge folder:** **Secure Score - Contoso**, the folder with the settings document.

**3. Limits and who hears from it.**

- **Limits:** start with a per-check-in limit of about 150,000 tokens and the default monthly limit. Leave the finish rules off.
- **Who should hear from it?** You, plus every Admin and Owner, by default. Turn on **Also post to Teams channels** if your security team works there.

**4. Test it.** Click **Save draft**, then **Try a check-in now**. Check the score matches the Microsoft Defender portal, the proposed Planner cards read well, and every fix names its users and points. Deny anything you don't want, then click **Start**.

**On demand:** the agent also comes with a small workflow, **Microsoft Secure Score Review**, that runs one check-in when you click **Run** with `{"companyId": 12}`, with the same approvals.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/secure-score-reviewer#technical-details) for the tools it uses, its limits per check-in and how to build and test it.

---

## Technical details

**Marketplace ID:** AAI-00097 | **Type:** Pulsar (custom agent plus a goal workflow) | **Version:** 0.2.0

## Files

Each version is published as a release, with the agent and the goal workflow attached. Download them from the [**release**](https://github.com/cloudradial/Automations/releases/tag/secure-score-reviewer/v0.2.0).

| What | Link |
|---|---|
| Download the agent and workflow | [Release](https://github.com/cloudradial/Automations/releases/tag/secure-score-reviewer/v0.2.0) |
| Agent | [`secure-score-reviewer.agent.yml`](https://github.com/cloudradial/Automations/blob/main/secure-score-reviewer/secure-score-reviewer.agent.yml) |
| Goal workflow | [`secure-score-reviewer.yml`](https://github.com/cloudradial/Automations/blob/main/secure-score-reviewer/secure-score-reviewer.yml) |
| Knowledge template | [knowledge/](https://github.com/cloudradial/Automations/tree/main/secure-score-reviewer/knowledge) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/secure-score-reviewer/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/secure-score-reviewer) |

## Release blocker: the `microsoft-365-security` extension

The score, controls, MFA registration, risky users and Conditional Access reads come from `microsoft-365-security` 0.1.0, a **custom** extension (6 read-only tools: `m365sec_get_secure_score`, `m365sec_list_secure_score_controls`, `m365sec_list_auth_method_registration`, `m365sec_list_risky_users`, `m365sec_list_conditional_access_policies`, `m365sec_list_security_alerts`; secrets `M365-TenantID`, `M365-ClientID`, `M365-ClientSecret`). It has to reach the catalog through a Linear issue to Pablo before this agent can be listed.

## How it works

| Step | What the agent does |
|---|---|
| **Read** | Turn 1 in parallel: today's score (`m365sec_get_secure_score`, top 1, or top 30 monthly), the improvement actions (`m365sec_list_secure_score_controls`), the existing "Secure Score - " Planner cards (`cr_list_product`) and the asset type (`cr_list_flexible_asset_type`). Turn 2, only for the top gaps: MFA registration, risky users, Conditional Access, MFA group members. |
| **Rank** | Points missing, then low user impact, then low implementation cost. Accepted-risk controls are skipped. |
| **Report** | At most 10 Planner card writes (`cr_create_product`, `cr_patch_product`), the "Microsoft Secure Score" flexible asset (`cr_patch_flexible_asset`, `cr_create_flexible_asset`, and `cr_create_flexible_asset_type` once), and a monthly `cr_create_archive_item` in the "Security Reports" folder. |
| **Fix** | At most 5 proposals, 25 users each: `entra_add_group_member` (MFA group), `entra_revoke_sign_in_sessions` (high-risk user), `entra_disable_account` (inactive 90 days). |
| **Learn** | A tally per kind of fix in its notes. After 5 approvals in a row with no denial, it asks whether it may run that kind without asking. |

**Budget:** about 15 tool calls a check-in, never more than 20, inside the runner's 25-turn limit.

### Agent settings

- `model` is blank, so it uses the runner's provider. The prompt opens with the one-sentence-before-each-tool-call rule, so Anthropic never gets an empty message.
- `requiredExtensionSlugs`: `microsoft-365-security`, `microsoft-entra-id`, `cloudradial-v2-services`, `cloudradial-v2-compliance`, `cloudradial-v2-feedback`. That is 112 tools in total, under OpenAI's 128-tool limit.
- `dryRunDefault` is true. The goal workflow's agent node has `autoApprove: false`, `allowedExtensions` set to the same five extensions, and its webhook ships off.

### Changes from 0.1.0

- **Extensions:** 0.1.0 also required `microsoft-365` and `cloudradial-v2-companies`, 197 tools in all, which OpenAI rejects. Both are dropped. So the "require MFA re-registration" fix (`m365_reset_mfa`) is no longer proposed; it stays a recommendation on the card.
- **Prompt:** the empty-message rule, a budget line, named tools for each step, defaults for missing settings (it asks rather than invent a category id), and the Report Archives folder rule.
- **Settings:** a Secure Score Settings knowledge template.

### Not yet proven live

0.1.0 was saved as a Pulsar draft in a test tenant but never ran a check-in. Whether documents in the notes folder are read at every check-in (the support article says recent notes are) is also unproven; without them it asks for the Planner category id.

## Build and test

Edit `src/prompt.md`, `src/build.js` or `src/tools-snapshot.json`. Never edit the generated `.yml` files.

```
node secure-score-reviewer/src/build.js
node secure-score-reviewer/src/test.js
```

`test.js` checks that both files parse (and every embedded JSON string), the marker, slug and version, a blank model, the empty-message rule, that every tool the prompt names is in the snapshot and every write is an allowed proposal, the total tool count, `autoApprove: false`, the webhook off, no dashes, the README setup questions, and that the generated files are current.
