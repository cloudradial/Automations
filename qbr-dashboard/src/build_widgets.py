#!/usr/bin/env python3
"""QBR dashboard: token-driven widget template for CloudRadial UCP (from the Client Health Dashboard template).

Writes:
  widgets.json  - 4 Custom HTML widgets [title, html] that reference @CH* tokens
  tokens.json   - token name -> demo value (fictitious) for every token used
  preview.html  - widgets rendered with the demo values substituted, 2x2 grid

Usage: python3 build_template.py [out_dir]
Rules the template follows (verified in UCP, Nov 2026):
  - The HTML widget editor strips <svg>, <script> and <style>; inline styles only.
  - Widget size is fixed (2 wide x 3 high, about 460px tall); content must fit.
  - Company tokens (@Name) are replaced at render, in text and inside style values.
"""
import json, re, sys, os

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
F = "font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;"
WRAP = F + "padding:4px 6px;color:#0f1f3d;"
LBL = "font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#64748b;font-weight:600;"
GREEN, AMBER, RED, GREY = "#22c55e", "#f59e0b", "#ef4444", "#94a3b8"

# ---------- demo values (fictitious) ----------
T = {
 "CHPeriod": "November 2026", "CHUpdated": "Nov 13, 2026",
 "CHOpenTickets": "42", "CHNoteOpenTickets": "▼ 12% vs last month",
 "CHSlaPct": "96.4", "CHNoteSla": "▲ 1.8 pts, target 95%",
 "CHCsat": "4.8", "CHNoteCsat": "312 ratings",
 "CHFirstResponse": "14 min", "CHNoteFirstResponse": "▼ 3 min, median",
 "CHEndpoints": "318", "CHNoteEndpoints": "▲ 6 new this month",
 "CHSecureScore": "82", "CHNoteSecureScore": "▲ 4 pts, Microsoft 365",
 "CHHealthScore": "87", "CHHealthService": "92", "CHHealthSecurity": "85",
 "CHHealthLifecycle": "74", "CHHealthAdoption": "88",
}
months = [("Jun",188,181),("Jul",204,199),("Aug",176,183),("Sep",192,195),("Oct",210,214),("Nov*",131,138)]
mx = 240
for i,(m,c,x) in enumerate(months,1):
    T[f"CHTktMonth{i}"]=m; T[f"CHTktCreated{i}"]=str(c); T[f"CHTktClosed{i}"]=str(x)
    T[f"CHTktBarCreated{i}"]=f"{c/mx*100:.0f}"; T[f"CHTktBarClosed{i}"]=f"{x/mx*100:.0f}"
T["CHNoteTickets"]="* month to date"
cats=[("Password / MFA",28),("Hardware",19),("Microsoft 365",17),("Network",12),("Onboarding",11),("Other",13)]
for i,(n,p) in enumerate(cats,1):
    T[f"CHCatName{i}"]=n; T[f"CHCatPct{i}"]=str(p); T[f"CHCatBar{i}"]=f"{p/cats[0][1]*100:.0f}"
proj=[("Windows 11 Rollout","Endpoints",78,"Dec 12","On track"),("Intune Migration","Endpoints",45,"Jan 30","At risk"),
      ("Firewall Refresh","Network",100,"Done","Complete"),("SharePoint Rebuild","Collaboration",22,"Feb 27","On track"),
      ("Backup Modernization","Continuity",61,"Jan 15","On track")]
STATUS={"On track":("#dcfce7","#166534",GREEN),"At risk":("#fef3c7","#92400e",AMBER),"Off track":("#fee2e2","#991b1b",RED),"Complete":("#e0f2fe","#075985","#0ea5e9")}
for i,(n,c,p,d,s) in enumerate(proj,1):
    bg,fg,bar=STATUS[s]
    T.update({f"CHProjName{i}":n,f"CHProjType{i}":c,f"CHProjPct{i}":str(p),f"CHProjDue{i}":d,f"CHProjStatus{i}":s,
              f"CHProjBg{i}":bg,f"CHProjFg{i}":fg,f"CHProjBar{i}":bar})
sec=[("Mfa","MFA enrolled",97),("Patch","Patch compliance",93),("Edr","Antivirus coverage",100),("Backup","Devices checking in",98.7),("Training","Microsoft Secure Score",81),("Phish","Windows 10 (end of support)",4.1)]
for k,_,v in sec:
    T[f"CHSecPct{k}"]=str(v)
    T[f"CHSecColor{k}"]= (RED if v>10 else GREEN) if k=="Phish" else (GREEN if v>=90 else AMBER if v>=75 else RED)
life=[("Current",214,GREEN),("Plan",62,AMBER),("Replace",29,RED),("Oow",13,GREY)]
tot=sum(v for _,v,_ in life)
T["CHLcTotal"]=str(tot); T["CHLcBudget"]="$41,600"
for k,v,_ in life:
    T[f"CHLcCount{k}"]=str(v); T[f"CHLcPct{k}"]=f"{v/tot*100:.0f}"

for k in ["CHHealthService","CHHealthSecurity","CHHealthLifecycle","CHHealthAdoption"]:
    v=float(T[k]); T["CHColor"+k[8:]]= "#16a34a" if v>=80 else "#d97706" if v>=65 else "#dc2626"

# ---------- template (tokens only, no data) ----------
def kpi(label, val, note, color):
    return (f'<div style="background:#ffffff;border:1px solid #e3e8f0;border-radius:12px;padding:9px 12px;'
            f'box-shadow:0 2px 8px rgba(15,31,61,.06);border-top:4px solid {color};"><div style="{LBL}">{label}</div>'
            f'<div style="font-size:22px;font-weight:700;color:#0f1f3d;margin:2px 0 1px;">{val}</div>'
            f'<div style="font-size:12px;color:#64748b;">{note}</div></div>')
kpis="".join([kpi("Tickets This Quarter","@CHOpenTickets","@CHNoteOpenTickets","#3b82f6"),
              kpi("Resolved in 3 Days","@CHSlaPct%","@CHNoteSla","#14b8a6"),
              kpi("CSAT","@CHCsat / 5","@CHNoteCsat","#8b5cf6"),
              kpi("Median Resolve Time","@CHFirstResponse","@CHNoteFirstResponse","#f59e0b"),
              kpi("Managed Endpoints","@CHEndpoints","@CHNoteEndpoints","#0ea5e9"),
              kpi("Secure Score","@CHSecureScore%","@CHNoteSecureScore","#22c55e")])
subs="".join(f'<div style="flex:1;min-width:70px;background:#f8fafc;border:1px solid #eef2f7;border-radius:10px;padding:6px 10px;"><div style="font-size:11px;color:#64748b;">{n}</div><div style="font-size:20px;font-weight:700;color:@CHColor{k[8:]};">@{k}</div></div>'
             for n,k in [("Service","CHHealthService"),("Security","CHHealthSecurity"),("Lifecycle","CHHealthLifecycle"),("Adoption","CHHealthAdoption")])
w1=(f'<div style="{WRAP}"><div style="background:linear-gradient(120deg,#0f1f3d 0%,#1e3a8a 55%,#0d9488 100%);border-radius:12px;padding:11px 18px;color:#ffffff;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;">'
    f'<div><div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;opacity:.8;">@CompanyName</div><div style="font-size:22px;font-weight:700;margin-top:2px;">Quarterly Business Review</div><div style="font-size:12px;opacity:.85;margin-top:2px;">Reporting period: @CHPeriod</div></div>'
    f'<span style="display:inline-block;background:rgba(255,255,255,.16);border:1px solid rgba(255,255,255,.35);padding:5px 11px;border-radius:999px;font-size:11px;font-weight:600;">Updated @CHUpdated</span></div>'
    f'<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:9px;">{kpis}</div>'
    f'<div style="display:flex;align-items:center;gap:12px;margin-top:9px;flex-wrap:wrap;"><div style="width:72px;height:72px;border-radius:50%;background:conic-gradient(#14b8a6 0% @CHHealthScore%,#e2e8f0 @CHHealthScore% 100%);display:flex;align-items:center;justify-content:center;flex:none;"><div style="width:54px;height:54px;border-radius:50%;background:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;"><div style="font-size:22px;font-weight:700;line-height:1;">@CHHealthScore</div><div style="font-size:9px;color:#64748b;">health</div></div></div>'
    f'<div style="{LBL}width:90px;">Overall client health</div>{subs}</div></div>')

BH=200
cols="".join(
  f'<div style="flex:1;display:flex;flex-direction:column;align-items:center;"><div style="display:flex;gap:4px;align-items:flex-end;justify-content:center;width:100%;height:{BH+16}px;">'
  + "".join(f'<div style="display:flex;flex-direction:column;justify-content:flex-end;align-items:center;width:38%;height:100%;"><div style="font-size:10px;color:#475569;margin-bottom:3px;">@CHTkt{s}{i}</div><div style="width:100%;height:@CHTktBar{s}{i}%;max-height:{BH}px;background:{col};border-radius:5px 5px 2px 2px;"></div></div>' for s,col in (("Created","#3b82f6"),("Closed","#14b8a6")))
  + f'</div><div style="font-size:11px;font-weight:600;color:#334155;margin-top:6px;">@CHTktMonth{i}</div></div>' for i in range(1,7))
catbars="".join(f'<div style="margin:0 0 12px;"><div style="display:flex;justify-content:space-between;font-size:12.5px;color:#334155;margin-bottom:4px;"><span>@CHCatName{i}</span><b>@CHCatPct{i}%</b></div><div style="height:10px;background:#f1f5f9;border-radius:5px;"><div style="width:@CHCatBar{i}%;height:10px;background:{c};border-radius:5px;"></div></div></div>'
                for i,c in enumerate(["#3b82f6","#14b8a6","#8b5cf6","#f59e0b","#0ea5e9","#94a3b8"],1))
legend=('<div style="font-size:12px;color:#64748b;margin-top:8px;"><span style="display:inline-block;width:10px;height:10px;border-radius:3px;background:#3b82f6;margin-right:6px;"></span>Created '
        '<span style="display:inline-block;width:10px;height:10px;border-radius:3px;background:#14b8a6;margin:0 6px 0 14px;"></span>Closed <span style="margin-left:14px;">@CHNoteTickets</span></div>')
w2=(f'<div style="{WRAP}display:flex;gap:22px;flex-wrap:wrap;"><div style="flex:2;min-width:300px;"><div style="{LBL}margin-bottom:6px;">Tickets created vs closed</div>'
    f'<div style="display:flex;gap:8px;padding:6px 4px 0;background:repeating-linear-gradient(to top,#ffffff 0,#ffffff 39px,#eef2f7 39px,#eef2f7 40px);">{cols}</div>{legend}</div>'
    f'<div style="flex:1;min-width:200px;border-left:1px solid #eef2f7;padding-left:20px;"><div style="{LBL}margin-bottom:10px;">Top categories</div>{catbars}</div></div>')

td="padding:11px 8px;border-bottom:1px solid #eef2f7;"
prow="".join(f'<tr><td style="{td}"><div style="font-weight:600;color:#0f1f3d;">@CHProjName{i}</div><div style="font-size:11px;color:#94a3b8;">@CHProjType{i}</div></td>'
             f'<td style="{td}width:42%;"><div style="height:8px;background:#eef2f7;border-radius:4px;"><div style="width:@CHProjPct{i}%;height:8px;background:@CHProjBar{i};border-radius:4px;"></div></div></td>'
             f'<td style="{td}font-weight:700;color:#334155;text-align:right;">@CHProjPct{i}%</td><td style="{td}color:#64748b;white-space:nowrap;">@CHProjDue{i}</td>'
             f'<td style="{td}"><span style="font-size:11px;font-weight:700;padding:3px 9px;border-radius:999px;background:@CHProjBg{i};color:@CHProjFg{i};white-space:nowrap;">@CHProjStatus{i}</span></td></tr>' for i in range(1,6))
w3=(f'<div style="{WRAP}"><table style="width:100%;border-collapse:collapse;font-size:13px;"><tbody><tr style="text-align:left;color:#94a3b8;font-size:11px;text-transform:uppercase;letter-spacing:.06em;">'
    f'<th style="padding:4px 8px;">Project</th><th style="padding:4px 8px;">Progress</th><th></th><th style="padding:4px 8px;">Due</th><th style="padding:4px 8px;">Status</th></tr>{prow}</tbody></table></div>')

secbars="".join(f'<div style="margin:0 0 7px;"><div style="display:flex;justify-content:space-between;font-size:12.5px;color:#334155;margin-bottom:5px;"><span>{lab}</span><b>@CHSecPct{k}%</b></div><div style="height:9px;background:#eef2f7;border-radius:5px;"><div style="width:@CHSecPct{k}%;height:9px;background:@CHSecColor{k};border-radius:5px;"></div></div></div>' for k,lab,_ in sec)
stack='<div style="display:flex;height:20px;border-radius:10px;overflow:hidden;margin:6px 0 12px;">'+"".join(f'<div style="width:@CHLcPct{k}%;background:{c};"></div>' for k,_,c in life)+'</div>'
tiles="".join(f'<div style="background:#f8fafc;border:1px solid #eef2f7;border-left:4px solid {c};border-radius:10px;padding:7px 10px;"><div style="font-size:11px;color:#64748b;">{lab}</div><div style="font-size:19px;font-weight:700;color:#0f1f3d;">@CHLcCount{k}</div><div style="font-size:11px;color:#94a3b8;">@CHLcPct{k}% of fleet</div></div>'
              for (k,_,c),lab in zip(life,["Current","Plan refresh","Replace","Unknown OS"]))
w4=(f'<div style="{WRAP}display:flex;gap:20px;flex-wrap:wrap;"><div style="flex:1;min-width:240px;"><div style="{LBL}margin-bottom:10px;">Security posture</div>{secbars}</div>'
    f'<div style="flex:1;min-width:240px;border-left:1px solid #eef2f7;padding-left:20px;"><div style="{LBL}margin-bottom:4px;">Endpoint lifecycle</div>'
    f'<div style="display:flex;justify-content:space-between;align-items:baseline;"><div><span style="font-size:26px;font-weight:700;">@CHLcTotal</span> <span style="font-size:12px;color:#64748b;">devices</span></div><div style="font-size:11px;color:#64748b;">Est. refresh budget <b style="color:#0f1f3d;">@CHLcBudget</b></div></div>'
    f'{stack}<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">{tiles}</div></div></div>')

widgets=[("QBR Overview",w1),("Ticket Volume, Last 6 Months",w2),("Projects",w3),("Security and Device Lifecycle",w4)]

used=sorted(set(re.findall(r"@(CH[A-Za-z0-9]+)", "".join(h for _,h in widgets))))
missing=[u for u in used if u not in T]
assert not missing, missing
allnames=used+["CompanyName"]
clash=[(a,b) for a in allnames for b in allnames if a!=b and b.startswith(a)]
assert not clash, clash
tokens={u:T[u] for u in used}
os.makedirs(OUT, exist_ok=True)
json.dump([list(w) for w in widgets], open(os.path.join(OUT,"widgets.json"),"w"), indent=1)
json.dump(tokens, open(os.path.join(OUT,"tokens.json"),"w"), indent=1)

def fill(h):
    h=h.replace("@CompanyName","Contoso Ltd")
    return re.sub(r"@(CH[A-Za-z0-9]+)", lambda m: tokens[m.group(1)], h)
cells="".join(f'<div style="height:460px;background:#fff;border-top:3px solid #1e5aa8;overflow:auto;"><div style="font:11px Segoe UI;text-transform:uppercase;padding:8px 10px;">{t}</div><div style="padding:0 10px 10px;">{fill(h)}</div></div>' for t,h in widgets)
open(os.path.join(OUT,"preview.html"),"w").write(f'<body style="margin:0;background:#f3f4f6;padding:20px;"><div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px;">{cells}</div></body>')
print(f"{len(widgets)} widgets, {len(tokens)} tokens, sizes {[len(h) for _,h in widgets]}")
