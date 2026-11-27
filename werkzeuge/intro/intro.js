/* Auriliux-Intro als Schreibtisch-Hintergrund.
   Der Code zwischen den Markierungen ist 1:1 aus der Auriliux-Webseite übernommen
   (Claude_Projekte/AuriliuxWebseite/js/app.js: Laserfunken, Lasergeräusch, Intro). */
(() => {
  'use strict';
  const DEFAULTS = window.AURILIUX_DEFAULTS;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const clone = o => JSON.parse(JSON.stringify(o));
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const cssUrl = s => String(s).replace(/["\\\n]/g, c => encodeURIComponent(c));
  const rand = (a, b) => a + Math.random() * (b - a);
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  function loadImage(src) {
    return new Promise((res, rej) => {
      const img = new Image();
      img.onload = () => res(img);
      img.onerror = rej;
      img.src = src;
    });
  }

  let state = clone(DEFAULTS);
  let editing = false;

  /* ===== ab hier unverändert aus der Webseite ===== */
  const Embers = (() => {
    const cv = $('#embers');
    const ctx = cv.getContext('2d');
    let W = 0, H = 0, parts = [], raf = 0;

    function resize() {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = innerWidth; H = innerHeight;
      cv.width = W * dpr; cv.height = H * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    function tick() {
      raf = 0;
      ctx.clearRect(0, 0, W, H);
      ctx.globalCompositeOperation = 'lighter';
      for (let i = parts.length - 1; i >= 0; i--) {
        const p = parts[i];
        p.life++;
        p.vx *= 0.97;
        p.vy = p.vy * 0.97 + 0.22;
        p.x += p.vx;
        p.y += p.vy;
        const t = p.life / p.max;
        if (t >= 1) { parts.splice(i, 1); continue; }
        const a = t < 0.1 ? t / 0.1 : 1 - (t - 0.1) / 0.9;
        // kurzer, glühender Strich in Flugrichtung, kühlt von Weißgelb zu Orange ab
        ctx.strokeStyle = `rgba(255,${Math.round(150 + 100 * (1 - t))},${Math.round(60 + 140 * (1 - t))},${a})`;
        ctx.lineWidth = p.r;
        ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x - p.vx * 2.2, p.y - p.vy * 2.2); ctx.stroke();
      }
      if (parts.length) raf = requestAnimationFrame(tick);
    }
    resize();
    addEventListener('resize', resize);

    return {
      sparks(x, y, n = 3) {
        if (reduceMotion) return;
        for (let i = 0; i < n; i++) {
          const a = rand(-Math.PI, 0), s = rand(1.5, 5.5);
          parts.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, r: rand(0.8, 1.8), max: rand(18, 42), life: 0 });
        }
        if (!raf) raf = requestAnimationFrame(tick);
      }
    };
  })();

  /* ------------------------------------------------------------------------
     Intro: Ein CNC-Laser schneidet die Umrisse des Logos aus
     ------------------------------------------------------------------------ */
  /* Lasergeräusch zur Logo-Animation (assets/sound/cnc.wav): der gleichmäßige Teil der Aufnahme
     läuft in gleichbleibender Lautstärke als Schleife, solange graviert wird, und wandert im
     Stereobild mit dem Laserkopf. Hört die Gravur auf, stoppt auch die Maschine (das kurze Ende der
     Aufnahme) – und ein elektrischer Funke (assets/sound/funke.wav) knallt zum Schluss. */
  const CncSound = (() => {
    // Schleife: gleichmäßiger Teil der Aufnahme; Ausklang: das Ende, an dem die Maschine stoppt
    const FILE = 'assets/sound/cnc.wav', LOOP = [0.4, 7], TAIL = 7.5, VOL = 0.55;
    // Funke: der hörbare Teil der Aufnahme (Knall und Knistern), danach ist sie still
    const SPARK = 'assets/sound/funke.wav', SPARK_LEN = 1.4, SPARK_VOL = 0.7;
    let ctx = null, buf = null, sparkBuf = null, loading = null, src = null, gain = null, pan = null;
    function context() {
      const C = window.AudioContext || window.webkitAudioContext;
      if (!ctx && C) ctx = new C();
      if (ctx && ctx.state === 'suspended') ctx.resume().catch(() => {});
      return ctx;
    }
    function load() {
      loading = loading || (async () => {
        const c = context();
        if (!c) return null;
        const decode = async f => c.decodeAudioData(await (await fetch(f)).arrayBuffer());
        [buf, sparkBuf] = await Promise.all([decode(FILE), decode(SPARK).catch(e => { console.warn('Funkengeräusch nicht geladen.', e); return null; })]);
        return buf;
      })().catch(e => { console.warn('Lasergeräusch nicht geladen.', e); return null; });
      return loading;
    }
    // zum Schluss der Gravur: ein kurzer, scharfer Funke in der Mitte des Logos
    function spark() {
      if (!sparkBuf || !ctx || state.intro.sound === false) return;
      const t = ctx.currentTime, s = ctx.createBufferSource(), g = ctx.createGain();
      s.buffer = sparkBuf;
      g.gain.setValueAtTime(SPARK_VOL, t);
      g.gain.setTargetAtTime(0, t + SPARK_LEN - 0.15, 0.05);   // sanft enden statt abgeschnitten
      s.connect(g).connect(ctx.destination);
      s.start(t);
      s.stop(t + SPARK_LEN + 0.1);
    }
    // startet sofort – die Aufnahme ist vorher geladen (load), damit Ton und Laser gleichzeitig beginnen
    function start() {
      stop(0);
      const c = context();
      if (state.intro.sound === false || !c || !buf) return;
      src = c.createBufferSource();
      src.buffer = buf;
      src.loop = true;
      src.loopStart = LOOP[0];
      src.loopEnd = LOOP[1];
      gain = c.createGain();
      gain.gain.value = 0;
      if (!pan && c.createStereoPanner) { pan = c.createStereoPanner(); pan.connect(c.destination); }
      src.connect(gain).connect(pan || c.destination);
      src.start(0, LOOP[0]);
      gain.gain.setTargetAtTime(VOL, c.currentTime, 0.008);   // praktisch sofort volle Lautstärke
    }
    // Lage des Laserkopfs: 0 = links, 1 = rechts
    function follow(x) { if (pan && src) pan.pan.setTargetAtTime((x * 2 - 1) * 0.6, ctx.currentTime, 0.05); }
    // Gravur fertig: in das Ende der Aufnahme überblenden, an dem die Maschine stoppt
    function finish() {
      if (!src) return;
      const t = ctx.currentTime, tail = ctx.createBufferSource(), g = ctx.createGain();
      tail.buffer = buf;
      g.gain.value = 0;
      tail.connect(g).connect(pan || ctx.destination);
      tail.start(t, TAIL);
      tail.stop(t + buf.duration - TAIL);
      g.gain.setTargetAtTime(VOL, t, 0.04);
      gain.gain.cancelScheduledValues(t);
      gain.gain.setTargetAtTime(0, t, 0.04);
      src.stop(t + 0.3);
      src = tail;
      gain = g;
    }
    // abbrechen (Intro übersprungen oder verlassen): schnell ausblenden
    function stop(fade = 0.12) {
      if (!src || !ctx) { src = gain = null; return; }
      const t = ctx.currentTime;
      gain.gain.cancelScheduledValues(t);
      gain.gain.setTargetAtTime(0, t, Math.max(0.001, fade / 3));
      src.stop(t + fade + 0.05);
      src = gain = null;
    }
    return { load, start, follow, finish, spark, stop };
  })();

  const Intro = (() => {
    const stage = $('#logoStage');
    const screen = $('#intro');
    let run = 0, anims = [], raf = 0, shineTimer = 0, ready = false, built = Promise.resolve(null);
    let blobSrc = '', blobUrl = '';
    const contourCache = new Map();

    const track = a => (anims.push(a), a);

    // Data-URLs (Bilder im Browser-Speicher) einmalig in eine Blob-URL wandeln
    async function displayUrl(src) {
      if (!src.startsWith('data:')) return src;
      if (blobSrc === src) return blobUrl;
      try {
        const b = await (await fetch(src)).blob();
        if (blobUrl) URL.revokeObjectURL(blobUrl);
        blobSrc = src;
        blobUrl = URL.createObjectURL(b);
        return blobUrl;
      } catch { return src; }
    }

    // keepSound: beim regulären Ende den Ausklang des Lasergeräuschs nicht abschneiden
    function stop(keepSound = false) {
      if (!keepSound) CncSound.stop();
      run++;
      cancelAnimationFrame(raf);
      raf = 0;
      anims.forEach(a => { try { a.cancel(); } catch { /* egal */ } });
      anims = [];
      clearInterval(shineTimer);
    }

    async function build() {
      const src = await displayUrl(state.site.logo || DEFAULTS.site.logo);
      const img = await loadImage(src).catch(() => null);
      const ratio = img && img.naturalWidth ? img.naturalWidth / img.naturalHeight : 1.5;
      const split = clamp(+state.intro.splitY || 68, 5, 100);
      screen.style.setProperty('--ratio', ratio);
      stage.style.setProperty('--split', split + '%');
      stage.classList.remove('assembled');
      const s = esc(src);
      stage.innerHTML = `
        <div class="layer glow"><img src="${s}" alt=""></div>
        <div class="layer full"><img src="${s}" alt=""></div>
        <canvas class="cut"></canvas>
        <div class="flash"></div>
        <div class="shine"></div>`;
      const shine = $('.shine', stage);
      if (window.CSS && CSS.supports('mask-mode', 'luminance')) {
        shine.style.maskImage = `url("${cssUrl(src)}")`;
        shine.style.maskMode = 'luminance';
        shine.style.maskSize = '100% 100%';
      } else {
        shine.remove();
      }
      return { src, img, ratio, split };
    }

    // Ramer-Douglas-Peucker: entfernt überflüssige Punkte einer Linie
    function simplify(pts, eps) {
      if (pts.length < 3) return pts;
      const keep = new Uint8Array(pts.length);
      keep[0] = keep[pts.length - 1] = 1;
      const stack = [[0, pts.length - 1]];
      while (stack.length) {
        const [a, b] = stack.pop();
        const [ax, ay] = pts[a], [bx, by] = pts[b];
        const dx = bx - ax, dy = by - ay, len = Math.hypot(dx, dy) || 1;
        let max = 0, idx = -1;
        for (let i = a + 1; i < b; i++) {
          const d = Math.abs(dy * (pts[i][0] - ax) - dx * (pts[i][1] - ay)) / len;
          if (d > max) { max = d; idx = i; }
        }
        if (max > eps) { keep[idx] = 1; stack.push([a, idx], [idx, b]); }
      }
      return pts.filter((_, i) => keep[i]);
    }

    // Erkennt die Umrisse des Logos (Marching Squares) und ordnet sie zu Schneidebahnen.
    // Wirft einen Fehler, wenn der Browser das Bild nicht auslesen darf (z. B. bei file://).
    function traceContours(img, split) {
      const key = img.src + '|' + split;
      if (contourCache.has(key)) return contourCache.get(key);

      const W = 640, H = Math.round(W * img.naturalHeight / img.naturalWidth);
      const c = document.createElement('canvas');
      c.width = W; c.height = H;
      const cx = c.getContext('2d', { willReadFrequently: true });
      cx.filter = 'blur(0.8px)';
      cx.drawImage(img, 0, 0, W, H);
      const px = cx.getImageData(0, 0, W, H).data;

      // Logos mit transparentem Hintergrund über die Deckkraft, sonst über die Helligkeit erkennen
      let transparent = 0;
      for (let i = 3; i < px.length; i += 16) if (px[i] < 200) transparent++;
      const useAlpha = transparent > (px.length / 16) * 0.05;

      const GW = W + 2, GH = H + 2;          // 1 px Rand, damit jede Kontur geschlossen ist
      const on = new Uint8Array(GW * GH);
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          const i = (y * W + x) * 4;
          const solid = useAlpha
            ? px[i + 3] > 128
            : (0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]) * (px[i + 3] / 255) > 70;
          if (solid) on[(y + 1) * GW + x + 1] = 1;
        }
      }

      // Kantenpunkte liegen auf halben Pixeln → doppelte Koordinaten als Schlüssel
      const K = GW * 2 + 2;
      const adj = new Map();
      const link = (a, b) => {
        (adj.get(a) || adj.set(a, []).get(a)).push(b);
        (adj.get(b) || adj.set(b, []).get(b)).push(a);
      };
      for (let y = 0; y < GH - 1; y++) {
        for (let x = 0; x < GW - 1; x++) {
          const code = on[y * GW + x] << 3 | on[y * GW + x + 1] << 2 | on[(y + 1) * GW + x + 1] << 1 | on[(y + 1) * GW + x];
          if (code === 0 || code === 15) continue;
          const T = 2 * y * K + 2 * x + 1, R = (2 * y + 1) * K + 2 * x + 2;
          const B = (2 * y + 2) * K + 2 * x + 1, L = (2 * y + 1) * K + 2 * x;
          switch (code) {
            case 1: case 14: link(L, B); break;
            case 2: case 13: link(B, R); break;
            case 3: case 12: link(L, R); break;
            case 4: case 11: link(T, R); break;
            case 6: case 9: link(T, B); break;
            case 7: case 8: link(L, T); break;
            case 5: link(T, R); link(L, B); break;
            case 10: link(L, T); link(B, R); break;
          }
        }
      }

      // Punkte zu geschlossenen Konturen verbinden
      const seen = new Set();
      const emblem = [], text = [];
      const splitY = H * split / 100;
      for (const start of adj.keys()) {
        if (seen.has(start)) continue;
        const raw = [];
        let prev = -1, cur = start;
        for (;;) {
          seen.add(cur);
          raw.push([(cur % K) / 2 - 1, Math.floor(cur / K) / 2 - 1]);
          const nb = adj.get(cur);
          const next = nb[0] !== prev ? nb[0] : nb[1];
          if (next === undefined || seen.has(next)) break;
          prev = cur;
          cur = next;
        }
        if (raw.length < 40) continue;   // Rauschen ignorieren

        const mid = raw.length >> 1;
        let pts = simplify(raw.slice(0, mid + 1), 0.6).concat(simplify(raw.slice(mid), 0.6).slice(1));
        // Der Laser setzt jeweils am obersten Punkt der Kontur an
        let top = 0;
        pts.forEach((p, i) => { if (p[1] < pts[top][1]) top = i; });
        pts = pts.slice(top).concat(pts.slice(0, top));
        pts.push(pts[0]);

        const cum = [0];
        let minX = Infinity, sumY = 0;
        for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
        pts.forEach(p => { minX = Math.min(minX, p[0]); sumY += p[1]; });
        const len = cum[cum.length - 1];
        if (len < 30) continue;
        const loop = { pts, cum, len, minX };
        (sumY / pts.length < splitY ? emblem : text).push(loop);
      }

      // Erst das Emblem (große Außenkontur zuerst), dann der Schriftzug von links nach rechts
      emblem.sort((a, b) => b.len - a.len);
      text.sort((a, b) => a.minX - b.minX);
      const loops = emblem.slice(0, 90).concat(text.slice(0, 90));
      const result = { W, H, loops, total: loops.reduce((s, l) => s + l.len, 0) };
      contourCache.set(key, result);
      return result;
    }

    // Laserkopf fährt alle Konturen nacheinander ab
    function laser(contours, id, duration) {
      return new Promise(resolve => {
        const cv = $('.cut', stage);
        const rect = stage.getBoundingClientRect();
        const dpr = Math.min(window.devicePixelRatio || 1, 2);
        cv.width = Math.round(rect.width * dpr);
        cv.height = Math.round(rect.height * dpr);
        const ctx = cv.getContext('2d');
        const trace = document.createElement('canvas');   // bleibende, abgekühlte Schnittlinie
        trace.width = cv.width;
        trace.height = cv.height;
        const tctx = trace.getContext('2d');
        const css = getComputedStyle(document.documentElement);
        tctx.lineCap = tctx.lineJoin = 'round';
        tctx.lineWidth = 1.3 * dpr;
        tctx.strokeStyle = css.getPropertyValue('--gold-light').trim() || '#f6dc8c';
        tctx.shadowColor = css.getPropertyValue('--gold').trim() || '#d4a640';
        tctx.shadowBlur = 7 * dpr;

        const k = (rect.width * dpr) / contours.W;    // Abtastpixel → Canvaspixel
        const loops = contours.loops;
        let li = 0, pi = 0, done = 0;
        let pos = loops[0].pts[0];
        let trail = [pos];
        const t0 = performance.now();

        const frame = now => {
          if (id !== run) { resolve(false); return; }
          // (einzige Änderung am Webseiten-Code: nach Ablauf der Zeit 1 px Zugabe, sonst bleibt der Laser durch
          //  Rundung manchmal kurz vor dem Ende der letzten Kontur stehen)
          const target = Math.min(1, (now - t0) / duration) * contours.total + (now - t0 >= duration ? 1 : 0);

          tctx.beginPath();
          tctx.moveTo(pos[0] * k, pos[1] * k);
          while (li < loops.length) {
            const { pts: P, cum: C, len } = loops[li];
            const local = target - done;
            while (pi < P.length - 1 && C[pi + 1] <= local) {
              pi++;
              pos = P[pi];
              tctx.lineTo(pos[0] * k, pos[1] * k);
              trail.push(pos);
            }
            if (pi >= P.length - 1) {          // Kontur geschlossen → zur nächsten springen
              done += len;
              li++;
              pi = 0;
              if (li < loops.length) {
                pos = loops[li].pts[0];
                tctx.moveTo(pos[0] * k, pos[1] * k);
                trail = [pos];
              }
              continue;
            }
            const f = (local - C[pi]) / (C[pi + 1] - C[pi] || 1);
            pos = [P[pi][0] + (P[pi + 1][0] - P[pi][0]) * f, P[pi][1] + (P[pi + 1][1] - P[pi][1]) * f];
            tctx.lineTo(pos[0] * k, pos[1] * k);
            break;
          }
          tctx.stroke();
          if (trail.length > 60) trail = trail.slice(-60);

          ctx.clearRect(0, 0, cv.width, cv.height);
          ctx.drawImage(trace, 0, 0);

          if (li < loops.length) {
            const hx = pos[0] * k, hy = pos[1] * k;
            const hot = trail.slice(-22);
            hot.push(pos);
            ctx.save();
            ctx.globalCompositeOperation = 'lighter';
            ctx.lineCap = ctx.lineJoin = 'round';
            // glühende, frisch geschnittene Kante
            ctx.beginPath();
            hot.forEach((p, i) => (i ? ctx.lineTo(p[0] * k, p[1] * k) : ctx.moveTo(p[0] * k, p[1] * k)));
            ctx.strokeStyle = 'rgba(255,140,40,.85)';
            ctx.lineWidth = 3 * dpr;
            ctx.shadowColor = '#ff7a1a';
            ctx.shadowBlur = 16 * dpr;
            ctx.stroke();
            ctx.strokeStyle = 'rgba(255,248,225,.95)';
            ctx.lineWidth = 1.2 * dpr;
            ctx.shadowBlur = 0;
            ctx.stroke();
            // Laserpunkt mit Flackern
            const r = rand(16, 26) * dpr;
            const g = ctx.createRadialGradient(hx, hy, 0, hx, hy, r);
            g.addColorStop(0, 'rgba(255,255,255,1)');
            g.addColorStop(0.15, 'rgba(255,242,205,.95)');
            g.addColorStop(0.4, 'rgba(255,150,50,.45)');
            g.addColorStop(1, 'rgba(255,90,20,0)');
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(hx, hy, r, 0, 6.283);
            ctx.fill();
            ctx.fillStyle = 'rgba(255,220,160,.35)';
            ctx.fillRect(hx - 42 * dpr, hy - 0.7 * dpr, 84 * dpr, 1.4 * dpr);
            ctx.restore();
            Embers.sparks(rect.left + hx / dpr, rect.top + hy / dpr, 3);
            CncSound.follow((rect.left + hx / dpr) / innerWidth);
            raf = requestAnimationFrame(frame);
          } else {
            raf = 0;
            resolve(true);
          }
        };
        raf = requestAnimationFrame(frame);
      });
    }

    function impact(duration) {
      track($('.flash', stage).animate(
        [{ opacity: 0, transform: 'scale(.3)' }, { opacity: 1, offset: 0.15 }, { opacity: 0, transform: 'scale(2.2)' }],
        { duration: 1100, easing: 'ease-out' }));
      track($('.glow', stage).animate(
        [{ opacity: 0 }, { opacity: 1, offset: 0.15 }, { opacity: 0.22 }],
        { duration, easing: 'ease-out' }));
    }

    function sweep() {
      const shine = $('.shine', stage);
      if (!shine || reduceMotion) return;
      shine.animate(
        [{ opacity: 0, backgroundPosition: '100% 0' }, { opacity: 1, offset: 0.2 }, { opacity: 1, offset: 0.8 }, { opacity: 0, backgroundPosition: '0% 0' }],
        { duration: 1700, easing: 'ease-in-out' });
    }

    function finish() {
      stop(true);
      const full = $('.full', stage);
      if (full) { full.style.opacity = ''; full.style.filter = ''; }
      stage.classList.add('assembled');
      screen.classList.add('ready');
      ready = true;
      sweep();
      shineTimer = setInterval(sweep, 7000);
    }

    async function play(force = false) {
      stop();
      const id = run;
      ready = false;
      screen.classList.remove('ready');
      // Geräusche gleich mitladen, während das Logo vorbereitet wird
      const soundReady = state.intro.sound !== false ? CncSound.load() : null;
      built = build();
      const info = await built;
      if (id !== run) return;
      if (reduceMotion || (!force && (!state.intro.enabled || editing))) { finish(); return; }

      const speed = clamp(+state.intro.speed || 1, 0.3, 3);
      const T = ms => ms / speed;
      let contours = null;
      try { if (info.img) contours = traceContours(info.img, info.split); } catch { contours = null; }

      // Das Logo liegt zunächst nur als dunkle, unbearbeitete Metallplatte da
      const full = $('.full', stage);
      full.style.opacity = 0.08;
      full.style.filter = 'grayscale(1) brightness(.7)';

      await sleep(T(500));
      if (id !== run) return;

      // 1) Laser schneidet die Konturen aus – das Lasergeräusch läuft genau so lange. Der Laser
      //    startet erst, wenn der Ton bereit ist (höchstens 1,5 s warten), damit beide zugleich beginnen.
      if (contours && contours.loops.length) {
        if (soundReady) await Promise.race([soundReady, sleep(1500)]);
        if (id !== run) return;
        CncSound.start();
        const ok = await laser(contours, id, T(clamp(contours.total * 0.45, 3000, 6500)));
        if (!ok || id !== run) return;
        CncSound.finish();   // die Maschine stoppt …
        CncSound.spark();    // … und zum Schluss knallt ein Funke
      }

      // 2) Das ausgeschnittene Logo glüht auf und kühlt zu Gold ab
      impact(T(1900));
      track(full.animate([
        { opacity: 0.08, filter: 'grayscale(1) brightness(.7)' },
        { opacity: 1, filter: 'grayscale(0) brightness(2.6)', offset: 0.3 },
        { opacity: 1, filter: 'grayscale(0) brightness(1)' }
      ], { duration: T(1600), easing: 'ease-out', fill: 'forwards' }));
      track($('.cut', stage).animate([{ opacity: 1 }, { opacity: 0 }], { duration: T(1300), easing: 'ease-in', fill: 'forwards' }));
      await sleep(T(1600));
      if (id !== run) return;

      // 3) Goldener Glanz + Start-Button
      finish();
    }

    async function skip() {
      if (ready) return;
      CncSound.stop();
      run++;
      await built;
      finish();
    }

    return { play, skip, stop, get ready() { return ready; } };
  })();

  /* ===== Ende der Übernahme ===== */

  // Steuerung durch die Mac-App: Intro abspielen (mit oder ohne Lasergeräusch) und Fertig melden
  const melde = m => { try { window.webkit.messageHandlers.hg.postMessage(m); } catch { /* Vorschau im Browser */ } };
  new MutationObserver(() => { if ($('#intro').classList.contains('ready')) melde('fertig'); })
    .observe($('#intro'), { attributes: true, attributeFilter: ['class'] });
  window.introStarten = (ton) => { state.intro.sound = !!ton; Intro.play(true); };
  window.introFertig = () => Intro.skip();
  melde('geladen');
})();
