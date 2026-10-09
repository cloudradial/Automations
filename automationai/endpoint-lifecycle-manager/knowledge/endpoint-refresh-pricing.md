# Endpoint Refresh Pricing

Owner: vCIO / Lifecycle · Effective: 2026-10-09 · Used by: Endpoint LifeCycle Manager

> **These are example prices.** Replace them with your own approved models, parts and labour rate. Today the workflow reads pricing from its run input, not from this file: copy the [Run input](#run-input) block below into the workflow's Routine input. Keep this file and the Routine input in step. This file is laid out for Knowledge, so an agent can read it once workflows and agents can use Knowledge for pricing. Keep the headings and the setting names, because the agent searches by them.

## Pricing settings

| Setting | Example | What it controls |
|---|---|---|
| `currency` | USD | Only sets the symbol on cards: `USD`, `CAD`, `AUD` and `NZD` show $, `GBP` shows £, `EUR` shows €. |
| `hourlyRate` | 150 | Your labour rate per hour. Labour hours are multiplied by this. |
| `showPriceToClient` | true | `true` lets clients see the price on a card once it's Completed. `false` keeps prices internal. Your cost is never shown to clients either way. |

## Replacement models

Used on the **Replace** and **Plan replacement** cards. Each computer is priced at the approved model for its type.

| Device type | Model | Price | Cost |
|---|---|---|---|
| Windows laptop | Dell Latitude 7450 | 1450 | 1180 |
| Windows desktop | Dell OptiPlex 7020 | 1050 | 850 |
| Mac laptop | MacBook Air 13 M4 | 1299 | 1150 |
| Mac desktop | Mac mini M4 | 799 | 700 |
| Windows | Standard Windows PC | 1250 | 1000 |
| Mac | Standard Mac | 1299 | 1150 |

- **Device type** comes from the Mac model name, then the endpoint's enclosure, then whether it reports a battery.
- **Windows** and **Mac** are fallbacks for computers whose laptop or desktop type isn't recorded.
- A computer with no matching model is listed as not priced and left out of the total.

## Upgrade and repair parts

Used on the **Upgrade in place**, **Retain** and **Human review** (servers) cards. Each computer gets only the parts its data shows it needs.

| Part | Price | Cost | When a computer needs it |
|---|---|---|---|
| RAM upgrade | 120 | 80 | Memory is recorded and below 7.5 GB. A nominal 8 GB computer reports about 7.8 GB, so it doesn't count. |
| SSD upgrade | 180 | 110 | The endpoint reports no SSD, in a company where at least one endpoint reports an SSD. Servers never get this part. |
| Warranty extension | 250 | 190 | The warranty has expired or ends within 90 days. |

- These are the only part names the workflow can match. Other names are ignored with a warning.
- A part a computer needs but that has no price is listed as not priced and left out of the total.

## Labour hours

Labour is the hours below multiplied by `hourlyRate`.

| Applies to | Hours | How it's counted |
|---|---|---|
| Upgrade in place | 2 | Per computer on the card. |
| Retain | 1 | Per computer on the card. |
| Human review | 2 | Per server on the card. |
| Virtual machines | 1 | Per virtual machine on the card. Virtual machines get labour only, no parts. |
| RAM upgrade | 0.5 | Each time the part is fitted. |
| SSD upgrade | 1 | Each time the part is fitted. |

## What each card shows

- **Replace and Plan replacement:** the model, quantity and price for each device type, and the total. The card's project cost is the models' cost.
- **Upgrade in place, Retain and Human review:** each part with its quantity and price, the labour hours at your rate, and the total. The project cost is the parts' cost; labour cost isn't included. Software and licences are quoted after a technician has checked each device.
- **Virtual machines:** labour only.
- **Needs data:** no price.
- If nothing on an upgrade or repair card can be priced, the card says labour is billed at your hourly rate and that parts, software and licences will be quoted.
- Clients see a card's price only once the card is Completed, and only when `showPriceToClient` is `true`. The cost stays in the card's internal cost field and internal note.

## Run input

Paste this into the workflow's Routine input, with your own values. It matches the tables above. Add `"companyIds"` or `"mode"` alongside `"pricing"` as needed.

```json
{
  "pricing": {
    "currency": "USD",
    "hourlyRate": 150,
    "showPriceToClient": true,
    "models": {
      "Windows laptop":  { "model": "Dell Latitude 7450", "price": 1450, "cost": 1180 },
      "Windows desktop": { "model": "Dell OptiPlex 7020", "price": 1050, "cost": 850 },
      "Mac laptop":      { "model": "MacBook Air 13 M4", "price": 1299, "cost": 1150 },
      "Mac desktop":     { "model": "Mac mini M4", "price": 799, "cost": 700 },
      "Windows":         { "model": "Standard Windows PC", "price": 1250, "cost": 1000 },
      "Mac":             { "model": "Standard Mac", "price": 1299, "cost": 1150 }
    },
    "parts": {
      "RAM upgrade":        { "price": 120, "cost": 80 },
      "SSD upgrade":        { "price": 180, "cost": 110 },
      "Warranty extension": { "price": 250, "cost": 190 }
    },
    "labourHours": {
      "Upgrade in place": 2,
      "Retain": 1,
      "Human review": 2,
      "Virtual machines": 1,
      "RAM upgrade": 0.5,
      "SSD upgrade": 1
    }
  }
}
```

Include `pricing` on every run. Prices aren't remembered between runs, so a run without it leaves new cards unpriced.
