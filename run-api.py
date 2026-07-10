import uvicorn

from core.platform_compat import suppress_console_windows

if __name__ == "__main__":
    # Headless under pm2: stop child processes (git/tailscale/HF probes) from
    # flashing a console window on every spawn. No-op off Windows.
    suppress_console_windows()
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=7000,
        reload=False
    )