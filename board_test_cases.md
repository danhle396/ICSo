# Test trên board DE2 — Project 23: Traffic Light Controller FSM with Emergency Override

> Board Altera DE2 (Cyclone II EP2C35F672C6) · file nạp `quartus/output_files/de2_traffic.sof` · 1 tick = 1 s (SW[17] = 0)
> B1–B9 là các case cần chụp ảnh cho báo cáo (`paper/photos/board_B1.jpg` … `board_B9.jpg`).

## Tổng hợp

| Case | Tên | Nhóm | Chụp ảnh | Đối chiếu mô phỏng | Trạng thái |
|---|---|---|---|---|---|
| B0 | Nạp board, nhịp tim | Khởi động | Không | — | Chưa test |
| B1 | Chu kỳ thường 28 s | Chu kỳ | Có | T1 | Chưa test |
| B2 | Người đi bộ bấm nút | Đi bộ | Có | T2 | Chưa test |
| B3 | Giữ nút / bấm nhiều lần | Đi bộ | Có | T3 | Chưa test |
| B4 | Khẩn cấp khi đang xanh | Khẩn cấp | Có | T5, T17 | Chưa test |
| B5 | Giữ khẩn cấp rồi thả | Khẩn cấp | Có | T5, T16 | Chưa test |
| B6 | Khẩn cấp lúc đi bộ | Khẩn cấp | Có | T7 | Chưa test |
| B7 | Kéo dài pha xanh | Cảm biến xe | Có | T13, T14 | Chưa test |
| B8 | Reset giữa pha | Reset | Có | T10 | Chưa test |
| B9 | Gạt công tắc khẩn cấp liên tục | Độ bền | Có | T11, T12 | Chưa test |
| B10 | Khẩn cấp khi đang vàng | Khẩn cấp | Không | T6 | Chưa test |
| B11 | Khẩn cấp và nút cùng lúc | Khẩn cấp | Không | T8 | Chưa test |
| B12 | Khẩn cấp lần hai trong RECOVER | Khẩn cấp | Không | T9 | Chưa test |
| B13 | Khẩn cấp khi EW xanh | Khẩn cấp | Không | T18 | Chưa test |
| B14 | Bấm nút trong pha đi bộ | Đi bộ | Không | T4 | Chưa test |
| B15 | Đi bộ chặn kéo dài xanh | Cảm biến xe | Không | — | Chưa test |
| B16 | Chế độ nhanh ×10 | Tốc độ | Không | T15 | Chưa test |
| B17 | Khẩn cấp rất lâu | Khẩn cấp | Không | T16 | Chưa test |

## Chuẩn bị

- [ ] Cắm nguồn 9 V và cáp USB vào cổng USB-Blaster của DE2
- [ ] Gạt công tắc **SW19 = RUN**
- [ ] Nạp `de2_traffic.sof` (Quartus Programmer → USB-Blaster → JTAG → Start)
- [ ] Gạt tất cả SW về 0, sau đó **SW[1] = 1, SW[2] = 1** (cả hai hướng có xe)
- [ ] SW[17] = 0 (tốc độ thật)
- [ ] Nhấn rồi thả KEY[0] (reset)
- [ ] Mở đồng hồ bấm giờ trên điện thoại

## Cách đọc board

| Hiển thị | Ý nghĩa |
|---|---|
| HEX4 | Số trạng thái: 0 NS_G · 1 NS_Y · 2 RED1 · 3 EW_G · 4 EW_Y · 5 RED2 · 6 PED_WALK · 7 EMERGENCY · 8 RECOVER |
| HEX3 / HEX2 | Chữ đèn hướng NS / EW: `r` đỏ, `y` vàng, `G` xanh |
| HEX1–HEX0 | Số giây còn lại của pha |
| LEDR0 / LEDG1 / LEDG0 | Đèn NS: đỏ / vàng / xanh |
| LEDR2 / LEDG3 / LEDG2 | Đèn EW: đỏ / vàng / xanh |
| LEDR17 | Đèn đi bộ |
| LEDR16 | Có người đang chờ qua đường |
| LEDR15 | Khẩn cấp |
| LEDG8 | Nhịp tim: đổi trạng thái mỗi giây |

| Điều khiển | Chức năng |
|---|---|
| KEY[0] | Reset |
| KEY[1] | Nút người đi bộ |
| SW[0] | Cảm biến xe ưu tiên (khẩn cấp) |
| SW[1] / SW[2] | Có xe chờ ở hướng NS / EW |
| SW[17] | Chạy nhanh ×10 |

## Luôn kiểm tra trong mọi case

- [ ] LEDG0 và LEDG2 **không bao giờ** cùng sáng (không có hai hướng cùng xanh)
- [ ] Đèn xanh luôn chuyển sang vàng rồi mới sang đỏ
- [ ] LEDR17 (đi bộ) chỉ sáng khi cả hai hướng đều đỏ

---

## B0 · Nạp board, nhịp tim

**Mục đích:** board chạy đúng file vừa nạp, clock 50 MHz hoạt động.
**Thao tác:** nạp `.sof`, quan sát LEDG8 khoảng 10 s, nhấn KEY[0].

- [ ] LEDG8 sáng 1 s, tắt 1 s, đều đặn
- [ ] Sau reset: HEX4 = 0, HEX3–HEX2 = `Gr`, HEX1–HEX0 = 10

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt

---

## B1 · Chu kỳ thường 28 s

**Mục đích:** trình tự đèn và thời gian từng pha đúng đặc tả.
**Thiết lập:** SW[1] = SW[2] = 1, các SW khác = 0.
**Thao tác:** reset, để board chạy 2 vòng, bấm giờ.

- [ ] HEX4 chạy 0 → 1 → 2 → 3 → 4 → 5 → 0
- [ ] HEX3–HEX2 lần lượt `Gr` → `yr` → `rr` → `rG` → `ry` → `rr`
- [ ] Pha xanh 10 s (HEX đếm 10 → 01)
- [ ] Pha vàng 3 s (03 → 01)
- [ ] Đỏ chung 1 s (01)
- [ ] Một vòng đầy đủ = 28 s
- [ ] Không lúc nào hai hướng cùng xanh

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B1.jpg`

---

## B2 · Người đi bộ bấm nút

**Mục đích:** yêu cầu đi bộ được chốt và phục vụ sau pha đỏ chung.
**Thiết lập:** như B1.
**Thao tác:** khi đang NS xanh (HEX4 = 0), nhấn nhanh KEY[1] một lần.

- [ ] LEDR16 sáng ngay khi bấm
- [ ] NS vẫn xanh đủ 10 s, vàng 3 s, rồi đỏ chung 1 s
- [ ] Sau đó HEX4 = 6, LEDR17 sáng, cả hai hướng đỏ, HEX đếm 05 → 01 (5 s)
- [ ] LEDR16 tắt khi vào pha đi bộ
- [ ] Hết pha đi bộ thì **EW** xanh (HEX4 = 3)

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B2.jpg`

---

## B3 · Giữ nút / bấm nhiều lần

**Mục đích:** một yêu cầu chỉ sinh một pha đi bộ.
**Thao tác 1:** giữ KEY[1] liên tục qua 2 vòng.
**Thao tác 2:** reset, bấm KEY[1] 3 lần liên tiếp trong lúc NS xanh.

- [ ] Giữ nút: chỉ có **1** pha đi bộ; vòng sau không có pha đi bộ dù vẫn giữ nút
- [ ] Bấm 3 lần: chỉ có **1** pha đi bộ

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B3.jpg`

---

## B4 · Khẩn cấp khi đang xanh

**Mục đích:** khẩn cấp cắt pha xanh nhưng vẫn qua đủ vàng.
**Thao tác:** khi NS xanh đang hiện khoảng 06, gạt SW[0] = 1 (giữ nguyên).

- [ ] LEDR15 sáng ngay
- [ ] NS chuyển vàng ngay (HEX4 = 1, HEX3 = `y`)
- [ ] Vàng **đủ 3 s** (03 → 01), không ngắn hơn
- [ ] Sau đó HEX4 = 7, HEX3–HEX2 = `rr`, HEX1–HEX0 = 00

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B4.jpg`

---

## B5 · Giữ khẩn cấp rồi thả

**Mục đích:** toàn đỏ không có timeout; sau khi thả, hướng bị cắt nhường lượt.
**Thao tác:** tiếp B4, giữ SW[0] = 1 khoảng 30 s, rồi gạt SW[0] = 0.

- [ ] Trong lúc giữ: vẫn HEX4 = 7, toàn đỏ, không tự thoát
- [ ] Khi thả: LEDR15 tắt
- [ ] HEX4 = 8 (RECOVER) trong 2 s (02 → 01), toàn đỏ
- [ ] Sau đó **EW** xanh (HEX4 = 3), vì NS là hướng vừa bị cắt

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B5.jpg`

---

## B6 · Khẩn cấp lúc đi bộ

**Mục đích:** khẩn cấp ngắt cả pha đi bộ.
**Thao tác:** bấm KEY[1], chờ đến pha đi bộ (HEX4 = 6), gạt SW[0] = 1; sau vài giây gạt về 0.

- [ ] LEDR17 tắt ngay, HEX4 = 7
- [ ] Khi thả: RECOVER 2 s rồi **EW** xanh
- [ ] Người đi bộ mất lượt: LEDR16 tắt, không có pha đi bộ sau RECOVER

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B6.jpg`

---

## B7 · Kéo dài pha xanh

**Mục đích:** hướng kia không có xe thì pha xanh kéo dài tới 15 s.
**Thao tác 1:** SW[1] = 1, SW[2] = 0 (EW không có xe), reset, bấm giờ pha NS xanh.
**Thao tác 2:** lặp lại; khi HEX đã đứng ở 01 được vài giây thì gạt SW[2] = 1.

- [ ] NS xanh tổng cộng **15 s**: HEX đếm 10 → 01, rồi đứng ở 01 thêm 5 s
- [ ] Sau 15 s mới chuyển vàng
- [ ] Gạt SW[2] = 1 giữa lúc kéo dài: pha xanh kết thúc ở giây kế tiếp

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B7.jpg`

---

## B8 · Reset giữa pha

**Mục đích:** reset đưa về trạng thái đầu ngay lập tức.
**Thao tác:** khi đang EW xanh (HEX4 = 3), nhấn và giữ KEY[0] 2 s, rồi thả.

- [ ] Ngay khi nhấn: HEX4 = 0, HEX3–HEX2 = `Gr`, HEX1–HEX0 = 10
- [ ] LEDR15, LEDR16, LEDR17 tắt
- [ ] Trong lúc giữ: board đứng yên
- [ ] Khi thả: bắt đầu đếm từ 10

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B8.jpg`

---

## B9 · Gạt công tắc khẩn cấp liên tục

**Mục đích:** bộ chống dội và FSM không tạo trạng thái sai khi công tắc bị gạt loạn.
**Thao tác:** khi NS xanh, gạt SW[0] lên xuống nhanh nhiều lần, cuối cùng để ở 1.

- [ ] Mỗi lần pha xanh bị cắt đều qua vàng đủ 3 s
- [ ] Không lúc nào hai hướng cùng xanh
- [ ] Cuối cùng HEX4 = 7
- [ ] LEDR15 thôi nháy ngay khi công tắc đứng yên

**Quan sát thực tế:**
**Kết quả:** Đạt / Không đạt
**Ảnh:** `board_B9.jpg`

---

## B10 · Khẩn cấp khi đang vàng

**Thao tác:** gạt SW[0] = 1 ngay khi NS vừa chuyển vàng (HEX4 = 1).

- [ ] Pha vàng **không** bị rút ngắn, vẫn đủ 3 s
- [ ] Sau đó HEX4 = 7

**Kết quả:** Đạt / Không đạt

---

## B11 · Khẩn cấp và nút cùng lúc

**Thao tác:** khi NS xanh, gạt SW[0] = 1 và nhấn KEY[1]; giữ SW[0] khoảng 10 s rồi thả.

- [ ] Vàng 3 s → HEX4 = 7
- [ ] LEDR16 vẫn sáng trong suốt pha khẩn cấp
- [ ] Thả SW[0]: 8 (2 s) → 6 (đi bộ 5 s) → EW xanh

**Kết quả:** Đạt / Không đạt

---

## B12 · Khẩn cấp lần hai trong RECOVER

**Thao tác:** gạt SW[0] = 0 để vào RECOVER (HEX4 = 8), rồi trong vòng 2 s gạt lại SW[0] = 1.

- [ ] Quay về HEX4 = 7 ngay, không chờ hết RECOVER

**Kết quả:** Đạt / Không đạt

---

## B13 · Khẩn cấp khi EW xanh

**Thao tác:** khi EW xanh (HEX4 = 3), gạt SW[0] = 1; vài giây sau gạt về 0.

- [ ] EW vàng 3 s → HEX4 = 7
- [ ] Khi thả: 8 (2 s) → **NS** xanh (EW là hướng vừa bị cắt)

**Kết quả:** Đạt / Không đạt

---

## B14 · Bấm nút trong pha đi bộ

**Thao tác:** trong lúc HEX4 = 6, nhấn KEY[1].

- [ ] LEDR16 không sáng
- [ ] Vòng sau không có thêm pha đi bộ

**Kết quả:** Đạt / Không đạt

---

## B15 · Đi bộ chặn kéo dài xanh

**Thao tác:** SW[1] = 1, SW[2] = 0, reset; khi NS xanh thì nhấn KEY[1].

- [ ] NS xanh chỉ 10 s, không kéo dài lên 15 s
- [ ] Sau đỏ chung có pha đi bộ

**Kết quả:** Đạt / Không đạt

---

## B16 · Chế độ nhanh ×10

**Thao tác:** gạt SW[17] = 1 khoảng 10 s, rồi về 0.

- [ ] Mọi pha nhanh gấp 10: một vòng ≈ 2.8 s
- [ ] LEDG8 nháy nhanh
- [ ] Về 0: tốc độ trở lại bình thường (1 tick = 1 s)

**Kết quả:** Đạt / Không đạt

---

## B17 · Khẩn cấp rất lâu

**Thao tác:** giữ SW[0] = 1 hơn 1 phút.

- [ ] Vẫn HEX4 = 7, HEX1–HEX0 = 00, không tự thoát

**Kết quả:** Đạt / Không đạt

---

## Ghi chú khi test

- Đo thời gian ở SW[17] = 0; ở chế độ nhanh pha vàng chỉ 0.3 s, khó nhìn.
- Công tắc có độ trễ chống dội khoảng 15 ms, mắt không nhận ra: phản ứng "ngay lập tức" là đúng.
- Nếu quan sát khác kỳ vọng, ghi đúng như đã thấy vào "Quan sát thực tế" và đối chiếu với test mô phỏng ở bảng tổng hợp.
