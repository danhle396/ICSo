"""
CE2031 Project 23 - short presentation on the VKU template.

    python slides\\build_slides.py
    -> slides\\Nhom5_LETHANHDANH_FINAL_slides.pptx

Needs python-pptx. Starts from slides\\template\\VKU-SLIDE.pptx: slide 1 of the
template (VKU header) is the title and closing background, slide 2 (VKU logo,
slide number) the background of every content slide. The pictures are the
project files themselves:
    diagrams\\design_flow.png, diagrams\\architecture.png, diagrams\\paper_fsm.png,
    diagrams\\paper_tb.png     (python diagrams\\export_drawio.py)
    paper\\figures\\gtkwave_T5.png, gtkwave_T2.png   (paper\\capture_gtkwave.ps1)
and the numbers come from logs\\summary.log.
"""
import copy
import re
from pathlib import Path

from PIL import Image
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Inches, Pt

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
TEMPLATE = HERE / "template" / "VKU-SLIDE.pptx"
OUT = HERE / "Nhom5_LETHANHDANH_FINAL_slides.pptx"

RED = RGBColor(0xC3, 0x20, 0x33)        # colours of the VKU template
YEL = RGBColor(0xFF, 0xD0, 0x11)
NAVY = RGBColor(0x39, 0x4F, 0x88)
INK = RGBColor(0x1F, 0x29, 0x37)
MUTED = RGBColor(0x55, 0x5F, 0x6D)
CARD = RGBColor(0xF3, 0xF5, 0xFA)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
FONT = "Arial"

SW, SH = 20.0, 11.25                    # slide size, inches
X0, X1 = 0.7, 19.3                      # content margins
TOP, BOT = 1.75, 10.3                   # below the header line, above the bars


# ---- template handling ----------------------------------------------------------
def clone(prs, src):
    """Append a copy of slide src (shapes and their pictures)."""
    dst = prs.slides.add_slide(src.slide_layout)
    for el in list(dst.shapes._spTree):
        if el.tag in (qn("p:sp"), qn("p:pic")):
            dst.shapes._spTree.remove(el)
    rid = {}
    for old, rel in src.part.rels.items():
        if rel.reltype.endswith("/image"):
            rid[old] = dst.part.relate_to(rel._target, rel.reltype)
    for el in src.shapes._spTree:
        if el.tag in (qn("p:sp"), qn("p:pic"), qn("p:grpSp")):
            new = copy.deepcopy(el)
            for blip in new.iter(qn("a:blip")):
                blip.set(qn("r:embed"), rid[blip.get(qn("r:embed"))])
            dst.shapes._spTree.append(new)
    return dst


def drop_slide(prs, slide):
    lst = prs.slides._sldIdLst
    for sid in list(lst):
        if prs.part.related_part(sid.rId) is slide.part:
            prs.part.drop_rel(sid.rId)
            lst.remove(sid)


def slide_number_field(slide):
    """The template types the number ('2', '14'): make it a slide-number field."""
    for shp in slide.shapes:
        if shp.has_text_frame and re.fullmatch(r"\d+", shp.text_frame.text.strip() or "x"):
            p = shp.text_frame.paragraphs[0]._p
            r = p.find(qn("a:r"))
            fld = p.makeelement(qn("a:fld"), {"id": "{B6F15528-21DE-4FAA-801E-634DDDAF4B2B}",
                                               "type": "slidenum"})
            fld.append(copy.deepcopy(r.find(qn("a:rPr"))))
            t = p.makeelement(qn("a:t"), {})
            t.text = "‹#›"
            fld.append(t)
            r.addprevious(fld)
            p.remove(r)


# ---- drawing helpers ------------------------------------------------------------
def text(slide, x, y, w, h, runs, size=18, color=INK, bold=False, align=PP_ALIGN.LEFT,
         anchor=MSO_ANCHOR.TOP, name=None, spacing=6):
    """runs: str, or list of paragraphs; a paragraph is str or list of (text, opts)."""
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        tb.name = name
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    paras = runs if isinstance(runs, list) else [runs]
    for i, para in enumerate(paras):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_after = Pt(spacing)
        for t, o in ([(para, {})] if isinstance(para, str) else para):
            r = p.add_run()
            r.text = t
            f = r.font
            f.name = FONT
            f.size = Pt(o.get("size", size))
            f.bold = o.get("bold", bold)
            f.italic = o.get("italic", False)
            f.color.rgb = o.get("color", color)
    return tb


def title(slide, t):
    text(slide, X0, 0.42, 16.4, 0.85, t, size=36, color=NAVY, bold=True,
         anchor=MSO_ANCHOR.BOTTOM, name="Title")


def picture(slide, path, x, y, w=None, h=None, name=None):
    iw, ih = Image.open(path).size
    if w is None:
        w = h * iw / ih
    if h is None:
        h = w * ih / iw
    pic = slide.shapes.add_picture(str(path), Inches(x), Inches(y), Inches(w), Inches(h))
    pic.name = name or Path(path).stem
    return pic, w, h


def box(slide, x, y, w, h, fill=CARD, line=None, shape=MSO_SHAPE.ROUNDED_RECTANGLE, name=None):
    s = slide.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    s.fill.solid()
    s.fill.fore_color.rgb = fill
    if line is None:
        s.line.fill.background()
    else:
        s.line.color.rgb = line
        s.line.width = Pt(1.5)
    s.shadow.inherit = False
    if shape == MSO_SHAPE.ROUNDED_RECTANGLE:
        s.adjustments[0] = 0.08
    if name:
        s.name = name
    return s


def badge(slide, x, y, d, label, fill, color=WHITE, size=20):
    c = box(slide, x, y, d, d, fill=fill, shape=MSO_SHAPE.OVAL, name=f"Badge {label}")
    tf = c.text_frame
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = label
    r.font.name, r.font.size, r.font.bold, r.font.color.rgb = FONT, Pt(size), True, color
    return c


# ---- numbers --------------------------------------------------------------------
def numbers():
    log = (ROOT / "logs" / "summary.log").read_text(encoding="utf-8")
    runs = re.findall(r"TRAFFIC TB PASSED : seed (\d+), (\d+) cycles, (\d+) directed checks", log)
    cov = re.search(r"states (\d+/\d+), arcs (\d+/\d+)", log)
    mut = re.search(r"(\d+)/(\d+) mutants caught", log)
    return {
        "seeds": len(runs),
        "cycles": sum(int(c) for _, c, _ in runs),
        "checks": int(runs[0][2]),
        "states": cov.group(1), "arcs": cov.group(2),
        "mutants": f"{mut.group(1)}/{mut.group(2)}",
        "golden": len(re.findall(r"golden model: PASS, 0 mismatch", log)),
        "all": "ALL PASSED" in log,
    }


def fmt(n):
    return f"{n:,}".replace(",", " ")


# ---- slides ---------------------------------------------------------------------
def s_title(s):
    text(s, X0 + 0.3, 2.7, 16, 0.5, "ĐỒ ÁN CUỐI KỲ  ·  CE2031 THIẾT KẾ VI MẠCH SỐ", size=20,
         color=RED, bold=True, name="Course")
    text(s, X0 + 0.3, 3.35, 18, 2.4,
         ["Bộ điều khiển đèn giao thông FSM", "có chế độ ưu tiên khẩn cấp"],
         size=54, color=NAVY, bold=True, spacing=0, name="Title")
    text(s, X0 + 0.3, 5.85, 17, 0.6,
         "Project 23  ·  SystemVerilog  ·  FPGA Cyclone II trên kit DE2", size=24, color=MUTED,
         name="Subtitle")
    box(s, X0 + 0.3, 7.0, 9.6, 2.35, name="Team card")
    text(s, X0 + 0.7, 7.25, 9.0, 2.0, [
        [("Nhóm 5", {"bold": True, "color": NAVY, "size": 22})],
        "Lê Thành Danh  (23CE010)  –  RTL, FPGA",
        "Phan Duy Luân  (23CE041)  –  kiểm chứng, board",
        [("GVHD: TS. Dương Ngọc Pháp", {"color": MUTED})],
    ], size=19, spacing=4, name="Team")


def s_flow(s):
    title(s, "Quy trình thiết kế")
    _, w, _ = picture(s, ROOT / "diagrams" / "design_flow.png", X0, TOP, h=BOT - TOP)
    x = X0 + w + 0.7
    steps = [
        ("1", "Đặc tả & kiến trúc", "Thông số pha, bảng I/O, FSM Moore 9 trạng thái, sơ đồ khối"),
        ("2", "RTL SystemVerilog", "7 module: strobe_gen, sync_debounce, clk_divider, state_timer, traffic_fsm, bin2bcd8, traffic_top"),
        ("3", "Mô phỏng & kiểm chứng", "Icarus 0.9.7, ModelSim-Altera; test định hướng + ngẫu nhiên, golden model Python, coverage, mutant"),
        ("4", "Tổng hợp & timing", "Quartus II 13.0sp1, TimeQuest; so sánh mã hoá Binary / Gray / One-Hot"),
        ("5", "Hiện thực trên DE2", "de2_top + gán 106 chân; nạp .sof qua USB-Blaster, chạy kịch bản trên board"),
    ]
    y, gap, hh = TOP + 0.05, 0.22, 1.5
    colors = [NAVY, RED, NAVY, RED, NAVY]
    for (n, head, body), c in zip(steps, colors):
        badge(s, x, y + 0.2, 0.75, n, c)
        text(s, x + 1.05, y + 0.12, X1 - x - 1.05, hh - 0.1, [
            [(head, {"bold": True, "color": INK, "size": 22})],
            [(body, {"color": MUTED, "size": 17})],
        ], spacing=3, name=f"Step {n}")
        y += hh + gap


def s_arch(s):
    title(s, "Kiến trúc hệ thống")
    w = 17.6
    _, w, h = picture(s, ROOT / "diagrams" / "architecture.png", (SW - w) / 2, TOP, w=w)
    text(s, X0, TOP + h + 0.3, X1 - X0, 0.5, [[
        ("Luồng tín hiệu: ", {"bold": True, "color": NAVY}),
        ("công tắc / nút → đồng bộ + chống dội → FSM → bộ đếm pha → LED, LED 7 đoạn. "
         "Mỗi lần đổi pha, bộ chia xung được khởi động lại.", {}),
    ]], size=17, color=INK, name="Caption")


def s_fsm(s):
    title(s, "Máy trạng thái: 9 trạng thái, ưu tiên khẩn cấp")
    _, w, h = picture(s, ROOT / "diagrams" / "paper_fsm.png", X0, TOP + 0.3, w=11.3)
    x = X0 + w + 0.5
    rules = [
        ("Khẩn cấp khi đang xanh", "qua vàng đủ 3 s rồi mới sang đỏ, không bao giờ xanh → đỏ"),
        ("EMERGENCY toàn đỏ", "không giới hạn thời gian; thả ra → RECOVER đỏ 2 s"),
        ("Hướng bị cắt được đi trước", "cờ next_ew chọn pha xanh sau RECOVER / đi bộ"),
        ("Không mất yêu cầu đi bộ", "được giữ qua khẩn cấp và phục vụ sau RECOVER"),
    ]
    y = TOP + 0.3
    for i, (head, body) in enumerate(rules):
        box(s, x, y, X1 - x, 1.55, name=f"Rule {i + 1} card")
        badge(s, x + 0.25, y + 0.4, 0.7, str(i + 1), RED if i == 0 else NAVY)
        text(s, x + 1.2, y + 0.2, X1 - x - 1.4, 1.2, [
            [(head, {"bold": True, "size": 20})],
            [(body, {"color": MUTED, "size": 16})],
        ], spacing=2, name=f"Rule {i + 1}")
        y += 1.55 + 0.25
    text(s, X0, TOP + 0.3 + h + 0.3, w, 0.9, [[
        ("Thời gian pha: ", {"bold": True, "color": NAVY}),
        ("xanh 10 s (kéo dài tới 15 s khi hướng kia trống) · vàng 3 s · đỏ chung 1 s · đi bộ 5 s", {}),
    ]], size=17, name="Phase times")


def s_verif(s, n):
    title(s, "Mô phỏng và kiểm chứng")
    _, w, h = picture(s, ROOT / "diagrams" / "paper_tb.png", X0, TOP + 0.2, w=8.4)
    text(s, X0, TOP + 0.2 + h + 0.25, w, 1.4, [
        "Hai trình mô phỏng (Icarus, ModelSim) cho cùng một vết tín hiệu, từng chu kỳ.",
        "Golden model Python viết từ đặc tả, không từ RTL.",
    ], size=16, color=MUTED, spacing=4, name="Notes")
    stats = [
        ("18", f"test định hướng\n{n['checks']} điểm kiểm tra"),
        (fmt(n["cycles"]), f"chu kỳ mô phỏng\n{n['seeds']} seed ngẫu nhiên"),
        (f"{n['states']} · {n['arcs']}", "coverage\ntrạng thái · cung"),
        ("0", "sai khác so với\ngolden model"),
        ("8", "thuộc tính an toàn\n0 vi phạm"),
        (n["mutants"], "mutant lỗi\nđều bị phát hiện"),
    ]
    gx = X0 + w + 0.6
    cw = (X1 - gx - 0.4) / 2
    ch = 2.05
    for i, (big, small) in enumerate(stats):
        cx = gx + (i % 2) * (cw + 0.4)
        cy = TOP + 0.2 + (i // 2) * (ch + 0.3)
        box(s, cx, cy, cw, ch, name=f"Stat {i + 1} card")
        text(s, cx + 0.35, cy + 0.2, cw - 0.5, 0.95, big, size=40, bold=True,
             color=RED if i in (3, 5) else NAVY, name=f"Stat {i + 1} value")
        text(s, cx + 0.35, cy + 1.12, cw - 0.5, 0.85, small.split("\n"), size=16,
             color=MUTED, spacing=0, name=f"Stat {i + 1} label")
    if n["all"]:
        text(s, gx, TOP + 0.2 + 3 * (ch + 0.3) + 0.05, X1 - gx, 0.5, [[
            ("Kết quả: ", {"bold": True, "color": NAVY}),
            ("ALL PASSED trên cả 3 seed (logs/summary.log)", {}),
        ]], size=17, name="Verdict")


def s_wave(s, head, png, marks, note):
    title(s, head)
    w = 16.8
    _, w, h = picture(s, png, (SW - w) / 2, TOP, w=w)
    y = TOP + h + 0.3
    cw = (X1 - X0 - 0.3 * (len(marks) - 1)) / len(marks)
    for i, (m, desc) in enumerate(marks):
        cx = X0 + i * (cw + 0.3)
        box(s, cx, y, cw, BOT - y, name=f"Marker {m} card")
        badge(s, cx + 0.2, y + 0.22, 0.6, m, NAVY, size=18)
        text(s, cx + 0.95, y + 0.18, cw - 1.1, BOT - y - 0.3, desc, size=15, color=INK,
             name=f"Marker {m}")
    s.notes_slide.notes_text_frame.text = note


def build():
    prs = Presentation(str(TEMPLATE))
    tpl = list(prs.slides)
    title_bg, content_bg = tpl[0], tpl[1]
    content = [clone(prs, content_bg) for _ in range(6)]
    closing = clone(prs, title_bg)
    for sl in tpl[1:]:
        drop_slide(prs, sl)
    for sl in content:
        slide_number_field(sl)

    n = numbers()
    s_title(title_bg)
    s_flow(content[0])
    s_arch(content[1])
    s_fsm(content[2])
    s_verif(content[3], n)
    fig = ROOT / "paper" / "figures"
    s_wave(content[4], "Dạng sóng: khẩn cấp khi đang xanh (test T5)", fig / "gtkwave_T5.png", [
        ("A", "Gạt công tắc khẩn cấp (emg_sensor = 1)"),
        ("B", "Qua đồng bộ + chống dội: xanh kết thúc, NS vàng"),
        ("C", "Vàng đủ 3 tick → EMERGENCY, toàn đỏ, time_left = 00"),
        ("D", "Thả công tắc khẩn cấp"),
        ("E", "RECOVER 2 tick, rồi EW (hướng chưa bị cắt) xanh"),
    ], "Ảnh chụp trực tiếp GTKWave mở traffic_tb.vcd; marker A–E đặt tại thời điểm đọc từ chính file VCD. 1 tick = 4 chu kỳ clock trong mô phỏng.")
    s_wave(content[5], "Dạng sóng: người đi bộ bấm nút (test T2)", fig / "gtkwave_T2.png", [
        ("A", "Bấm nút trong lúc NS đang vàng"),
        ("B", "Yêu cầu được chốt: ped_req = 1"),
        ("C", "Sau đỏ chung RED1 → PED_WALK, đèn đi bộ sáng 5 tick"),
        ("D", "Hết pha đi bộ → EW xanh"),
    ], "Yêu cầu đi bộ được chốt cho đến khi phục vụ; nhấn giữ hay nhấn nhiều lần chỉ sinh một pha đi bộ.")

    text(closing, 0, 4.2, SW, 1.2, "Cảm ơn thầy và các bạn đã lắng nghe!", size=48, color=NAVY,
         bold=True, align=PP_ALIGN.CENTER, name="Thanks")
    text(closing, 0, 5.6, SW, 0.7, "Hỏi & đáp", size=28, color=RED, bold=True,
         align=PP_ALIGN.CENTER, name="QA")
    prs.save(str(OUT))
    print("wrote", OUT)


if __name__ == "__main__":
    build()
