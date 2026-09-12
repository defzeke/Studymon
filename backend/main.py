"""Studymon API skeleton — Phase 0: health check only.

Phase 5 adds POST /extract (PDF -> Claude document -> structured JSON).
Phase 7 adds POST /grade {type, question, answer, source_context} -> {score_0_1, feedback}.
"""
from fastapi import FastAPI

app = FastAPI(title="Studymon API")


@app.get("/health")
def health() -> dict:
    return {"ok": True}
