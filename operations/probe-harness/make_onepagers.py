#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["fpdf2"]
# ///
"""
Render the prospect one-pagers to branded A4 PDFs.

Conforms to `branding/006 BRAND_PACK.md` §4.2 and §8. Voice and copy blocks are
lifted from the reference implementation `branding/003 HOMEPAGE_MOCKUP.html`.

STRUCTURE (v2, rebuilt 6 Aug after review). Every page:
  1. Hook-led headline. One of Wrong / Missing / Losing. Never a method headline.
  2. Standfirst: why they should read on, before any number.
  3. The question their buyers asked.
  4. What came back: counts only.
  5. The finding: ONE specimen. States the error, NEVER the remedy.
  6. Who it named instead.
  7. Why this matters: the emotional turn, hook-specific.
  8. What VIDET is: they have never heard of us. Two sentences.
  9. Founding cohort: the reason to act now, not just the price.

RULES ENCODED HERE:
  - No page names the source of an error. Naming it hands over the fix for free.
  - No page suggests a remedy, a channel or a surface to correct.
  - Every page carries exactly one hook. Mixed hooks read as a list of complaints.

  uv run make_onepagers.py
"""
from pathlib import Path
from fpdf import FPDF
import json

ROOT = Path(__file__).resolve().parents[2]
LOGO = ROOT / "branding" / "logo" / "videt-mark.svg"
OUT = ROOT / "prospects" / "onepagers"
DATA = Path(__file__).resolve().parent / "onepager_content.json"

CHALK, SURFACE = (242, 243, 239), (250, 250, 247)
PETROL, INK, INK2, INK3 = (14, 69, 83), (30, 43, 40), (68, 83, 78), (93, 107, 101)
WASH, RULE, OCHRE = (227, 237, 236), (214, 218, 210), (135, 82, 19)

M = 16
PW = 210 - 2 * M

# Shared blocks. Voice from 003 HOMEPAGE_MOCKUP.html, verbatim where quoted.
WHO_WE_ARE = (
    "This is the only sales channel you cannot see: no impression, no click, no record, so nothing in "
    "your reporting will ever show you the buyer who asked a machine and was handed someone else's name. "
    "We measure what the assistants actually say when a buyer asks who to use, counted and dated, so you "
    "can read what they read. Already paying someone for search or AI work? Keep them. We tell them where "
    "to aim, and tell you whether it worked."
)
FOUNDING = (
    "You were chosen, not scraped. We measure a small number of firms whose work suggests they would "
    "actually want the answer, and we do it before making contact. That is why this page already exists.\n"
    "Lee Powell runs every assessment himself. Thirty years in commercial software, creator of Scrivener "
    "for Windows and its million-plus writers, two companies built and sold, previously IBM, banking and "
    "pharmaceutical systems, Oxford masters on a full scholarship. Someone who can talk business and read "
    "the machine.\n"
    "You will know what the machines say about your business before your competitors know about theirs. "
    "When something moves, you will be able to prove it moved and say when it started, because nobody can "
    "measure backwards and a baseline begun today is one they cannot buy at any price. And whatever this "
    "costs later, it will never cost you more than it does now."
)
CTA = (
    "Assessment A$990, or A$1,490 with a 90-day re-measure that puts a before and after on paper. "
    "Delivered personally within five business days. If the machines already have you covered, "
    "we will show you that, and there is nothing for you to buy."
)


class OnePager(FPDF):
    def __init__(self, hold_reason=None):
        super().__init__(format="A4", unit="mm")
        self.hold_reason = hold_reason
        self.set_auto_page_break(True, margin=26)
        self.set_margins(M, M, M)

    def header(self):
        self.set_fill_color(*CHALK)
        self.rect(0, 0, 210, 297, "F")
        self.image(str(LOGO), x=M, y=12, h=5.5)
        self.set_xy(M + 9, 12)
        self.set_font("Helvetica", "B", 12)
        self.set_text_color(*PETROL)
        self.cell(40, 5.5, "VIDET")
        self.set_font("Helvetica", "", 8.5)
        self.set_text_color(*INK3)
        self.set_xy(210 - M - 40, 12)
        self.cell(40, 5.5, "videt.ai", align="R")
        self.set_draw_color(*RULE)
        self.set_line_width(0.2)
        self.line(M, 20, 210 - M, 20)
        self.set_y(25)
        if self.hold_reason:
            self.set_fill_color(255, 244, 230)
            self.set_draw_color(*OCHRE)
            self.rect(M, 22, PW, 6, "DF")
            self.set_xy(M + 2, 22.5)
            self.set_font("Courier", "B", 7.5)
            self.set_text_color(*OCHRE)
            self.cell(PW - 4, 5, f"DRAFT, NOT FOR SEND. {self.hold_reason.upper()}")
            self.set_y(31)

    def footer(self):
        self.set_y(-24)
        self.set_draw_color(*RULE)
        self.line(M, self.get_y(), 210 - M, self.get_y())
        self.ln(2)
        self.set_font("Helvetica", "I", 7.5)
        self.set_text_color(*INK3)
        self.multi_cell(PW, 3.6,
            "This is a measurement of AI assistant behaviour, not professional advice.\n"
            "Every observation is logged with its date, the assistant, the model and the session. Ask us for any of them.", align="L")

    def label(self, text):
        self.ln(2.2)
        self.set_font("Courier", "B", 7)
        self.set_text_color(*OCHRE)
        self.cell(PW, 3.6, " ".join(text.upper()), new_x="LMARGIN", new_y="NEXT")
        self.ln(0.9)

    def eyebrow(self, business):
        """Names the recipient above the headline. Nothing about this page is generic."""
        self.set_font("Courier", "B", 7.5)
        self.set_text_color(*OCHRE)
        self.cell(PW, 4, " ".join(f"PREPARED FOR {business.upper()}"), new_x="LMARGIN", new_y="NEXT")
        self.set_font("Courier", "", 7)
        self.set_text_color(*INK3)
        self.cell(PW, 4, " ".join("6 AUGUST 2026 . MEASURED, NOT ESTIMATED"), new_x="LMARGIN", new_y="NEXT")
        self.ln(2.5)

    def h1(self, text):
        self.set_font("Helvetica", "B", 18)
        self.set_text_color(*PETROL)
        self.multi_cell(PW, 7.2, text, align="L")
        self.ln(1.2)

    def stand(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(*INK2)
        self.multi_cell(PW, 4.7, text, align="L")
        self.ln(0.5)

    def body(self, text, size=9.3, colour=INK):
        self.set_font("Helvetica", "", size)
        self.set_text_color(*colour)
        self.multi_cell(PW, 4.3, text, align="L")

    def counts(self, rows):
        for fig, desc in rows:
            y = self.get_y()
            self.set_font("Helvetica", "B", 11)
            self.set_text_color(*PETROL)
            self.set_xy(M, y)
            self.cell(28, 5, fig)
            self.set_font("Helvetica", "", 9.5)
            self.set_text_color(*INK)
            self.set_xy(M + 28, y)
            self.multi_cell(PW - 28, 5, desc, align="L")
            self.ln(0.8)

    def quotebox(self, text):
        self.ln(0.5)
        y0 = self.get_y()
        self.set_font("Helvetica", "I", 10)
        self.set_text_color(*INK)
        self.set_xy(M + 5, y0 + 2)
        self.multi_cell(PW - 8, 4.8, text, align="L")
        y1 = self.get_y()
        self.set_fill_color(*WASH)
        self.rect(M, y0, 1.6, y1 - y0 + 2.5, "F")
        self.set_y(y1 + 2.5)

    def fits(self, h):
        """Push a solid block to the next page rather than let it split."""
        if self.get_y() + h > self.h - self.b_margin:
            self.add_page()

    def panel(self, heading, text):
        """Surface-tinted panel for the who-we-are and founding blocks."""
        self.ln(1.2)
        self.set_font("Helvetica", "", 8.6)
        y0 = self.get_y()
        lines = len(self.multi_cell(PW - 8, 4.0, text, dry_run=True, output="LINES"))
        h = 4.0 * (lines + 1) + 3.8
        self.fits(h + 2)
        y0 = self.get_y()
        self.set_fill_color(*SURFACE)
        self.set_draw_color(*RULE)
        self.rect(M, y0, PW, h, "DF")
        self.set_xy(M + 4, y0 + 2.5)
        self.set_font("Helvetica", "B", 9)
        self.set_text_color(*PETROL)
        self.cell(PW - 8, 4.0, heading, new_x="LMARGIN", new_y="NEXT")
        self.set_x(M + 4)
        self.set_font("Helvetica", "", 8.6)
        self.set_text_color(*INK2)
        self.multi_cell(PW - 8, 4.0, text, align="L")
        self.set_y(y0 + h + 1)

    def offerbox(self, text):
        self.ln(1)
        self.set_font("Helvetica", "", 9.5)
        y0 = self.get_y()
        h = 4.6 * len(self.multi_cell(PW - 8, 4.6, text, dry_run=True, output="LINES")) + 6
        self.fits(h + 2)
        y0 = self.get_y()
        self.set_fill_color(*PETROL)
        self.rect(M, y0, PW, h, "F")
        self.set_xy(M + 4, y0 + 3)
        self.set_font("Helvetica", "", 9.5)
        self.set_text_color(*CHALK)
        self.multi_cell(PW - 8, 4.6, text, align="L")
        self.set_y(y0 + h + 2)


def build(rep):
    pdf = OnePager(hold_reason=rep.get("hold"))
    pdf.add_page()
    pdf.eyebrow(rep["business"])
    pdf.h1(rep["headline"])
    pdf.stand(rep["standfirst"])
    pdf.label("The question your buyers are asking")
    pdf.quotebox(rep["question"])
    pdf.label("What came back")
    pdf.counts([tuple(r) for r in rep["counts"]])
    pdf.label(rep.get("finding_label", "One thing it said"))
    pdf.body(rep["finding"])
    pdf.label("Who it named instead")
    pdf.body(rep["named_instead"])
    pdf.label("Why this matters")
    pdf.body(rep["why_matters"], size=10)
    pdf.panel("What this gives you", WHO_WE_ARE)
    pdf.panel("Why you, and who is doing this", FOUNDING)
    pdf.offerbox(CTA)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{rep['slug']}-videt-screen-2026-08-06.pdf"
    pdf.output(str(path))
    return path


if __name__ == "__main__":
    reports = json.loads(DATA.read_text())
    for rep in reports:
        p = build(rep)
        print(f"[{rep['hook'].upper():<7}] {p.name}{'  DRAFT' if rep.get('hold') else ''}")
    print(f"\n{len(reports)} PDFs in {OUT}")
