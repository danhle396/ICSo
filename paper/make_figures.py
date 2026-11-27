"""
CE2031 Project 23 - data for the LaTeX paper.

    python paper/make_figures.py     (after run_sim.ps1, run_modelsim.ps1 and
                                      quartus/run_quartus.tcl)

Writes
  paper/results.tex              every measured number as a macro, read from
                                 logs/*.log, logs/enc_*/*, logs/timing/*.rpt and
                                 quartus/output_files/*.rpt - nothing typed by hand
  paper/figures/wave_events.json  time window and event markers of directed
                                 tests T5 (emergency during a green) and T2
                                 (pedestrian request), read from the VCD; used by
                                 paper/capture_gtkwave.ps1, which takes the real
                                 GTKWave screenshots of the paper
"""
import json
import re
from pathlib import Path

PAPER = Path(__file__).resolve().parent
ROOT = PAPER.parent
FIG = PAPER / "figures"
FIG.mkdir(exist_ok=True)
SEEDS = (1, 7, 2026)
PROPS = ("a_safe", "a_emg", "a_yel", "a_onehot", "a_ped", "a_allred", "a_gmax", "a_ylen")


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


def first_change(sig, after, value):
    w = load_vcd(ROOT / "traffic_tb.vcd", {sig})[sig]
    want = int(value, 2)
    return next(t for t, v in w if t > after and "x" not in v and int(v, 2) == want)


def figures():
    """Event times of T5 and T2 for the GTKWave captures (markers A..E)."""
    tb = "traffic_tb"
    a, b = test_window(5)
    a += 40                                           # skip the reset of the test
    e1 = first_change(f"{tb}.emg_sensor", a, "1")
    s1 = first_change(f"{tb}.emg_sync", a, "1")
    y1 = first_change(f"{tb}.state_dbg", a, "0001")
    m1 = first_change(f"{tb}.state_dbg", a, "0111")
    e0 = first_change(f"{tb}.emg_sensor", m1, "0")
    r1 = first_change(f"{tb}.state_dbg", m1, "1000")
    g1 = first_change(f"{tb}.state_dbg", r1, "0011")
    events = {"T5": {"from": a, "to": b,
                     "markers": {"A": e1, "B": y1, "C": m1, "D": e0, "E": r1}}}
    with open(PAPER / "results.tex", "a", encoding="ascii") as f:
        f.write("%% T5 event times (GTKWave markers A..E), in clock cycles\n")
        f.write("\\newcommand{\\WaveDbLat}{%d}\n" % round((s1 - e1) / 10 + 0.5))   # rising edges
        f.write("\\newcommand{\\WaveYellow}{%d}\n" % round((m1 - y1) / 10))
        f.write("\\newcommand{\\WaveRecover}{%d}\n" % round((g1 - r1) / 10))

    a, b = test_window(2)
    a += 340                                          # from the end of the first green
    p1 = first_change(f"{tb}.ped_btn", a, "1")
    q1 = first_change(f"{tb}.ped_req_dbg", a, "1")
    w1 = first_change(f"{tb}.state_dbg", a, "0110")
    g2 = first_change(f"{tb}.state_dbg", w1, "0011")
    events["T2"] = {"from": a, "to": b, "markers": {"A": p1, "B": q1, "C": w1, "D": g2}}
    (FIG / "wave_events.json").write_text(json.dumps(events, indent=2) + "\n")
    for t, e in events.items():
        print(f"wrote figures/wave_events.json  {t}: {e['from']:.0f}..{e['to']:.0f} ns, "
              + ", ".join(f"{k}={v:.0f}" for k, v in e["markers"].items()))


if __name__ == "__main__":
    results()
    figures()
