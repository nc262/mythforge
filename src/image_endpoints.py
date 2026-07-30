"""Picking the image endpoint to generate against.

Lifted out of routes/gallery_routes.py. The character studio — the one router the
Godot client genuinely depends on (30 of its 31 paths are called) — imported
`_first_visible_image_endpoint` from the gallery router, which the client never
touches at all. So the gallery could not be removed without taking image
generation down with it, which is the single thing the backend still exists for.

Three small functions, no routes, no request handling: shared logic belongs in
src/, not in whichever router happened to define it first.
"""
from __future__ import annotations

from core.database import ModelEndpoint


def normalize_image_endpoint_base(url: str) -> str:
    """Compare endpoints by host, not by whether someone typed the /v1 suffix."""
    base = (url or "").strip().rstrip("/")
    if base.endswith("/v1"):
        base = base[:-3].rstrip("/")
    return base


def visible_image_endpoint_query(db, owner: str | None):
    from src.auth_helpers import owner_filter
    q = db.query(ModelEndpoint).filter(
        ModelEndpoint.model_type == "image",
        ModelEndpoint.is_enabled == True,  # noqa: E712
    )
    return owner_filter(q, ModelEndpoint, owner)


def first_visible_image_endpoint(db, owner: str | None):
    """The caller's own endpoint if they have one, else any shared enabled one."""
    endpoints = visible_image_endpoint_query(db, owner).all()
    if owner:
        for ep in endpoints:
            if getattr(ep, "owner", None) == owner:
                return ep
    return endpoints[0] if endpoints else None


def visible_image_endpoint_for_base(db, base: str, owner: str | None):
    target = normalize_image_endpoint_base(base)
    if not target:
        return None
    fallback = None
    for ep in visible_image_endpoint_query(db, owner).all():
        if normalize_image_endpoint_base(getattr(ep, "base_url", "")) == target:
            if owner and getattr(ep, "owner", None) == owner:
                return ep
            if fallback is None:
                fallback = ep
    return fallback
