//! Herzschlag – Leistungs-Wächter von Auriliux OS (läuft als root, gestartet von systemd).
//!  1. Vorrang: das vordere Programm bekommt den größten Anteil am Prozessor (cgroups)
//!  2. Fokus-Modus: im Vollbild werden ruhende Hintergrundprogramme eingefroren, aktive stark gedrosselt
//!  3. Wärme-Schutz: Lüfter läuft früher (aber sanft) an, bei Dauerhitze wird der Turbo sanft gedeckelt
//!  4. Energieprofile: am Netz „Leistung“, im Akku „Ausgewogen“, unter 20 % „Sparen“
//!  5. Status für die Goldleiste: /run/auriliux/herzschlag/status.json (Temperatur, Last, Verursacher)
//! Programme, die über die Auriliux-Oberfläche starten, liegen je in einem eigenen Bereich
//! „app-auriliux-<kennung>-<nr>.scope“. Welches Programm vorne ist, schreibt die Goldleiste nach
//! /run/user/<uid>/auriliux/vorne (Zeile 1: Kennung, Zeile 2: 1 = Vollbild).
use gemeinsam::datei;
use gemeinsam::json::J;
use gemeinsam::sys;
use std::collections::{HashMap, VecDeque};
use std::fs;
use std::io::Read;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

const LAUFZEIT: &str = "/run/auriliux/herzschlag";
const O_NOFOLLOW: i32 = 0o400000;

fn lies(p: impl AsRef<Path>) -> String {
    datei::lies(p)
}
fn schreib(p: impl AsRef<Path>, wert: &str) -> bool {
    fs::write(p, wert).is_ok()
}

// ═════════ Messen ═════════

struct Cpu {
    vorher: Option<(u64, u64)>,
}
impl Cpu {
    fn last(&mut self) -> f64 {
        let t = lies("/proc/stat");
        let z: Vec<u64> = t.lines().next().unwrap_or("").split_whitespace().skip(1).filter_map(|x| x.parse().ok()).collect();
        if z.len() < 5 {
            return 0.0;
        }
        let leer = z[3] + z[4];
        let gesamt: u64 = z.iter().take(8).sum();
        let r = match self.vorher {
            Some((g, l)) if gesamt > g => 1.0 - (leer.saturating_sub(l)) as f64 / (gesamt - g) as f64,
            _ => 0.0,
        };
        self.vorher = Some((gesamt, leer));
        r.clamp(0.0, 1.0)
    }
}

fn hwmon(name: &str) -> Option<PathBuf> {
    for e in fs::read_dir("/sys/class/hwmon").ok()?.flatten() {
        if lies(e.path().join("name")).trim() == name {
            return Some(e.path());
        }
    }
    None
}

fn temperatur(coretemp: &Option<PathBuf>) -> f64 {
    if let Some(p) = coretemp {
        if let Some(t) = datei::lies_zahl(p.join("temp1_input")) {
            return t / 1000.0;
        }
    }
    let mut max = 0.0f64;
    if let Ok(d) = fs::read_dir("/sys/class/thermal") {
        for e in d.flatten() {
            if let Some(t) = datei::lies_zahl(e.path().join("temp")) {
                max = max.max(t / 1000.0);
            }
        }
    }
    max
}

fn speicher() -> (u64, u64, u64) {
    let t = lies("/proc/meminfo");
    let w = |n: &str| -> u64 {
        t.lines().find(|z| z.starts_with(n)).and_then(|z| z.split_whitespace().nth(1)).and_then(|x| x.parse().ok()).unwrap_or(0) * 1024
    };
    let swap = w("SwapTotal:").saturating_sub(w("SwapFree:"));
    (w("MemTotal:"), w("MemAvailable:"), swap)
}

fn druck(art: &str) -> f64 {
    datei::feld_nach(&lies(format!("/proc/pressure/{}", art)), "avg10=").and_then(|x| x.parse().ok()).unwrap_or(0.0)
}

/// (am Netzteil?, Akku-Prozent)
fn strom() -> (bool, Option<u32>) {
    let mut netz: Option<bool> = None;
    let mut akku = None;
    if let Ok(d) = fs::read_dir("/sys/class/power_supply") {
        for e in d.flatten() {
            let p = e.path();
            match lies(p.join("type")).trim() {
                "Mains" | "USB" => {
                    if lies(p.join("online")).trim() == "1" {
                        netz = Some(true);
                    } else if netz.is_none() {
                        netz = Some(false);
                    }
                }
                "Battery" => akku = datei::lies_zahl(p.join("capacity")).map(|x| x as u32),
                _ => {}
            }
        }
    }
    (netz.unwrap_or(akku.is_none()), akku)
}

// ═════════ Energie und Wärme ═════════

#[derive(Clone, Copy, PartialEq)]
enum Profil {
    Leistung,
    Ausgewogen,
    Sparen,
}
impl Profil {
    fn name(self) -> &'static str {
        match self {
            Profil::Leistung => "Leistung",
            Profil::Ausgewogen => "Ausgewogen",
            Profil::Sparen => "Sparen",
        }
    }
    /// (höchste Leistung in %, Turbo aus?, Energie-Vorgabe für Prozessoren mit HWP)
    fn grenzen(self) -> (u32, bool, &'static str) {
        match self {
            Profil::Leistung => (100, false, "balance_performance"),
            Profil::Ausgewogen => (100, false, "balance_power"),
            Profil::Sparen => (70, true, "power"),
        }
    }
}

struct Regler {
    max_perf: Option<PathBuf>,
    no_turbo: Option<PathBuf>,
    epp: Vec<PathBuf>,
    ursprung_max: String,
    ursprung_turbo: String,
    ursprung_epp: Vec<String>,
    gesetzt: Option<(u32, bool, &'static str)>,
    fremd: bool,
}

/// laufen schon andere Energie-Verwalter? Dann halten wir uns bei den Vorgaben raus.
fn fremder_verwalter() -> bool {
    sys::prozesse().into_iter().any(|p| {
        let n = sys::name_von(p);
        n == "tuned" || n.starts_with("power-profiles") || n == "tlp" || n == "auto-cpufreq"
    })
}

impl Regler {
    fn neu() -> Regler {
        let ps = Path::new("/sys/devices/system/cpu/intel_pstate");
        let max_perf = Some(ps.join("max_perf_pct")).filter(|p| p.exists());
        let no_turbo = Some(ps.join("no_turbo")).filter(|p| p.exists());
        let mut epp = vec![];
        if let Ok(d) = fs::read_dir("/sys/devices/system/cpu/cpufreq") {
            for e in d.flatten() {
                let p = e.path().join("energy_performance_preference");
                if p.exists() {
                    epp.push(p);
                }
            }
        }
        // nach einem Absturz: gemerkte Ursprungswerte gelten, nicht die von uns gesetzten
        let gemerkt = lies(format!("{}/regler-ursprung", LAUFZEIT));
        let mut z = gemerkt.lines();
        let (ursprung_max, ursprung_turbo) = match (z.next(), z.next()) {
            (Some(a), Some(b)) if !a.is_empty() => (a.to_string(), b.to_string()),
            _ => (
                max_perf.as_ref().map(|p| lies(p).trim().to_string()).unwrap_or_default(),
                no_turbo.as_ref().map(|p| lies(p).trim().to_string()).unwrap_or_default(),
            ),
        };
        let _ = fs::write(format!("{}/regler-ursprung", LAUFZEIT), format!("{}\n{}\n", ursprung_max, ursprung_turbo));
        let ursprung_epp = epp.iter().map(|p| lies(p).trim().to_string()).collect();
        Regler { max_perf, no_turbo, epp, ursprung_max, ursprung_turbo, ursprung_epp, gesetzt: None, fremd: fremder_verwalter() }
    }

    fn anwenden(&mut self, profil: Profil, deckel: u32) {
        let (max, turbo_aus, epp) = profil.grenzen();
        let ziel = (max.min(deckel), turbo_aus, epp);
        if self.gesetzt == Some(ziel) {
            return;
        }
        if let Some(p) = &self.max_perf {
            schreib(p, &ziel.0.to_string());
        }
        if let Some(p) = &self.no_turbo {
            schreib(p, if ziel.1 { "1" } else { "0" });
        }
        if !self.fremd {
            for p in &self.epp {
                schreib(p, ziel.2);
            }
        }
        self.gesetzt = Some(ziel);
    }

    fn zuruecksetzen(&self) {
        if let Some(p) = &self.max_perf {
            schreib(p, if self.ursprung_max.is_empty() { "100" } else { self.ursprung_max.as_str() });
        }
        if let Some(p) = &self.no_turbo {
            schreib(p, if self.ursprung_turbo.is_empty() { "0" } else { self.ursprung_turbo.as_str() });
        }
        if !self.fremd {
            for (p, w) in self.epp.iter().zip(&self.ursprung_epp) {
                schreib(p, w);
            }
        }
        let _ = fs::remove_file(format!("{}/regler-ursprung", LAUFZEIT));
    }
}

/// Wärme-Schutz: über 85 °C (länger als 20 s) wird die Höchstleistung in 5-%-Schritten gesenkt (nie unter 60 %),
/// über 92 °C schneller; unter 78 °C geht es langsam wieder hoch. Sanft statt hart.
struct Waerme {
    deckel: u32,
    heiss_seit: Option<Instant>,
    kuehl_seit: Option<Instant>,
    zuletzt: Instant,
}
impl Waerme {
    fn schritt(&mut self, t: f64) {
        let jetzt = Instant::now();
        if t >= 85.0 {
            self.kuehl_seit = None;
            let seit = *self.heiss_seit.get_or_insert(jetzt);
            let warte = if t >= 92.0 { 6 } else { 20 };
            if jetzt.duration_since(seit).as_secs() >= warte && jetzt.duration_since(self.zuletzt).as_secs() >= warte.min(10) {
                self.deckel = self.deckel.saturating_sub(5).max(60);
                self.zuletzt = jetzt;
            }
        } else if t <= 78.0 {
            self.heiss_seit = None;
            let seit = *self.kuehl_seit.get_or_insert(jetzt);
            if self.deckel < 100 && jetzt.duration_since(seit).as_secs() >= 30 && jetzt.duration_since(self.zuletzt).as_secs() >= 15 {
                self.deckel = (self.deckel + 5).min(100);
                self.zuletzt = jetzt;
            }
        } else {
            self.heiss_seit = None;
            self.kuehl_seit = None;
        }
    }
}

/// Lüfter (applesmc): wir heben nur die Mindestdrehzahl an – die Apple-Steuerung (SMC) regelt darüber weiter selbst.
struct Luefter {
    ordner: Option<PathBuf>,
    ursprung: u32,
    max: u32,
    gesetzt: u32,
}
impl Luefter {
    fn neu() -> Luefter {
        let ordner = ["/sys/devices/platform/applesmc.768"].iter().map(PathBuf::from).find(|p| p.join("fan1_min").exists())
            .or_else(|| hwmon("applesmc").filter(|p| p.join("fan1_min").exists()));
        let mut l = Luefter { ordner, ursprung: 0, max: 0, gesetzt: 0 };
        if let Some(o) = &l.ordner {
            let gemerkt = datei::lies_zahl(format!("{}/luefter-ursprung", LAUFZEIT));
            l.ursprung = gemerkt.unwrap_or_else(|| datei::lies_zahl(o.join("fan1_min")).unwrap_or(1200.0)) as u32;
            l.max = datei::lies_zahl(o.join("fan1_max")).unwrap_or(6200.0) as u32;
            l.gesetzt = l.ursprung;
            let _ = fs::write(format!("{}/luefter-ursprung", LAUFZEIT), l.ursprung.to_string());
        }
        l
    }
    fn drehzahl(&self) -> Option<u32> {
        self.ordner.as_ref().and_then(|o| datei::lies_zahl(o.join("fan1_input"))).map(|x| x as u32)
    }
    fn schritt(&mut self, t: f64) {
        let Some(o) = &self.ordner else { return };
        if lies(o.join("fan1_manual")).trim() == "1" {
            return; // jemand anderes steuert gerade von Hand
        }
        let anteil = ((t - 55.0) / 30.0).clamp(0.0, 1.0);
        let oben = (self.max as f64 * 0.85).max(self.ursprung as f64);
        let ziel = (self.ursprung as f64 + (oben - self.ursprung as f64) * anteil) as u32 / 100 * 100;
        let ziel = ziel.max(self.ursprung);
        if (ziel as i64 - self.gesetzt as i64).abs() >= 200 || (ziel == self.ursprung && self.gesetzt != self.ursprung) {
            if schreib(o.join("fan1_min"), &ziel.to_string()) {
                self.gesetzt = ziel;
            }
        }
    }
    fn zuruecksetzen(&self) {
        if let Some(o) = &self.ordner {
            schreib(o.join("fan1_min"), &self.ursprung.to_string());
        }
        let _ = fs::remove_file(format!("{}/luefter-ursprung", LAUFZEIT));
    }
}

// ═════════ Vorrang und Fokus-Modus (cgroups) ═════════

#[derive(Clone, Copy, PartialEq, Debug)]
enum Soll {
    Normal,
    Vorne,
    Gedrosselt,
    Eingefroren,
}

struct Bereich {
    kennung: String,
    pfad: PathBuf,
    soll: Soll,
    proben: VecDeque<(Instant, u64, u64)>, // Zeit, Rechenzeit (µs), geschriebene Bytes
}

impl Bereich {
    fn messen(&mut self) {
        let cpu = datei::feld_nach(&lies(self.pfad.join("cpu.stat")), "usage_usec ").and_then(|x| x.parse().ok()).unwrap_or(0);
        let mut io = 0u64;
        for z in lies(self.pfad.join("io.stat")).lines() {
            if let Some(w) = datei::feld_nach(z, "wbytes=") {
                io += w.parse::<u64>().unwrap_or(0);
            }
        }
        self.proben.push_back((Instant::now(), cpu, io));
        while self.proben.len() > 6 {
            self.proben.pop_front();
        }
    }
    /// arbeitet das Programm gerade (Rechnen, Herunterladen, Musik)?
    fn aktiv(&self) -> bool {
        let (Some(a), Some(b)) = (self.proben.front(), self.proben.back()) else { return true };
        let s = b.0.duration_since(a.0).as_secs_f64();
        if s < 3.0 {
            return true;
        }
        let cpu = (b.1.saturating_sub(a.1)) as f64 / (s * 1e6);
        let io = (b.2.saturating_sub(a.2)) as f64 / s;
        cpu > 0.015 || io > 25_000.0
    }
    fn anwenden(&mut self, soll: Soll, schutz: u64) {
        if self.soll == soll {
            return;
        }
        let (gewicht, frieren, low) = match soll {
            Soll::Normal => ("100", "0", "0".to_string()),
            Soll::Vorne => ("400", "0", schutz.to_string()),
            Soll::Gedrosselt => ("1", "0", "0".to_string()),
            Soll::Eingefroren => ("1", "1", "0".to_string()),
        };
        schreib(self.pfad.join("cpu.weight"), gewicht);
        if self.pfad.join("io.weight").exists() {
            schreib(self.pfad.join("io.weight"), if soll == Soll::Vorne { "default 400" } else if gewicht == "1" { "default 1" } else { "default 100" });
        }
        schreib(self.pfad.join("memory.low"), &low);
        schreib(self.pfad.join("cgroup.freeze"), frieren);
        self.soll = soll;
    }
}

/// Programme, die nie eingefroren werden (höchstens gedrosselt)
const NIE_EINFRIEREN: [&str; 10] = ["james", "spotify", "rhythmbox", "vlc", "mpv", "audacious", "lollypop", "elisa", "pavucontrol", "foot"];

pub fn kennung_saeubern(s: &str) -> String {
    s.chars().filter(|c| c.is_ascii_alphanumeric()).collect::<String>().to_lowercase()
}

fn app_ordner(uid: u32) -> PathBuf {
    PathBuf::from(format!("/sys/fs/cgroup/user.slice/user-{0}.slice/user@{0}.service/app.slice", uid))
}

/// „app-auriliux-googlechrome-4711.scope“ → „googlechrome“
fn kennung_aus_scope(n: &str) -> Option<String> {
    let rest = n.strip_prefix("app-auriliux-")?.strip_suffix(".scope")?;
    let (k, nr) = rest.rsplit_once('-')?;
    if nr.chars().all(|c| c.is_ascii_digit()) {
        Some(k.to_string())
    } else {
        None
    }
}

struct Fokus {
    uid: Option<u32>,
    vorne: String,
    vollbild: bool,
    bereiche: HashMap<String, Bereich>,
    puls: Instant,
    schutz: u64,
}

impl Fokus {
    /// aktive Sitzung finden und lesen, was vorne ist (Datei gehört dem Benutzer, keine Verweise)
    fn vorne_lesen(&mut self) {
        let mut beste: Option<(i64, u32, String)> = None;
        if let Ok(d) = fs::read_dir("/run/user") {
            for e in d.flatten() {
                let Ok(uid) = e.file_name().to_string_lossy().parse::<u32>() else { continue };
                if uid < 1000 {
                    continue;
                }
                let p = e.path().join("auriliux/vorne");
                let Ok(mut f) = fs::OpenOptions::new().read(true).custom_flags(O_NOFOLLOW).open(&p) else { continue };
                let Ok(m) = f.metadata() else { continue };
                if m.uid() != uid || !m.is_file() {
                    continue;
                }
                let mut t = String::new();
                let _ = (&mut f).take(256).read_to_string(&mut t);
                if beste.as_ref().map(|b| m.mtime() > b.0).unwrap_or(true) {
                    beste = Some((m.mtime(), uid, t));
                }
            }
        }
        match beste {
            Some((_, uid, t)) => {
                let mut z = t.lines();
                self.uid = Some(uid);
                self.vorne = kennung_saeubern(z.next().unwrap_or(""));
                self.vollbild = z.next().map(|v| v.trim() == "1").unwrap_or(false);
            }
            None => {
                self.vorne.clear();
                self.vollbild = false;
            }
        }
    }

    fn bereiche_lesen(&mut self) {
        let Some(uid) = self.uid else { return };
        let ordner = app_ordner(uid);
        let mut da: Vec<String> = Vec::new();
        if let Ok(d) = fs::read_dir(&ordner) {
            for e in d.flatten() {
                let n = e.file_name().to_string_lossy().into_owned();
                if let Some(k) = kennung_aus_scope(&n) {
                    da.push(n.clone());
                    self.bereiche.entry(n).or_insert_with(|| Bereich { kennung: k, pfad: e.path(), soll: Soll::Normal, proben: VecDeque::new() });
                }
            }
        }
        self.bereiche.retain(|n, _| da.contains(n));
    }

    fn messen(&mut self) {
        for b in self.bereiche.values_mut() {
            if b.soll != Soll::Eingefroren {
                b.messen();
            }
        }
    }

    fn aktiv(&self) -> bool {
        self.vollbild && !self.vorne.is_empty()
    }

    fn schritt(&mut self) {
        let fokus = self.aktiv();
        let vorne = self.vorne.clone();
        let schutz = self.schutz;
        for b in self.bereiche.values_mut() {
            let k = kennung_saeubern(&b.kennung);
            let soll = if !vorne.is_empty() && k == vorne {
                Soll::Vorne
            } else if fokus {
                if b.soll == Soll::Eingefroren {
                    Soll::Eingefroren
                } else if NIE_EINFRIEREN.iter().any(|n| k.contains(n)) || b.aktiv() {
                    Soll::Gedrosselt
                } else {
                    Soll::Eingefroren
                }
            } else {
                Soll::Normal
            };
            b.anwenden(soll, schutz);
        }
    }

    /// Eingefrorene kurz auftauen (alle 5 s für 0,15 s), damit ihre Verbindungen zum Bildschirm nicht überlaufen
    fn puls(&mut self) {
        if self.puls.elapsed() < Duration::from_secs(5) {
            return;
        }
        self.puls = Instant::now();
        let gefroren: Vec<PathBuf> = self.bereiche.values().filter(|b| b.soll == Soll::Eingefroren).map(|b| b.pfad.clone()).collect();
        if gefroren.is_empty() {
            return;
        }
        for p in &gefroren {
            schreib(p.join("cgroup.freeze"), "0");
        }
        std::thread::sleep(Duration::from_millis(150));
        for p in &gefroren {
            schreib(p.join("cgroup.freeze"), "1");
        }
    }

    fn alles_normal(&mut self) {
        for b in self.bereiche.values_mut() {
            b.anwenden(Soll::Normal, 0);
        }
    }

    fn namen(&self, s: Soll) -> Vec<String> {
        let mut v: Vec<String> = self.bereiche.values().filter(|b| b.soll == s).map(|b| b.kennung.clone()).collect();
        v.sort();
        v.dedup();
        v
    }
}

/// Notfall (z. B. nach einem Absturz): alle Auriliux-Programmbereiche aller Benutzer auftauen
fn alles_auftauen() {
    if let Ok(d) = fs::read_dir("/sys/fs/cgroup/user.slice") {
        for u in d.flatten() {
            let n = u.file_name().to_string_lossy().into_owned();
            let Some(uid) = n.strip_prefix("user-").and_then(|x| x.strip_suffix(".slice")) else { continue };
            let Ok(uid) = uid.parse::<u32>() else { continue };
            if let Ok(a) = fs::read_dir(app_ordner(uid)) {
                for e in a.flatten() {
                    if kennung_aus_scope(&e.file_name().to_string_lossy()).is_some() {
                        schreib(e.path().join("cgroup.freeze"), "0");
                        schreib(e.path().join("cpu.weight"), "100");
                        schreib(e.path().join("memory.low"), "0");
                    }
                }
            }
        }
    }
}

// ═════════ Verursacher finden ═════════

struct Prozessuhr {
    vorher: HashMap<i32, u64>,
    zeit: Instant,
}

/// (Name, Kennung des Programms, Prozessoranteil, Arbeitsspeicher)
fn verursacher(uhr: &mut Prozessuhr) -> Option<(String, String, f64, u64)> {
    let tick = 100.0; // USER_HZ
    let s = uhr.zeit.elapsed().as_secs_f64().max(0.5);
    let mut jetzt: HashMap<i32, u64> = HashMap::new();
    let mut gruppen: HashMap<String, (String, String, f64, u64)> = HashMap::new();
    for p in sys::prozesse() {
        let st = lies(format!("/proc/{}/stat", p));
        let Some(i) = st.rfind(')') else { continue };
        let f: Vec<&str> = st[i + 2..].split_whitespace().collect();
        if f.len() < 22 {
            continue;
        }
        let zeit = f[11].parse::<u64>().unwrap_or(0) + f[12].parse::<u64>().unwrap_or(0);
        let rss = f[21].parse::<u64>().unwrap_or(0) * 4096;
        jetzt.insert(p, zeit);
        let anteil = uhr.vorher.get(&p).map(|v| zeit.saturating_sub(*v) as f64 / tick / s).unwrap_or(0.0);
        let name = st[st.find('(').map(|x| x + 1).unwrap_or(0)..i].to_string();
        let cg = lies(format!("/proc/{}/cgroup", p));
        let kennung = cg.rsplit('/').next().and_then(|n| kennung_aus_scope(n.trim())).unwrap_or_default();
        let schl = if kennung.is_empty() { name.clone() } else { kennung.clone() };
        let g = gruppen.entry(schl).or_insert((name.clone(), kennung.clone(), 0.0, 0));
        g.2 += anteil;
        g.3 += rss;
    }
    uhr.vorher = jetzt;
    uhr.zeit = Instant::now();
    gruppen.into_values().max_by(|a, b| (a.2 + a.3 as f64 / 1e10).partial_cmp(&(b.2 + b.3 as f64 / 1e10)).unwrap_or(std::cmp::Ordering::Equal))
}

fn groesster_speicher() -> Option<(String, String, u64)> {
    let mut best: Option<(String, String, u64)> = None;
    let mut gruppen: HashMap<String, (String, String, u64)> = HashMap::new();
    for p in sys::prozesse() {
        if sys::uid_von(p).unwrap_or(0) < 1000 {
            continue;
        }
        let status = lies(format!("/proc/{}/status", p));
        let rss = status.lines().find(|z| z.starts_with("VmRSS:")).and_then(|z| z.split_whitespace().nth(1)).and_then(|x| x.parse::<u64>().ok()).unwrap_or(0) * 1024;
        let name = sys::name_von(p);
        let cg = lies(format!("/proc/{}/cgroup", p));
        let kennung = cg.rsplit('/').next().and_then(|n| kennung_aus_scope(n.trim())).unwrap_or_default();
        let schl = if kennung.is_empty() { name.clone() } else { kennung.clone() };
        gruppen.entry(schl).or_insert((name, kennung, 0)).2 += rss;
    }
    for g in gruppen.into_values() {
        if best.as_ref().map(|b| g.2 > b.2).unwrap_or(true) {
            best = Some(g);
        }
    }
    best
}

// ═════════ Hauptschleife ═════════

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--zuruecksetzen") {
        alles_auftauen();
        let ps = "/sys/devices/system/cpu/intel_pstate";
        let ur = lies(format!("{}/regler-ursprung", LAUFZEIT));
        let mut z = ur.lines();
        schreib(format!("{}/max_perf_pct", ps), z.next().filter(|s| !s.is_empty()).unwrap_or("100"));
        schreib(format!("{}/no_turbo", ps), z.next().filter(|s| !s.is_empty()).unwrap_or("0"));
        if let Some(u) = datei::lies_zahl(format!("{}/luefter-ursprung", LAUFZEIT)) {
            schreib("/sys/devices/platform/applesmc.768/fan1_min", &(u as u32).to_string());
        }
        return;
    }
    let einmal = args.iter().any(|a| a == "--einmal");
    let status_pfad = args.iter().position(|a| a == "--ausgabe").and_then(|i| args.get(i + 1).cloned()).unwrap_or_else(|| format!("{}/status.json", LAUFZEIT));
    if !einmal && unsafe { sys::geteuid() } != 0 {
        eprintln!("Herzschlag muss als root laufen.");
        std::process::exit(1);
    }
    let _ = fs::create_dir_all(LAUFZEIT);
    if let Some(o) = Path::new(&status_pfad).parent() {
        let _ = fs::create_dir_all(o);
    }
    sys::signale_abfangen();

    let coretemp = hwmon("coretemp");
    let mut cpu = Cpu { vorher: None };
    let mut regler = if einmal { None } else { Some(Regler::neu()) };
    let mut luefter = if einmal { Luefter { ordner: None, ursprung: 0, max: 0, gesetzt: 0 } } else { Luefter::neu() };
    let mut waerme = Waerme { deckel: 100, heiss_seit: None, kuehl_seit: None, zuletzt: Instant::now() };
    let (gesamt, _, _) = speicher();
    let mut fokus = Fokus { uid: None, vorne: String::new(), vollbild: false, bereiche: HashMap::new(), puls: Instant::now(), schutz: gesamt / 4 };
    let mut uhr = Prozessuhr { vorher: HashMap::new(), zeit: Instant::now() };
    let mut verlauf_t: VecDeque<f64> = VecDeque::new();
    let mut verlauf_c: VecDeque<f64> = VecDeque::new();
    let mut hohe_last_seit: Option<Instant> = None;
    let mut letzte_messung = Instant::now() - Duration::from_secs(10);
    let mut letzter_vorne = (String::new(), false);
    let mut alter_status = String::new();
    let mut takt: u64 = 0;
    cpu.last();
    if einmal {
        std::thread::sleep(Duration::from_millis(1000));
    }
    eprintln!("Herzschlag läuft (Kerntemperatur: {}, Lüfter: {})", coretemp.is_some(), luefter.ordner.is_some());

    loop {
        if sys::ende() {
            break;
        }
        // alle 0,5 s: was ist vorne? (schnelle Reaktion beim Programmwechsel)
        fokus.vorne_lesen();
        let jetzt_vorne = (fokus.vorne.clone(), fokus.vollbild);
        let wechsel = jetzt_vorne != letzter_vorne;
        if wechsel {
            fokus.bereiche_lesen();
            fokus.schritt();
            letzter_vorne = jetzt_vorne;
        }
        fokus.puls();

        if letzte_messung.elapsed() >= Duration::from_secs(2) || einmal {
            letzte_messung = Instant::now();
            takt += 1;
            let last = cpu.last();
            let t = temperatur(&coretemp);
            let (gesamt, frei, swap) = speicher();
            let ram = if gesamt > 0 { 1.0 - frei as f64 / gesamt as f64 } else { 0.0 };
            let (netz, akku) = strom();
            let profil = if netz { Profil::Leistung } else if akku.map(|a| a < 20).unwrap_or(false) { Profil::Sparen } else { Profil::Ausgewogen };
            if t > 0.0 {
                waerme.schritt(t);
                luefter.schritt(t);
            }
            if let Some(r) = regler.as_mut() {
                r.anwenden(profil, waerme.deckel);
            }
            fokus.bereiche_lesen();
            fokus.messen();
            fokus.schritt();

            if last >= 0.85 {
                hohe_last_seit.get_or_insert(Instant::now());
            } else {
                hohe_last_seit = None;
            }
            let ueberlast = hohe_last_seit.map(|s| s.elapsed().as_secs() >= 20).unwrap_or(false);
            let druck_speicher = druck("memory");
            let speicher_knapp = druck_speicher > 10.0 || (gesamt > 0 && (frei as f64) < gesamt as f64 * 0.08);
            let zustand = if ueberlast && (t >= 85.0 || last >= 0.95) {
                "ueberlast"
            } else if waerme.deckel < 100 || t >= 88.0 {
                "heiss"
            } else if speicher_knapp {
                "speicher"
            } else if t >= 78.0 || ueberlast {
                "warm"
            } else {
                "ruhig"
            };
            // Verursacher nur suchen, wenn es etwas zu melden gibt (spart Rechenzeit)
            let mut wer = J::Null;
            let mut text = String::new();
            if zustand == "speicher" {
                if let Some((name, kennung, rss)) = groesster_speicher() {
                    text = format!("Arbeitsspeicher knapp – „{}“ belegt {}", if kennung.is_empty() { &name } else { &kennung }, datei::groesse(rss));
                    wer = J::o(vec![("name", J::t(name)), ("kennung", J::t(kennung)), ("cpu", J::Z(0.0)), ("ram", J::I(rss as i64))]);
                }
            } else if zustand != "ruhig" || einmal {
                if let Some((name, kennung, anteil, rss)) = verursacher(&mut uhr) {
                    if anteil > 0.05 || einmal {
                        wer = J::o(vec![("name", J::t(&name)), ("kennung", J::t(&kennung)), ("cpu", J::Z(anteil)), ("ram", J::I(rss as i64))]);
                        text = format!("„{}“ braucht {} % Prozessor", if kennung.is_empty() { &name } else { &kennung }, (anteil * 100.0).round());
                    }
                }
            } else {
                uhr.vorher.clear();
            }
            let text = match zustand {
                "ueberlast" => format!("Überlast – {}", if text.is_empty() { "der Prozessor ist voll ausgelastet".to_string() } else { text }),
                "heiss" => format!("Heiß ({} °C) – Turbo sanft gedeckelt auf {} %", t.round(), waerme.deckel),
                "speicher" => if text.is_empty() { "Arbeitsspeicher knapp".to_string() } else { text },
                "warm" => format!("Wird warm ({} °C) – Lüfter läuft früher an", t.round()),
                _ => "Alles ruhig".into(),
            };
            verlauf_t.push_back(t);
            verlauf_c.push_back(last);
            while verlauf_t.len() > 90 {
                verlauf_t.pop_front();
                verlauf_c.pop_front();
            }
            let status = J::o(vec![
                ("zeit", J::I(datei::jetzt_ms())),
                ("zustand", J::t(zustand)),
                ("text", J::t(text)),
                ("cpu", J::Z(last)),
                ("temp", J::Z(t)),
                ("luefter", luefter.drehzahl().map(|d| J::I(d as i64)).unwrap_or(J::Null)),
                ("luefterMin", J::I(luefter.gesetzt as i64)),
                ("luefterMax", J::I(luefter.max as i64)),
                ("profil", J::t(profil.name())),
                ("netz", J::B(netz)),
                ("akku", akku.map(|a| J::I(a as i64)).unwrap_or(J::Null)),
                ("deckel", J::I(waerme.deckel as i64)),
                ("fremd", J::B(regler.as_ref().map(|r| r.fremd).unwrap_or(false))),
                ("ram", J::Z(ram)),
                ("swap", J::I(swap as i64)),
                ("druck", J::o(vec![("cpu", J::Z(druck("cpu"))), ("speicher", J::Z(druck_speicher))])),
                ("verursacher", wer),
                ("vorne", J::t(&fokus.vorne)),
                (
                    "fokus",
                    J::o(vec![
                        ("aktiv", J::B(fokus.aktiv())),
                        ("eingefroren", J::texte(&fokus.namen(Soll::Eingefroren))),
                        ("gedrosselt", J::texte(&fokus.namen(Soll::Gedrosselt))),
                        ("programme", J::I(fokus.bereiche.len() as i64)),
                    ]),
                ),
                ("verlauf", J::o(vec![
                    ("temp", J::L(verlauf_t.iter().map(|x| J::Z(*x)).collect())),
                    ("cpu", J::L(verlauf_c.iter().map(|x| J::Z(*x)).collect())),
                ])),
            ])
            .text();
            // nur schreiben, wenn sich etwas Sichtbares geändert hat oder alle 10 s (für die Verlaufskurve)
            let kern = format!("{}|{}|{}|{}|{}|{}", zustand, fokus.aktiv(), profil.name(), waerme.deckel, (t / 2.0).round(), (last * 20.0).round());
            if kern != alter_status || takt % 5 == 0 || wechsel {
                let _ = datei::schreiben(&status_pfad, status.as_bytes(), 0o644);
                alter_status = kern;
            }
            if einmal {
                println!("{}", status);
                return;
            }
        } else if wechsel {
            // Fokus-Änderung sofort sichtbar machen (Goldleiste: „FOKUS“)
            letzte_messung = Instant::now() - Duration::from_secs(10);
        }
        std::thread::sleep(Duration::from_millis(500));
    }
    fokus.alles_normal();
    if let Some(r) = &regler {
        r.zuruecksetzen();
    }
    luefter.zuruecksetzen();
    eprintln!("Herzschlag beendet – alles zurückgesetzt");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kennungen() {
        assert_eq!(kennung_aus_scope("app-auriliux-googlechrome-4711.scope"), Some("googlechrome".into()));
        assert_eq!(kennung_aus_scope("app-gnome-x-1.scope"), None);
        assert_eq!(kennung_aus_scope("app-auriliux-google-chrome-48213.scope"), Some("google-chrome".into()));
        assert_eq!(kennung_saeubern("google-chrome"), "googlechrome");
    }
}
