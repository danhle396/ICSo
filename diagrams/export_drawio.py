"""
CE2031 Project 23 - export draw.io diagrams to PDF (vector, for LaTeX) and PNG
(2x, for slides), without the draw.io desktop app.

    python diagrams\\export_drawio.py                 # every diagrams\\*.drawio
    python diagrams\\export_drawio.py fsm.drawio      # only some files

How: the diagram is placed in an HTML page that loads draw.io's own viewer
(viewer-static.min.js, shipped with the VS Code extension hediet.vscode-drawio),
and headless Chrome / Edge prints it to PDF and takes a PNG screenshot. The page
size is the size the viewer gives the SVG (min-width / min-height), so the
output is cropped to the diagram.

Environment overrides: DRAWIO_VIEWER (path of viewer-static.min.js),
CHROME (path of chrome.exe or msedge.exe).
"""
import glob
import html
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
BORDER = 6  # px around the diagram


def find_viewer():
    env = os.environ.get("DRAWIO_VIEWER")
    if env:
        return pathlib.Path(env)
    pat = os.path.expanduser(
        "~/.vscode/extensions/hediet.vscode-drawio-*/drawio/src/main/webapp/js/viewer-static.min.js")
    hits = sorted(glob.glob(pat))
    if not hits:
        sys.exit("viewer-static.min.js not found: install the VS Code extension "
                 "hediet.vscode-drawio or set DRAWIO_VIEWER")
    return pathlib.Path(hits[-1])


def find_chrome():
    env = os.environ.get("CHROME")
    cands = [env] if env else []
    cands += [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
              r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
              r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
              r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"]
    for c in cands:
        if c and os.path.exists(c):
            return c
    sys.exit("Chrome / Edge not found: set CHROME")


def page(xml, viewer, size=None):
    """HTML page rendering one diagram. With size=(w, h) the page is fixed to it;
    without, the title reports the size the viewer computed."""
    cfg = json.dumps({"xml": xml, "toolbar": "", "nav": False,
                      "lightbox": False, "border": BORDER, "resize": False})
    if size:
        w, h = size
        css = (f"@page{{size:{w}px {h}px;margin:0}}"
               f"html,body{{margin:0;padding:0;width:{w}px;height:{h}px;"
               f"overflow:hidden;background:#fff}}")
        js = ""
    else:
        css = "html,body{margin:0;padding:0;background:#fff}"
        js = """<script>
function fit(){var s=document.querySelector('#g svg'); if(!s){setTimeout(fit,50);return;}
 var R=parseFloat(s.style.minWidth), B=parseFloat(s.style.minHeight);
 s.querySelectorAll('path,rect,ellipse,polygon,polyline,line,image,foreignObject div div div')
  .forEach(function(e){var r=e.getBoundingClientRect();
    if(r.width>0||r.height>0){R=Math.max(R,r.right);B=Math.max(B,r.bottom);}});
 document.title='SIZE '+Math.ceil(R+%d)+' '+Math.ceil(B+%d);}
window.addEventListener('load',function(){setTimeout(fit,300);});
</script>""".replace("%d", str(BORDER))
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head>'
            f'<body><div id="g" class="mxgraph" data-mxgraph="{html.escape(cfg)}"></div>'
            f'<script src="{viewer.as_uri()}"></script>{js}</body></html>')


def chrome(exe, *args):
    base = [exe, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--allow-file-access-from-files", "--virtual-time-budget=5000"]
    return subprocess.run(base + list(args), capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=180)


def export(src, viewer, exe, tmp):
    xml = src.read_text(encoding="utf-8")
    probe = tmp / (src.stem + "_probe.html")
    probe.write_text(page(xml, viewer), encoding="utf-8")
    r = chrome(exe, "--dump-dom", probe.as_uri())
    m = re.search(r"<title>SIZE (\d+) (\d+)</title>", r.stdout)
    if not m:
        sys.exit(f"{src.name}: the viewer did not render the diagram")
    w, h = int(m.group(1)), int(m.group(2))

    fixed = tmp / (src.stem + ".html")
    fixed.write_text(page(xml, viewer, (w, h)), encoding="utf-8")
    pdf = src.with_suffix(".pdf")
    png = src.with_suffix(".png")
    chrome(exe, "--no-pdf-header-footer", f"--print-to-pdf={pdf}", fixed.as_uri())
    chrome(exe, f"--window-size={w},{h}", "--force-device-scale-factor=2",
           f"--screenshot={png}", fixed.as_uri())
    for f in (pdf, png):
        if not f.exists():
            sys.exit(f"{src.name}: {f.name} was not written")
    print(f"{src.name}: {w} x {h} px -> {pdf.name}, {png.name}")


def main():
    viewer, exe = find_viewer(), find_chrome()
    names = sys.argv[1:] or sorted(p.name for p in HERE.glob("*.drawio"))
    with tempfile.TemporaryDirectory() as t:
        for n in names:
            export((HERE / n).resolve() if not os.path.isabs(n) else pathlib.Path(n),
                   viewer, exe, pathlib.Path(t))


if __name__ == "__main__":
    main()
