//! Quarantäne: gefährliche Dateien werden in einen Ordner verschoben, den nur root lesen darf.
//! Sie lassen sich später unverändert zurückholen (ohne Ausführrecht) oder endgültig löschen.
use crate::DATEN;
use gemeinsam::datei;
use gemeinsam::json::{self, J};
use std::fs;
use std::os::unix::fs::{chown, MetadataExt, PermissionsExt};
use std::path::Path;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;

static NUMMER: AtomicU32 = AtomicU32::new(0);

#[derive(Clone)]
pub struct Eintrag {
    pub id: String,
    pub zeit: i64,
    pub uid: u32,
    pub original: String,
    pub grund: String,
    pub groesse: u64,
}

pub struct Quarantaene {
    liste: Mutex<Vec<Eintrag>>,
}

fn ordner() -> String {
    format!("{}/quarantaene", DATEN)
}
fn liste_datei() -> String {
    format!("{}/quarantaene.json", DATEN)
}

impl Eintrag {
    fn json(&self) -> J {
        J::o(vec![
            ("id", J::t(&self.id)),
            ("zeit", J::I(self.zeit)),
            ("uid", J::I(self.uid as i64)),
            ("original", J::t(&self.original)),
            ("name", J::t(self.original.rsplit('/').next().unwrap_or(""))),
            ("grund", J::t(&self.grund)),
            ("groesse", J::I(self.groesse as i64)),
        ])
    }
}

impl Quarantaene {
    pub fn laden() -> Quarantaene {
        let _ = fs::create_dir_all(ordner());
        let _ = fs::set_permissions(ordner(), fs::Permissions::from_mode(0o700));
        let mut l = Vec::new();
        if let Some(j) = json::lesen(&datei::lies(liste_datei())) {
            for e in j.als_liste() {
                let id = e.text_von("id");
                if id.is_empty() || !Path::new(&format!("{}/{}", ordner(), id)).exists() {
                    continue;
                }
                l.push(Eintrag {
                    id,
                    zeit: e.feld("zeit").and_then(|v| v.als_zahl()).unwrap_or(0),
                    uid: e.feld("uid").and_then(|v| v.als_zahl()).unwrap_or(0) as u32,
                    original: e.text_von("original"),
                    grund: e.text_von("grund"),
                    groesse: e.feld("groesse").and_then(|v| v.als_zahl()).unwrap_or(0) as u64,
                });
            }
        }
        Quarantaene { liste: Mutex::new(l) }
    }

    fn speichern(l: &[Eintrag]) {
        let j = J::L(l.iter().map(|e| e.json()).collect());
        let _ = datei::schreiben(&liste_datei(), j.text().as_bytes(), 0o600);
    }

    pub fn json(&self) -> J {
        let l = self.liste.lock().unwrap_or_else(|e| e.into_inner());
        J::L(l.iter().rev().take(60).map(|e| e.json()).collect())
    }

    pub fn anzahl(&self) -> usize {
        self.liste.lock().map(|l| l.len()).unwrap_or(0)
    }

    /// Datei wegsperren. Liefert den Eintrag oder eine deutsche Fehlermeldung.
    pub fn einsperren(&self, pfad: &str, uid: u32, grund: &str) -> Result<Eintrag, String> {
        let meta = fs::symlink_metadata(pfad).map_err(|_| "Die Datei ist nicht mehr da.".to_string())?;
        let id = format!("q{}-{}", datei::jetzt_ms(), NUMMER.fetch_add(1, Ordering::Relaxed));
        let ziel = format!("{}/{}", ordner(), id);
        if fs::rename(pfad, &ziel).is_err() {
            // anderes Laufwerk (USB-Stick): kopieren, dann am Ursprung löschen
            fs::copy(pfad, &ziel).map_err(|e| format!("Konnte nicht wegsperren: {}", e))?;
            if fs::remove_file(pfad).is_err() {
                let _ = fs::remove_file(&ziel);
                return Err("Die Datei lässt sich am Ursprungsort nicht entfernen.".into());
            }
        }
        let _ = chown(&ziel, Some(0), Some(0));
        let _ = fs::set_permissions(&ziel, fs::Permissions::from_mode(0o000));
        let e = Eintrag {
            id,
            zeit: datei::jetzt_ms(),
            uid: if uid == 0 { meta.uid() } else { uid },
            original: pfad.to_string(),
            grund: grund.to_string(),
            groesse: meta.len(),
        };
        let mut l = self.liste.lock().unwrap_or_else(|e| e.into_inner());
        l.push(e.clone());
        Quarantaene::speichern(&l);
        Ok(e)
    }

    fn nehmen(&self, id: &str, wer: u32) -> Result<Eintrag, String> {
        let l = self.liste.lock().unwrap_or_else(|e| e.into_inner());
        let e = l.iter().find(|e| e.id == id).cloned().ok_or("Unbekannter Eintrag")?;
        if wer != 0 && wer != e.uid {
            return Err("Diese Datei gehört einem anderen Benutzer.".into());
        }
        Ok(e)
    }

    fn entfernen(&self, id: &str) {
        let mut l = self.liste.lock().unwrap_or_else(|e| e.into_inner());
        l.retain(|e| e.id != id);
        Quarantaene::speichern(&l);
    }

    /// zurück an den alten Ort (ohne Ausführrecht). Ist der Name belegt, kommt „(zurückgeholt)“ dazu.
    pub fn zurueckholen(&self, id: &str, wer: u32) -> Result<String, String> {
        let e = self.nehmen(id, wer)?;
        let quelle = format!("{}/{}", ordner(), e.id);
        let mut ziel = e.original.clone();
        if Path::new(&ziel).exists() {
            let p = Path::new(&e.original);
            let stamm = p.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
            let endung = p.extension().map(|s| format!(".{}", s.to_string_lossy())).unwrap_or_default();
            let eltern = p.parent().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
            ziel = format!("{}/{} (zurückgeholt){}", eltern, stamm, endung);
        }
        let eltern = Path::new(&ziel).parent().ok_or("Ungültiger Ort")?;
        if !eltern.is_dir() {
            return Err("Der ursprüngliche Ordner existiert nicht mehr.".into());
        }
        if fs::rename(&quelle, &ziel).is_err() {
            fs::copy(&quelle, &ziel).map_err(|e| format!("Zurückholen fehlgeschlagen: {}", e))?;
            let _ = fs::remove_file(&quelle);
        }
        let _ = chown(&ziel, Some(e.uid), Some(gemeinsam::sys::gid_von(e.uid)));
        let _ = fs::set_permissions(&ziel, fs::Permissions::from_mode(0o600));
        self.entfernen(id);
        Ok(format!("Zurückgeholt nach {}", ziel))
    }

    pub fn loeschen(&self, id: &str, wer: u32) -> Result<String, String> {
        let e = self.nehmen(id, wer)?;
        let _ = fs::remove_file(format!("{}/{}", ordner(), e.id));
        self.entfernen(id);
        Ok("Endgültig gelöscht".into())
    }
}
