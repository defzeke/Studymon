"""Quality check for question generation and grading against the golden set. Calls Claude, so it
costs money (roughly $1-2 a run on the default models): run it by hand, with --yes.

    uv run --no-project --with-requirements requirements.txt python evals/run_evals.py --yes
"""
import json
import pathlib
import sys
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import ai  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
ESSAY_PASS = 0.65


def extraction() -> bool:
    ok = True
    for path in sorted((HERE / "reviewers").glob("*.txt")):
        text = path.read_text(encoding="utf-8")
        raw = json.loads(ai.generate_questions(text, None))["questions"]
        kept = ai.check_questions(raw, text)
        types = Counter(q["type"] for q in kept)
        tiers = Counter(q["difficulty"] for q in kept)
        kept_rate = len(kept) / max(1, len(raw))
        good = kept_rate >= 0.8 and all(types[t] >= 3 for t in ("identification", "essay", "multiple_choice"))
        ok &= good
        print("%-22s %s kept %d/%d (%.0f%%)  types %s  tiers %s" % (
            path.stem, "PASS" if good else "FAIL", len(kept), len(raw), kept_rate * 100, dict(types), dict(tiers)))
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
