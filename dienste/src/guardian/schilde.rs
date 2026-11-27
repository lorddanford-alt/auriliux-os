//! Regelmäßige Prüfung aller Schilde (alle 15 Minuten und auf Knopfdruck): System, Netz, Updates, USB …
use crate::scanner::{self, Stand};
use crate::usb;
use crate::wache;
use crate::Ereignis;
use gemeinsam::datei;
use gemeinsam::json::{self, J};
use std::fs;
use std::path::Path;

#[derive(Clone)]
pub struct Schild {
    pub id: &'static str,
    pub name: &'static str,
    pub zustand: &'static str, // ok | warn | aus | folgt
    pub stufe: &'static str,   // für die Bewertung: hoch | mittel | info | ""
    pub text: String,
    pub details: Vec<String>,
}

impl Schild {
    fn neu(id: &'static str, name: &'static str) -> Schild {
        Schild { id, name, zustand: "ok", stufe: "", text: String::new(), details: vec![] }
    }
    fn warn(mut self, stufe: &'static str, text: impl Into<String>) -> Schild {
        self.zustand = "warn";
        self.stufe = stufe;
        self.text = text.into();
        self
    }
    fn ok(mut self, text: impl Into<String>) -> Schild {
        self.text = text.into();
        self
    }
    pub fn json(&self) -> J {
        J::o(vec![
            ("id", J::t(self.id)),
            ("name", J::t(self.name)),
            ("zustand", J::t(self.zustand)),
            ("stufe", J::t(self.stufe)),
            ("text", J::t(&self.text)),
            ("details", J::texte(&self.details)),
        ])
    }
}

/// Was der Hauptteil gerade weiß (wird in den Prüf-Faden kopiert)
#[derive(Clone, Default)]
pub struct Lage {
    pub ausfuehrung: Option<String>, // None = läuft, Some(Fehler)
    pub schreibwache: Option<String>,
    pub gefrierfach: bool,
    pub freigaben: usize,
    pub scan: Stand,
    pub autostart_eintraege: usize,
    pub autostart_offen: usize,
    pub quarantaene: usize,
    pub einrichten: bool,
}

fn schreibgeschuetzt(ort: &str) -> Option<bool> {
    let t = fs::read_to_string("/proc/self/mountinfo").ok()?;
    let mut bester: Option<(usize, bool)> = None;
    for z in t.lines() {
        let f: Vec<&str> = z.split(' ').collect();
        if f.len() < 6 {
            continue;
        }
        let punkt = wache::entschluesseln(f[4]);
        let passt = ort == punkt || punkt == "/" || ort.starts_with(&format!("{}/", punkt));
        if passt && bester.map(|(l, _)| punkt.len() >= l).unwrap_or(true) {
            bester = Some((punkt.len(), f[5].split(',').any(|o| o == "ro")));
        }
    }
    bester.map(|(_, ro)| ro)
}

fn verschluesselt() -> bool {
    if let Ok(d) = fs::read_dir("/sys/block") {
        for e in d.flatten() {
            let n = e.file_name().to_string_lossy().into_owned();
            if n.starts_with("dm-") && datei::lies(format!("/sys/block/{}/dm/uuid", n)).starts_with("CRYPT-") {
                return true;
            }
        }
    }
    false
}

fn tage(ms: i64) -> i64 {
    ((datei::jetzt_ms() - ms) / 86_400_000).max(0)
}

/// offene Türen: Programme, die auf Verbindungen von außen warten (nicht nur auf diesem Rechner)
fn offene_ports() -> Vec<u16> {
    let mut aus = Vec::new();
    for (datei, loopback) in [("/proc/net/tcp", "0100007F"), ("/proc/net/tcp6", "00000000000000000000000001000000")] {
        for z in fs::read_to_string(datei).unwrap_or_default().lines().skip(1) {
            let f: Vec<&str> = z.split_whitespace().collect();
            if f.len() < 4 || f[3] != "0A" {
                continue;
            }
            let Some((adr, port)) = f[1].split_once(':') else { continue };
            if adr == loopback || adr.starts_with("0000000000000000FFFF00000100007F") {
                continue;
            }
            if let Ok(p) = u16::from_str_radix(port, 16) {
                if !aus.contains(&p) {
                    aus.push(p);
                }
            }
        }
    }
    aus.sort();
    aus
}

/// bootc: (Abbild, Version, Update bereit?, Rückweg vorhanden?)
fn abbild() -> Option<(String, String, Option<String>, bool)> {
    let roh = datei::befehl("bootc", &["status", "--format=json"], 30)
        .filter(|(c, _)| *c == 0)
        .or_else(|| datei::befehl("bootc", &["status", "--json"], 30).filter(|(c, _)| *c == 0))?
        .1;
    let j = json::lesen(&roh)?;
    let gebootet = j.pfad(&["status", "booted"])?;
    if gebootet.ist_null() {
        return None;
    }
    let bild = gebootet.pfad(&["image", "image", "image"]).and_then(|v| v.als_text()).unwrap_or("").to_string();
    let version = gebootet.pfad(&["image", "version"]).and_then(|v| v.als_text())
        .or_else(|| gebootet.pfad(&["image", "timestamp"]).and_then(|v| v.als_text()))
        .unwrap_or("").to_string();
    let bereit = j.pfad(&["status", "staged"]).filter(|v| !v.ist_null()).map(|s| {
        s.pfad(&["image", "version"]).and_then(|v| v.als_text()).unwrap_or("neu").to_string()
    });
    let rueckweg = j.pfad(&["status", "rollback"]).map(|v| !v.ist_null()).unwrap_or(false);
    Some((bild, version, bereit, rueckweg))
}

pub fn pruefen(lage: &Lage) -> (Vec<Schild>, Vec<Ereignis>, Vec<usb::Geraet>, Option<String>) {
    let mut s = Vec::new();
    let mut ereignisse = Vec::new();
    let mut usb_meldung = None;

    // 1. System-Schild
    let mut sys_s = Schild::neu("system", "System-Schild");
    let ro = schreibgeschuetzt("/usr").unwrap_or(false);
    let selinux = datei::lies("/sys/fs/selinux/enforce").trim().to_string();
    let mut d = vec![];
    d.push(if ro { "Systemdateien sind schreibgeschützt".to_string() } else { "Systemdateien sind beschreibbar".to_string() });
    d.push(match selinux.as_str() {
        "1" => "SELinux wacht (erzwingend)".into(),
        "0" => "SELinux beobachtet nur".into(),
        _ => "SELinux ist aus".into(),
    });
    let crypt = verschluesselt();
    d.push(if crypt { "Festplatte verschlüsselt (LUKS2)".into() } else { "Festplatte nicht verschlüsselt".into() });
    let bild = abbild();
    if let Some((name, version, _, rueckweg)) = &bild {
        d.push(format!("Abbild {}{}", name.rsplit('/').next().unwrap_or(name), if version.is_empty() { String::new() } else { format!(" · {}", version) }));
        d.push(if *rueckweg { "Rückweg zum vorherigen Stand vorhanden".into() } else { "Noch kein vorheriger Stand zum Zurückkehren".into() });
    }
    sys_s.details = d;
    sys_s = if !ro {
        sys_s.warn("hoch", "Systemdateien sind nicht schreibgeschützt")
    } else if selinux != "1" {
        sys_s.warn("mittel", "SELinux schützt nicht vollständig")
    } else if !crypt {
        sys_s.warn("mittel", "Systemdateien geschützt – aber die Festplatte ist nicht verschlüsselt")
    } else {
        sys_s.ok("Systemdateien unveränderlich, SELinux wacht, Festplatte verschlüsselt")
    };
    s.push(sys_s);

    // 2. Ausführungs-Schild
    let mut a = Schild::neu("ausfuehrung", "Ausführungs-Schild");
    a.details = vec![
        "Gilt für Benutzerordner, Downloads, /tmp und USB-Sticks".into(),
        format!("{} Programm{} freigegeben", lage.freigaben, if lage.freigaben == 1 { "" } else { "e" }),
    ];
    a = match &lage.ausfuehrung {
        None => a.ok("Programme aus Benutzerordnern starten nur nach deiner Freigabe"),
        Some(f) => a.warn("hoch", format!("Läuft nicht: {}", f)),
    };
    s.push(a);

    // 3. Echtzeit-Scanner
    let mut e = Schild::neu("scanner", "Echtzeit-Scanner");
    let st = &lage.scan;
    e.details = vec![
        format!("{} Dateien geprüft, {} Funde", st.geprueft, st.funde),
        "Eigene Regeln · YARA · ClamAV-Virenliste".into(),
        match st.clam.as_str() {
            "bereit" => "Virenliste geladen".into(),
            "startet" => "Virenliste wird geladen …".into(),
            "aus" => "Virenliste ruht (startet bei Bedarf, spart 1 GB Arbeitsspeicher)".into(),
            "keine-signaturen" => "Virenliste noch nicht heruntergeladen".into(),
            "fehlt" => "ClamAV fehlt".into(),
            _ => "ClamAV meldet einen Fehler".into(),
        },
    ];
    let sig = scanner::signaturen_alter();
    if sig > 0 {
        e.details.push(format!("Virenliste aktualisiert: {}", tage_text(sig)));
    }
    if st.uebersprungen > 0 {
        e.details.push(format!("{} Dateien übersprungen (zu viele auf einmal)", st.uebersprungen));
    }
    e = if let Some(f) = &lage.schreibwache {
        e.warn("hoch", format!("Läuft nicht: {}", f))
    } else if sig == 0 {
        e.warn("mittel", "Prüft mit eigenen Regeln – die Virenliste wird beim ersten Internetkontakt geladen")
    } else if tage(sig) > 7 {
        e.warn("mittel", format!("Virenliste ist {} Tage alt", tage(sig)))
    } else {
        e.ok("Jede neue Datei wird sofort geprüft")
    };
    s.push(e);

    // 4. Netz-Schild
    let mut n = Schild::neu("netz", "Netz-Schild");
    let fw_laeuft = matches!(datei::befehl("firewall-cmd", &["--state"], 15), Some((0, _)));
    let zone = datei::befehl("firewall-cmd", &["--get-default-zone"], 15).map(|(_, t)| t.trim().to_string()).unwrap_or_default();
    let ports = offene_ports();
    n.details = vec![
        if fw_laeuft { format!("Firewall aktiv (Zone „{}“)", zone) } else { "Firewall läuft nicht".into() },
        if ports.is_empty() { "Kein Programm wartet auf Verbindungen von außen".into() } else { format!("Offene Türen: Port {}", ports.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(", ")) },
        "DNS-Filter gegen Schadseiten folgt".into(),
    ];
    n = if !fw_laeuft {
        n.warn("hoch", "Die Firewall ist aus – von außen wäre der Rechner erreichbar")
    } else if zone != "drop" && zone != "block" {
        n.warn("mittel", format!("Firewall lässt in Zone „{}“ einiges herein", zone))
    } else if !ports.is_empty() {
        n.warn("info", "Firewall dicht – aber ein Programm wartet auf Verbindungen")
    } else {
        n.ok("Von außen kommt nichts herein")
    };
    s.push(n);

    // 5. USB-Schild
    let mut u = Schild::neu("usb", "USB-Schild");
    let mut gesperrt = vec![];
    if !usb::vorhanden() {
        u = u.warn("mittel", "USBGuard fehlt");
    } else {
        if lage.einrichten && !usb::eingerichtet() {
            match usb::einrichten() {
                Ok(t) => usb_meldung = Some(t),
                Err(f) => u.details.push(format!("Einrichten fehlgeschlagen: {}", f)),
            }
        }
        let aktiv = usb::aktiv();
        if aktiv {
            gesperrt = usb::gesperrte();
        }
        u.details.push(if aktiv { "USBGuard aktiv – neue Geräte sind gesperrt, bis du sie zulässt".into() } else { "USBGuard ist aus".into() });
        if !gesperrt.is_empty() {
            u.details.push(format!("{} Gerät(e) gerade gesperrt", gesperrt.len()));
        }
        u = if aktiv { u.ok("Neue USB-Geräte brauchen deine Zustimmung") } else if !usb::eingerichtet() { u.warn("mittel", "Wird beim ersten Start eingerichtet") } else { u.warn("hoch", "USBGuard läuft nicht") };
    }
    s.push(u);

    // 6. Erpresser-Schild
    let mut r = Schild::neu("erpresser", "Erpresser-Schild");
    r.details = vec![
        format!("Friert Programme ein, die in 20 s mehr als {} Dateien unlesbar überschreiben", wache::ERPRESSER_GRENZE),
        "Stündliche Schnappschüsse folgen mit dem Tresor".into(),
    ];
    r = if lage.schreibwache.is_some() {
        r.warn("hoch", "Läuft nicht (Schreib-Wache fehlt)")
    } else if !lage.gefrierfach {
        r.warn("info", "Wacht – kann Programme aber nur anhalten, nicht sicher einfrieren")
    } else {
        r.ok("Wacht über plötzliches Massen-Verschlüsseln")
    };
    s.push(r);

    // 7. Autostart-Wächter
    let mut w = Schild::neu("autostart", "Autostart-Wächter");
    w.details = vec![format!("{} Autostart-Einträge bekannt", lage.autostart_eintraege)];
    w = if lage.autostart_offen > 0 {
        w.warn("", format!("{} neue Einträge warten auf deine Entscheidung", lage.autostart_offen))
    } else {
        w.ok("Meldet jeden neuen Eintrag, der sich beim Start mitladen will")
    };
    s.push(w);

    // Updates
    let mut up = Schild::neu("updates", "Updates");
    let auto = matches!(datei::befehl("systemctl", &["is-enabled", "auriliux-update.timer"], 10), Some((0, _)));
    up.details.push(if auto { "Sucht täglich nach dem neuen Systemabbild (am Netzteil)".into() } else { "Automatische Suche ist aus".into() });
    up.details.push("Startet nie von selbst neu – das Update wird beim nächsten Neustart aktiv".into());
    up = match &bild {
        Some((_, _, Some(v), _)) => {
            ereignisse.push(
                Ereignis::neu("update", "info", "Update bereit", format!("Das neue Systemabbild ({}) ist geladen und wird beim nächsten Neustart aktiv.", v))
                    .knopf("ok", "Verstanden")
                    .schluessel(format!("update:{}", v)),
            );
            up.warn("info", "Update geladen – wird beim nächsten Neustart aktiv")
        }
        Some(_) if auto => up.ok("System ist aktuell"),
        Some(_) => up.warn("mittel", "Automatische Updates sind aus"),
        None => up.warn("info", "Update-Stand nicht lesbar"),
    };
    s.push(up);

    (s, ereignisse, gesperrt, usb_meldung)
}

fn tage_text(ms: i64) -> String {
    let t = tage(ms);
    match t {
        0 => "heute".into(),
        1 => "gestern".into(),
        n => format!("vor {} Tagen", n),
    }
}

/// gibt es diese Datei? (für Tests im Container ohne alles)
#[allow(dead_code)]
pub fn da(p: &str) -> bool {
    Path::new(p).exists()
}
