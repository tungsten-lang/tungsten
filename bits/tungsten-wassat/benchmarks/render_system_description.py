#!/usr/bin/env python3
"""Render the maintained SAT Competition system description as an IEEE-style PDF."""

from __future__ import annotations

import argparse
import html
import re
import subprocess
from pathlib import Path

from pypdf import PdfReader
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    ListFlowable,
    ListItem,
    PageTemplate,
    Paragraph,
    Spacer,
)


HERE = Path(__file__).resolve().parent
BIT_ROOT = HERE.parent
REPO_ROOT = BIT_ROOT.parents[1]
DEFAULT_SOURCE = BIT_ROOT / "docs" / "satcomp-system-description.md"
DEFAULT_OUTPUT = REPO_ROOT / "output" / "pdf" / "wassat-satcomp-system-description.pdf"


def command(*args: str) -> str:
    return subprocess.run(
        list(args), cwd=REPO_ROOT, check=True, capture_output=True, text=True
    ).stdout.strip()


def revision() -> str:
    rev = command("git", "rev-parse", "--short=12", "HEAD")
    dirty = subprocess.run(
        ["git", "status", "--porcelain", "--", str(BIT_ROOT.relative_to(REPO_ROOT))],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return rev + ("+dirty" if dirty else "")


def source_lines() -> int:
    files = sorted((BIT_ROOT / "lib").glob("*.w")) + [BIT_ROOT / "bin" / "wassat.w"]
    return sum(path.read_text().count("\n") for path in files)


def inline(text: str) -> str:
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"`([^`]+)`", r'<font name="Courier">\1</font>', escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", escaped)
    return escaped


def parse_source(path: Path) -> tuple[str, str, str, list[tuple[str, object]]]:
    text = path.read_text().replace("{{revision}}", revision())
    text = text.replace("{{source_lines}}", f"{source_lines():,}")
    lines = text.splitlines()
    if not lines or not lines[0].startswith("# "):
        raise ValueError("system description must start with a level-one title")
    title = lines[0][2:].strip()
    nonblank = [line.strip() for line in lines[1:] if line.strip()]
    if len(nonblank) < 2:
        raise ValueError("system description needs author and affiliation lines")
    author, affiliation = nonblank[0], nonblank[1]

    body_start = 1
    found = 0
    while body_start < len(lines) and found < 2:
        if lines[body_start].strip():
            found += 1
        body_start += 1

    blocks: list[tuple[str, object]] = []
    paragraph: list[str] = []
    bullets: list[str] = []

    def flush() -> None:
        nonlocal paragraph, bullets
        if paragraph:
            blocks.append(("paragraph", " ".join(paragraph)))
            paragraph = []
        if bullets:
            blocks.append(("bullets", bullets))
            bullets = []

    for raw in lines[body_start:]:
        line = raw.strip()
        if line.startswith("## "):
            flush()
            blocks.append(("heading", line[3:].strip()))
        elif line.startswith("- "):
            if paragraph:
                flush()
            bullets.append(line[2:].strip())
        elif not line:
            flush()
        else:
            if bullets:
                flush()
            paragraph.append(line)
    flush()
    return title, author, affiliation, blocks


def styles() -> dict[str, ParagraphStyle]:
    return {
        "body": ParagraphStyle(
            "body",
            fontName="Times-Roman",
            fontSize=8.25,
            leading=9.25,
            alignment=TA_JUSTIFY,
            spaceAfter=2.8,
            allowWidows=0,
            allowOrphans=0,
        ),
        "abstract": ParagraphStyle(
            "abstract",
            fontName="Times-Roman",
            fontSize=8.0,
            leading=9.0,
            alignment=TA_JUSTIFY,
            leftIndent=7,
            rightIndent=7,
            spaceAfter=4,
        ),
        "heading": ParagraphStyle(
            "heading",
            fontName="Helvetica-Bold",
            fontSize=8.5,
            leading=9.5,
            alignment=TA_CENTER,
            spaceBefore=4.2,
            spaceAfter=2.0,
            keepWithNext=True,
        ),
        "references": ParagraphStyle(
            "references",
            fontName="Times-Roman",
            fontSize=7.25,
            leading=7.8,
            alignment=TA_LEFT,
            spaceAfter=2,
        ),
        "bullet": ParagraphStyle(
            "bullet",
            fontName="Times-Roman",
            fontSize=8.0,
            leading=9.2,
            alignment=TA_JUSTIFY,
        ),
    }


def render(source: Path, output: Path) -> None:
    title, author, affiliation, blocks = parse_source(source)
    output.parent.mkdir(parents=True, exist_ok=True)

    page_w, page_h = letter
    margin_x = 0.62 * inch
    bottom = 0.52 * inch
    title_band = 0.95 * inch
    top = page_h - title_band
    gap = 0.24 * inch
    col_w = (page_w - 2 * margin_x - gap) / 2
    frames = [
        Frame(margin_x, bottom, col_w, top - bottom, id="left", showBoundary=0),
        Frame(margin_x + col_w + gap, bottom, col_w, top - bottom, id="right", showBoundary=0),
    ]

    def page(canvas, doc) -> None:
        canvas.saveState()
        if doc.page == 1:
            canvas.setFont("Times-Bold", 16)
            canvas.drawCentredString(page_w / 2, page_h - 0.35 * inch, title)
            canvas.setFont("Times-Roman", 9.2)
            canvas.drawCentredString(page_w / 2, page_h - 0.58 * inch, author)
            canvas.setFont("Times-Italic", 8.2)
            canvas.drawCentredString(page_w / 2, page_h - 0.74 * inch, affiliation)
        canvas.setStrokeColor(colors.HexColor("#777777"))
        canvas.setLineWidth(0.25)
        canvas.line(margin_x, 0.39 * inch, page_w - margin_x, 0.39 * inch)
        canvas.setFillColor(colors.HexColor("#555555"))
        canvas.setFont("Helvetica", 6.5)
        canvas.drawString(
            margin_x,
            0.24 * inch,
            "DRAFT - 2027 submission details remain subject to the published rules",
        )
        canvas.drawRightString(page_w - margin_x, 0.24 * inch, str(doc.page))
        canvas.restoreState()

    doc = BaseDocTemplate(
        str(output),
        pagesize=letter,
        leftMargin=margin_x,
        rightMargin=margin_x,
        topMargin=title_band,
        bottomMargin=bottom,
        title=title,
        author=author,
        subject="SAT Competition system description",
    )
    doc.addPageTemplates([PageTemplate(id="ieee-two-column", frames=frames, onPage=page)])

    style = styles()
    story = []
    section = ""
    for kind, value in blocks:
        if kind == "heading":
            section = str(value)
            story.append(Paragraph(inline(section.upper()), style["heading"]))
        elif kind == "paragraph":
            para_style = style["body"]
            content = inline(str(value))
            if section == "Abstract":
                para_style = style["abstract"]
                content = "<b>Abstract-</b> " + content
            elif section == "References":
                para_style = style["references"]
            story.append(Paragraph(content, para_style))
        elif kind == "bullets":
            items = [
                ListItem(Paragraph(inline(item), style["bullet"]), leftIndent=7)
                for item in value
            ]
            story.append(
                ListFlowable(
                    items,
                    bulletType="bullet",
                    bulletFontName="Times-Roman",
                    bulletFontSize=6,
                    leftIndent=12,
                    bulletOffsetY=1,
                    spaceAfter=3,
                )
            )
    doc.build(story)

    pages = len(PdfReader(str(output)).pages)
    if pages < 1 or pages > 2:
        raise RuntimeError(f"competition description rendered to {pages} pages; expected 1-2")
    print(f"rendered {pages} page(s): {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    render(args.source.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
