"""Endpoint URLs must compare by host, not by a naive rstrip.

Was tests/test_gallery_endpoint_matching.py, pointing at
routes/gallery_routes._normalize_image_endpoint_base. The gallery router is gone
(32 endpoints, none called by the game) but this function moved to
src/image_endpoints.py rather than dying with it — the character studio needs it
to pick an image endpoint, which is the backend's remaining job.

The regression it pins is worth keeping: `rstrip("/v1")` strips CHARACTERS, not
the suffix, so it collapsed ".../v11" onto "..." and ".../dev1" onto ".../dev".
"""
from src.image_endpoints import normalize_image_endpoint_base


def _match(ep_url: str, base_url: str) -> bool:
    return normalize_image_endpoint_base(ep_url) == normalize_image_endpoint_base(base_url)


def test_suffix_stripped_not_characters():
    # Must NOT match — these differ, and only a character-wise strip confuses them.
    assert _match("http://localhost:8000/v11", "http://localhost:8000") is False
    assert _match("http://localhost:8000/dev1", "http://localhost:8000/dev") is False


def test_v1_suffix_is_optional():
    assert _match("http://localhost:8000/v1", "http://localhost:8000") is True
    assert _match("http://localhost:8000", "http://localhost:8000/v1") is True
    assert _match("http://localhost:8000/v1/", "http://localhost:8000/v1") is True
