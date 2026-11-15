"""Build perf/dashboard.html from perf/history.jsonl (docs/perf-plan-1.6.1.md). One self-contained file, no server:

    python tools/perf/perf_dashboard.py            (perf_report.py runs it after every suite)

Shows, for the chosen test and metric: frame time per suite (race active vs the mod idle), the latest against the
baseline, each A/B comparison with its verdict (inside the spread between pairs = "no change", grey), where the frame
goes, the Earth Rally hooks by worst time, and a frame trace of any capture."""
import json
import os
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
HISTORY = os.path.join(REPO, "perf", "history.jsonl")
OUT = os.path.join(REPO, "perf", "dashboard.html")


def med(xs):
    xs = [x for x in xs if x is not None]
    return round(statistics.median(xs), 2) if xs else None


def comparisons(rows):
    """Per suite: each (test, switch) group, every value against the first one seen (the base)."""
    out = []
    by_suite = {}
    for r in rows:
        by_suite.setdefault(r["suite"], []).append(r)
    for suite, rs in by_suite.items():
        groups = {}
        for r in rs:
            groups.setdefault((r.get("test"), r.get("switch") or "-"), {}).setdefault(json.dumps(r.get("value")), []).append(r)
        for (test, sw), vals in groups.items():
            items = list(vals.items())
            if len(items) < 2:
                continue
            bv, base = items[0]
            bp99 = med(x["p99"] for x in base)
            bsp = (max(x["p99"] for x in base) - min(x["p99"] for x in base)) if len(base) > 1 else None
            for v, xs in items[1:]:
                p99 = med(x["p99"] for x in xs)
                sp = (max(x["p99"] for x in xs) - min(x["p99"] for x in xs)) if len(xs) > 1 else None
                noise = max([s for s in (bsp, sp) if s is not None] or [0])
                d = round(p99 - bp99, 2)
                verdict = "nochange" if noise and abs(d) <= noise else ("single" if len(xs) < 2 else (
                    "faster" if d < 0 else "slower"))
                out.append({"suite": suite, "label": rs[0].get("label"), "test": test, "switch": sw,
                            "base": json.loads(bv), "value": json.loads(v), "baseP99": bp99, "p99": p99,
                            "baseP50": med(x["p50"] for x in base), "p50": med(x["p50"] for x in xs),
                            "d": d, "noise": round(noise, 2), "n": len(xs), "verdict": verdict})
    return out


def main():
    rows = []
    if os.path.exists(HISTORY):
        with open(HISTORY, encoding="utf-8") as fh:
            rows = [json.loads(line) for line in fh if line.strip()]
    data = {"rows": rows, "comparisons": comparisons(rows)}
    html = TEMPLATE.replace("/*DATA*/null", json.dumps(data, separators=(",", ":")))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(html)
    print(f"dashboard: {os.path.relpath(OUT, REPO)} ({len(rows)} captures)")


TEMPLATE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Earth Rally performance</title>
<style>
:root{color-scheme:light;--surface:#fcfcfb;--panel:#f4f3f0;--line:#e2e1dc;--text:#0b0b0b;--text2:#52514e;--muted:#7a7974;
--s1:#2a78d6;--s2:#eb6834;--c1:#2a78d6;--c2:#eb6834;--c3:#1baf7a;--c4:#eda100;--c5:#e87ba4;--c6:#008300;--c7:#6250d6;--c8:#a9a8a2;
--good:#0ca30c;--bad:#d03b3b;--grey:#a9a8a2}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])){color-scheme:dark;--surface:#1a1a19;--panel:#232321;--line:#383835;
--text:#f0efec;--text2:#c3c2b7;--muted:#8f8e88;--s1:#3987e5;--s2:#d95926;--c1:#3987e5;--c2:#d95926;--c3:#199e70;--c4:#c98500;--c5:#d55181;
--c6:#0ca30c;--c7:#9085e9;--c8:#6b6a65;--grey:#6b6a65}}
:root[data-theme="dark"]{color-scheme:dark;--surface:#1a1a19;--panel:#232321;--line:#383835;--text:#f0efec;--text2:#c3c2b7;--muted:#8f8e88;
--s1:#3987e5;--s2:#d95926;--c1:#3987e5;--c2:#d95926;--c3:#199e70;--c4:#c98500;--c5:#d55181;--c6:#0ca30c;--c7:#9085e9;--c8:#6b6a65;--grey:#6b6a65}
*{box-sizing:border-box}
body{margin:0;background:var(--surface);color:var(--text);font:14px/1.45 system-ui,-apple-system,Segoe UI,sans-serif}
main{max-width:1100px;margin:0 auto;padding:20px 16px 48px}
h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:28px 0 8px}
.sub{color:var(--text2);margin:0 0 16px}
.bar{display:flex;flex-wrap:wrap;gap:8px 16px;align-items:center;padding:10px 12px;background:var(--panel);border-radius:8px}
label{color:var(--text2);font-size:13px}select{font:inherit;padding:3px 6px;background:var(--surface);color:var(--text);border:1px solid var(--line);border-radius:6px}
.card{background:var(--panel);border-radius:8px;padding:12px;overflow-x:auto}
svg{display:block;max-width:100%}
.axis text{fill:var(--muted);font-size:11px}.grid line{stroke:var(--line)}
.ref{stroke:var(--muted);stroke-dasharray:4 4;stroke-width:1}.reftext{fill:var(--muted);font-size:11px}
.legend{display:flex;gap:16px;font-size:13px;color:var(--text2);margin:4px 0 8px}.sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:6px;vertical-align:-1px}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{text-align:right;padding:5px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
th:first-child,td:first-child,th.l,td.l{text-align:left}th{color:var(--text2);font-weight:600}
.v-faster{color:var(--good);font-weight:600}.v-slower{color:var(--bad);font-weight:600}.v-nochange,.v-single{color:var(--muted)}
#tip{position:fixed;pointer-events:none;background:var(--surface);color:var(--text);border:1px solid var(--line);border-radius:6px;padding:6px 8px;font-size:12px;box-shadow:0 2px 8px rgba(0,0,0,.15);display:none;z-index:9;max-width:320px}
.empty{color:var(--muted);padding:24px;text-align:center}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px}@media (max-width:760px){.grid2{grid-template-columns:1fr}}
</style></head><body><main>
<h1>Earth Rally performance</h1>
<p class="sub">Frame time (ms, lower is better) on Overmountain, Weaver Bend, car standing at fixed spots. Built from <code>perf/history.jsonl</code>.</p>
<div class="bar">
 <label>Test <select id="fTest"></select></label>
 <label>Metric <select id="fMetric"><option value="p99">p99</option><option value="p95">p95</option><option value="p50">p50</option><option value="over50">frames over 50 ms</option></select></label>
 <label>Capture <select id="fCap"></select></label>
</div>
<h2>Frame time per suite</h2>
<div class="card"><div class="legend"><span><i class="sw" style="background:var(--s1)"></i>Race active (running)</span><span><i class="sw" style="background:var(--s2)"></i>Mod idle (none)</span></div><div id="trend"></div></div>
<h2>Latest vs baseline</h2><div class="card" id="latest"></div>
<h2>A/B comparisons</h2><div class="card" id="ab"></div>
<div class="grid2">
 <div><h2>Where the frame goes (selected capture)</h2><div class="card" id="engine"></div></div>
 <div><h2>Earth Rally hooks (selected capture)</h2><div class="card" id="hooks"></div></div>
</div>
<h2>Frame trace (selected capture)</h2><div class="card" id="trace"></div>
</main><div id="tip"></div>
<script>
const D=/*DATA*/null;
const rows=D.rows||[];const $=s=>document.querySelector(s);const tip=$('#tip');
const NS='http://www.w3.org/2000/svg';
function el(n,a,p){const e=document.createElementNS(NS,n);for(const k in a)e.setAttribute(k,a[k]);if(p)p.appendChild(e);return e}
function showTip(ev,html){tip.innerHTML=html;tip.style.display='block';const x=Math.min(ev.clientX+14,innerWidth-330);tip.style.left=x+'px';tip.style.top=(ev.clientY+14)+'px'}
function hideTip(){tip.style.display='none'}
function med(a){a=a.filter(x=>x!=null).sort((x,y)=>x-y);if(!a.length)return null;const m=a.length>>1;return a.length%2?a[m]:(a[m-1]+a[m])/2}
const f2=x=>x==null?'–':(+x).toFixed(2);
const tests=[...new Set(rows.map(r=>r.test).filter(Boolean))];
const fTest=$('#fTest'),fMetric=$('#fMetric'),fCap=$('#fCap');
for(const t of tests){const o=document.createElement('option');o.value=o.textContent=t;fTest.appendChild(o)}
if(tests.includes('quick'))fTest.value='quick';
const caps=rows.map((r,i)=>({i,name:r.suite+' / '+r.capture}));
for(const c of caps.slice().reverse()){const o=document.createElement('option');o.value=c.i;o.textContent=c.name;fCap.appendChild(o)}
function suites(){const s=[];for(const r of rows)if(!s.includes(r.suite))s.push(r.suite);return s}

function trend(){
 const box=$('#trend');box.innerHTML='';const t=fTest.value,m=fMetric.value;
 const ss=suites().filter(s=>rows.some(r=>r.suite===s&&r.test===t));
 if(!ss.length){box.innerHTML='<div class="empty">No captures for this test yet.</div>';return}
 const ser=[['running','var(--s1)'],['none','var(--s2)']].map(([st,c])=>({st,c,pts:ss.map((s,i)=>{const xs=rows.filter(r=>r.suite===s&&r.test===t&&r.state===st);return{i,s,v:med(xs.map(r=>r[m])),n:xs.length,lab:xs[0]&&xs[0].label,commit:xs[0]&&xs[0].commit}}).filter(p=>p.v!=null)}));
 const W=Math.max(520,box.clientWidth||900),H=260,L=48,R=16,T=14,B=44;
 const all=ser.flatMap(s=>s.pts.map(p=>p.v));let ymax=Math.max(...all,m==='over50'?1:35)*1.12;
 const x=i=>L+(ss.length<2?(W-L-R)/2:i*(W-L-R)/(ss.length-1)),y=v=>T+(H-T-B)*(1-v/ymax);
 const svg=el('svg',{width:W,height:H,viewBox:`0 0 ${W} ${H}`,role:'img','aria-label':'frame time per suite'},box);
 const g=el('g',{class:'grid'},svg);const ax=el('g',{class:'axis'},svg);
 for(let k=0;k<=4;k++){const v=ymax*k/4;el('line',{x1:L,x2:W-R,y1:y(v),y2:y(v)},g);el('text',{x:L-6,y:y(v)+4,'text-anchor':'end'},ax).textContent=v.toFixed(m==='over50'?0:1)}
 if(m!=='over50')for(const [v,lab] of [[16.7,'60 fps'],[33.3,'30 fps']])if(v<ymax){el('line',{x1:L,x2:W-R,y1:y(v),y2:y(v),class:'ref'},svg);el('text',{x:W-R-2,y:y(v)-4,'text-anchor':'end',class:'reftext'},svg).textContent=lab}
 ss.forEach((s,i)=>{const r=rows.find(r=>r.suite===s);const tx=el('text',{x:x(i),y:H-B+16,'text-anchor':'middle'},ax);tx.textContent=(r.commit||'')+(r.dirty?'*':'');const t2=el('text',{x:x(i),y:H-B+30,'text-anchor':'middle'},ax);t2.textContent=(r.label||'').slice(0,18)});
 for(const s of ser){if(s.pts.length>1)el('polyline',{points:s.pts.map(p=>x(p.i)+','+y(p.v)).join(' '),fill:'none',stroke:s.c,'stroke-width':2,'stroke-linejoin':'round'},svg);
  for(const p of s.pts){el('circle',{cx:x(p.i),cy:y(p.v),r:4.5,fill:s.c,stroke:'var(--panel)','stroke-width':2},svg)}}
 const hit=el('rect',{x:L,y:T,width:W-L-R,height:H-T-B,fill:'transparent'},svg);const cross=el('line',{y1:T,y2:H-B,stroke:'var(--muted)','stroke-width':1,visibility:'hidden'},svg);
 hit.addEventListener('mousemove',ev=>{const b=svg.getBoundingClientRect();const px=(ev.clientX-b.left)*W/b.width;let i=Math.round((px-L)/((W-L-R)/Math.max(1,ss.length-1)));i=Math.max(0,Math.min(ss.length-1,i));cross.setAttribute('x1',x(i));cross.setAttribute('x2',x(i));cross.setAttribute('visibility','visible');
  let h=`<b>${ss[i]}</b>`;for(const s of ser){const p=s.pts.find(p=>p.i===i);if(p)h+=`<br><i class="sw" style="background:${s.c}"></i>${s.st}: ${f2(p.v)} ${m==='over50'?'frames':'ms'} (n ${p.n})`}const r=rows.find(r=>r.suite===ss[i]);h+=`<br>${r.label||''} · ${r.commit||''}${r.dirty?' (dirty)':''}`;showTip(ev,h)});
 hit.addEventListener('mouseleave',()=>{cross.setAttribute('visibility','hidden');hideTip()});
}

function latest(){
 const box=$('#latest');const t=fTest.value;const ss=suites().filter(s=>rows.some(r=>r.suite===s&&r.test===t));
 if(ss.length<1){box.innerHTML='<div class="empty">No data yet.</div>';return}
 const b=ss[0],l=ss[ss.length-1];const g=(s,st,k)=>med(rows.filter(r=>r.suite===s&&r.test===t&&r.state===st).map(r=>r[k]));
 let h='<table><tr><th>State</th><th>Metric</th><th>Baseline</th><th>Latest</th><th>Change</th><th>Gap to idle left</th></tr>';
 for(const st of ['running','none'])for(const k of ['p50','p99','over50']){const bv=g(b,st,k),lv=g(l,st,k);if(bv==null&&lv==null)continue;const d=(lv!=null&&bv!=null)?lv-bv:null;
  let gap='–';if(st==='running'&&k!=='over50'){const bn=g(b,'none',k),ln=g(l,'none',k);if(bn!=null&&ln!=null&&bv-bn>0)gap=Math.round(100*(lv-ln)/(bv-bn))+' %'}
  h+=`<tr><td>${st}</td><td>${k}</td><td>${f2(bv)}</td><td>${f2(lv)}</td><td>${d==null?'–':(d>0?'+':'')+d.toFixed(2)}</td><td>${gap}</td></tr>`}
 box.innerHTML=h+`</table><p class="sub" style="margin:8px 0 0">Baseline ${b} · latest ${l}. Change inside the spread between pairs is noise: see the A/B table.</p>`;
}

function ab(){
 const box=$('#ab');const cs=(D.comparisons||[]).filter(c=>c.test===fTest.value||fTest.value==='');
 const all=(D.comparisons||[]);const use=cs.length?cs:all;
 if(!use.length){box.innerHTML='<div class="empty">No A/B pairs yet.</div>';return}
 const V={faster:'faster',slower:'slower',nochange:'no change (inside spread)',single:'one pair only'};
 let h='<table><tr><th class="l">Suite</th><th class="l">Test</th><th class="l">Switch</th><th>Base → value</th><th>p99 base</th><th>p99</th><th>Δ p99</th><th>Spread</th><th>n</th><th class="l">Verdict</th></tr>';
 for(const c of use.slice().reverse())h+=`<tr><td class="l">${c.suite}</td><td class="l">${c.test}</td><td class="l">${c.switch}</td><td>${c.base} → ${c.value}</td><td>${f2(c.baseP99)}</td><td>${f2(c.p99)}</td><td>${c.d>0?'+':''}${f2(c.d)}</td><td>${f2(c.noise)}</td><td>${c.n}</td><td class="l v-${c.verdict}">${V[c.verdict]}</td></tr>`;
 box.innerHTML=h+'</table>';
}

function engine(){
 const box=$('#engine');box.innerHTML='';const r=rows[+fCap.value];if(!r||!r.engine){box.innerHTML='<div class="empty">No capture.</div>';return}
 const skip=new Set(['FrameTime','Frame','Total','FPS']);const e=Object.entries(r.engine).filter(([k,v])=>v!=null&&!skip.has(k)).sort((a,b)=>b[1]-a[1]);
 const top=e.slice(0,7);const other=e.slice(7).reduce((s,x)=>s+x[1],0);if(other>0.01)top.push(['Other',other]);
 const total=top.reduce((s,x)=>s+x[1],0);if(!total){box.innerHTML='<div class="empty">No engine timings.</div>';return}
 const W=Math.max(300,box.clientWidth-24||480),H=28;const svg=el('svg',{width:W,height:H,viewBox:`0 0 ${W} ${H}`,role:'img','aria-label':'engine time per frame'},box);
 let x0=0;top.forEach(([k,v],i)=>{const w=W*v/total;const c=k==='Other'?'var(--c8)':`var(--c${i+1})`;const rc=el('rect',{x:x0+1,y:2,width:Math.max(1,w-2),height:H-4,rx:4,fill:c},svg);
  rc.addEventListener('mousemove',ev=>showTip(ev,`<b>${k}</b><br>${f2(v)} ms a frame (mean)`));rc.addEventListener('mouseleave',hideTip);x0+=w});
 let h='<table style="margin-top:8px"><tr><th class="l">Category</th><th>ms / frame</th></tr>';top.forEach(([k,v],i)=>{h+=`<tr><td class="l"><i class="sw" style="background:${k==='Other'?'var(--c8)':'var(--c'+(i+1)+')'}"></i>${k}</td><td>${f2(v)}</td></tr>`});
 box.insertAdjacentHTML('beforeend',h+`</table><p class="sub" style="margin:8px 0 0">${r.capture}: p50 ${f2(r.p50)} · p99 ${f2(r.p99)} · ${r.frames} frames${r.presentmon?` · CPUBusy ${r.presentmon.cpuBusy} · GPUBusy ${r.presentmon.gpuBusy}`:''}</p>`);
}

function hooks(){
 const box=$('#hooks');const r=rows[+fCap.value];if(!r||!r.hooks){box.innerHTML='<div class="empty">No capture.</div>';return}
 const e=Object.entries(r.hooks).sort((a,b)=>(b[1].max||0)-(a[1].max||0));
 let h='<table><tr><th class="l">Hook</th><th>max ms</th><th>ms / frame</th></tr>';for(const [k,v] of e)h+=`<tr><td class="l">${k}</td><td>${f2(v.max)}</td><td>${f2(v.perFrame)}</td></tr>`;
 box.innerHTML=h+`</table><p class="sub" style="margin:8px 0 0">GC ${f2(r.gcKBs)} KB/s · statics ${r.counts&&r.counts.statics} · road nodes ${r.counts&&r.counts.nodes} · props ${r.counts&&r.counts.props}</p>`;
}

function trace(){
 const box=$('#trace');box.innerHTML='';const r=rows[+fCap.value];if(!r||!r.trace||!r.trace.length){box.innerHTML='<div class="empty">No trace.</div>';return}
 const tr=r.trace,W=Math.max(520,box.clientWidth-24||900),H=200,L=44,R=12,T=10,B=24;const ymax=Math.max(55,...tr)*1.08;
 const x=i=>L+i*(W-L-R)/Math.max(1,tr.length-1),y=v=>T+(H-T-B)*(1-v/ymax);
 const svg=el('svg',{width:W,height:H,viewBox:`0 0 ${W} ${H}`,role:'img','aria-label':'frame trace'},box);const g=el('g',{class:'grid'},svg),ax=el('g',{class:'axis'},svg);
 for(let k=0;k<=4;k++){const v=ymax*k/4;el('line',{x1:L,x2:W-R,y1:y(v),y2:y(v)},g);el('text',{x:L-6,y:y(v)+4,'text-anchor':'end'},ax).textContent=v.toFixed(0)}
 for(const [v,lab] of [[16.7,'60 fps'],[33.3,'30 fps'],[50,'50 ms']]){el('line',{x1:L,x2:W-R,y1:y(v),y2:y(v),class:'ref'},svg);el('text',{x:W-R-2,y:y(v)-4,'text-anchor':'end',class:'reftext'},svg).textContent=lab}
 el('polyline',{points:tr.map((v,i)=>x(i)+','+y(v)).join(' '),fill:'none',stroke:'var(--s1)','stroke-width':1.5,'stroke-linejoin':'round'},svg);
 const spikes=(r.spikes||[]);
 const hit=el('rect',{x:L,y:T,width:W-L-R,height:H-T-B,fill:'transparent'},svg);const dot=el('circle',{r:4.5,fill:'var(--s1)',stroke:'var(--panel)','stroke-width':2,visibility:'hidden'},svg);
 hit.addEventListener('mousemove',ev=>{const b=svg.getBoundingClientRect();let i=Math.round(((ev.clientX-b.left)*W/b.width-L)/((W-L-R)/Math.max(1,tr.length-1)));i=Math.max(0,Math.min(tr.length-1,i));dot.setAttribute('cx',x(i));dot.setAttribute('cy',y(tr[i]));dot.setAttribute('visibility','visible');
  showTip(ev,`<b>${f2(tr[i])} ms</b> (worst frame in this slice)<br>${r.capture}`)});
 hit.addEventListener('mouseleave',()=>{dot.setAttribute('visibility','hidden');hideTip()});
 if(spikes.length){let h='<table style="margin-top:8px"><tr><th>Spike ms</th><th class="l">Earth Rally hooks that frame (ms)</th></tr>';for(const s of spikes.slice(0,12))h+=`<tr><td>${f2(s.ms)}</td><td class="l">${Object.entries(s.hooks||{}).map(([k,v])=>k+' '+v).join(', ')||'none over 0.5 ms'}</td></tr>`;box.insertAdjacentHTML('beforeend',h+'</table>')}
 else box.insertAdjacentHTML('beforeend','<p class="sub" style="margin:8px 0 0">No frames over 33 ms.</p>');
}

function all(){trend();latest();ab();engine();hooks();trace()}
fTest.onchange=fMetric.onchange=fCap.onchange=all;addEventListener('resize',all);
if(!rows.length)document.querySelector('main').insertAdjacentHTML('beforeend','<div class="empty">No captures yet: run tools/perf/run_bench.py.</div>');else all();
</script></body></html>
"""

if __name__ == "__main__":
    main()
