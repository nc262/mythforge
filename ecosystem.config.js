// cwd is pinned to this file's directory so the apps resolve no matter where
// `pm2 start` is invoked from. odysseus-api imports `app:app`, so it MUST run
// from the repo root.
//
// interpreter_args "/c" is REQUIRED for the .cmd app: without it pm2 launches
// `cmd` with no args, which opens an idle interactive shell (reported "online")
// instead of running the .cmd — so the service never actually starts.
//
// The image engine is a plain pm2 app now. It used to be two hidden processes
// (ComfyUI + an OpenAI-shaped bridge) supervised at arm's length by
// scripts/image-stack-watchdog.mjs, because ComfyUI's ZLUDA console had to stay
// hidden — a visible window can catch CTRL_CLOSE and abort ZLUDA — which ruled
// out running it under pm2 directly. sd-server is one native Vulkan binary with
// no CUDA shim and therefore no console fragility, so pm2 supervises it itself
// and the port-polling watchdog is deleted rather than repointed.
const cwd = __dirname;

module.exports = {
  apps: [
    // chroma removed — Mythforge cut ChromaDB (batch 2) and the rag/memory MCP
    // servers that consumed it (see src/builtin_mcp.py), so nothing needs it.
    //
    // env: this repo's backend shares the odysseus checkout's DATA_DIR (the
    // account, model config and saved worlds live there). The shipped exe uses
    // its own data dir via the supervisor; this is the DEV canonical runtime only.
    { name: "odysseus-api", script: "run-api.py", interpreter: "python", cwd,
      env: {
        ODYSSEUS_DATA_DIR: "C:\\Users\\cptahabb\\Documents\\Code\\odysseus\\data",
        // Mythforge is a single-player desktop game — no login. AUTH_ENABLED=false
        // disables the auth middleware so the client goes straight to the menu.
        // Set to "true" only if hosting a shared server for friends (see README).
        AUTH_ENABLED: "false"
      } },
    // stable-diffusion.cpp on Vulkan. interpreter "none" because this is a native
    // exe, not a script. The checkpoint still lives in the ComfyUI tree — that
    // install is left alone for other projects; this just reads the file.
    //
    // Every flag here was measured, not copied:
    //   --diffusion-fa  flash attention in the diffusion model. On an RX 7900 GRE
    //                   this is the difference between comfortable and tight VRAM
    //                   at SDXL 1024.
    //   --vae-tiling    THE fix for a 36 s VAE decode. Untiled, decoding one
    //                   1024x1024 latent asked for a single Vulkan buffer past
    //                   this device's limit; ggml logged "Failed to allocate
    //                   pinned memory ... ErrorOutOfDeviceMemory" and fell back to
    //                   a slow path. Decode was 36.2 s of a 50.4 s image — the
    //                   sampling was never the problem.
    // Steps stay at the server default of 20. Worth knowing: sd-server IGNORES the
    // `steps` field in the OpenAI-shaped request body — a request asking for 8 ran
    // 20/20 in the log — so this is set by flag or not at all. Turbo checkpoints
    // advertise ~8 steps and it does halve sampling (11.3 s/image against 17.2 s),
    // but at 8 the composition collapsed: same prompt and seed rendered the
    // subject tiny and near-black where 20 filled the frame. Paying 6 s for a
    // usable image is the right trade.
    { name: "image-engine", cwd, interpreter: "none",
      script: "C:\\Users\\cptahabb\\Documents\\Code\\stable-diffusion.cpp\\sd-server.exe",
      args: [
        "-m", "C:\\Users\\cptahabb\\Documents\\Code\\ComfyUI-Zluda\\models\\checkpoints\\DreamShaperXL_Turbo_v2_1.safetensors",
        "--listen-port", "8189",
        "--diffusion-fa",
        "--vae-tiling"
      ],
      autorestart: true, restart_delay: 5000 }
  ]
}