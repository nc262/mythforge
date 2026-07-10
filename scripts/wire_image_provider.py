#!/usr/bin/env python3
"""Register the local ComfyUI image bridge as an Odysseus image provider and
select it as the default image model. Idempotent — safe to re-run.

Run with the Odysseus venv from the repo root:
    venv\\Scripts\\python.exe scripts\\wire_image_provider.py
"""
import json
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

BRIDGE_BASE_URL = "http://localhost:8101/v1"
CKPT = "DreamShaperXL_Turbo_v2_1.safetensors"
ENDPOINT_NAME = "Local ComfyUI (ZLUDA)"

from core.database import SessionLocal, ModelEndpoint
from src.settings import load_settings, save_settings

db = SessionLocal()
try:
    ep = db.query(ModelEndpoint).filter(ModelEndpoint.base_url == BRIDGE_BASE_URL).first()
    if ep is None:
        ep = ModelEndpoint(id=uuid.uuid4().hex)
        db.add(ep)
        action = "created"
    else:
        action = "updated"
    ep.name = ENDPOINT_NAME
    ep.base_url = BRIDGE_BASE_URL
    ep.api_key = None
    ep.is_enabled = True
    ep.model_type = "image"
    ep.endpoint_kind = "local"
    ep.model_refresh_mode = "manual"   # bridge exposes /v1/models, but don't depend on probe timing
    ep.cached_models = json.dumps([CKPT])
    db.commit()
    print(f"Endpoint {action}: {ENDPOINT_NAME} -> {BRIDGE_BASE_URL} (image, model={CKPT})")
finally:
    db.close()

settings = load_settings()
settings["image_gen_enabled"] = True
settings["image_model"] = CKPT
# Turbo checkpoint: 'medium' quality maps to ~6 steps in the bridge.
if not settings.get("image_quality"):
    settings["image_quality"] = "medium"
save_settings(settings)
print(f"Settings: image_gen_enabled=True, image_model={CKPT}, image_quality={settings['image_quality']}")
print("Done. Odysseus will route image generation to the local ComfyUI bridge.")
