#!/usr/bin/env python3
"""Attrappe des James-Servers (api.php) für den Cloud-Bau: antwortet wie der echte Server, aber mit festen
Texten und ohne Claude/ElevenLabs. So kann der Bau das James-Fenster und den James-Dienst wirklich
durchspielen: Einrichtung, Herzschlag, Chat Stück für Stück, Aufträge, Abschreiben und Vorlesen.
Nur Python-Standardbibliothek. Protokoll (ohne Schlüssel) in --log.

    python3 werkzeuge/james-attrappe.py --port 8766 --token <32+ Zeichen> --log vorschau/james-attrappe.log
"""
import argparse, hmac, json, sys, threading, time
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=8766)
ap.add_argument("--token", required=True)
ap.add_argument("--log", default="-")
A = ap.parse_args()
sperre = threading.Lock()


def log(s):
    z = time.strftime("%H:%M:%S ") + s
    with sperre:
        if A.log == "-":
            print(z, flush=True)
        else:
            with open(A.log, "a", encoding="utf-8") as f:
                f.write(z + "\n")


def zeit(min_vorher):
    return (datetime.now() - timedelta(minutes=min_vorher)).isoformat(timespec="seconds")


nachrichten = [
    {"id": 101, "rolle": "user", "text": "Guten Morgen James, was steht heute an?", "quelle": "stimme", "erstellt": zeit(95)},
    {"id": 102, "rolle": "assistant", "text": "Guten Morgen! Heute hast du drei Dinge offen:\n\n- **Auriliux OS** auf dem MacBook testen\n- den Tresor-Code festlegen\n- um 18 Uhr Sport\n\nSoll ich dich um halb sechs erinnern?", "quelle": "stimme", "erstellt": zeit(94)},
    {"id": 103, "rolle": "user", "text": "Ja, bitte.", "quelle": "stimme", "erstellt": zeit(93)},
    {"id": 104, "rolle": "assistant", "text": "Mach ich – ich melde mich um 17:30 Uhr.", "quelle": "stimme", "erstellt": zeit(93)},
]
auftraege = [
    {"id": 7, "titel": "Wabenfinder: nach Größe sortieren", "beschreibung": "Im Wabenfinder eine Sortierung nach Dateigröße ergänzen (Rechtsklick → Sortieren). Fertig, wenn große Dateien zuerst stehen und der Bau grün ist.",
     "ordner": "~/Projekte/Auriliux", "status": "vorgeschlagen", "ergebnis": "", "von": "ki", "erstellt": zeit(30), "aktualisiert": zeit(30)},
    {"id": 6, "titel": "Probe-Auftrag aus dem Bau", "beschreibung": "Nur lesen und kurz zusammenfassen, nichts verändern.",
     "ordner": "~/Projekte/Probe", "status": "freigegeben", "ergebnis": "", "von": "mensch", "erstellt": zeit(20), "aktualisiert": zeit(20)},
    {"id": 5, "titel": "Notizen aufräumen", "beschreibung": "Doppelte Notizen im Ordner Dokumente finden.", "ordner": "~/Dokumente",
     "status": "erledigt", "ergebnis": "3 doppelte Notizen gefunden und aufgelistet (nichts gelöscht).\n\n(Dauer: 2 min, Exit-Code 0)", "von": "ki",
     "erstellt": zeit(300), "aktualisiert": zeit(290)},
]
naechste_id = [200]
herzschlaege = [0]
abgeholt = [False]

# Stille als MP3 (MPEG-1 Layer III, 128 kbit/s, 44,1 kHz): 38 leere Rahmen ≈ 1 s
STILLE = (b"\xff\xfb\x90\x64" + b"\x00" * 413) * 38

ANTWORT = ("Morgen hast du einen ruhigen Tag. Um 10 Uhr ist der Termin beim Zahnarzt, danach nichts Festes. "
           "Das Wetter wird sonnig bei 14 Grad – gut für einen Spaziergang. Soll ich dir den Termin eine Stunde vorher ansagen?")


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def antwort(self, o, status=200):
        d = json.dumps(o, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(d)))
        self.end_headers()
        self.wfile.write(d)

    def angemeldet(self):
        t = self.headers.get("X-KI-Token", "")
        b = self.headers.get("Authorization", "")
        if b.startswith("Bearer "):
            t = t or b[7:]
        return hmac.compare_digest(t, A.token)

    def do_GET(self):
        self.do_POST()

    def do_POST(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        a = (q.get("a") or [""])[0]
        n = int(self.headers.get("Content-Length") or 0)
        roh = self.rfile.read(n) if n else b""
        if not u.path.endswith("api.php"):
            return self.antwort({"ok": False, "fehler": "Nicht gefunden"}, 404)
        if not self.angemeldet():
            log(f"{a}: abgelehnt (falscher Schlüssel)")
            return self.antwort({"ok": False, "fehler": "Nicht angemeldet"}, 401)
        e = {}
        if roh and self.headers.get("Content-Type", "").startswith("application/json"):
            try:
                e = json.loads(roh)
            except ValueError:
                e = {}
        try:
            getattr(self, "a_" + a, self.a_unbekannt)(e, q, roh)
        except BrokenPipeError:
            log(f"{a}: Verbindung vom Gerät beendet")

    def a_unbekannt(self, e, q, roh):
        self.antwort({"ok": False, "fehler": "Unbekannte Aktion"}, 404)

    def a_zustand(self, e, q, roh):
        log("zustand")
        self.antwort({"ok": True, "name": "James", "version": "1.5.4 (Attrappe)", "app": True,
                      "auftraege_vorgeschlagen": sum(1 for x in auftraege if x["status"] == "vorgeschlagen"),
                      "einstellungen": {"name": "James", "mikro_an": True, "weckwort": "James"}})

    def a_verlauf(self, e, q, roh):
        vor = int((q.get("vor") or ["0"])[0] or 0)
        l = [m for m in nachrichten if not vor or m["id"] < vor][-60:]
        log(f"verlauf ({len(l)} Nachrichten{', vor ' + str(vor) if vor else ''})")
        self.antwort({"ok": True, "nachrichten": l})

    def a_herzschlag(self, e, q, roh):
        herzschlaege[0] += 1
        log(f"herzschlag #{herzschlaege[0]}: anwesend={e.get('anwesend')} schalter={e.get('schalter')} system={e.get('system')!r} app={e.get('app')!r}")
        aktionen = [{"art": "hinweis", "ziel": "Willkommen auf Auriliux OS – ich bin jetzt auch hier."}] if herzschlaege[0] == 1 else []
        self.antwort({"ok": True, "darf_handeln": bool(e.get("schalter")) and bool(e.get("anwesend")), "impuls_minuten": 0,
                      "auftrag_wartet": any(x["status"] == "freigegeben" for x in auftraege), "abbrechen": [], "name": "James",
                      "aktionen": aktionen,
                      "stimme": {"mikro_an": True, "weckwort": "James", "gespraech_sekunden": 12, "pause_sekunden": 1.5, "vorlesen": True}})

    def a_impuls(self, e, q, roh):
        self.antwort({"ok": True, "nachricht": None})

    def a_senden_live(self, e, q, roh):
        text = str(e.get("text", "")).strip()
        log(f"senden_live ({e.get('modus')}, {len(text)} Zeichen)")
        if not text:
            return self.antwort({"ok": False, "fehler": "Leere Nachricht"}, 400)
        nid = naechste_id[0]; naechste_id[0] += 2
        nachrichten.append({"id": nid, "rolle": "user", "text": text, "quelle": "stimme" if e.get("modus") == "stimme" else "chat", "erstellt": zeit(0)})
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def teil(o, fuell=0):
            d = json.dumps(o, ensure_ascii=False).encode() + b"\n" + (b" " * fuell + b"\n" if fuell else b"")
            self.wfile.write(b"%x\r\n" % len(d) + d + b"\r\n")
            self.wfile.flush()

        teil({"t": "start"})
        time.sleep(1.2)
        woerter = ANTWORT.split(" ")
        satz = ""
        for i, w in enumerate(woerter):
            d = w + ("" if i == len(woerter) - 1 else " ")
            teil({"t": "text", "d": d})
            satz += d
            if w.endswith((".", "?", "!")):
                teil({"t": "satz", "text": satz.strip()}, 4096)
                satz = ""
            time.sleep(0.12)
        if satz.strip():
            teil({"t": "satz", "text": satz.strip()}, 4096)
        nachrichten.append({"id": nid + 1, "rolle": "assistant", "text": ANTWORT, "quelle": "stimme" if e.get("modus") == "stimme" else "chat", "erstellt": zeit(0)})
        teil({"t": "fertig", "id": nid + 1, "text": ANTWORT, "aktionen": []})
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()
        log("senden_live fertig")

    def a_sprechen(self, e, q, roh):
        log(f"sprechen ({len(str(e.get('text', '')))} Zeichen{', id ' + str(e['id']) if e.get('id') else ''})")
        self.send_response(200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(len(STILLE)))
        self.end_headers()
        self.wfile.write(STILLE)

    def a_zuhoeren(self, e, q, roh):
        ok = b"RIFF" in roh[:400] and b"WAVE" in roh[:400]
        log(f"zuhoeren: {len(roh)} Bytes, WAV={'ja' if ok else 'nein'}")
        self.antwort({"ok": True, "text": "James, was steht morgen bei mir an?" if ok else ""})

    def a_auftraege(self, e, q, roh):
        log("auftraege")
        self.antwort({"ok": True, "auftraege": auftraege})

    def a_auftrag_abholen(self, e, q, roh):
        for x in auftraege:
            if x["status"] == "freigegeben":
                x["status"] = "laeuft"
                log(f"auftrag_abholen → #{x['id']}")
                return self.antwort({"ok": True, "auftrag": x})
        self.antwort({"ok": True, "auftrag": None})

    def a_auftrag_melden(self, e, q, roh):
        for x in auftraege:
            if x["id"] == int(e.get("id", 0)):
                x["status"] = e.get("status", "fehler")
                x["ergebnis"] = str(e.get("ergebnis", ""))[:30000]
        erste = str(e.get("ergebnis", "")).strip().splitlines()[:3]
        log(f"auftrag_melden #{e.get('id')}: {e.get('status')} – {' / '.join(erste)}")
        self.antwort({"ok": True})

    def a_auftrag_setzen(self, e, q, roh):
        for x in auftraege:
            if x["id"] == int(e.get("id", 0)):
                x["status"] = e.get("status", x["status"])
        log(f"auftrag_setzen #{e.get('id')} → {e.get('status')}")
        self.antwort({"ok": True})

    def a_auftrag_neu(self, e, q, roh):
        auftraege.insert(0, {"id": max(x["id"] for x in auftraege) + 1, "titel": e.get("titel", ""), "beschreibung": e.get("beschreibung", ""),
                             "ordner": e.get("ordner", ""), "status": "freigegeben", "ergebnis": "", "von": "mensch", "erstellt": zeit(0), "aktualisiert": zeit(0)})
        log("auftrag_neu")
        self.antwort({"ok": True})

    def a_auftrag_loeschen(self, e, q, roh):
        auftraege[:] = [x for x in auftraege if x["id"] != int(e.get("id", 0)) or x["status"] == "laeuft"]
        self.antwort({"ok": True})


log(f"Attrappe läuft auf 127.0.0.1:{A.port}")
ThreadingHTTPServer(("127.0.0.1", A.port), H).serve_forever()
