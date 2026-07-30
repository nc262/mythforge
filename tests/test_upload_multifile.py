"""Regression tests for issue #1346 — the multi-file upload rate limit.

Original root cause: the per-IP concurrency guard in routes/upload_routes.py
summed its condition over `files`, and the condition didn't depend on the loop
variable, so it collapsed to `len(files)` whenever the IP had any recent upload.
A multi-file batch sent right after a single upload counted itself as N
concurrent uploads and tripped `max_concurrent_uploads` with a 429.

**routes/upload_routes.py is deleted** — 6 endpoints, none called by the Godot
client. The three endpoint-level tests went with it (they built the router and
invoked its handler directly).

What is kept, and why: `src/upload_handler.py` SURVIVES, because chat_routes
takes it for attachment handling. Its counting and rate-limit behaviour is the
half of #1346 that can still regress, so those tests stay — the guard against a
legitimate batch being throttled is worth keeping even with no HTTP surface in
front of it.
"""
import time

from src.upload_handler import count_recent_uploads, UploadHandler

# Was read out of static/js/fileHandler.js so the server cap was checked against
# the real client cap. The web UI is deleted, so there is no frontend to read and
# the constant is inlined. Weaker than it was, deliberately not dropped: if a
# Godot client ever batches uploads, point this at ITS constant.
FRONTEND_MAX_FILES = 10


def test_count_recent_uploads_ignores_batch_size():
    now = time.time()
    assert count_recent_uploads([], now) == 0
    assert count_recent_uploads([now - 1, now - 2, now - 3], now, window=10) == 3
    assert count_recent_uploads([now - 1, now - 50], now, window=10) == 1
    assert count_recent_uploads([now - 11], now, window=10) == 0


def test_rate_limit_accommodates_a_full_batch():
    # The per-minute file cap must comfortably exceed the client batch cap, or a
    # single legitimate multi-file attach trips it (issue #1346).
    h = UploadHandler.__new__(UploadHandler)
    UploadHandler.__init__(h, base_dir="/tmp", upload_dir="/tmp/_odysseus_test_uploads_cfg")
    assert h.upload_rate_limit >= FRONTEND_MAX_FILES


def test_six_file_batch_is_not_rate_limited(tmp_path):
    h = UploadHandler(base_dir=str(tmp_path), upload_dir=str(tmp_path / "uploads"))
    ip = "9.9.9.9"
    # Six events inside the window must stay under the per-minute cap.
    now = time.time()
    h.upload_rate_log[ip] = [now - i for i in range(6)]
    assert count_recent_uploads(h.upload_rate_log[ip], now, window=60) == 6
    assert h.upload_rate_limit >= 6
