# Assessment Export — API Details

Concrete query patterns for the `cloudradial-ucp` MCP server. All OData params are passed **without**
the leading `$` (the server adds it). Default page `top=100`, max `200`. The API returns no next-page
link: keep paging until a page comes back shorter than `top`.

Assessment rows use `title` (not `name`), `dateConducted` (not `dateCompleted`) and `totalScore`,
`maxScore`, `compliantScore`, `partialScore` (nullable numbers; blank until the assessment is scored). There is no `score`
field. `type` is 10 for a template, 20 for an assessment (the only type the portal lists) and 30 for
a run. `status` is a plain integer with undocumented codes, so don't filter on it server-side.

**Never pass `select` on `assessment`:** `$select=assessmentId,title` returned HTTP 500 in live
testing. Pull whole rows and keep the fields you need.

## 1. Count completed runs (all companies)

```
count_resources
  resource_type: "assessment"
  filter: "type eq 30 and dateConducted ne null"
```

If the date filter is rejected, count `type eq 30` and drop rows without `dateConducted` after
listing them. For the portal's view (one row per assessment), use `type eq 20` instead.

## 2. List completed runs across every company (paged)

Page 1:

```
list_resources
  resource_type: "assessment"
  filter: "type eq 30 and dateConducted ne null"
  orderby: "dateConducted desc"
  top: 200
```

Page 2, 3, ...: repeat with `skip: 200`, `skip: 400`, ... until a page returns < 200 rows.

Do **not** add a `companyId` filter — omitting it is what makes the result span all customers.

## 3. Scope to a date range (e.g. this quarter)

Add a date range to the filter, for example
`type eq 30 and dateConducted ge 2026-04-01T00:00:00Z and dateConducted le 2026-06-30T23:59:59Z`.
If the API rejects the combined filter, pull the `orderby: "dateConducted desc"` set and filter
client-side, stopping once rows fall before the start of the range.

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
  name: "Contoso"
```

## 5. Question-level detail

The API has no question-level data. Its metadata has no assessment question, answer or run entity
(`/v2/odata/assessmentRun` and `/v2/odata/assessmentQuestion` don't exist), and `assessment` rows
are summary-level only. For per-question responses, use the portal's per-run Excel export or Word
report, and say so.

## 6. Scoring reference (for gap counting)

+2 Compliant · +1 Partially Compliant · 0 N/A · -1 Missing · -2 Not Compliant. Negative = gap.

## Notes / caveats

- The `type` codes come from live data, not the API documentation.
- Public API/developer docs: https://developers.cloudradial.com
- Portal reporting reference:
  https://support.cloudradial.com/hc/en-us/articles/360054632252-Running-and-Using-Assessment-Reports
