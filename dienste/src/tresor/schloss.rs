//! Das Zahlenschloss des Tresors: Code aus drei Zahlen (0–99) wie bei einem echten Drehschloss.
//! Gespeichert wird nur ein gesalzener PBKDF2-SHA256-Wert (nur für root lesbar). Nach Fehlversuchen
//! wird immer länger gesperrt (5 Fehler → 1 Minute, danach jeweils doppelt so lang, höchstens 1 Stunde).
//! Nach dem Öffnen gibt es ein Zugangs-Kärtchen (Token), das 15 Minuten gilt und nur für diesen Benutzer.
use gemeinsam::datei;
use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::time::{Duration, Instant};

const RUNDEN: u32 = 60_000;
const GUELTIG: Duration = Duration::from_secs(15 * 60);

// ── SHA-256 (FIPS 180-4) ──
const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
    0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
    0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

pub fn sha256(daten: &[u8]) -> [u8; 32] {
    let mut h: [u32; 8] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    let mut m = daten.to_vec();
    let bits = (daten.len() as u64).wrapping_mul(8);
    m.push(0x80);
    while m.len() % 64 != 56 {
        m.push(0);
    }
    m.extend_from_slice(&bits.to_be_bytes());
    for block in m.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([block[4 * i], block[4 * i + 1], block[4 * i + 2], block[4 * i + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ (!e & g);
            let t1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        for (x, y) in h.iter_mut().zip([a, b, c, d, e, f, g, hh]) {
            *x = x.wrapping_add(y);
        }
    }
    let mut aus = [0u8; 32];
    for i in 0..8 {
        aus[4 * i..4 * i + 4].copy_from_slice(&h[i].to_be_bytes());
    }
    aus
}

pub fn hmac(schluessel: &[u8], nachricht: &[u8]) -> [u8; 32] {
    let mut k = [0u8; 64];
    if schluessel.len() > 64 {
        k[..32].copy_from_slice(&sha256(schluessel));
    } else {
        k[..schluessel.len()].copy_from_slice(schluessel);
    }
    let mut innen: Vec<u8> = k.iter().map(|b| b ^ 0x36).collect();
    innen.extend_from_slice(nachricht);
    let mut aussen: Vec<u8> = k.iter().map(|b| b ^ 0x5c).collect();
    aussen.extend_from_slice(&sha256(&innen));
    sha256(&aussen)
}

/// PBKDF2-HMAC-SHA256, ein Block (32 Byte)
pub fn pbkdf2(passwort: &[u8], salz: &[u8], runden: u32) -> [u8; 32] {
    let mut s = salz.to_vec();
    s.extend_from_slice(&1u32.to_be_bytes());
    let mut u = hmac(passwort, &s);
    let mut t = u;
    for _ in 1..runden {
        u = hmac(passwort, &u);
        for (a, b) in t.iter_mut().zip(u.iter()) {
            *a ^= b;
        }
    }
    t
}

pub fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{:02x}", x)).collect()
}

fn aus_hex(t: &str) -> Vec<u8> {
    (0..t.len() / 2).filter_map(|i| u8::from_str_radix(t.get(2 * i..2 * i + 2)?, 16).ok()).collect()
}

pub fn zufall(n: usize) -> Vec<u8> {
    let mut b = vec![0u8; n];
    if let Ok(mut f) = fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut b);
    }
    b
}

/// „12-34-56“ → in Ordnung? (drei Zahlen 0–99)
pub fn code_gueltig(code: &str) -> bool {
    let t: Vec<&str> = code.split('-').collect();
    t.len() == 3 && t.iter().all(|z| !z.is_empty() && z.len() <= 2 && z.chars().all(|c| c.is_ascii_digit()))
}

/// einheitliche Schreibweise („7-3-45“ → „07-03-45“)
fn normal(code: &str) -> String {
    code.split('-').map(|z| format!("{:02}", z.parse::<u32>().unwrap_or(0))).collect::<Vec<_>>().join("-")
}

fn gleich(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

pub struct Schloss {
    ordner: String,
    fehler: u32,
    gesperrt_bis: i64,
    karten: HashMap<String, (u32, Instant)>,
}

impl Schloss {
    pub fn laden(ordner: &str) -> Schloss {
        let s = datei::lies(format!("{}/sperre", ordner));
        let mut t = s.split_whitespace();
        let fehler = t.next().and_then(|x| x.parse().ok()).unwrap_or(0);
        let gesperrt_bis = t.next().and_then(|x| x.parse().ok()).unwrap_or(0);
        Schloss { ordner: ordner.to_string(), fehler, gesperrt_bis, karten: HashMap::new() }
    }

    pub fn gesetzt(&self) -> bool {
        datei::lies(format!("{}/code", self.ordner)).contains(':')
    }

    pub fn gesperrt_bis(&self) -> i64 {
        if self.gesperrt_bis > datei::jetzt_ms() { self.gesperrt_bis } else { 0 }
    }

    fn sperre_schreiben(&self) {
        let _ = datei::schreiben(&format!("{}/sperre", self.ordner), format!("{} {}\n", self.fehler, self.gesperrt_bis).as_bytes(), 0o600);
    }

    pub fn setzen(&mut self, code: &str) -> Result<(), String> {
        if !code_gueltig(code) {
            return Err("Der Code besteht aus drei Zahlen von 0 bis 99.".into());
        }
        let salz = zufall(16);
        let wert = pbkdf2(normal(code).as_bytes(), &salz, RUNDEN);
        datei::schreiben(&format!("{}/code", self.ordner), format!("{}:{}\n", hex(&salz), hex(&wert)).as_bytes(), 0o600)
            .map_err(|e| format!("Code ließ sich nicht speichern: {}", e))?;
        self.karten.clear();
        Ok(())
    }

    /// Ok(()) oder Err((Meldung, gesperrt bis ms))
    pub fn pruefen(&mut self, code: &str) -> Result<(), (String, i64)> {
        let jetzt = datei::jetzt_ms();
        if self.gesperrt_bis > jetzt {
            return Err(("Zu viele Fehlversuche – das Schloss ist noch gesperrt.".into(), self.gesperrt_bis));
        }
        let gespeichert = datei::lies(format!("{}/code", self.ordner));
        let (salz, wert) = gespeichert.trim().split_once(':').unwrap_or(("", ""));
        let richtig = code_gueltig(code) && !wert.is_empty() && gleich(&pbkdf2(normal(code).as_bytes(), &aus_hex(salz), RUNDEN), &aus_hex(wert));
        if richtig {
            self.fehler = 0;
            self.gesperrt_bis = 0;
            self.sperre_schreiben();
            return Ok(());
        }
        self.fehler += 1;
        if self.fehler >= 5 {
            let minuten = (1i64 << (self.fehler - 5).min(6)).min(60);
            self.gesperrt_bis = jetzt + minuten * 60_000;
        }
        self.sperre_schreiben();
        let rest = 5i64 - self.fehler as i64;
        let text = if self.gesperrt_bis > jetzt {
            "Falscher Code – das Schloss sperrt jetzt.".to_string()
        } else {
            format!("Falscher Code – noch {} Versuch{} bis zur Sperre.", rest, if rest == 1 { "" } else { "e" })
        };
        Err((text, self.gesperrt_bis))
    }

    pub fn karte_ausgeben(&mut self, uid: u32) -> String {
        let t = hex(&zufall(16));
        self.karten.retain(|_, (_, ab)| ab.elapsed() < GUELTIG);
        self.karten.insert(t.clone(), (uid, Instant::now()));
        t
    }

    /// gilt die Karte für diesen Benutzer? (verlängert sie bei Benutzung)
    pub fn karte_gilt(&mut self, karte: &str, uid: u32) -> bool {
        match self.karten.get_mut(karte) {
            Some((u, ab)) if *u == uid && ab.elapsed() < GUELTIG => {
                *ab = Instant::now();
                true
            }
            _ => false,
        }
    }

    pub fn karte_weg(&mut self, karte: &str) {
        self.karten.remove(karte);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_bekannte_werte() {
        assert_eq!(hex(&sha256(b"")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(hex(&sha256(b"abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        assert_eq!(
            hex(&sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
    }

    #[test]
    fn hmac_und_pbkdf2_bekannte_werte() {
        // RFC 4231, Fall 2
        assert_eq!(hex(&hmac(b"Jefe", b"what do ya want for nothing?")), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
        // PBKDF2-HMAC-SHA256 („password“, „salt“)
        assert_eq!(hex(&pbkdf2(b"password", b"salt", 1)), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b");
        assert_eq!(hex(&pbkdf2(b"password", b"salt", 4096)), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a");
    }

    #[test]
    fn code_und_sperre() {
        let ordner = std::env::temp_dir().join(format!("tresor-test-{}", std::process::id()));
        let _ = fs::create_dir_all(&ordner);
        let o = ordner.to_string_lossy().to_string();
        let mut s = Schloss::laden(&o);
        assert!(!s.gesetzt());
        assert!(s.setzen("12-3").is_err());
        assert!(s.setzen("12-100-3").is_err());
        s.setzen("7-42-99").unwrap();
        assert!(s.gesetzt());
        assert!(s.pruefen("07-42-99").is_ok());
        for _ in 0..4 {
            assert!(s.pruefen("1-2-3").is_err());
        }
        assert_eq!(s.gesperrt_bis(), 0);
        let (_, bis) = s.pruefen("1-2-3").unwrap_err();
        assert!(bis > datei::jetzt_ms());
        // gesperrt: auch der richtige Code geht jetzt nicht
        assert!(s.pruefen("7-42-99").is_err());
        let k = s.karte_ausgeben(1000);
        assert!(s.karte_gilt(&k, 1000));
        assert!(!s.karte_gilt(&k, 1001));
        let _ = fs::remove_dir_all(&ordner);
    }
}
