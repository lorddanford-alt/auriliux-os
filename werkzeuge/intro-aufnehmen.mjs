// Nimmt das Laser-Intro der Auriliux-Webseite Bild für Bild auf (für das Boot-Intro).
// Läuft beim Cloud-Bau: Google Chrome ohne Bildschirm, gesteuert über das DevTools-Protokoll –
// ohne zusätzliche Pakete (nur Node mit eingebautem WebSocket).
//   node --experimental-websocket intro-aufnehmen.mjs <adresse> <ausgabeordner>
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [adresse, aus] = process.argv.slice(2);
const schlafen = ms => new Promise(r => setTimeout(r, ms));
fs.mkdirSync(aus, { recursive: true });

const chrome = spawn(process.env.CHROME || 'google-chrome', [
  '--headless=new', '--remote-debugging-port=9333', '--no-first-run', '--no-default-browser-check',
  '--hide-scrollbars', '--mute-audio', '--force-color-profile=srgb', '--user-data-dir=' + (process.env.CHROME_PROFIL || '/tmp/intro-chrome'),
  '--window-size=1280,800', 'about:blank'], { stdio: 'ignore' });
process.on('exit', () => { try { chrome.kill(); } catch { /* egal */ } });

let ziel = null;
for (let i = 0; i < 60 && !ziel; i++) {
  await schlafen(250);
  try {
    const l = await (await fetch('http://127.0.0.1:9333/json/list')).json();
    ziel = l.find(t => t.type === 'page');
  } catch { /* Chrome startet noch */ }
}
if (!ziel) { console.error('Chrome nicht erreichbar'); process.exit(1); }

const ws = new WebSocket(ziel.webSocketDebuggerUrl);
await new Promise((ok, f) => { ws.onopen = ok; ws.onerror = f; });
let nr = 0;
const offen = new Map();
const hoerer = [];
ws.onmessage = ev => {
  const m = JSON.parse(ev.data);
  if (m.id && offen.has(m.id)) { const [ok, f] = offen.get(m.id); offen.delete(m.id); m.error ? f(new Error(m.error.message)) : ok(m.result); }
  else if (m.method) hoerer.forEach(h => h(m));
};
const senden = (method, params = {}) => new Promise((ok, f) => { const id = ++nr; offen.set(id, [ok, f]); ws.send(JSON.stringify({ id, method, params })); });
const auswerten = async ausdruck => (await senden('Runtime.evaluate', { expression: ausdruck, returnByValue: true, awaitPromise: true })).result.value;

await senden('Page.enable');
await senden('Runtime.enable');
await senden('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 2, mobile: false });
await senden('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'no-preference' }] });
// Zeitlupe: die Seite läuft 10× langsamer (Uhren, Zeitgeber, Bildwiederholung, Animationen) – so kommt die
// Aufnahme mit, und daraus werden später flüssige 25 Bilder je Sekunde in Originalgeschwindigkeit.
const ZEITLUPE = 0.1;
await senden('Page.addScriptToEvaluateOnNewDocument', { source: `(() => {
  const F = ${ZEITLUPE};
  const pn = performance.now.bind(performance), p0 = pn(), dn = Date.now, d0 = dn();
  performance.now = () => p0 + (pn() - p0) * F;
  Date.now = () => d0 + (dn() - d0) * F;
  const st = window.setTimeout, si = window.setInterval;
  window.setTimeout = (f, ms, ...a) => st(f, (ms || 0) / F, ...a);
  window.setInterval = (f, ms, ...a) => si(f, (ms || 0) / F, ...a);
  const raf = window.requestAnimationFrame.bind(window), caf = window.cancelAnimationFrame.bind(window);
  const SCHRITT = Math.round(1 / F); let nr = 0; const aktiv = new Map();
  window.requestAnimationFrame = cb => {
    const id = ++nr; let n = 0;
    const weiter = () => aktiv.set(id, raf(() => { if (++n < SCHRITT) return weiter(); aktiv.delete(id); cb(performance.now()); }));
    weiter();
    return id;
  };
  window.cancelAnimationFrame = id => { if (aktiv.has(id)) { caf(aktiv.get(id)); aktiv.delete(id); } };
  const an = Element.prototype.animate;
  Element.prototype.animate = function (...a) { const x = an.apply(this, a); x.playbackRate = F; return x; };
  si(() => document.getAnimations().forEach(x => { if (x.playbackRate !== F) x.playbackRate = F; }), 20);
})();` });
const geladen = new Promise(ok => hoerer.push(m => { if (m.method === 'Page.loadEventFired') ok(); }));
await senden('Page.navigate', { url: adresse });
await geladen;
await schlafen(2500);

// Bühne des Logos (in CSS-Pixeln) – zugeschnitten wird später
const buehne = await auswerten("JSON.stringify(document.getElementById('logoStage').getBoundingClientRect())");

// Ausschnitt um das Logo (mit Rand für die Funken, unten mehr – sie fallen), in CSS-Pixeln
const bu = JSON.parse(buehne);
const x0 = Math.max(0, bu.x - 120), x1 = Math.min(1280, bu.x + bu.width + 120);
const y0 = Math.max(0, bu.y - 70), y1 = Math.min(800, bu.y + bu.height + 120);
const ausschnitt = { x: x0, y: y0, width: x1 - x0, height: y1 - y0, scale: 1 };

// Einzelbilder in voller Retina-Auflösung (Faktor 2), so schnell es geht – dank Zeitlupe dicht genug
const bilder = [];
async function foto() {
  const a = Date.now();
  const r = await senden('Page.captureScreenshot', { format: 'png', clip: ausschnitt, fromSurface: true });
  const t = (a + Date.now()) / 2000;
  const datei = `roh-${String(bilder.length).padStart(5, '0')}.png`;
  fs.writeFileSync(path.join(aus, datei), Buffer.from(r.data, 'base64'));
  bilder.push({ t, datei });
}
await foto();
const start = Date.now() / 1000;
await auswerten('introStarten(false)');
let fertig = 0;
while (!fertig && Date.now() / 1000 - start < 240) {
  await foto();
  if (bilder.length % 4 === 0 && await auswerten("document.getElementById('intro').classList.contains('ready')")) fertig = Date.now() / 1000;
}
const nachlauf = Date.now() + 900 / ZEITLUPE;          // erster goldener Glanz läuft noch ein Stück
while (Date.now() < nachlauf) await foto();
const ende = Date.now() / 1000;

const dauer = ((fertig || ende) - start) * ZEITLUPE;
fs.writeFileSync(path.join(aus, 'aufnahme.json'), JSON.stringify({ start, fertig, ende, zeitlupe: ZEITLUPE, buehne: bu, ausschnitt, bilder }, null, 1));
console.log(`Intro aufgenommen: ${bilder.length} Bilder in ${(ende - start).toFixed(1)} s (Intro ${dauer.toFixed(1)} s, ${fertig ? 'fertig' : 'NICHT fertig'})`);
ws.close();
chrome.kill();
process.exit(fertig ? 0 : 2);
