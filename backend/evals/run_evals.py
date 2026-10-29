"""Quality check for question generation and grading against the golden set. Calls Claude, so it
costs money (roughly $2-3 a run on the default models): run it by hand, with --yes.

    uv run --no-project --with-requirements requirements.txt python evals/run_evals.py --yes
"""
import io
import json
import pathlib
import sys
import textwrap
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import ai  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
ESSAY_PASS = 0.65


def _score(name: str, raw: list, kept: list) -> bool:
    types = Counter(q["type"] for q in kept)
    tiers = Counter(q["difficulty"] for q in kept)
    kept_rate = len(kept) / max(1, len(raw))
    good = kept_rate >= 0.8 and all(types[t] >= 3 for t in ("identification", "essay", "multiple_choice"))
    print("%-22s %s kept %d/%d (%.0f%%)  types %s  tiers %s" % (
        name, "PASS" if good else "FAIL", len(kept), len(raw), kept_rate * 100, dict(types), dict(tiers)))
    return good


def _as_docx(text: str) -> bytes:
    import docx
    d = docx.Document()
    for para in text.split("\n"):
        d.add_paragraph(para)
    buf = io.BytesIO()
    d.save(buf)
    return buf.getvalue()


def _as_photo(text: str) -> bytes:
    """The reviewer drawn as a page of notes, standing in for a phone photo."""
    from PIL import Image, ImageDraw
    lines = textwrap.wrap(text.replace("\n", " "), 70)
    img = Image.new("RGB", (1200, 40 + 30 * len(lines)), "white")
    draw = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        draw.text((30, 20 + 30 * i), line, fill="black")
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def extraction() -> bool:
    ok = True
    for path in sorted((HERE / "reviewers").glob("*.txt")):
        text = path.read_text(encoding="utf-8")
        raw = json.loads(ai.generate_questions(text))["questions"]
        ok &= _score(path.stem, raw, ai.check_questions(raw, text))
    # The other upload paths, built from one reviewer: a Word file (read as text) and a photo.
    text = (HERE / "reviewers" / "biology_cells.txt").read_text(encoding="utf-8")
    docx_text = ai.office_text(_as_docx(text), "docx")
    raw = json.loads(ai.generate_questions(docx_text))["questions"]
    ok &= _score("biology_cells.docx", raw, ai.check_questions(raw, docx_text))
    raw = json.loads(ai.generate_questions("", _as_photo(text), "image/png"))["questions"]
    ok &= _score("biology_cells.png", raw, ai.check_questions(raw, ""))
    return ok


def grading() -> bool:
    cases = json.loads((HERE / "grading_cases.json").read_text(encoding="utf-8"))
    by_name = {c["name"]: c for c in cases}
    ok = True
    for c in cases:
        q = dict(by_name[c["same_as"]], **{k: v for k, v in c.items() if k != "same_as"}) if "same_as" in c else c
        if q["mode"] == "identification":
            r = ai.grade_identification(q, q["answer"])
        else:
            r = ai.grade_essay(q, q["answer"])
        s = r["score"]
        good = {"pass": s >= ESSAY_PASS, "fail": s < 0.34, "partial": 0.2 <= s < ESSAY_PASS}[c["expect"]]
        ok &= good
        print("%-18s %s score %.2f (expect %s)  %s" % (c["name"], "PASS" if good else "FAIL", s, c["expect"], r["feedback"]))
    return ok


if __name__ == "__main__":
    if "--yes" not in sys.argv:
        sys.exit("This calls Claude and costs money. Re-run with --yes.")
    results = [extraction(), grading()]
    sys.exit(0 if all(results) else 1)
