# Endpoint Reporting

> Warranty status, device inventory, and software audits, all from a chat prompt.

**Say this:**

```
Which of Contoso's devices are out of warranty?
```

<img src="images/skill-result.png" alt="Endpoint inventory in CloudRadial portal" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Warranty report
`Per-company` · `Read-only` · **Tested**

```
Which of Contoso's devices are out of warranty or expire in the next 90 days?
List name, serial, model and expiration date, and list devices with no
warranty date separately.
```

**What you get:** Devices grouped by warranty status.

**Good to know:** A blank warranty date means unknown, not expired.

### Refresh warranty dates
`Per-company` · `Writes to the portal` · **Tested**

```
Refresh warranty for all of Acme Corp's devices. Check for duplicate serial
numbers first and tell me about any before you start.
```

**What you get:** Warranty lookups queued by serial number. New dates appear a few minutes later.

**Good to know:** A serial number on two endpoints (often left over from a deleted company) makes serial-based calls fail. The skill checks first.

### Write a warranty date by hand
`Per-company` · `Writes to the portal` · **Tested**

```
Set the warranty end date on Contoso's laptop with serial ABC123 to 3/31/2027.
Show me the current value first and only save when I confirm.
```

**What you get:** The date saved and read back.

### Software audit
`Per-company` · `Read-only` · **Tested**

```
Show all software installed on Contoso's DC01, with version and install date.
```

**What you get:** Installed applications for one device.

### Device count
`All clients` · `Read-only` · **Tested**

```
How many endpoints does each of my clients have? Split servers, workstations
and virtual machines.
```

**What you get:** Counts by client and type.

## Good to know

- **Warranty refresh is async**: `endpoint_update_warranty` triggers a background fetch; new dates appear minutes later.
- **The warranty tool needs the serial number**, not the endpoint ID. Claude looks up the serial first if needed.
- **`lastCheckIn` matters**: devices that haven't checked in recently may have stale data.

## Related skills

- [Assessment & Compliance](../assessment-compliance): combine with warranty data for GAP analysis.
- [Reporting & Admin](../reporting-admin): for archived endpoint audit reports.
