import json
from types import SimpleNamespace


def test_resolve_model_uses_cached_models_when_live_probe_fails(monkeypatch):
    from src import ai_interaction
    import src.database as database

    endpoint = SimpleNamespace(
        base_url="http://localhost:8101/v1",
        cached_models=json.dumps(["DreamShaperXL_Turbo_v2_1.safetensors"]),
        is_enabled=True,
        name="Local image",
    )

    class Query:
        def filter(self, *args, **kwargs):
            return self

        def all(self):
            return [endpoint]

    class DB:
        def query(self, model):
            return Query()

        def close(self):
            pass

    monkeypatch.setattr(database, "SessionLocal", lambda: DB())

    def fail_models_probe(*args, **kwargs):
        raise RuntimeError("bridge is busy")

    monkeypatch.setattr("httpx.get", fail_models_probe)

    url, model, headers = ai_interaction._resolve_model(
        "DreamShaperXL_Turbo_v2_1.safetensors"
    )

    assert url == "http://localhost:8101/v1/chat/completions"
    assert model == "DreamShaperXL_Turbo_v2_1.safetensors"
    assert headers == {}
