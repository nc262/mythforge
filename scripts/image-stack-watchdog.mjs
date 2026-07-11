// image-stack-watchdog.mjs — keep the image stack alive.
//
// ComfyUI (:8188) + the OpenAI bridge (:8101) run as hidden GPU processes (a
// visible console can catch a CTRL_CLOSE and abort ZLUDA), so they can't be
// plain pm2 apps. This lightweight watchdog CAN be: pm2 runs it in the logged-in
// session, and whenever a port goes dark it relaunches the hidden
// start-image-stack.ps1 (idempotent — it only starts whatever's actually down).
// Net effect: the image stack auto-restarts on crash instead of staying dead.
import { execFile } from 'node:child_process';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PS1 = path.join(HERE, 'start-image-stack.ps1');
const CHECK_MS = 30_000;
let launching = false;

function portUp(port) {
  return new Promise((res) => {
    const s = net.connect({ host: '127.0.0.1', port, timeout: 2500 }, () => { s.destroy(); res(true); });
    s.on('error', () => res(false));
    s.on('timeout', () => { s.destroy(); res(false); });
  });
}

async function tick() {
  if (launching) return;
  const [comfy, bridge] = await Promise.all([portUp(8188), portUp(8101)]);
  if (comfy && bridge) return;
  launching = true;
  console.log(`${new Date().toISOString()} image stack down (comfy=${comfy} bridge=${bridge}) — relaunching`);
  execFile('powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', PS1],
    { windowsHide: true, timeout: 10 * 60_000 },
    (err) => {
      launching = false;   // start-image-stack.ps1 returns once both are up (or its own 8-min wait elapses)
      if (err) console.error(`launch error: ${err.message}`);
      else console.log(`${new Date().toISOString()} relaunch pass complete`);
    });
}

console.log('image-stack-watchdog started');
tick();
setInterval(tick, CHECK_MS);
