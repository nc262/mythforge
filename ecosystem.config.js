// cwd is pinned to this file's directory so the apps resolve no matter where
// `pm2 start` is invoked from. odysseus-api imports `app:app`, so it MUST run
// from the repo root.
//
// interpreter_args "/c" is REQUIRED for the .cmd app: without it pm2 launches
// `cmd` with no args, which opens an idle interactive shell (reported "online")
// instead of running the .cmd — so the service never actually starts.
//
// The image stack (ComfyUI + bridge) is intentionally NOT managed here. It is a
// one-shot GPU launcher that needs the interactive logon session, so it is
// started at boot by the hidden Startup VBS (scripts/start-image-stack.ps1),
// not by pm2. Run that PS1 directly to (re)start image generation.
const cwd = __dirname;

module.exports = {
  apps: [
    // chroma removed — Mythforge cut ChromaDB (batch 2) and the rag/memory MCP
    // servers that consumed it (see src/builtin_mcp.py), so nothing needs it.
    { name: "odysseus-api", script: "run-api.py", interpreter: "python", cwd }
  ]
}