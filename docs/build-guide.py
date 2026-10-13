#!/usr/bin/env python3
"""Build docs/WebSDR-Digital-Receive-Only-Guide.pdf from README.md and docs/*.md.

    python3 docs/build-guide.py

Needs ReportLab (sudo apt install python3-reportlab, or pip install reportlab).
Re-run it whenever the Markdown changes; the PDF is generated, never edited by hand.
Understands the Markdown these docs use: headings, paragraphs, bullet and numbered
lists, tables, fenced code blocks, and inline code, bold, italic and links.
"""
import datetime
import os
import re
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, KeepTogether, ListFlowable, ListItem,
                                PageBreak, PageTemplate, Paragraph, Preformatted, Spacer, Table,
                                TableStyle)
from reportlab.platypus.tableofcontents import TableOfContents

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "WebSDR-Digital-Receive-Only-Guide.pdf")
TITLE = "WebSDR-Digital-Receive-Only"
REPO_URL = "https://github.com/KC3WHJ/WebSDR-Digital-Receive-Only"
CHAPTERS = [  # (file, chapter title); each file's own top "#" heading is replaced by this
    ("README.md", "Overview"),
    ("docs/USAGE.md", "Using it"),
    ("docs/HOW-IT-WORKS.md", "How it works"),
    ("docs/TROUBLESHOOTING.md", "Troubleshooting"),
]

# ------------------------------------------------------------------ fonts
FONT_DIR = "/usr/share/fonts/truetype/dejavu"
try:
    for name, f in (("Sans", "DejaVuSans.ttf"), ("Sans-Bold", "DejaVuSans-Bold.ttf"),
                    ("Sans-Italic", "DejaVuSans-Oblique.ttf"), ("Sans-BoldItalic", "DejaVuSans-BoldOblique.ttf"),
                    ("Mono", "DejaVuSansMono.ttf"), ("Mono-Bold", "DejaVuSansMono-Bold.ttf")):
        pdfmetrics.registerFont(TTFont(name, os.path.join(FONT_DIR, f)))
    pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-Bold", italic="Sans-Italic", boldItalic="Sans-BoldItalic")
    SANS, SANS_B, MONO = "Sans", "Sans-Bold", "Mono"
except Exception:  # no DejaVu: ReportLab's built-in fonts
    SANS, SANS_B, MONO = "Helvetica", "Helvetica-Bold", "Courier"

ACCENT = colors.HexColor("#1F4E79")
MUTED = colors.HexColor("#555555")
RULE = colors.HexColor("#B8C4D0")
CODE_BG = colors.HexColor("#F2F4F7")
HEAD_BG = colors.HexColor("#E3EAF2")

S = {
    "body": ParagraphStyle("body", fontName=SANS, fontSize=9.5, leading=13.5, spaceAfter=6),
    "h1": ParagraphStyle("h1", fontName=SANS_B, fontSize=20, leading=24, textColor=ACCENT, spaceAfter=12),
    "h2": ParagraphStyle("h2", fontName=SANS_B, fontSize=13, keepWithNext=1, leading=16, textColor=ACCENT, spaceBefore=12, spaceAfter=6),
    "h3": ParagraphStyle("h3", fontName=SANS_B, fontSize=11, keepWithNext=1, leading=14, spaceBefore=8, spaceAfter=4),
    "cell": ParagraphStyle("cell", fontName=SANS, fontSize=8.5, leading=11),
    "cellh": ParagraphStyle("cellh", fontName=SANS_B, fontSize=8.5, leading=11),
    "code": ParagraphStyle("code", fontName=MONO, fontSize=7.6, leading=9.6, textColor=colors.black),
    "cover_t": ParagraphStyle("cover_t", fontName=SANS_B, fontSize=28, leading=34, textColor=ACCENT, alignment=TA_CENTER),
    "cover_s": ParagraphStyle("cover_s", fontName=SANS, fontSize=13, leading=18, textColor=MUTED, alignment=TA_CENTER),
    "cover_m": ParagraphStyle("cover_m", fontName=SANS, fontSize=10, leading=15, alignment=TA_CENTER),
    "toc1": ParagraphStyle("toc1", fontName=SANS_B, fontSize=10.5, leading=14, leftIndent=0, spaceBefore=4),
    "toc2": ParagraphStyle("toc2", fontName=SANS, fontSize=8.8, leading=11.2, leftIndent=16),
}

# ----------------------------------------------------------------- inline
def inline(text):
    """Markdown inline markup -> ReportLab paragraph markup."""
    codes = []
    def keep_code(m):
        codes.append(m.group(1))
        return "\x00%d\x00" % (len(codes) - 1)
    text = re.sub(r"`([^`]+)`", keep_code, text)
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(r"&lt;(https?://[^&\s]+)&gt;", r'<link href="\1" color="#1F4E79">\1</link>', text)
    def link(m):
        label, url = m.group(1), m.group(2)
        if url.startswith("http"):
            return '<link href="%s" color="#1F4E79"><u>%s</u></link>' % (url, label)
        return label  # links between the docs: they're chapters of this PDF
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<i>\1</i>", text)
    def put_code(m):
        c = codes[int(m.group(1))].replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        return '<font name="%s" color="#7A2E0E">%s</font>' % (MONO, c)
    return re.sub(r"\x00(\d+)\x00", put_code, text)

# ----------------------------------------------------------------- blocks
def table(rows, width):
    head, body = rows[0], rows[2:]
    ncol = len(head)
    lens = [max(len(r[i]) if i < len(r) else 0 for r in [head] + body) for i in range(ncol)]
    lens = [min(max(n, 6), 70) for n in lens]
    widths = [width * n / sum(lens) for n in lens]
    data = [[Paragraph(inline(c), S["cellh"]) for c in head]]
    data += [[Paragraph(inline(r[i]) if i < len(r) else "", S["cell"]) for i in range(ncol)] for r in body]
    t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
        ("GRID", (0, 0), (-1, -1), 0.4, RULE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]))
    return t

def code_block(lines, width):
    chars = int((width - 14) / pdfmetrics.stringWidth("M", MONO, S["code"].fontSize))
    t = Table([[Preformatted("\n".join(lines), S["code"], maxLineLength=chars, newLineChars="    ")]], colWidths=[width])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), CODE_BG), ("BOX", (0, 0), (-1, -1), 0.4, RULE),
                           ("LEFTPADDING", (0, 0), (-1, -1), 6), ("TOPPADDING", (0, 0), (-1, -1), 5),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    return t

def make_list(items, numbered):
    flow = [ListItem(Paragraph(inline(i), S["body"]), leftIndent=14) for i in items]
    kw = dict(bulletType="1", bulletFormat="%s.") if numbered else dict(bulletType="bullet", start="•")
    return ListFlowable(flow, leftIndent=14, bulletFontName=SANS, bulletFontSize=9, **kw)

def convert(md, chapter, width):
    """One Markdown file -> flowables. Its first '#' heading becomes the chapter title."""
    out = [Paragraph(chapter, S["h1"])]
    lines = md.splitlines()
    i, first_h1 = 0, True
    para = []
    def flush():
        if para:
            out.append(Paragraph(inline(" ".join(para)), S["body"]))
            para.clear()
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith("```"):
            flush(); i += 1; block = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                block.append(lines[i]); i += 1
            out.append(code_block(block, width)); out.append(Spacer(1, 6)); i += 1; continue
        m = re.match(r"^(#{1,3})\s+(.*)", s)
        if m:
            flush()
            level, text = len(m.group(1)), m.group(2)
            if level == 1 and first_h1:
                first_h1 = False  # the file's own title: replaced by the chapter title
            elif level <= 2:
                out.append(Paragraph(inline(text), S["h2"]))
            else:
                out.append(Paragraph(inline(text), S["h3"]))
            i += 1; continue
        if s.startswith("|"):
            flush(); rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                row = lines[i].strip()[1:-1] if lines[i].strip().endswith("|") else lines[i].strip()[1:]
                cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", row)]
                rows.append(cells); i += 1
            out.append(table(rows, width)); out.append(Spacer(1, 8)); continue
        lm = re.match(r"^(\s*)(-|\d+\.)\s+(.*)", line)
        if lm and not lm.group(1):
            flush(); numbered = lm.group(2) != "-"; items = []
            while i < len(lines):
                m2 = re.match(r"^(-|\d+\.)\s+(.*)", lines[i])
                if m2 and (m2.group(1) != "-") == numbered:
                    items.append(m2.group(2)); i += 1
                elif lines[i].startswith("  ") and lines[i].strip() and items:
                    items[-1] += " " + lines[i].strip(); i += 1   # continuation line
                else:
                    break
            out.append(make_list(items, numbered)); out.append(Spacer(1, 4)); continue
        if not s:
            flush(); i += 1; continue
        para.append(s); i += 1
    flush()
    return out

# ------------------------------------------------------------------- doc
class Guide(BaseDocTemplate):
    def __init__(self, path, **kw):
        super().__init__(path, pagesize=letter, leftMargin=0.85 * inch, rightMargin=0.85 * inch,
                         topMargin=0.8 * inch, bottomMargin=0.8 * inch, title=TITLE + " Guide",
                         author="KC3WHJ", subject="Receive-only JS8Call/CommStat and FLDIGI/FLMSG/FLAMP stations fed by a web SDR",
                         **kw)
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id="f")
        self.addPageTemplates([PageTemplate("cover", [frame]), PageTemplate("body", [frame], onPage=self.chrome)])
        self._h = 0

    def chrome(self, canv, doc):
        canv.saveState()
        canv.setStrokeColor(RULE); canv.setLineWidth(0.5)
        y = doc.bottomMargin - 0.35 * inch
        canv.line(doc.leftMargin, y + 12, doc.leftMargin + doc.width, y + 12)
        canv.setFont(SANS, 8); canv.setFillColor(MUTED)
        canv.drawString(doc.leftMargin, y, TITLE + " - Guide")
        canv.drawRightString(doc.leftMargin + doc.width, y, "Page %d" % doc.page)
        canv.restoreState()

    def beforeDocument(self):
        self._h = 0  # multiBuild lays the document out several times; keep bookmark keys stable

    def afterFlowable(self, f):
        if isinstance(f, Paragraph) and f.style.name in ("h1", "h2"):
            text = f.getPlainText()
            level = 0 if f.style.name == "h1" else 1
            key = "h%d" % self._h; self._h += 1
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(text, key, level=level, closed=level == 0)
            self.notify("TOCEntry", (level, text, self.page, key))

def version():
    for line in open(os.path.join(ROOT, "lib", "common.sh")):
        m = re.match(r'WEBSDR_JS8_VERSION="([^"]+)"', line)
        if m:
            return m.group(1)
    return "?"

def build():
    doc = Guide(OUT)
    w = doc.width
    story = [Spacer(1, 1.6 * inch),
             Paragraph(TITLE, S["cover_t"]), Spacer(1, 14),
             Paragraph("Receive-only digital-mode stations fed by a web SDR or KiwiSDR", S["cover_s"]),
             Spacer(1, 6),
             Paragraph("JS8Call + CommStat &nbsp;&middot;&nbsp; FLDIGI + FLMSG + FLAMP", S["cover_s"]),
             Spacer(1, 0.6 * inch),
             code_block(["web SDR / KiwiSDR -> browser tab -> virtual audio device -> JS8Call -> CommStat",
                         "web SDR / KiwiSDR -> browser tab -> virtual audio device -> FLDIGI  -> FLMSG / FLAMP",
                         "",
                         "No radio. No antenna. No transmitting."], w),
             Spacer(1, 0.8 * inch),
             Paragraph("Version %s &nbsp;&middot;&nbsp; %s" % (version(), datetime.date.today().strftime("%B %Y")), S["cover_m"]),
             Paragraph("KC3WHJ", S["cover_m"]),
             Paragraph('<link href="%s" color="#1F4E79">%s</link>' % (REPO_URL, REPO_URL), S["cover_m"]),
             Spacer(1, 0.4 * inch),
             Paragraph("<i>Generated from the project's README and docs by docs/build-guide.py.</i>",
                       ParagraphStyle("gen", parent=S["cover_m"], fontSize=8, textColor=MUTED))]
    from reportlab.platypus import NextPageTemplate
    story += [NextPageTemplate("body"), PageBreak(), Paragraph("Contents", ParagraphStyle("contents", parent=S["h1"]))]
    toc = TableOfContents(); toc.levelStyles = [S["toc1"], S["toc2"]]; toc.dotsMinLevel = 0
    story += [toc, PageBreak()]
    for n, (f, chapter) in enumerate(CHAPTERS):
        if n:
            story.append(PageBreak())
        story += convert(open(os.path.join(ROOT, f)).read(), chapter, w)
    doc.multiBuild(story)
    print("wrote", os.path.relpath(OUT, ROOT))

if __name__ == "__main__":
    sys.exit(build())
