//! USB-Schild über USBGuard: beim ersten Start werden alle eingebauten Geräte (Tastatur, Trackpad, Kamera …)
//! dauerhaft erlaubt, danach ist jedes neue Gerät gesperrt, bis du es zulässt. Schützt vor „Tastatur-Sticks“,
//! die blitzschnell Befehle eintippen.
use crate::DATEN;
use gemeinsam::datei;
use std::path::Path;

#[derive(Clone, Debug)]
pub struct Geraet {
    pub nr: String,
    pub kennung: String,
    pub name: String,
    pub arten: Vec<&'static str>,
}

pub fn vorhanden() -> bool {
    Path::new("/usr/sbin/usbguard-daemon").exists() || Path::new("/usr/bin/usbguard").exists()
}

pub fn eingerichtet() -> bool {
    Path::new(&format!("{}/usb-eingerichtet", DATEN)).exists()
}

pub fn aktiv() -> bool {
    matches!(datei::befehl("systemctl", &["is-active", "usbguard.service"], 10), Some((0, _)))
}

fn zwischen<'a>(z: &'a str, vor: &str) -> Option<&'a str> {
    let i = z.find(vor)? + vor.len();
    let rest = &z[i..];
    let e = rest.find('"')?;
    Some(&rest[..e])
}

fn art_von_klasse(k: &str) -> Option<&'static str> {
    Some(match k.get(0..2)? {
        "03" => "Tastatur/Maus",
        "08" => "Speicher",
        "e0" => "Bluetooth",
        "02" | "0a" => "Netzwerk",
        "0e" => "Kamera",
        "01" => "Ton",
        "07" => "Drucker",
        "09" => "Verteiler",
        "0b" => "Kartenleser",
        "ef" | "ff" => return None,
        _ => "Gerät",
    })
}

/// Zeile von `usbguard list-devices` zerlegen
pub fn zeile_lesen(z: &str) -> Option<Geraet> {
    let (nr, rest) = z.split_once(':')?;
    let nr = nr.trim();
    if nr.is_empty() || !nr.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let kennung = rest.split_whitespace().skip_while(|w| *w != "id").nth(1).unwrap_or("").to_string();
    let name = zwischen(rest, "name \"").unwrap_or("").to_string();
    let mut arten: Vec<&'static str> = Vec::new();
    if let Some(i) = rest.find("with-interface") {
        let s = &rest[i + "with-interface".len()..];
        let s = s.trim_start();
        let teil = if s.starts_with('{') { &s[1..s.find('}').unwrap_or(s.len())] } else { s.split_whitespace().next().unwrap_or("") };
        for k in teil.split_whitespace() {
            if let Some(a) = art_von_klasse(k) {
                if !arten.contains(&a) {
                    arten.push(a);
                }
            }
        }
    }
    Some(Geraet { nr: nr.to_string(), kennung, name, arten })
}

pub fn gesperrte() -> Vec<Geraet> {
    match datei::befehl("usbguard", &["list-devices", "--blocked"], 10) {
        Some((0, t)) => t.lines().filter_map(zeile_lesen).collect(),
        _ => vec![],
    }
}

pub fn zulassen(nr: &str) -> Result<String, String> {
    if nr.is_empty() || !nr.chars().all(|c| c.is_ascii_digit()) {
        return Err("Ungültiges Gerät".into());
    }
    match datei::befehl("usbguard", &["allow-device", "-p", nr], 15) {
        Some((0, _)) => Ok("Zugelassen".into()),
        _ => Err("USBGuard hat das Zulassen abgelehnt (Gerät schon abgezogen?)".into()),
    }
}

/// eingebaute Apple-Geräte nie aussperren (falls sich ihre Kennung doch einmal ändert)
pub fn eingebaut(g: &Geraet) -> bool {
    g.kennung.starts_with("05ac:") && (g.name.contains("Internal") || g.name.contains("FaceTime") || g.name.contains("Bluetooth"))
}

/// Erstes Einrichten: Regel aus den jetzt angeschlossenen Geräten erzeugen und USBGuard einschalten.
/// Geht irgendetwas schief, bleibt USBGuard aus (lieber ungeschützt als ohne Tastatur).
pub fn einrichten() -> Result<String, String> {
    if !vorhanden() {
        return Err("USBGuard ist nicht installiert".into());
    }
    if eingerichtet() {
        return Ok("schon eingerichtet".into());
    }
    let regeln = match datei::befehl("usbguard", &["generate-policy"], 30) {
        Some((0, t)) if t.lines().any(|z| z.starts_with("allow")) => t,
        _ => return Err("Konnte keine Regel für die eingebauten Geräte erzeugen".into()),
    };
    datei::schreiben("/etc/usbguard/rules.conf", regeln.as_bytes(), 0o600).map_err(|e| format!("rules.conf: {}", e))?;
    if !matches!(datei::befehl("systemctl", &["enable", "--now", "usbguard.service"], 40), Some((0, _))) {
        let _ = datei::befehl("systemctl", &["disable", "--now", "usbguard.service"], 40);
        return Err("USBGuard ließ sich nicht starten".into());
    }
    // Sicherheitsnetz: alles, was jetzt angeschlossen ist, muss erlaubt sein
    std::thread::sleep(std::time::Duration::from_secs(2));
    for g in gesperrte() {
        let _ = datei::befehl("usbguard", &["allow-device", "-p", &g.nr], 15);
    }
    let _ = datei::schreiben(&format!("{}/usb-eingerichtet", DATEN), b"1\n", 0o600);
    Ok("eingerichtet".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zeile() {
        let g = zeile_lesen(r#"12: block id 046d:c52b serial "" name "USB Receiver" hash "x" parent-hash "y" via-port "1-2" with-interface { 03:01:01 03:01:02 08:06:50 } with-connect-type "hotplug""#).unwrap();
        assert_eq!(g.nr, "12");
        assert_eq!(g.kennung, "046d:c52b");
        assert_eq!(g.name, "USB Receiver");
        assert_eq!(g.arten, vec!["Tastatur/Maus", "Speicher"]);
        let h = zeile_lesen(r#"3: block id 0781:5583 serial "4C53" name "Ultra Fit" with-interface 08:06:50"#).unwrap();
        assert_eq!(h.arten, vec!["Speicher"]);
    }
}
