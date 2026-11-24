"""Quality check for question generation and grading against the golden set. Contract: docs/api-backend.md §4.

A live run calls the real model (AI_BASE_URL and AI_API_KEY) and saves every reply under evals/runs/<time>/.
On Cloudflare's free allowance it costs nothing, but it spends part of the day's 10,000 neurons, so run
it by hand, with --yes. --rescore replays a saved run through the current checks and scoring with no
model calls, so a change to check_questions, the labels or the cases costs nothing to measure.

    python evals/run_evals.py --yes [--only biology_cells,ph_history] [--no-grading] [--pause 20]
    python evals/run_evals.py --yes --into evals/runs/<time>     # redo only what failed there
    python evals/run_evals.py --rescore evals/runs/<time>
"""
import argparse
import datetime
import io
import json
import pathlib
import re
import sys
import textwrap
import time
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import ai  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
ESSAY_PASS = 0.65
# Cloudflare's neurons per million tokens for Gemma 4 26B, so a run on Google's endpoint (which counts
# none) still reports what it would cost on Cloudflare.
CF_IN, CF_OUT = 9091, 27273
# Common Filipino function words: a question written in Filipino almost always has one.
FILIPINO = re.compile(r"\b(ang|ng|mga|sa|ay|na)\b", re.IGNORECASE)

calls: list = []
json_failures = [0]


def _record_calls() -> None:
    """Counts tokens, seconds and cut-off answers per model call, and replies that did not parse."""
    create, parse = ai.client.chat.completions.create, ai.parse_json

    def timed(**kw):
        t = time.monotonic()
        r = create(**kw)
        u = r.usage
        calls.append({"in": u.prompt_tokens if u else 0, "out": u.completion_tokens if u else 0,
                      "s": round(time.monotonic() - t, 1), "finish": r.choices[0].finish_reason})
        return r

    def counted(raw):
        try:
            return parse(raw)
        except ValueError:
            json_failures[0] += 1
            raise
    ai.client.chat.completions.create, ai.parse_json = timed, counted


def _cf_neurons(cs: list) -> float:
    return sum(c["in"] * CF_IN + c["out"] * CF_OUT for c in cs) / 1_000_000


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


def _reviewers(only: set) -> list:
    """(name, text sent, images, grounding text, words the count target comes from) per reviewer."""
    out = []
    for path in sorted((HERE / "reviewers").glob("*.txt")):
        text = path.read_text(encoding="utf-8")
        out.append((path.stem, text, None, text, text))
    # The other upload paths, built from one reviewer: a Word file (read as text) and a photo.
    bio = (HERE / "reviewers" / "biology_cells.txt").read_text(encoding="utf-8")
    docx_text = ai.office_text(_as_docx(bio), "docx")
    out.append(("biology_cells.docx", docx_text, None, docx_text, docx_text))
    out.append(("biology_cells.png", "", [(_as_photo(bio), "image/png")], "", bio))
    return [r for r in out if not only or r[0].split(".")[0] in only]


def extract_live(run: pathlib.Path, only: set, pause: float) -> None:
    for name, text, images, _, _ in _reviewers(only):
        path = run / ("extract_%s.json" % name)
        if path.exists() and not json.loads(path.read_text(encoding="utf-8"))["error"]:
            continue
        time.sleep(pause)
        before, t = len(calls), time.monotonic()
        try:
            raw, error = ai.generate_questions(text, images).get("questions", []), ""
        except ai.AIError as e:
            raw, error = [], str(e)
        saved = {"raw": raw, "error": error, "seconds": round(time.monotonic() - t, 1), "calls": calls[before:]}
        path.write_text(json.dumps(saved, ensure_ascii=False, indent=1), encoding="utf-8")


def _score(name: str, raw: list, kept: list, words: str, error: str) -> bool:
    types = Counter(q["type"] for q in kept)
    tiers = Counter(q["difficulty"] for q in kept)
    kept_rate = len(kept) / max(1, len(raw))
    # The prompt asks for about one question per 100 words, 9 to 30; accept 60 % of that.
    wanted = min(30, max(9, len(words.split()) // 100))
    good = not error and kept_rate >= 0.8 and len(kept) >= 0.6 * wanted \
        and all(types[t] >= 3 for t in ai.QUESTION_TYPES)
    # A reviewer in Filipino (file name ending in _fil) must get its questions in Filipino too.
    if name.split(".")[0].endswith("_fil"):
        good &= sum(bool(FILIPINO.search(q["text"])) for q in kept) >= 0.8 * max(1, len(kept))
    print("%-28s %s kept %d/%d (%.0f%%, wanted ~%d)  types %s  tiers %s %s" % (
        name, "PASS" if good else "FAIL", len(kept), len(raw), kept_rate * 100, wanted, dict(types), dict(tiers), error))
    return good


def extract_score(run: pathlib.Path) -> bool:
    """Rescores every saved extraction, writes the kept questions to kept.json for labelling, and
    prints the share of labelled questions that are good."""
    labels = json.loads((HERE / "question_labels.json").read_text(encoding="utf-8"))
    ok, kept_all, cs, secs = True, [], [], []
    by_name = {r[0]: r for r in _reviewers(set())}
    for path in sorted(run.glob("extract_*.json")):
        name = path.stem[len("extract_"):]
        saved = json.loads(path.read_text(encoding="utf-8"))
        _, _, _, grounding, words = by_name[name]
        kept = ai.check_questions(saved["raw"], grounding)
        ok &= _score(name, saved["raw"], kept, words, saved["error"])
        kept_all += [dict(q, reviewer=name) for q in kept]
        cs += saved["calls"]
        secs.append(saved["seconds"])
    (run / "kept.json").write_text(json.dumps(kept_all, ensure_ascii=False, indent=1), encoding="utf-8")
    rated = [labels[q["id"]] for q in kept_all if q["id"] in labels]
    good = [r for r in rated if r["correct"] and not r["ambiguous"] and r.get("fair") is not False]
    print("quality: %d of %d labelled questions good (%.0f%%); %d kept questions unlabelled" % (
        len(good), len(rated), 100 * len(good) / max(1, len(rated)), len(kept_all) - len(rated)))
    print("  wrong key %d, ambiguous %d, unfair options %d" % (sum(not r["correct"] for r in rated),
          sum(r["ambiguous"] for r in rated), sum(r.get("fair") is False for r in rated)))
    _cost("extraction", cs, secs)
    return ok


def _cost(label: str, cs: list, secs: list) -> None:
    n = max(1, len(cs))
    print("%s: %d model calls, %d cut off, %.0f Cloudflare neurons (%.0f per call), %d in / %d out tokens per call, "
          "slowest request %.0f s" % (label, len(cs), sum(c["finish"] == "length" for c in cs), _cf_neurons(cs),
                                       _cf_neurons(cs) / n, sum(c["in"] for c in cs) / n, sum(c["out"] for c in cs) / n,
                                       max(secs or [0])))


def _cases() -> list:
    cases = json.loads((HERE / "grading_cases.json").read_text(encoding="utf-8"))
    by_name = {c["name"]: c for c in cases}
    return [dict(by_name[c["same_as"]], **{k: v for k, v in c.items() if k != "same_as"}) if "same_as" in c else c
            for c in cases]


def grade_live(run: pathlib.Path, pause: float) -> None:
    """Grades every case not yet graded in `run` and saves the model's raw reply per case."""
    path = run / "grading.json"
    chat, replies = ai._chat, json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    meta = replies.pop("_meta", {"calls": [], "seconds": 0})

    def recording(*a, **k):
        replies[name] = {"error": ""}
        replies[name]["reply"] = chat(*a, **k)
        return replies[name]["reply"]
    ai._chat = recording
    before, t = len(calls), time.monotonic()
    for c in _cases():
        name = c["name"]
        if not replies.get(name, {"error": "not run"})["error"]:
            continue
        time.sleep(pause)
        try:
            (ai.grade_identification if c["mode"] == "identification" else ai.grade_essay)(c, c["answer"])
        except ai.AIError as e:
            replies[name] = {"error": str(e)}
    ai._chat = chat
    replies["_meta"] = {"calls": meta["calls"] + calls[before:], "seconds": meta["seconds"] + round(time.monotonic() - t, 1)}
    path.write_text(json.dumps(replies, ensure_ascii=False, indent=1), encoding="utf-8")


def grade_score(run: pathlib.Path) -> bool:
    """Replays the saved replies: each case's band, and per rubric point whether the grader's credit (after
    the server's evidence check) is one the case allows."""
    saved = json.loads((run / "grading.json").read_text(encoding="utf-8"))
    chat, ok, points, agree, bands = ai._chat, True, 0, 0, 0
    cases = _cases()
    for c in cases:
        s = saved.get(c["name"], {"error": "not run"})
        if s["error"]:
            ok = False
            print("%-24s FAIL %s" % (c["name"], s["error"]))
            continue
        ai._chat = lambda *a, **k: s["reply"]
        r = (ai.grade_identification if c["mode"] == "identification" else ai.grade_essay)(c, c["answer"])
        sc = r["score"]
        good = {"pass": sc >= ESSAY_PASS, "fail": sc < 0.34, "partial": 0.2 <= sc < ESSAY_PASS}[c["expect"]]
        bands += good
        ok &= good
        miss = ""
        if c["mode"] == "essay":
            got = ["none"] * len(c["rubric"])
            for p in s["reply"].get("points", []):
                i = p.get("index", -1) if isinstance(p, dict) else -1
                if isinstance(i, int) and 0 <= i < len(got) and ai._in_answer(str(p.get("evidence", "")), ai._norm(c["answer"])):
                    got[i] = p.get("credit", "none")
            hit = [g in want.split("|") for g, want in zip(got, c["credits"])]
            points, agree = points + len(hit), agree + sum(hit)
            miss = "" if all(hit) else " points %s, want %s" % (got, c["credits"])
        print("%-24s %s score %.2f (expect %s)%s  %s" % (c["name"], "PASS" if good else "FAIL", sc, c["expect"], miss, r["feedback"]))
    ai._chat = chat
    print("grading: %d of %d cases in band (%.0f%%); essay points agree %d of %d (%.0f%%)" % (
        bands, len(cases), 100 * bands / len(cases), agree, points, 100 * agree / max(1, points)))
    meta = saved.get("_meta", {"calls": [], "seconds": 0})
    _cost("grading", meta["calls"], [max([c["s"] for c in meta["calls"]] or [0])])
    return ok


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--yes", action="store_true", help="call the real model")
    p.add_argument("--rescore", type=pathlib.Path, help="a saved run to score again, offline")
    p.add_argument("--only", default="", help="comma-separated reviewer names")
    p.add_argument("--no-grading", action="store_true")
    # Google's free tier caps tokens per minute and answers 429 past it.
    p.add_argument("--into", type=pathlib.Path, help="a saved run: redo only its failed or missing items")
    p.add_argument("--pause", type=float, default=0, help="seconds between extractions; a fifth of it between grades")
    a = p.parse_args()
    if a.rescore:
        run = a.rescore
    elif a.yes:
        run = a.into or HERE / "runs" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        run.mkdir(parents=True, exist_ok=True)
        _record_calls()
        extract_live(run, set(filter(None, a.only.split(","))), a.pause)
        if not a.no_grading:
            grade_live(run, a.pause / 5)
        print("saved to %s, %d replies did not parse" % (run, json_failures[0]))
        old = run / "json_failures.txt"
        old.write_text(str(json_failures[0] + (int(old.read_text()) if old.exists() else 0)))
    else:
        sys.exit("A live run calls the real model and spends part of the day's free allowance: --yes. "
                 "Or --rescore a saved run.")
    results = [extract_score(run)]
    if (run / "grading.json").exists():
        results.append(grade_score(run))
    sys.exit(0 if all(results) else 1)
