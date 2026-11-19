#!/usr/bin/env python3
"""Device Health dashboard: 4 token-driven Custom HTML widgets (@DH tokens) for CloudRadial UCP.
Inline styles only (the portal editor strips svg/script/style). Each widget fits ~460px.
Writes widgets.json, tokens.json (demo values) and preview.html."""
import json, re, sys, os

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
F = "font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;"
WRAP = F + "padding:4px 6px;color:#0f1f3d;"
LBL = "font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#64748b;font-weight:600;"
GREEN, AMBER, RED, GREY, BLUE = "#22c55e", "#f59e0b", "#ef4444", "#94a3b8", "#3b82f6"

T = {
 "DHUpdated": "Nov 18, 2026 3:40 PM", "DHSource": "Datto RMM",
 "DHScoreNum": "82", "DHScoreColor": "#14b8a6", "DHScoreLabel": "Good",
 "DHDevices": "13", "DHNoteDevices": "3 sites",
 "DHOnline": "4", "DHNoteOnline": "9 offline",
 "DHPatchPct": "67", "DHNotePatch": "of patchable devices",
 "DHAvPct": "92", "DHNoteAv": "antivirus running",
 "DHReboot": "1", "DHNoteReboot": "need a restart",
 "DHStale": "5", "DHNoteStale": "not seen in 30+ days",
}
patch = [("Full","Fully patched",8,GREEN),("Pend","Approved, pending install",2,BLUE),("Err","Install errors",1,RED),("Rbt","Reboot required",1,AMBER),("None","No patch policy",1,GREY)]
mx = max(v for _,_,v,_ in patch) or 1
for k,_,v,_ in patch:
    T[f"DHPatchN{k}"] = str(v); T[f"DHPatchBar{k}"] = f"{v/mx*100:.0f}"
oss = [("Windows 11", 7), ("Windows 10", 3), ("macOS", 1), ("Other", 2)]
tot = sum(v for _,v in oss)
for i,(n,v) in enumerate(oss,1):
    T[f"DHOsName{i}"] = n; T[f"DHOsN{i}"] = str(v); T[f"DHOsPct{i}"] = f"{v/tot*100:.0f}"
need = [("CONTOSO-LT-014","Patch install errors","Nov 2","High"),("CONTOSO-LT-022","Reboot required","Nov 15","Medium"),
        ("CONTOSO-DT-007","Not seen in 172 days","May 30","Medium"),("CONTOSO-DT-003","Windows 10, end of support","Oct 11, 2024","Low"),
        ("CONTOSO-LT-009","Not seen in 544 days","May 23, 2024","Low"),("","","","")]
SEV = {"High":("#fee2e2","#991b1b"),"Medium":("#fef3c7","#92400e"),"Low":("#e0f2fe","#075985"),"":("#ffffff","#ffffff")}
for i,(n,iss,seen,sev) in enumerate(need,1):
    bg,fg = SEV[sev]
    T.update({f"DHNeedName{i}":n,f"DHNeedIssue{i}":iss,f"DHNeedSeen{i}":seen,f"DHNeedSev{i}":sev,f"DHNeedBg{i}":bg,f"DHNeedFg{i}":fg})
T["DHFixWeek"] = "3"; T["DHFixRate"] = "100"; T["DHFixLast"] = "Nov 18, 3:40 PM"
fixes = [("Nov 18 3:40 PM","CONTOSO-LT-031","Windows Update repair","Success"),("Nov 18 2:15 PM","CONTOSO-LT-031","Google Chrome installed","Success"),
         ("Nov 17 9:02 AM","CONTOSO-LT-018","Windows Update repair","Success"),("","","",""),("","","","")]
RES = {"Success":("#dcfce7","#166534"),"Failed":("#fee2e2","#991b1b"),"Running":("#e0f2fe","#075985"),"":("#ffffff","#ffffff")}
for i,(w,d,a,r) in enumerate(fixes,1):
    bg,fg = RES[r]
    T.update({f"DHFixWhen{i}":w,f"DHFixDev{i}":d,f"DHFixWhat{i}":a,f"DHFixRes{i}":r,f"DHFixBg{i}":bg,f"DHFixFg{i}":fg})

def kpi(label, val, note, color):
    return (f'<div style="background:#ffffff;border:1px solid #e3e8f0;border-radius:12px;padding:9px 12px;'
            f'box-shadow:0 2px 8px rgba(15,31,61,.06);border-top:4px solid {color};"><div style="{LBL}">{label}</div>'
            f'<div style="font-size:22px;font-weight:700;color:#0f1f3d;margin:2px 0 1px;">{val}</div>'
            f'<div style="font-size:12px;color:#64748b;">{note}</div></div>')
kpis = "".join([kpi("Managed devices","@DHDevices","@DHNoteDevices","#0ea5e9"),
                kpi("Online now","@DHOnline","@DHNoteOnline","#22c55e"),
                kpi("Fully patched","@DHPatchPct%","@DHNotePatch","#14b8a6"),
                kpi("Antivirus OK","@DHAvPct%","@DHNoteAv","#8b5cf6"),
                kpi("Reboot pending","@DHReboot","@DHNoteReboot","#f59e0b"),
                kpi("Not checking in","@DHStale","@DHNoteStale","#ef4444")])
w1 = (f'<div style="{WRAP}"><div style="background:linear-gradient(120deg,#0f1f3d 0%,#1e3a8a 55%,#0d9488 100%);border-radius:12px;padding:11px 18px;color:#ffffff;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;">'
      f'<div style="display:flex;align-items:center;gap:14px;"><div style="width:64px;height:64px;border-radius:50%;background:conic-gradient(@DHScoreColor 0% @DHScoreNum%,rgba(255,255,255,.2) @DHScoreNum% 100%);display:flex;align-items:center;justify-content:center;flex:none;"><div style="width:48px;height:48px;border-radius:50%;background:#0f1f3d;display:flex;flex-direction:column;align-items:center;justify-content:center;"><div style="font-size:19px;font-weight:700;line-height:1;">@DHScoreNum</div><div style="font-size:9px;opacity:.8;">@DHScoreLabel</div></div></div>'
      f'<div><div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;opacity:.8;">@CompanyName</div><div style="font-size:22px;font-weight:700;margin-top:2px;">Device Health</div><div style="font-size:12px;opacity:.85;margin-top:2px;">Live from @DHSource</div></div></div>'
      f'<span style="display:inline-block;background:rgba(255,255,255,.16);border:1px solid rgba(255,255,255,.35);padding:5px 11px;border-radius:999px;font-size:11px;font-weight:600;">Updated @DHUpdated</span></div>'
      f'<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:10px;">{kpis}</div></div>')

pbars = "".join(f'<div style="margin:0 0 13px;"><div style="display:flex;justify-content:space-between;font-size:13px;color:#334155;margin-bottom:5px;"><span><span style="display:inline-block;width:10px;height:10px;border-radius:3px;background:{c};margin-right:8px;"></span>{lab}</span><b>@DHPatchN{k}</b></div><div style="height:12px;background:#f1f5f9;border-radius:6px;"><div style="width:@DHPatchBar{k}%;height:12px;background:{c};border-radius:6px;"></div></div></div>' for k,lab,_,c in patch)
osrows = "".join(f'<div style="display:flex;justify-content:space-between;align-items:center;padding:9px 0;border-bottom:1px solid #eef2f7;font-size:13px;"><span style="color:#334155;">@DHOsName{i}</span><span><b style="color:#0f1f3d;">@DHOsN{i}</b> <span style="color:#94a3b8;font-size:11px;">@DHOsPct{i}%</span></span></div>' for i in range(1,5))
w2 = (f'<div style="{WRAP}display:flex;gap:22px;flex-wrap:wrap;"><div style="flex:2;min-width:280px;"><div style="{LBL}margin-bottom:6px;">Patch status by device</div>'
      f'<div style="display:flex;align-items:baseline;gap:8px;margin-bottom:12px;"><span style="font-size:40px;font-weight:800;color:#0f1f3d;line-height:1;">@DHPatchPct%</span><span style="font-size:12px;color:#64748b;">fully patched</span></div>{pbars}</div>'
      f'<div style="flex:1;min-width:180px;border-left:1px solid #eef2f7;padding-left:20px;"><div style="{LBL}margin-bottom:6px;">Operating systems</div>{osrows}</div></div>')

td = "padding:10px 8px;border-bottom:1px solid #eef2f7;"
nrows = "".join(f'<tr><td style="{td}font-weight:600;color:#0f1f3d;">@DHNeedName{i}</td><td style="{td}color:#334155;">@DHNeedIssue{i}</td><td style="{td}color:#64748b;white-space:nowrap;">@DHNeedSeen{i}</td>'
                f'<td style="{td}"><span style="font-size:11px;font-weight:700;padding:3px 9px;border-radius:999px;background:@DHNeedBg{i};color:@DHNeedFg{i};white-space:nowrap;">@DHNeedSev{i}</span></td></tr>' for i in range(1,7))
w3 = (f'<div style="{WRAP}"><div style="{LBL}margin-bottom:6px;">Devices that need attention</div><table style="width:100%;border-collapse:collapse;font-size:13px;"><tbody><tr style="text-align:left;color:#94a3b8;font-size:11px;text-transform:uppercase;letter-spacing:.06em;">'
      f'<th style="padding:4px 8px;">Device</th><th style="padding:4px 8px;">Issue</th><th style="padding:4px 8px;">Last seen</th><th style="padding:4px 8px;">Priority</th></tr>{nrows}</tbody></table></div>')

frows = "".join(f'<tr><td style="{td}color:#64748b;white-space:nowrap;font-size:12px;">@DHFixWhen{i}</td><td style="{td}font-weight:600;color:#0f1f3d;">@DHFixDev{i}</td><td style="{td}color:#334155;">@DHFixWhat{i}</td>'
                f'<td style="{td}"><span style="font-size:11px;font-weight:700;padding:3px 9px;border-radius:999px;background:@DHFixBg{i};color:@DHFixFg{i};white-space:nowrap;">@DHFixRes{i}</span></td></tr>' for i in range(1,6))
tile = lambda lab,val,c: f'<div style="flex:1;background:#f8fafc;border:1px solid #eef2f7;border-left:4px solid {c};border-radius:10px;padding:8px 12px;"><div style="font-size:11px;color:#64748b;">{lab}</div><div style="font-size:20px;font-weight:700;color:#0f1f3d;">{val}</div></div>'
w4 = (f'<div style="{WRAP}"><div style="{LBL}margin-bottom:8px;">Fixed automatically by Datto RMM</div>'
      f'<div style="display:flex;gap:10px;margin-bottom:8px;">{tile("Fixes this week","@DHFixWeek","#22c55e")}{tile("Success rate","@DHFixRate%","#14b8a6")}{tile("Last run","@DHFixLast","#3b82f6")}</div>'
      f'<table style="width:100%;border-collapse:collapse;font-size:13px;"><tbody>{frows}</tbody></table></div>')

widgets = [("Device Health Overview", w1), ("Patch Compliance", w2), ("Needs Attention", w3), ("Automatic Remediation", w4)]
used = sorted(set(re.findall(r"@(DH[A-Za-z0-9]+)", "".join(h for _,h in widgets))))
missing = [u for u in used if u not in T]; assert not missing, missing
names = used + ["CompanyName"]
clash = [(a,b) for a in names for b in names if a != b and b.startswith(a)]; assert not clash, clash
tokens = {u: T[u] for u in used}
os.makedirs(OUT, exist_ok=True)
json.dump([list(w) for w in widgets], open(os.path.join(OUT,"widgets.json"),"w"), indent=1)
json.dump(tokens, open(os.path.join(OUT,"tokens.json"),"w"), indent=1)
def fill(h):
    h = h.replace("@CompanyName","Contoso Ltd")
    return re.sub(r"@(DH[A-Za-z0-9]+)", lambda m: tokens[m.group(1)], h)
cells = "".join(f'<div style="height:460px;background:#fff;border-top:3px solid #1e5aa8;overflow:auto;"><div style="font:11px Segoe UI;text-transform:uppercase;padding:8px 10px;">{t}</div><div style="padding:0 10px 10px;">{fill(h)}</div></div>' for t,h in widgets)
open(os.path.join(OUT,"preview.html"),"w").write(f'<body style="margin:0;background:#f3f4f6;padding:20px;"><div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px;">{cells}</div></body>')
print(len(widgets), "widgets", len(tokens), "tokens", [len(h) for _,h in widgets])
