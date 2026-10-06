# Assessment Export — API Details

Concrete query patterns for the `cloudradial-ucp` MCP server. All OData params are passed **without**
the leading `$` (the server adds it). Default page `top=100`, max `200`.

## 1. Count completed assessments (all companies)

```
count_resources
  resource_type: "assessment"
  filter: "dateCompleted ne null"
```

If `dateCompleted ne null` is rejected, fall back to:

```
count_resources
  resource_type: "assessment"
  filter: "status eq 'Completed'"
```

## 2. List completed assessments across every company (paged)

Page 1:

```
list_resources
  resource_type: "assessment"
  filter: "dateCompleted ne null"
  select: "assessmentId,companyId,name,status,score,dateCompleted"
  orderby: "dateCompleted desc"
  top: 200
```

Page 2, 3, ...: repeat with `skip: 200`, `skip: 400`, ... until a page returns < 200 rows.

Do **not** add a `companyId` filter — omitting it is what makes the result span all customers.

## 3. Scope to a date range (e.g. this quarter)

```
filter: "dateCompleted ge 2026-04-01T00:00:00Z and dateCompleted le 2026-06-30T23:59:59Z"
```

Combine with a status/non-null check as needed. If the API rejects combined filters, pull the
`orderby dateCompleted desc` set and filter client-side.

## 4. Build the companyId -> name map

```
list_resources
  resource_type: "company"
  select: "companyId,name"
  top: 200
```

Page with `skip` as above. For a single known customer instead:

```
search_companies
  name: "Effortless Office"
```

## 5. Probe for question-level detail

The `assessment` list resource is summary-level only. To look for per-question data, inspect the
raw API. Start broad and read the returned shape before depending on it:

```
raw_api_call
  method: "GET"
  path: "/v2/odata/assessment"
  query: { "$top": 1 }
```

Then probe run/question-oriented paths that may exist in the portal's API surface (names vary by
version — inspect what each returns; a 404 means that path is not available):

```
raw_api_call  method: "GET"  path: "/v2/odata/assessmentRun"        query: { "$top": 1 }
raw_api_call  method: "GET"  path: "/v2/odata/assessmentQuestion"   query: { "$top": 1 }
```

If none return question/response/score fields, question-level data is not available via the API in
this portal — use the portal per-run Excel export or Word report instead, and say so.

## 6. Scoring reference (for gap counting)

+2 Compliant · +1 Partially Compliant · 0 N/A · -1 Missing · -2 Not Compliant. Negative = gap.

## Notes / caveats

- Exact `raw_api_call` paths and whether a question-level endpoint exists were not live-verified
  when this skill was written; the summary `assessment` resource fields are documented and reliable.
  Probe with `raw_api_call` and adapt to what the portal actually returns.
- Public API/developer docs: https://developers.cloudradial.com
- Portal reporting reference:
  https://support.cloudradial.com/hc/en-us/articles/360054632252-Running-and-Using-Assessment-Reports
