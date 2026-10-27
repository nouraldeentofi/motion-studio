// Watermark on every exported frame. Only the owner's password removes it.
// The password itself is not stored anywhere: the code keeps a salted
// PBKDF2 key's SHA-256, and an unlocked browser keeps the key (not a flag).
import { color, fontString } from './themes.js';
import { roundRectPath } from './util.js';

export const WM_TEXT = 'nouraldeentofi.com';
const SALT = '030716e3ff78d1e5ff021ab544ec8412';
const CHECK = 'dfd7f02105891afef760e2f8e8a48ffcbc12b7e271157f0c6799c7cf0b326236';
const ITER = 310000;
const KEY = 'nms:wm';

let unlocked = false;

const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
const bytes = (h) => new Uint8Array(h.match(/../g).map((x) => parseInt(x, 16)));
const sha = async (s) => hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));

async function derive(pw) {
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(pw), 'PBKDF2', false, ['deriveBits']);
  return hex(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: bytes(SALT), iterations: ITER }, base, 256));
}

export const watermarkOn = () => !unlocked;

// a browser that was unlocked before stays unlocked, but only with a key that checks out
export async function initWatermark() {
  try {
    const k = localStorage.getItem(KEY);
    unlocked = !!k && (await sha(k)) === CHECK;
  } catch (e) { unlocked = false; }
  return unlocked;
}

export async function unlockWatermark(pw) {
  const k = await derive(String(pw || '').trim().toLowerCase());
  if ((await sha(k)) !== CHECK) return false;
  unlocked = true;
  try { localStorage.setItem(KEY, k); } catch (e) { /* stays unlocked for this visit */ }
  return true;
}

export function lockWatermark() {
  unlocked = false;
  try { localStorage.removeItem(KEY); } catch (e) { /* ignore */ }
}

// bottom-left pill: node mark + address, readable on any background
export function drawWatermark(ctx, env) {
  if (unlocked) return;
  const { W, H, U, theme: th } = env;
  const size = 20 * U;
  ctx.save();
  ctx.setTransform(env.px, 0, 0, env.px, 0, 0);
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = 'source-over';
  ctx.filter = 'none';
  ctx.font = fontString('@mono', th, 600, size);
  if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
  ctx.direction = 'ltr';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  const tw = ctx.measureText(WM_TEXT).width;
  const mark = size * 1.25, gap = size * 0.45, padX = size * 0.6, h = size * 1.6;
  const w = padX * 2 + mark + gap + tw;
  // low in the corner, clear of the centred signature that most scenes end with
  const x = Math.round(W * 0.03), y = Math.round(H - H * 0.012 - h);
  ctx.globalAlpha = 0.55;
  ctx.fillStyle = color('@bg', th);
  roundRectPath(ctx, x, y, w, h, h / 2);
  ctx.fill();
  ctx.globalAlpha = 0.9;
  const cy = y + h / 2, mx = x + padX;
  const acc = color('@accent', th);
  ctx.strokeStyle = acc;
  ctx.fillStyle = acc;
  ctx.lineWidth = Math.max(1, size * 0.09);
  ctx.lineCap = 'round';
  const r = mark * 0.16;
  ctx.beginPath(); ctx.arc(mx + r, cy, r, 0, Math.PI * 2); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(mx + r * 2.2, cy); ctx.lineTo(mx + mark - r * 2.4, cy); ctx.stroke();
  ctx.beginPath(); ctx.arc(mx + mark - r * 1.1, cy, r * 1.1, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = color('@fg', th);
  ctx.fillText(WM_TEXT, mx + mark + gap, cy + size * 0.04);
  ctx.restore();
}
