---
name: access-control
description: "Manage who can do what in CloudRadial portals: security roles, role assignments, feature sets (which portal sections a company sees), user support PINs, and Signal client installs. Use when the user says \"security roles\", \"create a role\", \"give [user] the [role] role\", \"who has admin\", \"role assignments\", \"remove access\", \"feature set\", \"hide [section] from [company]\", \"which companies use feature set\", \"support PIN\", \"reset Signal on [device]\", \"revoke a Signal device\", \"Signal fleet\", or is auditing or changing portal access.\n"
metadata:
  version: "1.0.0"
---

# Access Control

Roles, role assignments, feature sets, support PINs and Signal installs decide who can see and do
what in client portals. Every change here is a security change, so the plugin's tools refuse to write
until the user has seen the exact change and you pass `confirmed: true`.

## Before any tool call

Call `setup_status` first. If it returns `configured: false`, defer to the `setup` skill.

## The confirmation rule

1. Read the current state first (the role, the user's assignments, the feature set's companies).
2. Call the write **without** `confirmed`. The tools return a preview (`changed: false`) or refuse with
   a message saying what's needed. Nothing changes.
3. Show the user exactly what will change: who, what, where, and what they lose or gain.
4. Only after an explicit yes, call again with `confirmed: true`.

Never batch several access changes behind one yes unless the user approved the whole list.

## Roles

Client roles control what portal users can see and do, module by module.

- **List:** `list_resources` with `resource_type: "role"` (no OData; `params` if needed). Read one with
  `get_resource`. Fields: `roleId` (a string), `name`, `description`, `isDefault`, `ticketPermission`,
  `claims` (one per module), `isProtected`, `isSystem`, `isPartnerRole`, `isCompanyAdminRole`,
  `protectionReason`, `hasUsers`.
- **Create:** `create_resource`, `resource_type: "role"`, `data: { name, description, isDefault,
  ticketPermission, claims: [{ module, permission }] }`, `confirmed: true`.
  - `ticketPermission`: 0 own tickets, 100 their site, 200 their company, 300 their company group.
  - `permission`: 0 None, 10000 Read, 20000 Edit, 25000 Delete, 30000 Full.
  - `module` codes are numbers (for example 100000 Home, 350000 Support_Tickets, 410000
    University_Courses). Copy them from an existing role's `claims` rather than guessing.
  - A new role also gets Full on Home, as in the portal. The API refuses partner-level modules or
    Full (30000) on a company module for a client role (400), and refuses a new role when the
    partner's plan allows no more (403).
- **Edit:** `update_resource` (PATCH, `confirmed: true`). Listed modules are set; unlisted modules keep
  their permission; set a module to 0 to remove access. Protected and system roles can't be changed;
  say so using `protectionReason`.
- **Delete:** `delete_resource` with `confirmed: true`. Check `hasUsers` first and tell the user who
  would lose the role.

## Role assignments

An assignment gives a user a role in a scope: one company, a company group, or the partner (every
client company).

- **List:** `access_control` with `action: "list_assignments"` and any of `user_id`, `role_id`,
  `company_id`, `company_group_id` (paged with `page`, `page_size`).
- **Assign:** `access_control` `action: "assign_role"` with `role_id`, `user_id`, `scope`
  (`company`, `company_group` or `partner`) and `scope_id`. The preview names the role and warns when
  the scope is the whole partner.
- **Remove:** `access_control` `action: "remove_assignment"` with `assignment_id`.
- Assignments can't be edited: remove and assign again.
- Assignments from Microsoft 365 groups or legacy user groups show a `memberType` other than 1 and an
  `m365GroupId` or `userGroupId`. Change those at the source, not here.

## Feature sets

A feature set decides which portal sidebar sections a company's users see.

- **List / read:** `list_resources` / `get_resource` with `resource_type: "feature_set"`. Fields:
  `featureSetId`, `name`, `home`, `removed` (hidden sidebar items), `isMenus`, `isDefault`,
  `companyCount`.
- **Create / edit / delete:** the generic tools with `confirmed: true`. `removed` lists the sidebar
  items to hide (numbers; copy them from an existing set). Leave `removed` out to keep the current list;
  `[]` shows everything.
- **Which companies use it:** `access_control` `action: "feature_set_companies"`.
- **Change its companies:** `access_control` `action: "set_feature_set_companies"` with the
  **complete** new list. The preview shows which companies are added and removed; removed companies
  fall back to the default feature set.

## Support PINs

A user's support PIN is what your help desk uses to verify a caller. `access_control`
`action: "set_support_pin"` with `user_id`, `company_id` and `support_pin`. The PIN is never echoed back
and can't be read through the API. Don't repeat the PIN in your reply.

## Signal client installs

- `signal_device` `action: "list"`: every install, most recently seen first, revoked ones included;
  filter on its state for the live fleet. `action: "fleet_stats"` for totals.
- `rebootstrap`: a one-shot reset. The install signs out and clears cached credentials and notices;
  someone has to sign in on that device again.
- `revoke`: permanent sign-out until `unrevoke`. Use for a lost or stolen device.
- All three need `confirmed: true`; without it the tool returns the device and what will happen.

## Access review workflow

When asked "who has admin" or for an access review of a company:

1. `list_resources` on `role` to get role names and which are admin roles (`isCompanyAdminRole`).
2. `access_control` `list_assignments` with `company_id` (page through all of them).
3. Resolve user names with `user_lookup` by `company_id`.
4. Present one row per user: name, email, role, scope, and flag partner-scope assignments and any
   user holding an admin role. Read-only: change nothing unless asked.

## Report honestly

Say exactly what changed and for whom. If the API refused a change (400 partner-level module, 403
role limit, protected role), quote its reason and don't retry with a workaround.
