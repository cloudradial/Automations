# Mapping Competitor Maturity Scores to CloudRadial

How to answer "what's our DMI?" without inventing a number.

## The competitor scores

### ScalePad Lifecycle Manager X — Digital Maturity Index

An opaque proprietary **300 to 850 "credit rating"** scale, higher is better,
deliberately not a transparent percentage. Scorecards add partner-defined health-scored
items, some auto-created from Lifecycle Manager data. ScalePad also pipes Microsoft
Secure Score straight into QBR deliverables.

The published band thresholds are not available. **Do not invent a
percentage-to-DMI conversion table.** If a partner wants a numeric equivalence, tell
them the mapping cannot be derived from published information.

### myITprocess

Weighted attainment: `report % = Σ(priority weight × answer %) / Σ(priority weight)`.
Priority High/Med/Low maps to 5/3/1. Answer Aligned/Marginal/Highly Vulnerable maps to
100/50/0. Human-answered standards, no auto-telemetry. The closest prior art to
CloudRadial's direction.

### vCIOToolbox

Three MSP-selectable models per template: AVGAVG (best-practice weighted average),
STANDARD-BPVR (each topic starts at 100, subtract a weight per negative answer, average
topics), AVGALLPOINTS (risk-only weighted average).

### Microsoft Secure Score (adjacent benchmark)

`points achieved / max achievable`, per-action risk-weighted, with partial credit and
peer benchmarking.

## What CloudRadial actually has

There is **no single maturity index**. There are two scores, running in opposite
directions, and the roll-up that would unify them is not built.

### Assessment score — the honest analog

Answers map to fixed weights via `AssessmentValueType`:

| Answer | Weight |
|---|---|
| Compliant | +2 |
| PartiallyCompliant | +1 |
| NA | 0 |
| Missing | −1 |
| NotCompliant | −2 |

Every non-NA question adds 2 to `maxScore`. NA questions leave the denominator
entirely. `totalScore / maxScore` produces the "X out of Y" posture number.

Read these off the assessment record: `compliantScore`, `partialScore`, `totalScore`,
`maxScore`.

**Negative totals are real.** A live portal returns rows like
`totalScore: -426, maxScore: 852`. Whether the UI floors the display at zero is not
documented. Check before explaining a negative number to a partner.

No per-question weighting, no category weighting, and no band thresholds exist. Band
thresholds are an open design item, not a shipped feature.

### Assessment runs give the trend

`POST /api/assessments/run` clones the assessment and its answers into a frozen
`Assessment_Run` row, stamps `dateConducted`, and computes `dateNextDue` from
`scheduleInterval`.

Critical caveat: **nothing enforces the cadence.** No background job generates the next
run or notifies anyone. The interval field is labelled "Recommended Interval" in the UI,
which is honest about what it is. A red overdue date is the entire mechanism. Tell
partners to calendar it.

Runs compare across the last four and export to XLSX. That comparison is the
quarter-over-quarter trend a DMI is actually used for.

### Policy risk score — opposite polarity

Computed on read, not written by the scan:

```
fails = TotalItems - ComplianceCount - Allowance

RiskScore = ScoringMethod == Any
    ? (fails <= 0 ? 0 : ScoreOccurence)   // flat score if anything fails
    : (fails * ScoreOccurence)            // score × number of failing items
```

Summed across a company's policies. **Higher is worse**, the inverse of the assessment
score. Banding today is a digit-length heuristic on the string form of the number:
3+ digits red, 2 digits orange, otherwise green.

A proper 0 to 100 posture roll-up does **not** exist. It is net-new work.

## The polarity problem

Assessments: higher is better. Policies: higher is worse. A blended client-facing
"Compliance score" combining both is a draft design decision, **not shipped**.

Never present a single blended posture number as available today.

## What to say to a partner

Lead with the assessment percentage, run quarterly, and show the trend across runs.

The differentiator is **explainability**, not the number itself. Every DMI point is a
black box. Every CloudRadial assessment point traces to a named question, and where the
partner filled in the question's remediation profile (`riskCost`, `riskImpact`,
`likelihood`, monthly and project unit pricing, optional catalog `productId`), it also
traces to a priced line of work.

That is the loop worth demonstrating:

```
Assessment question answered NotCompliant
  → Estimate of Work report prices the remediation
  → Add to Planner creates the plan item
  → Account Plan module renders it in the client deliverable
```

Score to recommendation to budget to report, with every hop visible. A DMI cannot show
its working.

## Do not claim

- A 300–850 equivalent, or any conversion between the two scales
- A blended policies-plus-assessments posture number
- A 0 to 100 policy score
- Enforced assessment recurrence
- Defined band thresholds or severity labels for either score
