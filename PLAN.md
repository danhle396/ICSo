# Project 23 — Traffic Light Controller FSM with Emergency Override

**Kế hoạch thực hiện chi tiết** · CE2031 Digital IC Design · Team 04
Le Thanh Danh (23CE010, RTL Architect) · Phan Duy Luan (23CE041, Verification & Physical Lead)
Board: Altera DE2, Cyclone II EP2C35F672C6 · Quartus II 13.0 SP1 Web Edition · Báo cáo cuối kỳ: **LaTeX (IEEEtran), tiếng Anh**

Tài liệu gốc: `CE2031_Milestone1_Proposal.pdf` (proposal đã nộp). Mọi thông số dưới đây lấy từ proposal;
chỗ nào bổ sung / làm rõ so với proposal đều được đánh dấu **[bổ sung]**.

**Rev 2 (29/10/2026):** rà soát lại theo tên đề tài và yêu cầu chạy trên DE2 nạp bằng Quartus II 13.0 SP1. Mọi điểm chưa chắc
đã được thử thật trên máy của nhóm (iverilog 0.9.7 + converter của lab 4, ModelSim-Altera 10.1d, Quartus 13.0 SP1 cho
EP2C35F672C6) bằng một prototype khả thi; chỗ sửa đánh dấu **[rev2]**, bằng chứng ở §12.

---

## 0. Định nghĩa "xong" (Definition of Done)

Đề tài được coi là hoàn thành khi **tất cả** các điều sau đúng:

| # | Tiêu chí | Bằng chứng |
|---|----------|-----------|
| D1 | RTL tổng hợp được, không latch, không warning nghiêm trọng | `quartus_map` report: 0 latch, 0 critical warning |
| D2 | Mô phỏng tự kiểm tra **PASS** (ca biên + ngẫu nhiên, ≥ 3 seed) | `logs/traffic_tb_seed*.log` |
| D3 | Golden model Python khớp RTL từng chu kỳ | `logs/golden_seed*.log` → `PASS, 0 mismatch` |
| D4 | 3 SVA của proposal không bị vi phạm | `traffic_checker.sv` PASS trên iverilog **và** ModelSim ASE; `traffic_sva.sv` biên dịch sạch (ModelSim ASE không thực thi SVA, §4.2) **[rev2]** |
| D5 | Coverage: 9/9 trạng thái, 100 % cung chuyển trạng thái | bảng coverage in cuối log TB |
| D6 | Mutant test: checker bắt được lỗi cố tình cài | `logs/mutant_*.log` → `FAILED` (như mong đợi) |
| D7 | Fmax ≥ 100 MHz, ≤ 300 LE, 0 bit M4K (Table 1 proposal) | Fitter + TimeQuest (*Slow Model Fmax Summary*) |
| D8 | So sánh Binary / Gray / One-Hot (LE, Fmax) | `logs/enc_*/` + bảng trong báo cáo |
| D9 | **Chạy được trên board DE2**: 9 kịch bản demo (§7) đúng kỳ vọng | ảnh/video board + checklist §7.3 |
| D10 | Báo cáo LaTeX tiếng Anh biên dịch 0 lỗi, mọi con số lấy từ log thật | `paper/Nhom5_..._FINAL.pdf` |

**Đối chiếu với tên đề tài** **[rev2]** — mỗi cụm trong "Traffic Light Controller FSM with Emergency Override" có phần hiện thực
và bằng chứng riêng:

| Cụm từ | Hiện thực | Bằng chứng |
|--------|-----------|-----------|
| Traffic Light Controller | ngã tư 2 hướng NS/EW, chu kỳ 2 × (10 + 3 + 1) = 28 s, đèn đi bộ, kéo dài xanh khi hướng kia không có xe | T1–T4, T13–T15 · B1–B3, B7 |
| FSM | Moore 9 trạng thái (§1.3), đầu ra từ thanh ghi; Quartus nhận ra FSM, so sánh Binary / Gray / One-Hot | coverage 9/9 trạng thái + 24 cung · D8 |
| Emergency Override | `emg` → đang xanh thì vàng đủ T_Y → toàn đỏ `EMERGENCY` (giữ tới khi thả, không timeout) → `RECOVER` → nhường hướng kia | `a_emg`, `a_yel`, `a_allred`, `a_ylen` · T5–T9, T16, T17 · B4–B6, B9 |

---

## 1. Đặc tả chức năng (chốt)

### 1.1 Thông số

| Tham số | Giá trị board | Giá trị mô phỏng | Ghi chú |
|---------|--------------|------------------|---------|
| `f_clk` | 50 MHz (CLOCK_50) | 10 ns period | |
| `TICK_DIV` | 50 000 000 (1 Hz) | 4 | 26 bit = ⌈log₂ 5·10⁷⌉ |
| `FAST_DIV` **[bổ sung]** | 5 000 000 (10 Hz) | 2 | SW[17]=1: chạy nhanh ×10 để demo |
| `T_G` | 10 s | 10 tick | Green |
| `T_G_MAX` | 15 s | 15 tick | Green tối đa khi kéo dài |
| `T_Y` | 3 s | 3 tick | Yellow |
| `T_R` | 1 s | 1 tick | All-red (RED1/RED2) |
| `T_WALK` | 5 s | 5 tick | PED_WALK |
| `T_RC` **[bổ sung]** | 2 s | 2 tick | RECOVER (proposal không ghi số) |
| `DB_DIV` **[bổ sung]** | 250 000 (200 Hz, 5 ms/mẫu) **[rev2]** | 1 (mỗi clk) | cần 3 mẫu bằng nhau: xung < 10 ms bị lọc, ≥ 15 ms chắc chắn qua → đủ cho dội SW (thường < 10 ms); 1 kHz (≈ 3 ms) là sát |

Chu kỳ bình thường: `T_cycle = 2(T_G + T_Y + T_R) = 28 s`.

### 1.2 I/O của `traffic_top` (Table 2 proposal)

| Tín hiệu | W | Dir | Mô tả |
|----------|---|-----|-------|
| `clk` | 1 | in | 50 MHz |
| `rst_n` | 1 | in | reset tích cực mức thấp (async assert, sync deassert ở `de2_top`) |
| `fast` **[bổ sung]** | 1 | in | 1 = tick 10 Hz |
| `ped_btn` | 1 | in | nút người đi bộ (mức cao = đang bấm) |
| `emg_sensor` | 1 | in | cảm biến còi xe ưu tiên |
| `car_ns`, `car_ew` | 1+1 | in | có xe chờ ở hướng NS / EW |
| `light_ns[2:0]`, `light_ew[2:0]` | 3+3 | out | `{R,Y,G}`, one-hot, ra từ thanh ghi |
| `ped_lamp` | 1 | out | đèn đi bộ |
| `time_left[7:0]` | 8 | out | thời gian còn lại, **BCD** 2 chữ số |
| `emergency_active` | 1 | out | cờ đã nhận yêu cầu khẩn cấp |
| `state_dbg[3:0]`, `ped_req_dbg`, `tick_dbg` **[bổ sung]** | | out | chỉ để hiển thị debug trên board |

### 1.3 Bảng chuyển trạng thái (Moore, 9 trạng thái)

Ký hiệu: `done = tick & (cnt == 1)` (tick cuối cùng của pha) · `emg` = emergency đã đồng bộ + lọc nhiễu
(trong RTL/SVA tên là `emg_sync` = đầu ra `sync_debounce` của SW[0]) **[rev2]** ·
`ped` = yêu cầu đi bộ đã chốt · `ext_ok = !car_opposite & !ped & (ext_cnt < T_G_MAX − T_G)`.
Thứ tự ưu tiên trong mỗi ô: **emg > done & ext_ok > done & ped > done > giữ nguyên**.

| State | Đèn NS | Đèn EW | ped_lamp | Điều kiện → Next | Timer nạp |
|-------|--------|--------|----------|------------------|-----------|
| `NS_G` (0) | G | R | 0 | `emg` → NS_Y · `done & ext_ok` → NS_G (kéo dài 1 tick) · `done` → NS_Y | T_G |
| `NS_Y` (1) | Y | R | 0 | `done & emg` → EMERGENCY · `done` → RED1 | T_Y |
| `RED1` (2) | R | R | 0 | `emg` → EMERGENCY · `done & ped` → PED_WALK · `done` → EW_G | T_R |
| `EW_G` (3) | R | G | 0 | đối xứng NS_G (`car_ns` thay `car_ew`) → EW_Y | T_G |
| `EW_Y` (4) | R | Y | 0 | `done & emg` → EMERGENCY · `done` → RED2 | T_Y |
| `RED2` (5) | R | R | 0 | `emg` → EMERGENCY · `done & ped` → PED_WALK · `done` → NS_G | T_R |
| `PED_WALK` (6) | R | R | 1 | `emg` → EMERGENCY · `done` → (`next_ew` ? EW_G : NS_G) | T_WALK |
| `EMERGENCY` (7) | R | R | 0 | `!emg` → RECOVER · còn lại giữ | 0 |
| `RECOVER` (8) | R | R | 0 | `emg` → EMERGENCY · `done & ped` → PED_WALK · `done` → (`next_ew` ? EW_G : NS_G) | T_RC |

Quy tắc phụ (chốt để RTL và golden model giống hệt nhau):

1. **Khẩn cấp khi đang xanh → vào vàng ngay, chạy đủ T_Y, rồi mới EMERGENCY.** Không cho xanh nhảy thẳng sang đỏ:
   vừa không an toàn, vừa làm fail assertion `a_yel` trong proposal. Khi đang vàng thì chờ hết vàng.
2. `next_ew` (1 bit): đặt = 1 khi vào NS_Y, = 0 khi vào EW_Y → hướng vừa bị cắt sẽ nhường lượt sau RECOVER / PED_WALK.
3. `ped_req`: set ở cạnh lên của `ped_clean` khi state ≠ PED_WALK; clear khi vào PED_WALK (clear thắng set nếu trùng chu kỳ).
   Bấm trong PED_WALK bị bỏ qua. Khẩn cấp ngắt PED_WALK: người đi bộ mất lượt (đã được phục vụ một phần).
4. Timer: khi `next_state != state` → nạp thời lượng của `next_state`; ngược lại nếu `tick & cnt != 0` → `cnt − 1`;
   khi kéo dài (`done & ext_ok`) → giữ `cnt = 1`, `ext_cnt + 1`. `ext_cnt` về 0 khi vào pha xanh.
   **[rev2]** Cùng chu kỳ nạp (`load`), **bộ chia tick được restart** → tick đầu tiên của pha mới đến sau đúng `TICK_DIV` chu kỳ,
   nên mọi pha dài đúng `T·TICK_DIV` chu kỳ, kể cả pha vào *lệch nhịp tick* (vàng do khẩn cấp, RECOVER khi thả khẩn cấp).
   Nếu để bộ chia chạy tự do, vàng do khẩn cấp chỉ còn `(T_Y−1)·TICK_DIV + 1` chu kỳ (≈ 2 s thay vì 3 s trên board), vi phạm
   quy tắc 1 (đã tái hiện bằng mô phỏng, §12). Chuyển pha bình thường (do `done`) không đổi: lúc đó bộ chia vốn đang quay về 0.
5. `emergency_active` = thanh ghi, `<= emg` → trễ đúng 1 clk sau `emg_sync` (≤ 3 clk theo Table 1).
6. Đèn ra từ thanh ghi: `light_* <= decode(next_state)` → cùng chu kỳ với thanh ghi state, không glitch.
7. Reset → `NS_G`, timer = T_G, `next_ew = 0`, `ped_req = 0`, `ext_cnt = 0`.

Hệ quả cần kiểm chứng **[rev2]**:
(a) độ trễ xấu nhất từ lúc `emg_sync` lên 1 đến `state = EMERGENCY` (toàn đỏ) = **`T_Y·TICK_DIV + 1`** chu kỳ (xảy ra khi đang
xanh; prototype đo được 13 với `TICK_DIV = 4`). Tính từ chân SW[0] thì cộng 2 clk đồng bộ + 3 mẫu debounce (≤ 15 ms) → ≈ 3.015 s trên board.
(b) mỗi pha vàng dài đúng `T_Y·TICK_DIV` chu kỳ, dù vào vàng do `done` hay do `emg`.

---

## 2. Cấu trúc thư mục

```
project23_traffic/
├── PLAN.md                  ← file này
├── rtl/
│   ├── clk_divider.sv       tick_1s (26 bit, TICK_DIV / FAST_DIV, restart khi đổi pha)
│   ├── strobe_gen.sv        xung lấy mẫu DB_DIV cho debouncer
│   ├── sync_debounce.sv     2-FF synchronizer + debouncer 3 mẫu
│   ├── state_timer.sv       down-counter 8 bit: load / dec / hold, ra cnt
│   ├── traffic_fsm.sv       FSM 9 state + ped_req + next_ew + ext_cnt + thanh ghi đèn
│   ├── bin2bcd8.sv          cnt (0..99) → 2 chữ số BCD (double dabble)
│   └── traffic_top.sv       ghép tất cả (Fig. 1 proposal)
├── tb/
│   ├── traffic_tb.sv        TB tự kiểm tra: directed + constrained-random, ghi trace
│   ├── traffic_checker.sv   checker procedural tương đương các SVA (iverilog 0.9.7 + ModelSim ASE) → nguồn kết quả D4
│   └── traffic_sva.sv       đặc tả SVA (bind); ModelSim ASE chỉ biên dịch, không thực thi (§4.2)
├── model/
│   └── golden.py            golden model cycle-accurate + scoreboard
├── vectors/                 stim_seed*.txt, rtl_seed*.txt (sinh ra khi chạy)
├── quartus/
│   ├── de2_traffic.qpf/.qsf  MỘT project duy nhất, top = de2_top
│   ├── de2_traffic.sdc
│   ├── de2_top.sv            wrapper board: đảo KEY, reset sync, HEX, LED
│   └── run_quartus.tcl       compile + TimeQuest + so sánh encoding
├── run_sim.ps1              iverilog (+ down-convert cho 0.9.7) → logs/
├── run_modelsim.ps1         ModelSim ASE: chạy lại TB + checker (simulator thứ 2), biên dịch SVA
├── logs/                    mọi log/report làm nguồn số liệu cho báo cáo
└── paper/
    ├── Nhom5_LETHANHDANH_FINAL.tex   IEEEtran, tiếng Anh
    ├── make_figures.py               log → results.tex (macro số liệu) + waveform TikZ
    ├── capture_gtkwave.ps1           chụp GTKWave thật
    ├── figures/  photos/
    └── results.tex
```

Quy ước code (để chạy được cả iverilog 0.9.7, ModelSim ASE và Quartus 13):
- SystemVerilog thật (`logic`, `always_ff`, `always_comb`, `unique case`), `run_sim.ps1` tự down-convert như lab 1–4.
- **Không dùng `enum`** — mã trạng thái là `localparam [3:0]` (0.9.7 không có enum; Quartus vẫn nhận ra FSM).
- Không dùng `$urandom` (dùng `$random(seed)`), không `++` trong RTL, mọi `always_comb` có gán mặc định.
- Không đưa thanh ghi state trực tiếp ra pin trong top (để Quartus re-encode được); `state_dbg` lấy qua decode.
- **[rev2]** Converter của lab đổi mọi `logic` → `reg` và `output logic` → `output reg`. Vì vậy **net nối giữa các instance và
  mọi tín hiệu gán bằng `assign` phải khai báo `wire`** (kể cả cổng ra của `traffic_top` lấy từ instance con: `output wire`);
  `logic` chỉ dùng cho biến gán trong `always_*`. Đã thử: `logic` nối instance → 0.9.7 báo
  *"reg … cannot be driven by primitives or continuous assignment"* (lab 1–4 mỗi lab một module nên chưa gặp).
- **[rev2]** Biểu thức có thể suy biến thành hằng theo parameter (vd. `strobe` khi `DB_DIV = 1`) phải viết `assign`, không viết
  `always_comb`: sau khi convert thành `always @*` thì không có tín hiệu nhạy nào → **khối không bao giờ chạy**, ra X
  (prototype gặp đúng lỗi này: debouncer đứng im, FSM không bao giờ vào PED_WALK/EMERGENCY).
- **[rev2]** Không dùng `'0`/`'1`, `.*`, `.name` (0.9.7 báo lỗi cú pháp); `$clog2` dùng được.
- Checker dùng immediate assertion `assert (c) else $error(...)` trong `always @(posedge clk)`: chạy được trên ModelSim ASE,
  converter đổi thành `if (!(c))` cho 0.9.7.

---

## 3. RTL — công việc theo module

| ID | Module | Nội dung chính | Người | Kiểm tra đơn vị |
|----|--------|----------------|-------|-----------------|
| R1 | `clk_divider` | `cnt` 0..DIV−1, chọn DIV theo `fast`; `cnt` về 0 khi đổi `fast` hoặc khi **`restart` = `load` của timer** **[rev2]** (quy tắc 4); `tick` ra từ thanh ghi: `tick <= !clr & (cnt == DIV−2)` — trùng từng chu kỳ với `cnt == DIV−1` tổ hợp nhưng đưa phép so sánh 26 bit ra khỏi đường FSM (cần DIV ≥ 2) | Danh | đếm tick trong N chu kỳ; sau restart tick đầu cách đúng DIV |
| R2 | `strobe_gen` | như R1, DIV = DB_DIV (DB_DIV = 1 → luôn 1, viết bằng `assign`, xem quy ước code) | Luân | — |
| R3 | `sync_debounce` | `s1<=in; s2<=s1;` khi `sample`: `sh<={sh[1:0],s2}` và `out<=1` nếu `{sh[1:0],s2}==3'b111`, `out<=0` nếu `==3'b000`, ngược lại giữ (chốt chính xác để golden model khớp) **[rev2]** · 5 instance: emg, ped, car_ns, car_ew, fast | Luân | glitch 1, 2 mẫu bị lọc; 3 mẫu qua |
| R4 | `state_timer` | load / dec on tick / hold, `cnt[7:0]`, `last = (cnt == 1)` | Danh | load, đếm về 0, hold |
| R5 | `traffic_fsm` | bảng §1.3 + quy tắc 1–7; 2 khối: `always_comb` next-state, `always_ff` state/đèn/ped_req/next_ew/ext_cnt/emg_active; `ext_cnt` 3 bit (≤ T_G_MAX − T_G = 5) | Danh | qua TB tổng |
| R6 | `bin2bcd8` | 0..99 → `{tens, ones}`, thuần tổ hợp, **double dabble (dịch + cộng 3)** **[rev2]**. Không dùng vòng lặp trừ 10 (prototype: 159 LE, riêng nó đẩy tổng lên 365 LE > 300); không dùng ROM (giữ 0 bit M4K). Double dabble: 24 LE | Luân | quét 0..99 |
| R7 | `traffic_top` | nối R1–R6 bằng `wire`; `load` của FSM → `restart` của R1 **[rev2]**; cạnh lên `ped_clean` → `ped_pulse` | Danh | — |
| R8 | `de2_top` | xem §6 | Luân | compile + board |

Lint: chạy `quartus_map` sớm (tuần RTL) để bắt latch / width mismatch; cả hai người cross-review code của nhau.

---

## 4. Kiểm chứng (Verification)

### 4.1 Kiến trúc testbench

```
        ┌──────────── traffic_tb ─────────────┐
 seed → │ stimulus gen (directed + random) ───┼──► DUT traffic_top (TICK_DIV=4, DB_DIV=1)
        │       │                             │        │
        │       └─► vectors/stim_seedN.txt    │        ├─► traffic_checker (always @posedge)
        │                                     │        ├─► traffic_sva (bind; ModelSim ASE chỉ biên dịch)
        │ trace writer ◄───────────────────────────────┘
        │       └─► vectors/rtl_seedN.txt     │
        │ coverage: state + transition        │
        └─────────────────────────────────────┘
 model/golden.py  stim_seedN.txt ──► mô hình Python ──► so với rtl_seedN.txt ──► PASS/FAIL
```

- Mỗi dòng stim: `cycle rst_n ped_btn emg_sensor car_ns car_ew fast`.
- Mỗi dòng trace: `cycle state light_ns light_ew ped_lamp time_left emergency_active`.
- `golden.py` mô hình **toàn bộ** đường đi (divider kể cả restart, sync 2 FF, debouncer, timer, FSM) theo đúng §1.3, so từng chu kỳ,
  in 10 mismatch đầu tiên, ghi `logs/golden_seedN.log`. Seed cố định: 1, 7, 2026.

### 4.2 Checker (3 SVA của proposal + bổ sung)

| Tên | Thuộc tính | Nguồn |
|-----|-----------|-------|
| `a_safe` | `!(green_ns && green_ew)` mọi cạnh clk | proposal (bắt buộc) |
| `a_emg` | `$rose(emg_sync) \|-> ##[1:3] emergency_active` | proposal |
| `a_yel` | `$fell(green_ns) \|-> yellow_ns` (và EW) | proposal |
| `a_onehot` **[bổ sung]** | mỗi hướng đúng 1 đèn sáng | |
| `a_ped` **[bổ sung]** | `ped_lamp \|-> red_ns && red_ew` | |
| `a_allred` **[bổ sung]** | `emg_sync` giữ ≥ L chu kỳ → toàn đỏ trong L = `T_Y·TICK_DIV+1` **[rev2]** | |
| `a_gmax` **[bổ sung]** | pha xanh ≤ `T_G_MAX·TICK_DIV` chu kỳ | |
| `a_ylen` **[rev2]** | mỗi pha vàng (NS, EW) dài đúng `T_Y·TICK_DIV` chu kỳ, trừ khi bị reset cắt | quy tắc 1 + 4 |

- **[rev2] Đã thử (29/10/2026): ModelSim-Altera Starter Edition 10.1d KHÔNG thực thi concurrent SVA.** `vlog -sv` vẫn biên dịch
  `assert property` / `bind` nhưng báo *"(randomization, coverage or assertion) detected … only supported in Questasim"*; `vsim` báo
  `(vsim-8311) System Verilog assertions are supported only in Questasim`, và một assertion cố tình sai không hề fail.
  Immediate assertion (`assert (c) else $error`) thì chạy bình thường.
- Vì vậy **`traffic_checker.sv` (procedural: bộ đếm chu kỳ + immediate assert, cùng ngữ nghĩa với bảng trên) là nguồn kết quả D4**,
  chạy trên iverilog 0.9.7 (qua converter) và ModelSim ASE (simulator thứ 2 để đối chứng). `traffic_sva.sv` giữ làm đặc tả hình thức
  trong báo cáo, chỉ yêu cầu `vlog -sv` biên dịch sạch; ghi rõ điều này trong paper. Muốn chạy SVA thật thì cần Questa
  (vd. Questa–Intel FPGA Starter Edition, license miễn phí): tuỳ chọn, không thuộc DoD.
- Mọi thuộc tính `disable iff (!rst_n)`; checker procedural xoá lịch sử khi `rst_n = 0`; TB giữ `rst_n = 0` qua ≥ 1 cạnh clk.
  Nếu không, reset giữa EW_G làm `a_yel` báo sai (xanh → đỏ không qua vàng là hành vi đúng của reset).

### 4.3 Danh sách test directed (corner cases trong proposal)

| T# | Kịch bản | Kỳ vọng |
|----|----------|---------|
| T1 | Reset rồi chạy 2 chu kỳ đầy đủ, không xe/không nút, `car_*=1` cả hai | đúng trình tự 10-3-1-10-3-1, 28 tick/chu kỳ |
| T2 | Bấm nút khi NS_Y | PED_WALK sau RED1, rồi EW_G |
| T3 | Bấm liên tục / giữ nút | chỉ 1 PED_WALK, không lặp |
| T4 | Bấm trong PED_WALK | bị bỏ qua |
| T5 | Emergency khi NS_G | NS_Y đủ 3 tick → EMERGENCY → (thả) RECOVER → EW_G |
| T6 | Emergency khi NS_Y | hết vàng → EMERGENCY |
| T7 | Emergency khi PED_WALK | EMERGENCY ngay, ped_lamp tắt |
| T8 | Emergency cùng lúc với nút đi bộ | EMERGENCY trước, sau RECOVER phục vụ PED_WALK |
| T9 | 2 emergency liền nhau (thả trong RECOVER) | RECOVER → EMERGENCY lại |
| T10 | Reset giữa pha | về NS_G, timer = T_G ngay |
| T11 | Glitch 1 và 2 chu kỳ trên emg / ped | bị lọc, FSM không đổi |
| T12 | Glitch đúng 3 chu kỳ | được nhận |
| T13 | Không có xe hướng EW | NS_G kéo dài tới 15 tick rồi nhường |
| T14 | Có xe EW xuất hiện giữa lúc kéo dài | dừng kéo dài ở tick kế |
| T15 | `fast` = 1 | tick nhanh hơn đúng tỉ lệ |
| T16 | Emergency kéo dài rất lâu | giữ toàn đỏ, không timeout |
| T17 **[rev2]** | Emergency khi đang xanh, lệch pha so với tick (quét mọi offset 0..TICK_DIV−1) | vàng đúng `T_Y·TICK_DIV` chu kỳ rồi mới EMERGENCY |
| T18 **[thực hiện]** | Emergency ngay sau vàng (rơi vào RED1 / RED2), trong EW_G; nút bấm phục vụ sau RED2 | phủ các cung RED1→EMG, EW_G→EW_Y (emg), EW_Y→EMG, RED2→EMG, RED2→PED, PED→NS_G, RECOVER→NS_G |

Sau directed: **≥ 20 000 chu kỳ random** mỗi seed (xác suất: emg bật 1/400 chu kỳ, giữ 5–60 chu kỳ; nút 1/150; glitch 1/50;
xe đổi 1/80; reset 1/5000). **[thực hiện]** 30 000 chu kỳ/seed, thêm `fast` đổi 1/4000. Mọi số ngẫu nhiên của một chu kỳ
được rút **trước**, không gọi `$random` trong điều kiện: SystemVerilog (ModelSim) đánh giá ngắn mạch `&&` nên bỏ qua lời gọi,
còn iverilog 0.9.7 thì không → hai simulator ra chuỗi kích thích khác nhau (đã gặp; sửa xong thì trace giống hệt từng chu kỳ).
T18 được thêm vì cung RED1→EMERGENCY gần như không xảy ra với random (RED1 chỉ 4 chu kỳ < độ trễ debounce 5 chu kỳ).

### 4.4 Coverage & mutant

- Coverage in cuối log: số lần thăm mỗi state, mỗi cung trong §1.3: **24 cung** theo điều kiện (NS_G 3, NS_Y 2, RED1 3, EW_G 3,
  EW_Y 2, RED2 3, PED_WALK 3, EMERGENCY 1, RECOVER 4; chưa kể reset). Mục tiêu 100 %; cung nào 0 → thêm test.
- Mutant (`run_sim.ps1` tự tạo, như lab 4), mỗi cái **phải FAIL**:
  M1 xanh → EMERGENCY thẳng (bỏ vàng) → `a_yel` · M2 debouncer 2 mẫu → T11 · M3 bỏ chốt `ped_req` → golden mismatch ·
  M4 NS_Y → EW_G (bỏ RED1) → golden mismatch · M5 `a_safe`: ép `light_ew` = G khi NS_G ·
  M6 **[rev2]** bỏ `restart` của bộ chia tick → `a_ylen` (prototype: vàng ngắn nhất 9/12 chu kỳ).

### 4.5 Script

- `run_sim.ps1`: down-convert (nếu không có `-g2012`) → compile → chạy TB với 3 seed → gọi `python -I model/golden.py` →
  chạy mutant → tổng kết PASS/FAIL ra màn hình và `logs/summary.log`. Sinh `traffic_tb.vcd` + `.gtkw` cho GTKWave.
- `run_modelsim.ps1`: `vlib work; vlog -sv rtl/*.sv tb/*.sv; vsim -c -do "run -all; quit"` → `logs/modelsim_tb.log`
  (TB + checker trên simulator thứ 2, phải ra cùng PASS/coverage như iverilog; SVA chỉ được biên dịch, xem §4.2).

---

## 5. Tổng hợp, STA, so sánh encoding

1. **Một project duy nhất** `quartus/de2_traffic.qpf`, top `de2_top`, là project dùng nạp board (có pin, ra `.sof`).
2. `de2_traffic.sdc`: `create_clock -period 20 [get_ports CLOCK_50]` (50 MHz board);
   `set_false_path` từ KEY/SW (đã qua synchronizer) và tới LED/HEX (tĩnh với mắt người).
   **[rev2]** *Không* dùng `derive_clock_uncertainty`: với Cyclone II, Quartus 13.0 chỉ báo
   `Warning (332153): Family doesn't support jitter analysis` và lệnh không có tác dụng.
   Cyclone II chỉ có 2 timing model **Slow Model / Fast Model** (không có góc "Slow 85 °C" như Cyclone III trở lên):
   Fmax đọc ở *Slow Model Fmax Summary* trong `.sta.rpt`. Để kiểm tra mục tiêu ≥ 100 MHz có slack dương: chạy thêm `quartus_sta`
   với SDC `-period 10` (chỉ tạo report, không đổi project).
3. `run_quartus.tcl` (theo mẫu labSta, cùng 1 project biên dịch nhiều lần):
   - lần 1–3: `set_global_assignment -name STATE_MACHINE_PROCESSING` = `SEQUENTIAL` (binary) / `GRAY` / `ONE-HOT`,
     `export_assignments`, `execute_flow -compile` → copy summary fit/sta vào `logs/enc_binary|gray|onehot/`;
   - lần cuối: encoding chọn cho bản nộp (dự kiến ONE-HOT hoặc AUTO; prototype: AUTO chọn One-Hot) → `output_files/` +
     `logs/timing/` (datasheet, setup, recovery, worst path chi tiết). Encoding của lần cuối cũng là giá trị còn lại trong `.qsf`.
   - Xác nhận encoding thật trong `*.map.rpt` → mục *State Machine - |de2_top|...|state*.
4. Bảng cho báo cáo: LE (tổng + theo entity), register, Fmax, worst slack, critical path. **[rev2]** Theo prototype: với `tick`
   tổ hợp, đường găng là `clk_divider.cnt` 26 bit → so sánh tick → `done` → next-state → timer (≈ 118 MHz); với `tick` thanh ghi
   (R1) chỉ còn timer `cnt` → `cnt == 1` → next-state → timer (≈ 133 MHz, One-Hot). Nếu Fmax < 100 MHz: pipeline phép so sánh
   `cnt == 1`, tách decode đèn (risk plan proposal).
5. (Tuỳ chọn, nếu kịp) Yosys/OpenSTA như proposal — cần cài OSS CAD Suite; không bắt buộc cho DoD.

---

## 6. Hiện thực trên board DE2 (`de2_top`)

### 6.1 Gán chân (Table 3 proposal + debug **[bổ sung]**)

| Chức năng | Tài nguyên DE2 | Pin | Ghi chú |
|-----------|----------------|-----|---------|
| `clk` | CLOCK_50 | PIN_N2 | chân clock chuyên dụng → Global Clock (đã kiểm ở Fitter); các lab trước chưa dùng CLOCK_50 **[rev2]** |
| `rst_n` | KEY[0] | PIN_G26 | KEY tích cực thấp → dùng trực tiếp, qua reset synchronizer |
| `ped_btn` | KEY[1] | PIN_N23 | đảo: `ped_btn = ~KEY[1]` |
| `emg_sensor` | SW[0] | PIN_N25 | |
| `car_ns` / `car_ew` | SW[1] / SW[2] | PIN_N26 / PIN_P25 | |
| `fast` **[bổ sung]** | SW[17] | PIN_V2 | demo nhanh ×10 |
| NS R / Y / G | LEDR[0] / LEDG[1] / LEDG[0] | AE23 / AF22 / AE22 | DE2 không có LED vàng → LEDG làm "Y" |
| EW R / Y / G | LEDR[2] / LEDG[3] / LEDG[2] | AB21 / V18 / W19 | |
| `ped_lamp` | LEDR[17] | PIN_AD12 | |
| `time_left` | HEX1 / HEX0 | (xem `.qsf`) | BCD → 7 đoạn, tích cực thấp |
| `emergency_active` **[bổ sung]** | LEDR[15] | PIN_AE13 | |
| `ped_req` (đang chờ) **[bổ sung]** | LEDR[16] | PIN_AE12 | |
| nhịp tim **[bổ sung]** | LEDG[8] | PIN_Y12 | FF đảo mỗi tick (`hb <= hb ^ tick`) **[rev2]**: xung `tick` chỉ rộng 20 ns, nối thẳng ra LED sẽ không thấy sáng |
| state 0–8 **[bổ sung]** | HEX4 | U9,U1,U2,T4,R7,R6,T3 | số trạng thái theo §1.3 |
| chữ đèn NS / EW **[rev2]** | HEX3 / HEX2 | (xem `.qsf`) | `r` / `y` / `G`: DE2 không có LED vàng, LEDG làm "Y" dễ nhầm với "G" trên ảnh/video |
| HEX5,6,7 | — | | tắt (`7'h7F`) |

Mọi pin còn lại: `RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"` (như các lab trước).
**[rev2]** Khối `set_location_assignment` chép nguyên từ `.qsf` của lab 4 (LEDR/LEDG/HEX, đã nạp board) và labSta (SW[17:0],
KEY[3:0]), thêm `CLOCK_50 → PIN_N2`. Cổng nào khai báo trong `de2_top` thì phải gán chân cho đủ từng bit (prototype: 106 chân,
0 critical warning).

### 6.2 Những điểm riêng của board (khác mô phỏng)

- `TICK_DIV = 50_000_000`, `FAST_DIV = 5_000_000`, `DB_DIV = 250_000` → override parameter trong `de2_top`;
  TB dùng giá trị nhỏ. **Cùng một RTL**, chỉ khác parameter.
- Reset synchronizer 2 FF (assert bất đồng bộ, nhả đồng bộ) trong `de2_top`.
- KEY của DE2 đã có mạch chống dội (Schmitt) nhưng SW thì **dội** → debouncer lấy mẫu 200 Hz (3 mẫu ≈ 10–15 ms) là cần thiết
  cho SW[0..2] và SW[17].
- Thử: gạt SW[0] nhanh liên tục → không được thấy đèn "nháy" sai (kịch bản B9).

---

## 7. Kịch bản demo trên board (hiện thực "chạy được trên board")

### 7.1 Chuẩn bị
1. `quartus/run_quartus.tcl` → có `output_files/de2_traffic.sof`.
2. **[rev2]** Cắm nguồn 9 V và cáp USB vào cổng **USB-Blaster** của DE2; công tắc **RUN/PROG (SW19) ở RUN** (chế độ JTAG).
   Nếu Programmer không thấy phần cứng: cài driver từ `F:\merged_partition_content\altera\quartus\drivers\usb-blaster`
   (Device Manager → Update driver).
3. Programmer → Hardware Setup: USB-Blaster → Mode JTAG → nạp `.sof`, hoặc
   `quartus_pgm -c USB-Blaster -m JTAG -o "p;output_files/de2_traffic.sof"`. `.sof` nằm trong SRAM: tắt nguồn là mất, phải nạp lại.
4. SW[17]=0 (tốc độ thật) hoặc 1 (nhanh khi trình bày). Các SW còn lại = 0, nhấn-thả KEY[0] (reset).

### 7.2 Các kịch bản (làm theo thứ tự, mỗi kịch bản chụp ảnh/quay video)

| B# | Thao tác | Quan sát kỳ vọng |
|----|----------|------------------|
| B1 | Reset, để chạy 1 chu kỳ (SW[1]=SW[2]=1) | HEX4: 0→1→2→3→4→5→0; HEX3-2: `Gr`→`yr`→`rr`→`rG`→`ry`→`rr`; HEX1-0 đếm 10…1, 3…1, 1; LEDG0 (NS G) và LEDG2 (EW G) **không bao giờ cùng sáng** |
| B2 | Trong NS_G, nhấn KEY[1] | LEDR16 sáng (đang chờ); sau NS_Y, RED1 → HEX4 = 6, LEDR17 sáng 5 s, hai hướng đỏ; sau đó EW xanh |
| B3 | Giữ KEY[1] liên tục | chỉ 1 lần PED_WALK |
| B4 | Trong NS_G, gạt SW[0]=1 | LEDR15 sáng ngay; NS vàng **đủ** 3 s (HEX1-0 = 03→01) → HEX4 = 7, tất cả đỏ, HEX1-0 = 00 |
| B5 | Giữ SW[0]=1 vài chục giây, rồi gạt về 0 | vẫn toàn đỏ; khi thả: HEX4 = 8 (RECOVER) 2 s → EW xanh |
| B6 | Đang PED_WALK, gạt SW[0]=1 | LEDR17 tắt ngay, EMERGENCY |
| B7 | SW[2]=0 (không xe EW), SW[1]=1 | NS xanh kéo dài tới 15 s (HEX1-0 dừng ở 01 thêm 5 tick); gạt SW[2]=1 → dừng kéo dài |
| B8 | Đang giữa pha, nhấn KEY[0] | về NS_G, HEX1-0 = 10 ngay |
| B9 **[rev2]** | Trong NS_G, gạt SW[0] lên/xuống nhanh nhiều lần rồi để ở 1 | mỗi lần cắt xanh đều qua vàng đủ 3 s; không lúc nào hai hướng cùng xanh; cuối cùng HEX4 = 7; LEDR15 thôi đổi ngay khi SW[0] đứng yên |

### 7.3 Checklist ảnh cho báo cáo
`photos/raw/` giữ ảnh gốc; `board_B1..B9.jpg` crop vùng LED/HEX (như lab 4). Ghi lại **những gì thực sự quan sát**
(nếu khác kỳ vọng thì báo cáo đúng như quan sát và debug — không sửa số).

---

## 8. Báo cáo LaTeX (tiếng Anh, IEEEtran)

`paper/Nhom5_LETHANHDANH_FINAL.tex` — theo mẫu `lab03_alu/paper_nhom5_alu_rev` và lab 4.
Tiêu đề đề xuất, giữ nguyên tên đề tài **[rev2]**: *Design and Verification of a Traffic Light Controller FSM with Emergency
Override on a Cyclone II FPGA*.

| Mục | Nội dung | Nguồn số liệu |
|-----|----------|---------------|
| Abstract | vấn đề, kết quả chính (LE, Fmax, PASS, demo) | `results.tex` |
| I. Introduction | bối cảnh, đóng góp | |
| II. Specification | Table 1 (target vs. đạt), I/O, công thức `DIV`, `T_cycle` | proposal + log |
| III. Microarchitecture | block diagram TikZ (datapath / control), sơ đồ trạng thái TikZ 9 state, bảng §1.3 | |
| IV. RTL Implementation | từng module, quy tắc coding, chống latch, output register | listing ngắn |
| V. Verification | kiến trúc TB, golden model, SVA, bảng test T1–T17, coverage, mutant | `logs/*.log` |
| VI. Synthesis & Timing | LE theo entity, Fmax, critical path, **so sánh Binary/Gray/One-Hot** | `logs/enc_*`, `logs/timing` |
| VII. FPGA Demonstration | bảng pin, ảnh B1–B9 (figure* 3×3) | `photos/` |
| VIII. Discussion | target vs. đạt, hạn chế (vd. emergency chỉ all-red, 1 cảm biến không biết hướng xe ưu tiên, không có minimum green trước khi bị ngắt), hướng mở rộng | |
| IX. Conclusion · References · Appendix (WBS, đóng góp từng người) | | |

Hình: waveform GTKWave thật (`capture_gtkwave.ps1`) cho T5 (emergency khi xanh) và T2 (pedestrian);
waveform TikZ sinh từ VCD bằng `make_figures.py`. Tất cả con số trong paper là macro trong `results.tex` — không gõ tay.

---

## 9. Tiến độ (theo Table 4 proposal)

| Tuần | Công việc | Danh | Luân | Đầu ra |
|------|-----------|------|------|--------|
| 6 | Chốt spec, sơ đồ FSM, bảng I/O | ✔ proposal | ✔ proposal | file này |
| 7–8 | RTL | R1, R4, R5, R7 | R2, R3, R6 | `rtl/*.sv`, lint sạch |
| 9 | Tích hợp, waveform đầu tiên | T1 chạy | `run_sim.ps1` | VCD + GTKWave |
| 10–11 | TB, golden model, SVA, coverage | review | TB, `golden.py`, SVA, mutant | D2–D6 |
| 12 | Quartus, STA, pin | SDC | `.qsf`, `de2_top` | D1, D7 |
| 13 | Tối ưu, so sánh encoding | `run_quartus.tcl` | bảng kết quả | D8 |
| 14 | Demo DE2, debug | | B1–B9 + ảnh | D9 |
| 15 | Báo cáo + slide nộp | III, IV, VI | V, VII | D10 |

Nếu trễ tiến độ (risk plan proposal): bỏ **kéo dài pha xanh** trước; FSM lõi, emergency override và assertion là bắt buộc.

---

## 10. Rủi ro & cách xử lý

| Rủi ro | Xử lý |
|--------|-------|
| ModelSim ASE không chạy SVA: **đã xác nhận** (vsim-8311) **[rev2]** | `traffic_checker.sv` procedural là nguồn kết quả D4 (chạy trên iverilog + ModelSim ASE); SVA giữ làm đặc tả, ghi rõ trong paper |
| Converter 0.9.7 hỏng khi có nhiều module (`logic` nối instance, `always_comb` hằng) **[rev2]** | theo quy ước code §2; chạy `run_sim.ps1` ngay khi có `traffic_top` đầu tiên (tuần 9) |
| Vượt 300 LE **[rev2]** | `bin2bcd8` double dabble (R6), `ext_cnt` 3 bit; xem LE theo entity trong Fitter sau mỗi lần compile |
| Programmer không thấy USB-Blaster (Windows 11) **[rev2]** | cài driver `quartus\drivers\usb-blaster`; SW19 ở RUN; đổi cổng USB |
| Golden model và RTL lệch 1 chu kỳ | chốt ngữ nghĩa §1.3 trước khi code; so trace từ chu kỳ đầu tiên lệch |
| Quartus không nhận FSM (không re-encode) | không dùng state làm số học / ra pin trực tiếp; kiểm tra mục *State Machine* trong map.rpt |
| SW dội trên board | debouncer 200 Hz × 3 mẫu (≈ 10–15 ms) **[rev2]**; kịch bản B9 |
| Fmax < 100 MHz | pipeline so sánh timer, đăng ký đầu ra decode |
| **Đề Milestone 1 ghi "traffic lights without bus interfaces will be rejected"** | đề tài đã được duyệt là Project 23; nếu GV yêu cầu thêm, mở rộng tuỳ chọn: UART RX/TX 115 200 baud đọc trạng thái, chỉnh `T_G/T_Y` (≈ 1 tuần thêm, làm sau D9) |

---

## 11. Lệnh chạy nhanh

```powershell
cd project23_traffic
.\run_sim.ps1                                   # mô phỏng + golden + mutant → logs\summary.log
gtkwave traffic_tb.vcd traffic_tb.gtkw          # xem waveform
.\run_modelsim.ps1                              # TB + checker trên ModelSim ASE (SVA chỉ biên dịch)
cd quartus
& "F:\merged_partition_content\altera\quartus\bin64\quartus_sh.exe" -t run_quartus.tcl   # compile + STA + encoding
# nạp board (SW19 = RUN): Quartus Programmer, hoặc
& "F:\merged_partition_content\altera\quartus\bin64\quartus_pgm.exe" -c USB-Blaster -m JTAG -o "p;output_files\de2_traffic.sof"
cd ..
python -I paper\make_figures.py                 # logs → paper\results.tex + waveform TikZ
.\paper\capture_gtkwave.ps1                     # ảnh GTKWave thật (T5, T2)
cd paper ; pdflatex Nhom5_LETHANHDANH_FINAL.tex (×2)
```

---

## 12. Kết quả kiểm chứng khả thi (Rev 2, 29/10/2026)

Một prototype viết nhanh theo §1.3 (đủ các module R1–R8 + TB random 40 000 chu kỳ × 3 seed) chỉ để thử các giả định của kế hoạch
trên đúng bộ công cụ của nhóm. **Không phải RTL nộp**; số liệu trong báo cáo vẫn phải lấy từ RTL thật (D10).

| Hạng mục | Cách thử | Kết quả |
|----------|----------|---------|
| Chân DE2 | so với `.qsf` lab 4 / labSta (đã nạp board) + pin report của Fitter | khớp §6.1; 106 chân; CLOCK_50 (PIN_N2) vào Global Clock GCLK2 |
| Quartus 13.0 SP1, EP2C35F672C6 | full compile, 4 encoding | cả 4 lần: 0 latch, 0 critical warning, 0 bit RAM; FSM 9 trạng thái được nhận và re-encode đúng tuỳ chọn |
| Tài nguyên / Fmax (Slow Model) | Fitter + TimeQuest | One-Hot (= AUTO) 234 LE / 133.3 MHz · Gray 242 LE / 133.8 MHz · Binary 256 LE / 125.3 MHz |
| `bin2bcd8` trừ 10 lặp | như trên | 159 LE → tổng 365 LE (vượt 300) → đổi sang double dabble: 24 LE (R6) |
| `tick` tổ hợp vs thanh ghi | TimeQuest + so trace | 118.5 → 133.3 MHz; trace 3 × 40 000 chu kỳ giống hệt nhau |
| Bộ chia tick tự do vs restart | iverilog, stimulus random | tự do: pha vàng 9…12 chu kỳ (FAIL, phải là 12); restart: luôn 12; trễ xấu nhất `emg_sync` → EMERGENCY = 13 = `T_Y·TICK_DIV + 1` |
| ModelSim-Altera 10.1d | probe SVA + immediate assert | concurrent SVA bị bỏ qua (vsim-8311); immediate assert chạy |
| iverilog 0.9.7 + converter lab 4 | probe từng cú pháp | `logic` nối instance, `assign` vào `logic`, `'0`, `.*`, `.name` → lỗi; `always_comb` suy biến hằng → không chạy; `$clog2` OK |
| `derive_clock_uncertainty` | `quartus_sta` | Cyclone II: Warning 332153, không tác dụng → bỏ khỏi SDC |
| `load = (next_state != state)` | `quartus_map` | Quartus vẫn nhận ra FSM → quy tắc 4 giữ nguyên cách viết |

---

## 13. Trạng thái thực hiện (16/11/2026)

Đã hiện thực toàn bộ cây thư mục §2 (RTL, TB, golden, script, Quartus, báo cáo). Mọi số dưới đây lấy từ log của lần chạy
đầy đủ cuối cùng (`run_sim.ps1` → `run_modelsim.ps1` → `run_quartus.tcl` → `make_figures.py`).

| # | Trạng thái | Bằng chứng |
|---|-----------|-----------|
| D1 | ✔ 0 latch, 0 critical warning (cả 3 encoding); đã dọn warning 10230 (cắt bit) | `logs/enc_*/de2_traffic.map.rpt`, `logs/quartus_compile.log` |
| D2 | ✔ 3 seed (1, 7, 2026) × 34 254 chu kỳ: 305 kiểm tra directed, 0 lỗi | `logs/traffic_tb_seed*.log` |
| D3 | ✔ golden khớp RTL 102 762/102 762 chu kỳ, 0 mismatch | `logs/golden_seed*.log` |
| D4 | ✔ checker procedural: 8 thuộc tính, 0 vi phạm, không cái nào rỗng (vd. `a_emg` kích hoạt 250 lần, `a_ylen` 1 934); `traffic_sva.sv` biên dịch sạch trên ModelSim (vsim-8311 như dự đoán); ModelSim và iverilog cho trace **giống hệt** từng chu kỳ | `logs/traffic_tb_seed*.log`, `logs/modelsim_tb.log`, `logs/modelsim_compile.log` |
| D5 | ✔ 9/9 trạng thái, 24/24 cung (cung hiếm nhất RECOVER→EMG: 5 lần) | dòng `COVERAGE` trong log |
| D6 | ✔ 6/6 mutant bị bắt (TB FAILED + golden FAIL; M1 → `a_yel`, M5 → `a_safe`, M6 → `a_ylen`) | `logs/mutant_M*.log`, `logs/golden_M*.log`, `logs/summary.log` |
| D7 | ✔ One-Hot: **230 LE**, 101 FF, **0 bit RAM**, Fmax **130.98 MHz** (Slow Model; Fast 288.6), slack +2.365 ns ở 10 ns | `logs/timing/*.rpt`, `quartus/output_files/` |
| D8 | ✔ Binary 254 LE / 112.46 MHz · Gray 247 LE / 118.02 MHz · One-Hot 230 LE / 130.98 MHz → bản nộp One-Hot | `logs/enc_binary/`, `enc_gray/`, `enc_onehot/` |
| D9 | ⏳ **cần làm trên board**: `quartus/output_files/de2_traffic.sof` đã sẵn; chạy B1–B9 (§7), chụp ảnh `paper/photos/board_B1..B9.jpg` | — |
| D10 | ◐ `paper/Nhom5_LETHANHDANH_FINAL.pdf` (9 trang) biên dịch 0 lỗi, 0 overfull; mọi số là macro trong `results.tex`. Còn 3 dấu đỏ: [V1] số nhóm (Group 5 hay Team 04), [V2] ảnh + quan sát board, [V3] đối chiếu Table 1/4 của proposal → xong thì `\draftmarksfalse` | `paper/` |

Khác biệt so với kế hoạch, phát hiện khi thực hiện:
- Đường găng thật của bản One-Hot là timer `cnt` → `cnt == 1` → next-state → nạp timer (7.67 ns), không phải bộ chia 26 bit
  (nhờ `tick` thanh ghi).
- Thêm T18 (§4.3) để phủ chắc các cung khẩn cấp hiếm; random rút số trước khi dùng (§4.3) để hai simulator trùng nhau.
- RTL gán mặc định `light_* <= L_R` rồi ghi đè trong `case`: Icarus ghi lại giá trị không đổi vào VCD ở mỗi cạnh clock
  (không phải glitch phần cứng); `make_figures.py` gộp các giá trị trùng khi vẽ waveform.
- Máy hiện không thấy USB-Blaster (`quartus_pgm -l`), nên chưa nạp thử board.
