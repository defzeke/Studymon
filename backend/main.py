"""Studymon API: a thin, stateless gateway between the game and the AI model (Gemma 4 on Cloudflare
Workers AI by default; see ai.py). Contract: docs/api-backend.md.

Every response is the job envelope the client's Api.job_status bus expects:
{"job_id", "status": "completed" | "failed", "progress", "result"}.
"""
import base64
import binascii
import datetime
import logging
import os
import re
import threading
from collections import Counter
from typing import Literal

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

import ai

MIN_CHARS = 80
MAX_CHARS = 200_000
MAX_PDF_BYTES = 20 * 1024 * 1024
MAX_PDF_PAGES = 100
MAX_IMAGE_BYTES = 5 * 1024 * 1024
# A photo's type -> the MIME type it goes to the model with. PDF, Word and PowerPoint become text here;
# a scanned PDF becomes page images.
IMAGE_TYPES = {"png": "image/png", "jpeg": "image/jpeg", "webp": "image/webp"}
MAX_ANSWER_CHARS = 4000
# Calls per client IP per UTC day, and for everyone together. No accounts, so these and the neuron
# budget below are what stop one player spending everyone's free allowance. Contract: docs/api-backend.md §6.
DAILY_LIMITS = {"extract": 5, "grade": 300, "report": 20}
DAILY_TOTAL = 20_000
# Cloudflare Workers AI is free up to 10,000 neurons a day (UTC) for the whole account. The server
# stops calling the model a little before that and answers offline instead. A route only starts a call
# when what it is likely to cost still fits. The count lives in memory, so a restart clears it; the
# Workers Free plan itself cannot bill past its allowance either way.
DAILY_NEURONS = float(os.environ.get("DAILY_NEURONS", "9000"))
LIKELY_NEURONS = {"extract": 400.0, "grade": 30.0}

app = FastAPI(title="Studymon API")
log = logging.getLogger("studymon")
_used: Counter = Counter()
_spent: dict[str, float] = {}
_spent_lock = threading.Lock()


def _today() -> str:
    return datetime.datetime.now(datetime.timezone.utc).date().isoformat()


def spend(neurons: float) -> None:
    with _spent_lock:
        day = _today()
        for k in [k for k in _spent if k != day]:
            del _spent[k]
        _spent[day] = _spent.get(day, 0.0) + neurons


def budget_fits(route: str) -> bool:
    with _spent_lock:
        return _spent.get(_today(), 0.0) + LIKELY_NEURONS[route] <= DAILY_NEURONS


ai.spend = spend


class ExtractRequest(BaseModel):
    job_id: str = Field(max_length=64)
    topic_name: str = Field(max_length=120)
    text: str = Field("", max_length=MAX_CHARS)
    file_base64: str = Field("", max_length=MAX_PDF_BYTES * 4 // 3 + 4)
    file_type: Literal["", "pdf", "png", "jpeg", "webp", "docx", "pptx"] = ""
    # "More questions" for a saved world: the questions it already has, so new ones do not repeat them.
    existing: list[str] = Field(default_factory=list, max_length=60)
    # The question types the player ticked in the World Builder.
    types: list[Literal["identification", "essay", "multiple_choice"]] = Field(
        default_factory=lambda: list(ai.QUESTION_TYPES), min_length=1, max_length=3)


class RubricPoint(BaseModel):
    point: str = Field(max_length=500)
    keywords: list[str] = Field(default_factory=list, max_length=10)
    weight: float = 1.0


class GradeRequest(BaseModel):
    job_id: str = Field(max_length=64)
    mode: Literal["identification", "essay"]
    question: str = Field(max_length=2000)
    answer: str = Field(max_length=MAX_ANSWER_CHARS)
    expected: str = Field("", max_length=2000)
    accepted: list[str] = Field(default_factory=list, max_length=20)
    rubric: list[RubricPoint] = Field(default_factory=list, max_length=8)
    model_answer: str = Field("", max_length=4000)
    source: str = Field("", max_length=4000)


def client_ip(request: Request) -> str:
    """The caller's address. Behind one proxy (Cloud Run, Fly) the proxy appends it as the last
    X-Forwarded-For entry; earlier entries come from the client and can be forged."""
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[-1].strip()
    return request.client.host if request.client else "?"


def over_limit(request: Request, route: str, job_id: str) -> JSONResponse | None:
    """Counts one call; a 429 envelope once the caller or everyone together is over today's limit.
    The counts live in memory, so each server instance keeps its own and a restart clears them."""
    day = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    for key in [k for k in _used if k[0] != day]:
        del _used[key]
    mine, total = (day, route, client_ip(request)), (day, "*", "*")
    if _used[mine] >= DAILY_LIMITS[route] or _used[total] >= DAILY_TOTAL:
        return JSONResponse(_failed(job_id, "You've reached today's AI limit. Try again tomorrow."), status_code=429)
    _used[mine] += 1
    _used[total] += 1
    return None


def _done(job_id: str, result) -> dict:
    return {"job_id": job_id, "status": "completed", "progress": 1.0, "result": result}


def _failed(job_id: str, message: str) -> dict:
    return {"job_id": job_id, "status": "failed", "progress": 1.0, "result": message}


def topic_id(name: str) -> str:
    """Same slug as the client's Api._slug_topic_id, so a world keeps its id on either path."""
    slug = re.sub(r"_+", "_", re.sub(r"[^a-z0-9_]", "", name.strip().lower().replace(" ", "_"))).strip("_")
    return "topic_" + slug if slug else "topic_001"


@app.get("/health")
def health() -> dict:
    return {"ok": True}


def _offline(job_id: str, name: str, reviewer_text: str, why: str):
    """No AI questions this time (the free allowance is spent, or the call failed): the reviewer's text
    goes back with no questions and `offline`, and the game writes simpler questions from it on the
    device. A photo or scan has no text to do that with, so it fails with the reason."""
    if len(reviewer_text.strip()) < MIN_CHARS:
        return _failed(job_id, why)
    return _done(job_id, {"topic_id": topic_id(name), "questions": [], "offline": True, "note": why,
                          "reviewer_text": reviewer_text[:MAX_CHARS]})


@app.post("/v1/extract")
def extract(req: ExtractRequest, request: Request):
    if limited := over_limit(request, "extract", req.job_id):
        return limited
    text, images = req.text, []
    if req.file_base64:
        try:
            data = base64.b64decode(req.file_base64, validate=True)
        except binascii.Error:
            return _failed(req.job_id, "That file could not be read.")
        kind = req.file_type
        if kind == "pdf":
            if len(data) > MAX_PDF_BYTES:
                return _failed(req.job_id, "That PDF is over 20 MB.")
            pages = ai.pdf_pages(data)
            if pages == 0:
                return _failed(req.job_id, "That file is not a readable PDF.")
            if pages > MAX_PDF_PAGES:
                return _failed(req.job_id, "That PDF has %d pages; the limit is %d." % (pages, MAX_PDF_PAGES))
            text = ai.pdf_text(data)
            # No text layer: a scan, which the model reads as page images.
            if len(text.strip()) < MIN_CHARS:
                text, images = "", [(png, "image/png") for png in ai.pdf_images(data)]
                if not images:
                    return _failed(req.job_id, "That PDF has no readable pages.")
        elif kind in IMAGE_TYPES:
            if len(data) > MAX_IMAGE_BYTES:
                return _failed(req.job_id, "That photo is over 5 MB. Take it at a lower size.")
            text, images = "", [(data, IMAGE_TYPES[kind])]
        elif kind in ("docx", "pptx"):
            text = ai.office_text(data, kind)
            if len(text.strip()) < MIN_CHARS:
                return _failed(req.job_id, "That file has too little text to study from.")
        else:
            return _failed(req.job_id, "That file type is not supported.")
    elif len(req.text.strip()) < MIN_CHARS:
        return _failed(req.job_id, "Too short: add more material.")
    if not budget_fits("extract"):
        return _offline(req.job_id, req.topic_name, text, "The AI has used today's free allowance. Try again tomorrow.")
    try:
        raw = ai.generate_questions(text, images, req.existing, req.types).get("questions", [])
    except ai.AIError as e:
        return _offline(req.job_id, req.topic_name, text, str(e))
    # `text` "" (a photo or scan) skips the check that each answer is in the reviewer.
    questions = ai.check_questions(raw if isinstance(raw, list) else [], text, req.existing, req.types)
    if not questions:
        return _offline(req.job_id, req.topic_name, text, "No usable questions came out of this reviewer. Try adding more detail.")
    # The reviewer's text goes back so the device can keep it for "More questions" (none for a photo).
    return _done(req.job_id, {"topic_id": topic_id(req.topic_name), "questions": questions,
                              "reviewer_text": text[:MAX_CHARS]})


@app.post("/v1/grade")
def grade(req: GradeRequest, request: Request):
    if limited := over_limit(request, "grade", req.job_id):
        return limited
    # The free allowance is spent: the game grades this answer offline instead.
    if not budget_fits("grade"):
        return JSONResponse(_failed(req.job_id, "AI grading is resting until tomorrow."), status_code=429)
    q = req.model_dump()
    try:
        if req.mode == "identification":
            return _done(req.job_id, ai.grade_identification(q, req.answer))
        if not req.rubric:
            return _failed(req.job_id, "This question has no rubric to grade against.")
        return _done(req.job_id, ai.grade_essay(q, req.answer))
    except ai.AIError as e:
        return _failed(req.job_id, str(e))


class ReportRequest(BaseModel):
    job_id: str = Field(max_length=64)
    kind: Literal["question", "feedback"]
    text: str = Field(max_length=4000)


@app.post("/v1/reports")
def report(req: ReportRequest, request: Request):
    """A player flagged generated content as wrong or offensive (store requirement). It is only
    logged: read the reports in the host's log viewer."""
    if limited := over_limit(request, "report", req.job_id):
        return limited
    log.warning("content report kind=%s text=%r", req.kind, req.text)
    return _done(req.job_id, {"ok": True})
