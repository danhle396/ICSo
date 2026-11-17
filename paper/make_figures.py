"""
CE2031 Project 23 - data for the LaTeX paper.

    python paper/make_figures.py     (after run_sim.ps1, run_modelsim.ps1 and
                                      quartus/run_quartus.tcl)

Writes
  paper/results.tex              every measured number as a macro, read from
                                 logs/*.log, logs/enc_*/*, logs/timing/*.rpt and
                                 quartus/output_files/*.rpt - nothing typed by hand
  paper/figures/wave_emg.tex     TikZ timing diagram of directed test T5
                                 (emergency during a green), drawn from the VCD
  paper/figures/wave_ped.tex     the same for T2 (pedestrian request)
The GTKWave screenshots come from paper/capture_gtkwave.ps1.
"""
import re
from pathlib import Path

PAPER = Path(__file__).resolve().parent
ROOT = PAPER.parent
FIG = PAPER / "figures"
FIG.mkdir(exist_ok=True)
SEEDS = (1, 7, 2026)
PROPS = ("a_safe", "a_emg", "a_yel", "a_onehot", "a_ped", "a_allred", "a_gmax", "a_ylen")
STATES = ["NS\\_G", "NS\\_Y", "RED1", "EW\\_G", "EW\\_Y", "RED2", "PED", "EMG", "RECOV"]


def read(rel):
    return (ROOT / rel).read_text(encoding="latin-1")


def grab(text, pattern, what, flags=re.M):
    m = re.search(pattern, text, flags)
    if not m:
        raise SystemExit(f"not found: {what}  ({pattern})")
    return m.group(1)


def thousands(n):
    return f"{int(n):,}".replace(",", "{,}")


def tex(s):
    return s.replace("_", r"\_").replace("|", r"$|$")


# ---- Simulation -----------------------------------------------------------------
def tb_numbers(log):
    status =re.search(r"TRAFFIC TB (PASSED|FAILED)", log).group(1)
    cycles = int(grab(log, r"TRAFFIC TB \w+ : seed \d+, (\d+) cycles", "cycles"))
    checks = int(grab(log, r"(\d+) directed checks", "checks"))
    errors = int(grab(log, r"directed checks, (\d+) errors", "errors"))
    viol = int(grab(log, r"(\d+) checker violations", "violations"))
    props = {p: tuple(int(x) for x in re.search(rf"^\s+{p}\s+(\d+)\s+(\d+)\s*$", log, re.M).groups())
             for p in PROPS}
    cov = re.search(r"COVERAGE : states (\d+)/9, arcs (\d+)/24", log)
    arcs = [int(x) for x in re.findall(r"^\s+arc\s+\d+\s+(\d+)\s*$", log, re.M)]
    states = [int(x) for x in re.findall(r"^\s+\d+\s+\S+\s+(\d+)\s*$", log, re.M)[:9]]
    return dict(status=status, cycles=cycles, checks=checks, errors=errors, viol=viol, props=props,
                states_cov=int(cov.group(1)), arcs_cov=int(cov.group(2)), arcs=arcs, states=states)


def results():
    v = {}
    runs = {s: tb_numbers(read(f"logs/traffic_tb_seed{s}.log")) for s in SEEDS}
    for s, r in runs.items():
        if r["status"] != "PASSED" or r["states_cov"] != 9 or r["arcs_cov"] != 24:
            raise SystemExit(f"seed {s} did not pass with full coverage")
    golden = {s: read(f"logs/golden_seed{s}.log") for s in SEEDS}
    for s, g in golden.items():
        if "PASS, 0 mismatch" not in g:
            raise SystemExit(f"golden model failed for seed {s}")
    r1 = runs[SEEDS[0]]
    v["SimSeeds"] = ", ".join(str(s) for s in SEEDS)
    v["SimCycles"] = thousands(r1["cycles"])
    v["SimCyclesAll"] = thousands(sum(r["cycles"] for r in runs.values()))
    v["DirChecks"] = str(r1["checks"])
    v["DirCycles"] = thousands(int(grab(read(f"logs/traffic_tb_seed{SEEDS[0]}.log"),
                                        r"Phase 1: \d+ directed checks, \d+ errors, (\d+) cycles", "dir cycles")))
    v["RandomCycles"] = thousands(int(grab(read(f"logs/traffic_tb_seed{SEEDS[0]}.log"),
                                           r"Phase 2: (\d+) random cycles", "random")))
    v["GoldenCycles"] = thousands(sum(int(grab(g, r"cycles compared: (\d+)", "golden cycles"))
                                      for g in golden.values()))
    for p in PROPS:
        key = p[2:].capitalize()
        v[f"Hit{key}"] = thousands(sum(r["props"][p][0] for r in runs.values()))
        if any(r["props"][p][1] for r in runs.values()):
            raise SystemExit(f"{p} violated")
    arc_tot = [sum(r["arcs"][i] for r in runs.values()) for i in range(24)]
    for i, n in enumerate(arc_tot):
        v[f"Arc{chr(ord('A') + i)}"] = thousands(n)
    v["ArcMin"] = thousands(min(arc_tot))
    arc_names = [r"\st{NS\_G}$\to$\st{NS\_Y} (emg)", r"\st{NS\_G} extension", r"\st{NS\_G}$\to$\st{NS\_Y}",
                 r"\st{NS\_Y}$\to$\st{EMG}", r"\st{NS\_Y}$\to$\st{RED1}", r"\st{RED1}$\to$\st{EMG}",
                 r"\st{RED1}$\to$\st{PED}", r"\st{RED1}$\to$\st{EW\_G}", r"\st{EW\_G}$\to$\st{EW\_Y} (emg)",
                 r"\st{EW\_G} extension", r"\st{EW\_G}$\to$\st{EW\_Y}", r"\st{EW\_Y}$\to$\st{EMG}",
                 r"\st{EW\_Y}$\to$\st{RED2}", r"\st{RED2}$\to$\st{EMG}", r"\st{RED2}$\to$\st{PED}",
                 r"\st{RED2}$\to$\st{NS\_G}", r"\st{PED}$\to$\st{EMG}", r"\st{PED}$\to$\st{EW\_G}",
                 r"\st{PED}$\to$\st{NS\_G}", r"\st{EMG}$\to$\st{RECOVER}", r"\st{RECOVER}$\to$\st{EMG}",
                 r"\st{RECOVER}$\to$\st{PED}", r"\st{RECOVER}$\to$\st{EW\_G}", r"\st{RECOVER}$\to$\st{NS\_G}"]
    v["ArcMinName"] = arc_names[arc_tot.index(min(arc_tot))]
    st_tot = [sum(r["states"][i] for r in runs.values()) for i in range(9)]
    for i, n in enumerate(st_tot):
        v[f"St{chr(ord('A') + i)}"] = thousands(n)

    # mutants
    for k in range(1, 7):
        log = read(f"logs/mutant_M{k}.log")
        g = read(f"logs/golden_M{k}.log")
        m = tb_numbers(log)
        viol = [p for p in PROPS if m["props"][p][1] > 0]
        v[f"MutErr{chr(ord('A') + k - 1)}"] = thousands(m["errors"])
        v[f"MutViol{chr(ord('A') + k - 1)}"] = thousands(m["viol"])
        v[f"MutProps{chr(ord('A') + k - 1)}"] = ", ".join(r"\code{%s}" % tex(p) for p in viol) or "--"
        v[f"MutGold{chr(ord('A') + k - 1)}"] = thousands(grab(g, r"FAIL, (\d+) mismatches", f"golden M{k}"))
        if m["status"] != "FAILED" and "FAIL" not in g:
            raise SystemExit(f"mutant M{k} not caught")

    # ModelSim
    ms = read("logs/modelsim_tb.log")
    if "identical stimulus and output trace" not in ms or "TRAFFIC TB PASSED" not in ms:
        raise SystemExit("ModelSim run not identical / not passed")
    v["MsimVersion"] = grab(read("logs/modelsim_compile.log"), r"ModelSim ALTERA vlog (\S+)", "msim version")

    # ---- Quartus: the three encodings ----
    def enc(tag):
        fit = read(f"logs/enc_{tag}/de2_traffic.fit.summary")
        sta = read(f"logs/enc_{tag}/de2_traffic.sta.rpt")
        le = grab(fit, r"Total logic elements : ([\d,]+)", "LE").replace(",", "")
        ff = grab(fit, r"Total registers : (\d+)", "regs")
        fmax = grab(sta.split("; Slow Model Fmax Summary", 1)[1], r"; ([\d.]+) MHz", "fmax")
        mp = read(f"logs/enc_{tag}/de2_traffic.map.rpt")
        ffsm = grab(mp, r"State Machine - \|de2_top\|traffic_top:u_top\|traffic_fsm:u_fsm\|state\s*;\n\+[-+]+\n; Name\s+;(.*)", "fsm")
        nbits = len([c for c in ffsm.split(";") if c.strip()])
        return le, ff, fmax, nbits

    for tag, key in (("binary", "Bin"), ("gray", "Gray"), ("onehot", "Hot")):
        le, ff, fmax, nbits = enc(tag)
        v[f"LE{key}"], v[f"FF{key}"], v[f"Fmax{key}"], v[f"Bits{key}"] = le, ff, fmax, str(nbits)
        for kind in ("map", "fit", "sta"):
            txt = read(f"logs/enc_{tag}/de2_traffic.{kind}.rpt")
            if "Critical Warning" in txt:
                raise SystemExit(f"critical warning in {tag} {kind}")
        if re.search(r"inferred latch", read(f"logs/enc_{tag}/de2_traffic.map.rpt"), re.I):
            raise SystemExit(f"latch in {tag}")

    # ---- Quartus: the hand-in build (ONE-HOT) ----
    fit = read("quartus/output_files/de2_traffic.fit.rpt")
    mp = read("quartus/output_files/de2_traffic.map.rpt")

    def entity(name):
        row = grab(fit, rf"^;\s+\|{re.escape(name)}\|\s*;([^\n]*)", name)
        cells = [c.strip() for c in row.split(";")]
        return cells[0].split()[0], cells[1].split()[0]

    for name, key in (("traffic_fsm:u_fsm", "Fsm"), ("clk_divider:u_div", "Div"),
                      ("strobe_gen:u_strobe", "Strobe"), ("state_timer:u_timer", "Timer"),
                      ("bin2bcd8:u_bcd", "Bcd"), ("sync_debounce:u_db_emg", "Db")):
        v[f"LE{key}"], v[f"FF{key}"] = entity(name)
    top_row = grab(fit, r"^;\s+\|de2_top\s*;([^\n]*)", "de2_top")
    v["LEtopOwn"] = re.search(r"\((\d+)\)", top_row).group(1)
    v["FFtopOwn"] = re.findall(r"\((\d+)\)", top_row)[1]
    v["LEtotal"] = grab(fit, r"^; Total logic elements\s+; ([\d,]+) /", "LE total").replace(",", "")
    v["NumRegisters"] = grab(fit, r"^; Total registers\s+; (\d+)", "registers")
    v["NumPins"] = grab(fit, r"^; Total pins\s+; (\d+) /", "pins")
    v["MemBits"] = grab(fit, r"^; Total memory bits\s+; ([\d,]+) /", "mem").replace(",", "")
    v["ClockGlobal"] = grab(fit, r"^; CLOCK_50\s+; PIN_N2\s+;[^;]+; Global Clock\s+; (\w+)", "gclk")
    v["QuartusVersion"] = grab(fit, r"Quartus II 64-Bit Version\s*; (\d+\.\d+\.\d+)", "version")
    v["EncFinal"] = grab(mp, r"Encoding Type:\s+(\S+)", "encoding")

    tim = ROOT / "logs" / "timing"
    v["FmaxSlow"] = grab((tim / "fmax.rpt").read_text(), r"; ([\d.]+) MHz", "fmax")
    v["FmaxFast"] = grab((tim / "fmax_fast.rpt").read_text(), r"; ([\d.]+) MHz", "fmax fast")

    def first_path(fname):
        t = (tim / fname).read_text()
        m = re.search(r"^; (-?[\d.]+) ; (\S+)\s+; (\S+)\s+; \S+\s+; \S+\s+; [\d.]+\s+; -?[\d.]+\s+; ([\d.]+)", t, re.M)
        return m.groups()

    s20, frm, to, dly = first_path("setup.rpt")
    s10, frm10, to10, dly10 = first_path("setup_10ns.rpt")
    v["SlackSetup"], v["SlackTen"], v["CritDelay"] = s20, s10, dly10
    v["CritFrom"] = tex(frm10.split("|")[-1] + " (" + frm10.split("|")[-2].split(":")[0] + ")")
    v["CritTo"] = tex(to10.split("|")[-1] + " (" + to10.split("|")[-2].split(":")[0] + ")")
    v["SlackHold"] = first_path("hold.rpt")[0]
    v["SlackRecovery"] = first_path("recovery.rpt")[0]
    v["SlackRemoval"] = first_path("removal.rpt")[0]

    with open(PAPER / "results.tex", "w", encoding="ascii") as f:
        f.write("% Generated by make_figures.py - do not edit.\n")
        f.write("% Sources: logs/*.log, logs/enc_*/*, logs/timing/*.rpt, quartus/output_files/*.rpt\n")
        for k, val in v.items():
            f.write(f"\\newcommand{{\\{k}}}{{{val}}}\n")
    print("wrote results.tex")
    for k, val in v.items():
        print(f"  {k:15s} {val}")


# ---- VCD -------------------------------------------------------------------------
def load_vcd(path, wanted):
    """{'scope.name': [(time_ns, value), ...]} for the wanted full names."""
    text = path.read_text()
    unit = grab(text, r"\$timescale\s+(\S+)", "timescale")
    tick = {"1ns": 1.0, "100ps": 0.1, "10ps": 0.01, "1ps": 0.001}[unit]
    ids, stack = {}, []
    header, body = text.split("$enddefinitions", 1)
    for tok in re.finditer(r"\$scope\s+\w+\s+(\S+)|\$upscope|\$var\s+\S+\s+\d+\s+(\S+)\s+(\S+)", header):
        if tok.group(1):
            stack.append(tok.group(1))
        elif tok.group(0).startswith("$upscope"):
            stack.pop()
        else:
            full = ".".join(stack + [tok.group(3)])
            if full in wanted:
                ids.setdefault(tok.group(2), []).append(full)
    waves = {n: [] for n in wanted}
    t = 0.0
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("$"):
            continue
        if line[0] == "#":
            t = int(line[1:]) * tick
        elif line[0] == "b":
            val, ident = line[1:].split()
            for n in ids.get(ident, []):
                waves[n].append((t, val))
        elif line[0] in "01xz" and line[1:] in ids:
            for n in ids[line[1:]]:
                waves[n].append((t, line[0]))
    def norm(val):                                    # 'b1' and 'b001' are the same value
        return val if ("x" in val or "z" in val) else int(val, 2)

    for n in wanted:
        dedup = {}
        for tt, val in waves[n]:                      # last value of each time step
            dedup[tt] = val
        merged = []
        for tt, val in sorted(dedup.items()):         # a default assignment followed by
            if not merged or norm(val) != norm(merged[-1][1]):   # the real one re-dumps
                merged.append((tt, val))              # an unchanged value: drop it
        waves[n] = merged
    return waves


def test_window(test):
    log = read(f"logs/traffic_tb_seed{SEEDS[0]}.log")
    starts = {int(a): int(b) for a, b in re.findall(r"^TEST_START T(\d+) (\d+) ns", log, re.M)}
    return starts[test], starts[test + 1]


def wave(test, t0, t1, rows, fname, marks=()):
    """rows: (label, signal, kind) with kind 'bit', 'tick', 'state', 'lamp', 'bcd'"""
    w = load_vcd(ROOT / "traffic_tb.vcd", {s for _, s, _ in rows})
    span = t1 - t0
    sx = 16.0 / span                                  # cm per ns: 16 cm wide
    row, h = 0.55, 0.36
    out = [f"% Generated by make_figures.py from traffic_tb.vcd (T{test}) - do not edit.",
           r"\begin{tikzpicture}[x=%.5fcm,y=1cm,font=\scriptsize,line width=0.45pt]" % sx]

    def segs(name):
        s = w[name]
        cur = [v for t, v in s if t <= t0]
        pts = [(t0, cur[-1] if cur else "x")] + [(t, v) for t, v in s if t0 < t < t1]
        return [(max(a, t0), v, pts[i + 1][0] if i + 1 < len(pts) else t1) for i, (a, v) in enumerate(pts)]

    nrow = len(rows)
    ybot = -(nrow - 1) * row - h - 0.12
    for k in range(0, int(span) // 100 + 1):         # grid every 100 ns (10 clock cycles)
        x = t0 + 100 * k
        out.append(r"\draw[black!25,dashed,line width=0.3pt] (%.1f,0.15) -- (%.1f,%.2f);" % (x - t0, x - t0, ybot))
        out.append(r"\node[below=-1pt,font=\tiny] at (%.1f,%.2f) {%d};" % (x - t0, ybot, 10 * k))
    out.append(r"\node[below=-1pt,font=\tiny,anchor=north west] at (%.1f,%.2f) {cycles};" % (span, ybot))
    for i, (label, sig, kind) in enumerate(rows):
        y0 = -i * row - h
        out.append(r"\node[anchor=east] at (-6,%.2f) {%s};" % (y0 + h / 2, label))
        if kind in ("bit", "tick"):
            pts = []
            for a, v, b in segs(sig):
                y = y0 + (h if v == "1" else 0)
                pts += [(a - t0, y), (b - t0, y)]
            out.append(r"\draw " + " -- ".join("(%.2f,%.2f)" % p for p in pts) + ";")
        else:
            d = 1.5
            for a, v, b in segs(sig):
                if "x" in v:
                    txt, fill = "", "fill=black!20"
                else:
                    n = int(v, 2)
                    fill = ""
                    if kind == "state":
                        txt = STATES[n] if n < 9 else "?"
                        if n == 7:
                            fill = "fill=red!25"
                    elif kind == "lamp":
                        txt = {1: "G", 2: "Y", 4: "R"}.get(n, "?")
                        fill = {1: "fill=green!35", 2: "fill=yellow!60", 4: "fill=red!25"}.get(n, "")
                    else:
                        txt = f"{n >> 4}{n & 15}"
                ym, yt = y0 + h / 2, y0 + h
                l, r = a - t0 + (d if a > t0 else 0), b - t0 - (d if b < t1 else 0)
                out.append(r"\draw[%s] (%.2f,%.2f) -- (%.2f,%.2f) -- (%.2f,%.2f) -- (%.2f,%.2f) -- (%.2f,%.2f) -- (%.2f,%.2f) -- cycle;"
                           % (fill, a - t0, ym, l, yt, r, yt, b - t0, ym, r, y0, l, y0))
                need = 5.5 * len(txt) + 6 if kind != "bcd" else 14
                if txt and (b - a) >= need * span / 760:
                    out.append(r"\node at (%.2f,%.2f) {\code{%s}};" % ((a + b) / 2 - t0, ym, txt))
    for (tm, k, text) in marks:
        out.append(r"\draw[->,>=stealth,thick] (%.1f,0.55) -- (%.1f,0.12);" % (tm - t0, tm - t0))
        out.append(r"\node[circle,draw,inner sep=0.6pt,font=\tiny\bfseries] at (%.1f,0.72) {%d};" % (tm - t0, k))
    out.append(r"\end{tikzpicture}")
    (FIG / fname).write_text("\n".join(out) + "\n")
    print(f"wrote figures/{fname}  (T{test}, {t0:.0f}..{t1:.0f} ns)")


def first_change(sig, after, value):
    w = load_vcd(ROOT / "traffic_tb.vcd", {sig})[sig]
    want = int(value, 2)
    return next(t for t, v in w if t > after and "x" not in v and int(v, 2) == want)


def figures():
    tb = "traffic_tb"
    rows = [
        (r"\code{emg\_sensor}", f"{tb}.emg_sensor", "bit"),
        (r"\code{emg\_sync}", f"{tb}.dut.emg_sync", "bit"),
        (r"\code{tick}", f"{tb}.dut.tick", "tick"),
        (r"state", f"{tb}.state_dbg", "state"),
        (r"NS light", f"{tb}.light_ns", "lamp"),
        (r"EW light", f"{tb}.light_ew", "lamp"),
        (r"\code{time\_left}", f"{tb}.time_left", "bcd"),
        (r"\code{emergency\_active}", f"{tb}.emergency_active", "bit"),
    ]
    a, b = test_window(5)
    a += 40                                           # skip the reset of the test
    e1 = first_change(f"{tb}.emg_sensor", a, "1")
    s1 = first_change(f"{tb}.emg_sync", a, "1")
    y1 = first_change(f"{tb}.state_dbg", a, "0001")
    m1 = first_change(f"{tb}.state_dbg", a, "0111")
    e0 = first_change(f"{tb}.emg_sensor", m1, "0")
    r1 = first_change(f"{tb}.state_dbg", m1, "1000")
    wave(5, a, b, rows, "wave_emg.tex",
         marks=((e1, 1, ""), (y1, 2, ""), (m1, 3, ""), (e0, 4, ""), (r1, 5, "")))
    with open(PAPER / "results.tex", "a", encoding="ascii") as f:
        f.write("%% T5 event times, cycles from the start of the figure\n")
        f.write("\\newcommand{\\WaveDbLat}{%d}\n" % round((s1 - e1) / 10 + 0.5))   # rising edges
        f.write("\\newcommand{\\WaveYellow}{%d}\n" % round((m1 - y1) / 10))
        f.write("\\newcommand{\\WaveRecover}{%d}\n" % round((first_change(f"{tb}.state_dbg", r1, "0011") - r1) / 10))

    rows_p = [
        (r"\code{ped\_btn}", f"{tb}.ped_btn", "bit"),
        (r"\code{ped\_req}", f"{tb}.ped_req_dbg", "bit"),
        (r"\code{tick}", f"{tb}.dut.tick", "tick"),
        (r"state", f"{tb}.state_dbg", "state"),
        (r"NS light", f"{tb}.light_ns", "lamp"),
        (r"EW light", f"{tb}.light_ew", "lamp"),
        (r"\code{ped\_lamp}", f"{tb}.ped_lamp", "bit"),
        (r"\code{time\_left}", f"{tb}.time_left", "bcd"),
    ]
    a, b = test_window(2)
    a += 340                                          # from the end of the first green
    wave(2, a, b, rows_p, "wave_ped.tex")


if __name__ == "__main__":
    results()
    figures()
