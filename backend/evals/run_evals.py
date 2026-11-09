"""Quality check for question generation and grading against the golden set. It calls the real model
(set AI_BASE_URL and AI_API_KEY, see docs/api-backend.md §4). On Cloudflare's free allowance it costs
nothing, but one run (11 extractions, 15 grades) is estimated at about 5,000 of the day's 10,000
neurons, so run it by hand, with --yes, at most once a day. The run prints what it really spent.

    uv run --no-project --with-requirements requirements.txt python evals/run_evals.py --yes
"""
import io
import json
import pathlib
import re
import sys
import textwrap
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import ai  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
ESSAY_PASS = 0.65


# Common Filipino function words: a question written in Filipino almost always has one.
FILIPINO = re.compile(r"\b(ang|ng|mga|sa|ay|na)\b", re.IGNORECASE)


def _score(name: str, raw: list, kept: list, text: str) -> bool:
    types = Counter(q["type"] for q in kept)
    tiers = Counter(q["difficulty"] for q in kept)
    kept_rate = len(kept) / max(1, len(raw))
    # The prompt asks for about one question per 100 words, 9 to MAX_QUESTIONS; accept 60 % of that.
    wanted = min(ai.MAX_QUESTIONS, max(9, len(text.split()) // 100))
    good = kept_rate >= 0.8 and len(kept) >= 0.6 * wanted \
        and all(types[t] >= 3 for t in ("identification", "essay", "multiple_choice"))
    # A reviewer in Filipino (file name ending in _fil) must get its questions in Filipino too.
    if name.split(".")[0].endswith("_fil"):
        good &= sum(bool(FILIPINO.search(q["text"])) for q in kept) >= 0.8 * max(1, len(kept))
    print("%-30s %s kept %d/%d (%.0f%%, wanted ~%d)  types %s  tiers %s" % (
        name, "PASS" if good else "FAIL", len(kept), len(raw), kept_rate * 100, wanted, dict(types), dict(tiers)))
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
        raw = ai.generate_questions(text).get("questions", [])
        ok &= _score(path.stem, raw, ai.check_questions(raw, text), text)
    # The other upload paths, built from one reviewer: a Word file (read as text) and a photo.
    text = (HERE / "reviewers" / "biology_cells.txt").read_text(encoding="utf-8")
    docx_text = ai.office_text(_as_docx(text), "docx")
    raw = ai.generate_questions(docx_text).get("questions", [])
    ok &= _score("biology_cells.docx", raw, ai.check_questions(raw, docx_text), docx_text)
    raw = ai.generate_questions("", [(_as_photo(text), "image/png")]).get("questions", [])
    ok &= _score("biology_cells.png", raw, ai.check_questions(raw, ""), text)
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
        print("%-24s %s score %.2f (expect %s)  %s" % (c["name"], "PASS" if good else "FAIL", s, c["expect"], r["feedback"]))
    return ok


def measured(label: str, run) -> bool:
    """Runs one half of the evals and prints its neurons per model call, the figures that
    docs/api-backend.md §3 and main.LIKELY_NEURONS record."""
    calls, spent = len(_spent), sum(_spent)
    ok = run()
    n, used = len(_spent) - calls, sum(_spent) - spent
    print("%s: %d model calls, %.0f neurons, %.0f per call" % (label, n, used, used / max(1, n)))
    return ok


_spent: list = []
ai.spend = _spent.append

if __name__ == "__main__":
    if "--yes" not in sys.argv:
        sys.exit("This calls the real model and spends part of the day's free allowance. Re-run with --yes.")
    results = [measured("extraction", extraction), measured("grading", grading)]
    print("neurons spent this run: %.0f" % sum(_spent))
    sys.exit(0 if all(results) else 1)
