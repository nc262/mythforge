// cwd is pinned to this file's directory so the apps resolve no matter where
// `pm2 start` is invoked from. odysseus-api imports `app:app`, so it MUST run
// from the repo root.
//
// interpreter_args "/c" is REQUIRED for the .cmd app: without it pm2 launches
// `cmd` with no args, which opens an idle interactive shell (reported "online")
// instead of running the .cmd — so the service never actually starts.
//
// The image stack (ComfyUI + bridge) can't be plain pm2 apps: ComfyUI's ZLUDA
// console must stay hidden (a visible window can catch CTRL_CLOSE and abort it),
// so it's launched hidden by scripts/start-image-stack.ps1. To make it auto-heal
// (previously a crash left image gen dead), pm2 runs image-stack-watchdog.mjs —
// a tiny no-GPU process that relaunches that hidden launcher whenever :8188 or
// :8101 go dark. So the stack is now managed (auto-restart) without the window
// fragility of running ComfyUI directly under pm2.
const cwd = __dirname;

module.exports = {
  apps: [
    // chroma removed — Mythforge cut ChromaDB (batch 2) and the rag/memory MCP
    // servers that consumed it (see src/builtin_mcp.py), so nothing needs it.
    { name: "odysseus-api", script: "run-api.py", interpreter: "python", cwd },
    { name: "image-stack", script: "scripts/image-stack-watchdog.mjs", cwd, autorestart: true, restart_delay: 5000 }
  ]
}