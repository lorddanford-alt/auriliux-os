//! Wachen über das Dateisystem (fanotify, direkt vom Linux-Kern):
//!  • Ausführungs-Schild: Programme aus Benutzerordnern, /tmp und USB-Sticks starten nur nach Freigabe.
//!  • Schreib-Wache: neu geschriebene Dateien gehen an den Scanner und an den Erpresser-Schild.
//!  • Erpresser-Schild: überschreibt ein Programm in Sekunden viele Dateien mit unlesbarem Inhalt, wird es eingefroren.
use crate::{Meldung, Schluessel, DATEN};
use gemeinsam::sys::{self, FanAntwort, FanMeta, FAN_META};
use std::collections::{HashMap, HashSet};
use std::ffi::c_void;
use std::fs::{self, File};
use std::mem::ManuallyDrop;
use std::os::unix::fs::MetadataExt;
use std::os::unix::io::FromRawFd;
use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant};

/// Orte, aus denen ein normaler Benutzer nichts ohne Freigabe starten darf
const GESPERRT: [&str; 9] = ["/var/home/", "/home/", "/tmp/", "/var/tmp/", "/dev/shm/", "/run/media/", "/run/user/", "/media/", "/mnt/"];

pub fn gesperrter_ort(p: &str) -> bool {
    GESPERRT.iter().any(|g| p.starts_with(g))
}

/// Dateien der Benutzer (ohne versteckte Ordner wie .cache) und USB-Sticks
pub fn beobachteter_ort(p: &str) -> bool {
    (p.starts_with("/var/home/") || p.starts_with("/home/") || p.starts_with("/run/media/"))
        && !p.contains("/.")
        && !p.ends_with(" (deleted)")
}

pub fn schluessel_von(m: &fs::Metadata) -> Schluessel {
    (m.dev(), m.ino(), m.ctime(), m.ctime_nsec(), m.size())
}

pub fn schluessel_text(s: &Schluessel) -> String {
    format!("{}:{}:{}:{}:{}", s.0, s.1, s.2, s.3, s.4)
}

pub fn schluessel_lesen(t: &str) -> Option<Schluessel> {
    let f: Vec<&str> = t.split(':').collect();
    if f.len() != 5 {
        return None;
    }
    Some((f[0].parse().ok()?, f[1].parse().ok()?, f[2].parse().ok()?, f[3].parse().ok()?, f[4].parse().ok()?))
}

/// Einhängepunkte aus /proc/self/mountinfo: (Kennung, Ort)
pub fn einhaengepunkte() -> Vec<(String, String)> {
    let t = fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    t.lines()
        .filter_map(|z| {
            let f: Vec<&str> = z.split(' ').collect();
            if f.len() < 5 {
                return None;
            }
            Some((f[0].to_string(), entschluesseln(f[4])))
        })
        .collect()
}

/// \040 → Leerzeichen usw.
pub fn entschluesseln(s: &str) -> String {
    let b = s.as_bytes();
    let mut aus = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'\\' && i + 3 < b.len() {
            let t = &b[i + 1..i + 4];
            if t.iter().all(|c| (b'0'..=b'7').contains(c)) {
                let n = (t[0] - b'0') as u32 * 64 + (t[1] - b'0') as u32 * 8 + (t[2] - b'0') as u32;
                aus.push((n & 0xff) as u8);
                i += 4;
                continue;
            }
        }
        aus.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&aus).into_owned()
}

fn markieren(fd: i32, ort: &str, maske: u64) -> bool {
    let c = sys::c(ort);
    let r = unsafe { sys::fanotify_mark(fd, sys::FAN_MARK_ADD | sys::FAN_MARK_FILESYSTEM, maske, sys::AT_FDCWD, c.as_ptr()) };
    if r == 0 {
        return true;
    }
    unsafe { sys::fanotify_mark(fd, sys::FAN_MARK_ADD | sys::FAN_MARK_MOUNT, maske, sys::AT_FDCWD, c.as_ptr()) == 0 }
}

/// Beide Wachen auf alle passenden Laufwerke setzen (neue USB-Sticks kommen beim nächsten Aufruf dazu)
pub struct Markierer {
    erledigt: HashSet<String>,
}

impl Markierer {
    pub fn neu() -> Markierer {
        Markierer { erledigt: HashSet::new() }
    }

    pub fn aktualisieren(&mut self, exec_fd: i32, schreib_fd: i32) {
        let punkte = einhaengepunkte();
        let mut ziele: Vec<(String, String)> = Vec::new();
        for feste in ["/var/home", "/home", "/tmp", "/var/tmp", "/dev/shm"] {
            if fs::metadata(feste).is_ok() {
                ziele.push((format!("fest:{}", feste), feste.to_string()));
            }
        }
        for (id, ort) in punkte {
            if ort.starts_with("/run/media/") || ort.starts_with("/run/user/") || ort.starts_with("/media/") || ort.starts_with("/mnt/") {
                ziele.push((format!("{}:{}", id, ort), ort));
            }
        }
        for (k, ort) in ziele {
            if self.erledigt.contains(&k) {
                continue;
            }
            let mut ok = true;
            if exec_fd >= 0 {
                ok &= markieren(exec_fd, &ort, sys::FAN_OPEN_EXEC_PERM);
            }
            if schreib_fd >= 0 && !ort.starts_with("/run/user/") && !ort.starts_with("/tmp") && !ort.starts_with("/dev/shm") {
                ok &= markieren(schreib_fd, &ort, sys::FAN_CLOSE_WRITE);
            }
            if ok {
                self.erledigt.insert(k);
            } else {
                eprintln!("Guardian: konnte {} nicht überwachen (Fehler {})", ort, sys::fehlernummer());
            }
        }
    }
}

// ═════════ Ausführungs-Schild ═════════

pub type Freigaben = Arc<RwLock<HashSet<Schluessel>>>;

/// eigener Faden, der dem Kern bei jedem Programmstart aus gesperrten Orten antwortet
pub fn ausfuehrung_starten(freigaben: Freigaben, tx: Sender<Meldung>) -> Result<i32, String> {
    let fd = unsafe { sys::fanotify_init(sys::FAN_CLASS_CONTENT | sys::FAN_CLOEXEC, sys::O_LARGEFILE | sys::O_CLOEXEC) };
    if fd < 0 {
        return Err(format!("fanotify nicht verfügbar (Fehler {})", sys::fehlernummer()));
    }
    std::thread::Builder::new()
        .name("ausfuehrung".into())
        .spawn(move || ausfuehrung_schleife(fd, freigaben, tx))
        .map_err(|e| e.to_string())?;
    Ok(fd)
}

fn ausfuehrung_schleife(fd: i32, freigaben: Freigaben, tx: Sender<Meldung>) {
    let mut buf = vec![0u8; 16 * 1024];
    let mut fehler = 0;
    loop {
        let n = unsafe { sys::read(fd, buf.as_mut_ptr() as *mut c_void, buf.len()) };
        if n < 0 {
            if sys::fehlernummer() == 4 {
                continue; // EINTR
            }
            fehler += 1;
            if fehler > 50 {
                // lieber ganz beenden (Kern erlaubt dann alles, systemd startet neu) als Starts hängen zu lassen
                eprintln!("Guardian: Ausführungs-Schild kann nicht mehr lesen – Neustart");
                std::process::abort();
            }
            std::thread::sleep(Duration::from_millis(20));
            continue;
        }
        fehler = 0;
        let n = n as usize;
        let mut off = 0;
        while off + FAN_META <= n {
            let m: FanMeta = unsafe { std::ptr::read_unaligned(buf.as_ptr().add(off) as *const FanMeta) };
            if (m.event_len as usize) < FAN_META {
                break;
            }
            off += m.event_len as usize;
            if m.fd < 0 {
                continue;
            }
            let ja = if m.mask & sys::FAN_OPEN_EXEC_PERM != 0 { entscheiden(&m, &freigaben, &tx) } else { true };
            let a = FanAntwort { fd: m.fd, response: if ja { sys::FAN_ALLOW } else { sys::FAN_DENY } };
            unsafe {
                sys::write(fd, &a as *const FanAntwort as *const c_void, std::mem::size_of::<FanAntwort>());
                sys::close(m.fd);
            }
        }
    }
}

fn entscheiden(m: &FanMeta, freigaben: &Freigaben, tx: &Sender<Meldung>) -> bool {
    let Some(pfad) = sys::fd_pfad(m.fd) else { return true };
    if !gesperrter_ort(&pfad) {
        return true;
    }
    // Systemdienste (root & Co.) nicht stören – geschützt werden die Programme der Benutzer
    let Some(uid) = sys::uid_von(m.pid) else { return true };
    if uid < 1000 {
        return true;
    }
    let datei = ManuallyDrop::new(unsafe { File::from_raw_fd(m.fd) });
    let Ok(meta) = datei.metadata() else { return false };
    let s = schluessel_von(&meta);
    if freigaben.read().map(|f| f.contains(&s)).unwrap_or(false) {
        return true;
    }
    let _ = tx.send(Meldung::StartVerhindert { pfad, uid, programm: sys::name_von(m.pid), schluessel: s });
    false
}

// ═════════ Erpresser-Schild ═════════

pub fn entropie(b: &[u8]) -> f64 {
    if b.is_empty() {
        return 0.0;
    }
    let mut h = [0u32; 256];
    for &x in b {
        h[x as usize] += 1;
    }
    let n = b.len() as f64;
    -h.iter().filter(|&&c| c > 0).map(|&c| {
        let p = c as f64 / n;
        p * p.log2()
    }).sum::<f64>()
}

pub struct Erpresser {
    fenster: HashMap<i32, Vec<(Instant, u64)>>,
    gemeldet: HashMap<i32, Instant>,
}

pub const ERPRESSER_GRENZE: usize = 20;

impl Erpresser {
    pub fn neu() -> Erpresser {
        Erpresser { fenster: HashMap::new(), gemeldet: HashMap::new() }
    }

    /// eine vorhandene Datei wurde mit zufällig wirkendem Inhalt überschrieben → Anzahl, wenn die Grenze erreicht ist
    pub fn beobachten(&mut self, pid: i32, ino: u64) -> Option<usize> {
        let jetzt = Instant::now();
        let v = self.fenster.entry(pid).or_default();
        v.push((jetzt, ino));
        v.retain(|(t, _)| jetzt.duration_since(*t) < Duration::from_secs(20));
        let verschieden: HashSet<u64> = v.iter().map(|(_, i)| *i).collect();
        if verschieden.len() >= ERPRESSER_GRENZE {
            if let Some(t) = self.gemeldet.get(&pid) {
                if jetzt.duration_since(*t) < Duration::from_secs(300) {
                    return None;
                }
            }
            self.gemeldet.insert(pid, jetzt);
            let n = verschieden.len();
            self.fenster.remove(&pid);
            return Some(n);
        }
        None
    }

    pub fn aufraeumen(&mut self) {
        let jetzt = Instant::now();
        self.fenster.retain(|_, v| v.last().map(|(t, _)| jetzt.duration_since(*t) < Duration::from_secs(30)).unwrap_or(false));
        self.gemeldet.retain(|_, t| jetzt.duration_since(*t) < Duration::from_secs(600));
    }
}

/// Gefrierfach: eigene Kontrollgruppe (cgroup) unterhalb des Guardian-Dienstes. Prozesse darin stehen still,
/// und der Benutzer (oder ein Schädling mit seinen Rechten) kann sie nicht selbst wieder auftauen.
pub struct Gefrierfach {
    basis: PathBuf,
    zaehler: u32,
}

fn cgroup_von(pid: i32) -> Option<String> {
    let t = fs::read_to_string(format!("/proc/{}/cgroup", pid)).ok()?;
    Some(t.lines().find(|z| z.starts_with("0::"))?[3..].trim().to_string())
}

fn nachkommen(wurzel: i32) -> Vec<i32> {
    let mut eltern: HashMap<i32, Vec<i32>> = HashMap::new();
    for p in sys::prozesse() {
        if let Some(e) = sys::eltern_von(p) {
            eltern.entry(e).or_default().push(p);
        }
    }
    let mut aus = vec![wurzel];
    let mut i = 0;
    while i < aus.len() && aus.len() < 500 {
        if let Some(k) = eltern.get(&aus[i]) {
            for &p in k {
                if !aus.contains(&p) {
                    aus.push(p);
                }
            }
        }
        i += 1;
    }
    aus
}

impl Gefrierfach {
    /// nur unter systemd mit „Delegate=yes“: der Dienst zieht selbst in die Untergruppe „dienst“ um
    pub fn einrichten() -> Option<Gefrierfach> {
        let eigen = cgroup_von(std::process::id() as i32)?;
        let eigen = eigen.trim_end_matches("/dienst").to_string();
        if !eigen.ends_with(".service") {
            return None;
        }
        let basis = PathBuf::from(format!("/sys/fs/cgroup{}", eigen));
        let dienst = basis.join("dienst");
        fs::create_dir_all(&dienst).ok()?;
        fs::write(dienst.join("cgroup.procs"), std::process::id().to_string()).ok()?;
        fs::create_dir_all(basis.join("eingefroren")).ok()?;
        Some(Gefrierfach { basis, zaehler: 0 })
    }

    fn fach(&self, name: &str) -> PathBuf {
        self.basis.join("eingefroren").join(name)
    }

    fn herkunft_datei(name: &str) -> String {
        format!("{}/gefroren-{}.txt", DATEN, name)
    }

    /// Prozess samt Kindern einfrieren → (Fachname, Prozessnummern)
    pub fn einfrieren(&mut self, pid: i32) -> Result<(String, Vec<i32>), String> {
        self.zaehler += 1;
        let name = format!("fach{}-{}", self.zaehler, pid);
        let fach = self.fach(&name);
        fs::create_dir_all(&fach).map_err(|e| e.to_string())?;
        fs::write(fach.join("cgroup.freeze"), "1").map_err(|e| e.to_string())?;
        let mut alle: Vec<i32> = Vec::new();
        let mut herkunft = String::new();
        for _ in 0..3 {
            for p in nachkommen(pid) {
                if alle.contains(&p) {
                    continue;
                }
                let alt = cgroup_von(p).unwrap_or_default();
                if fs::write(fach.join("cgroup.procs"), p.to_string()).is_ok() {
                    alle.push(p);
                    herkunft.push_str(&format!("{}\t{}\n", p, alt));
                }
            }
        }
        if alle.is_empty() {
            let _ = fs::remove_dir(&fach);
            return Err("Prozess ließ sich nicht verschieben".into());
        }
        let _ = fs::write(Gefrierfach::herkunft_datei(&name), herkunft);
        Ok((name, alle))
    }

    pub fn fortsetzen(&self, name: &str) -> Result<String, String> {
        let fach = self.fach(name);
        let herkunft = fs::read_to_string(Gefrierfach::herkunft_datei(name)).unwrap_or_default();
        for z in herkunft.lines() {
            let mut t = z.splitn(2, '\t');
            let (Some(p), Some(alt)) = (t.next(), t.next()) else { continue };
            if !alt.is_empty() {
                let _ = fs::write(format!("/sys/fs/cgroup{}/cgroup.procs", alt), p);
            }
        }
        let rest = fs::read_to_string(fach.join("cgroup.procs")).unwrap_or_default();
        if rest.trim().is_empty() {
            let _ = fs::remove_dir(&fach);
        } else {
            // Ursprungsgruppe gibt es nicht mehr → an Ort und Stelle auftauen
            let _ = fs::write(fach.join("cgroup.freeze"), "0");
        }
        let _ = fs::remove_file(Gefrierfach::herkunft_datei(name));
        Ok("Läuft weiter".into())
    }

    pub fn beenden(&self, name: &str) -> Result<String, String> {
        let fach = self.fach(name);
        if fs::write(fach.join("cgroup.kill"), "1").is_err() {
            for z in fs::read_to_string(fach.join("cgroup.procs")).unwrap_or_default().lines() {
                if let Ok(p) = z.trim().parse::<i32>() {
                    unsafe { sys::kill(p, sys::SIGKILL) };
                }
            }
        }
        for _ in 0..40 {
            if fs::read_to_string(fach.join("cgroup.procs")).map(|t| t.trim().is_empty()).unwrap_or(true) {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        let _ = fs::remove_dir(&fach);
        let _ = fs::remove_file(Gefrierfach::herkunft_datei(name));
        Ok("Beendet".into())
    }

    /// leere Fächer (Prozess hat sich beendet) wegräumen
    pub fn aufraeumen(&self) {
        if let Ok(d) = fs::read_dir(self.basis.join("eingefroren")) {
            for e in d.flatten() {
                let p = e.path();
                if fs::read_to_string(p.join("cgroup.procs")).map(|t| t.trim().is_empty()).unwrap_or(false) {
                    let _ = fs::remove_dir(&p);
                }
            }
        }
    }
}
