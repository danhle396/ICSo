"""
CE2031 Project 23 - Traffic Light Controller FSM with Emergency Override
Golden model: cycle-accurate model of traffic_top, written from PLAN.md 1.3
(not from the RTL), and a scoreboard that compares it with the RTL trace.

    python -I model/golden.py vectors/stim_seed1.txt vectors/rtl_seed1.txt [log]

The stimulus file gives, for every rising edge of clk, the inputs just before
the edge; the trace gives the outputs of the RTL just before the same edge.
The model replays the stimulus and predicts the outputs of every cycle:

  strobe_gen      sample every DB_DIV cycles
  sync_debounce   2 flip-flops, then 3 equal samples to change the output
                  (emg, ped, car_ns, car_ew, fast)
  clk_divider     tick every DIV cycles (TICK_DIV, FAST_DIV with fast), count
                  cleared when a phase starts or when fast changes
  state_timer     load the duration of the new phase / count ticks down / hold
                  at 1 during a green extension
  FSM             9 states, rules 1-7 of PLAN 1.3, lights from the next state
  bin2bcd8        time_left in BCD

rst_n is asynchronous: when it is 0 at an edge the registers are already in
their reset state before that edge.
Prints the first 10 mismatches; the last line is "PASS, 0 mismatch" or
"FAIL, N mismatches".
"""
import re
import sys
from pathlib import Path

NS_G, NS_Y, RED1, EW_G, EW_Y, RED2, PED_WALK, EMERGENCY, RECOVER = range(9)
NAMES = ["NS_G", "NS_Y", "RED1", "EW_G", "EW_Y", "RED2", "PED_WALK", "EMERGENCY", "RECOVER"]
L_R, L_Y, L_G = 0b100, 0b010, 0b001


class Debounce:
    """2-flip-flop synchronizer and 3-sample debouncer."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.s1 = self.s2 = self.sh = self.dout = 0

    def step(self, din, sample):
        if sample:
            v = ((self.sh & 0b11) << 1) | self.s2
            self.sh = v
            if v == 0b111:
                self.dout = 1
            elif v == 0b000:
                self.dout = 0
        self.s2 = self.s1
        self.s1 = din


class Controller:
    def __init__(self, p):
        self.p = p
        self.db = {n: Debounce() for n in ("emg", "ped", "cns", "cew", "fast")}
        self.reset()

    def reset(self):
        p = self.p
        for d in self.db.values():
            d.reset()
        self.scnt = 0                       # strobe_gen
        self.ped_q = 0
        self.dcnt = 0                       # clk_divider
        self.fast_q = 0
        self.tick_q = 0
        self.tcnt = p["T_G"]                # state_timer
        self.state = NS_G                   # FSM
        self.next_ew = 0
        self.ext_cnt = 0
        self.ped_req = 0
        self.emg_active = 0
        self.light_ns, self.light_ew, self.ped_lamp = L_G, L_R, 0

    # outputs before the edge
    def outputs(self):
        t = self.tcnt
        return (self.state, self.light_ns, self.light_ew, self.ped_lamp,
                ((t // 10) << 4) | (t % 10), self.emg_active)

    def duration(self, s):
        p = self.p
        return {NS_G: p["T_G"], EW_G: p["T_G"], NS_Y: p["T_Y"], EW_Y: p["T_Y"],
                RED1: p["T_R"], RED2: p["T_R"], PED_WALK: p["T_WALK"],
                RECOVER: p["T_RC"], EMERGENCY: 0}[s]

    def next_state(self, emg, done, car_ns, car_ew):
        p, s = self.p, self.state
        room = (not self.ped_req) and self.ext_cnt < p["T_G_MAX"] - p["T_G"]
        if s == NS_G:
            if emg:
                return NS_Y, False
            if done and not car_ew and room:
                return NS_G, True
            return (NS_Y if done else NS_G), False
        if s == EW_G:
            if emg:
                return EW_Y, False
            if done and not car_ns and room:
                return EW_G, True
            return (EW_Y if done else EW_G), False
        if s == NS_Y:
            return ((EMERGENCY if emg else RED1) if done else NS_Y), False
        if s == EW_Y:
            return ((EMERGENCY if emg else RED2) if done else EW_Y), False
        if s in (RED1, RED2):
            if emg:
                return EMERGENCY, False
            if done:
                if self.ped_req:
                    return PED_WALK, False
                return (EW_G if s == RED1 else NS_G), False
            return s, False
        if s == PED_WALK:
            if emg:
                return EMERGENCY, False
            if done:
                return (EW_G if self.next_ew else NS_G), False
            return s, False
        if s == EMERGENCY:
            return (RECOVER if not emg else EMERGENCY), False
        if s == RECOVER:
            if emg:
                return EMERGENCY, False
            if done:
                if self.ped_req:
                    return PED_WALK, False
                return (EW_G if self.next_ew else NS_G), False
            return s, False
        return NS_G, False

    # one rising edge with inputs (ped, emg, cns, cew, fast)
    def edge(self, ped, emg_in, cns, cew, fast):
        p = self.p
        # values before the edge
        sample = 1 if p["DB_DIV"] == 1 else int(self.scnt == p["DB_DIV"] - 1)
        emg = self.db["emg"].dout
        ped_clean = self.db["ped"].dout
        car_ns, car_ew = self.db["cns"].dout, self.db["cew"].dout
        fast_s = self.db["fast"].dout
        ped_pulse = ped_clean and not self.ped_q
        tick = self.tick_q
        done = tick and self.tcnt == 1

        nxt, extend = self.next_state(emg, done, car_ns, car_ew)
        load = nxt != self.state

        # clk_divider
        div = p["FAST_DIV"] if fast_s else p["TICK_DIV"]
        clr = load or (fast_s != self.fast_q)
        self.tick_q = int((not clr) and self.dcnt == div - 2)
        self.dcnt = 0 if (clr or self.dcnt == div - 1) else self.dcnt + 1
        self.fast_q = fast_s

        # state_timer
        if load:
            self.tcnt = self.duration(nxt)
        elif tick and not extend and self.tcnt != 0:
            self.tcnt -= 1

        # FSM registers
        if load and nxt == NS_Y:
            self.next_ew = 1
        elif load and nxt == EW_Y:
            self.next_ew = 0
        if load and nxt in (NS_G, EW_G):
            self.ext_cnt = 0
        elif extend:
            self.ext_cnt += 1
        if load and nxt == PED_WALK:
            self.ped_req = 0
        elif ped_pulse and self.state != PED_WALK:
            self.ped_req = 1
        self.emg_active = emg
        self.light_ns = {NS_G: L_G, NS_Y: L_Y}.get(nxt, L_R)
        self.light_ew = {EW_G: L_G, EW_Y: L_Y}.get(nxt, L_R)
        self.ped_lamp = int(nxt == PED_WALK)
        self.state = nxt

        # input conditioning
        self.ped_q = ped_clean
        for name, din in (("emg", emg_in), ("ped", ped), ("cns", cns), ("cew", cew), ("fast", fast)):
            self.db[name].step(din, sample)
        if p["DB_DIV"] > 1:
            self.scnt = 0 if self.scnt == p["DB_DIV"] - 1 else self.scnt + 1


def read_vectors(path):
    rows, header = [], ""
    for line in Path(path).read_text().splitlines():
        if line.startswith("#"):
            header += line + "\n"
        elif line.strip():
            rows.append(line.split())
    return header, rows


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    stim_path, rtl_path = sys.argv[1], sys.argv[2]
    log_path = sys.argv[3] if len(sys.argv) > 3 else None
    header, stim = read_vectors(stim_path)
    _, rtl = read_vectors(rtl_path)
    p = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", header)}
    for k in ("TICK_DIV", "FAST_DIV", "DB_DIV", "T_G", "T_G_MAX", "T_Y", "T_R", "T_WALK", "T_RC"):
        if k not in p:
            raise SystemExit(f"{stim_path}: parameter {k} missing from the header")

    m = Controller(p)
    lines, mismatches = [], 0
    n = min(len(stim), len(rtl))
    lines.append(f"golden model: {stim_path} vs {rtl_path}")
    lines.append("parameters: " + " ".join(f"{k}={v}" for k, v in p.items()))
    if len(stim) != len(rtl):
        lines.append(f"warning: {len(stim)} stimulus lines, {len(rtl)} trace lines")
    for i in range(n):
        cyc, rst_n, ped, emg, cns, cew, fast = (int(x, 2) if j else int(x) for j, x in enumerate(stim[i]))
        if rst_n == 0:
            m.reset()
        exp = m.outputs()
        r = rtl[i]
        if "x" in "".join(r[1:]) or "z" in "".join(r[1:]):
            got = None
        else:
            got = (int(r[1]), int(r[2], 2), int(r[3], 2), int(r[4], 2), int(r[5], 16), int(r[6], 2))
        if got != exp:
            mismatches += 1
            if mismatches <= 10:
                lines.append(
                    f"MISMATCH cycle {cyc}: expected state {NAMES[exp[0]]} NS={exp[1]:03b} EW={exp[2]:03b} "
                    f"walk={exp[3]} time_left={exp[4]:02x} emg={exp[5]} | RTL {' '.join(r[1:])}")
        if rst_n:
            m.edge(ped, emg, cns, cew, fast)
    lines.append(f"cycles compared: {n}")
    lines.append("PASS, 0 mismatch" if mismatches == 0 else f"FAIL, {mismatches} mismatches")
    text = "\n".join(lines)
    print(text)
    if log_path:
        Path(log_path).write_text(text + "\n")
    sys.exit(0 if mismatches == 0 else 1)


if __name__ == "__main__":
    main()
