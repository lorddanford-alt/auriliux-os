//! Kleines JSON zum Schreiben (Statusdateien) und Lesen (eigene Dateien, `bootc status`).
use std::fmt::Write;

#[derive(Clone, Debug, PartialEq)]
pub enum J {
    Null,
    B(bool),
    I(i64),
    Z(f64),
    T(String),
    L(Vec<J>),
    O(Vec<(String, J)>),
}

impl J {
    pub fn t(s: impl Into<String>) -> J {
        J::T(s.into())
    }

    pub fn o(felder: Vec<(&str, J)>) -> J {
        J::O(felder.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
    }

    pub fn texte(l: &[String]) -> J {
        J::L(l.iter().map(|s| J::T(s.clone())).collect())
    }

    pub fn text(&self) -> String {
        let mut s = String::new();
        self.schreiben(&mut s);
        s
    }

    fn schreiben(&self, s: &mut String) {
        match self {
            J::Null => s.push_str("null"),
            J::B(b) => s.push_str(if *b { "true" } else { "false" }),
            J::I(i) => {
                let _ = write!(s, "{}", i);
            }
            J::Z(z) => {
                if z.is_finite() {
                    let mut t = format!("{:.3}", z);
                    while t.ends_with('0') {
                        t.pop();
                    }
                    if t.ends_with('.') {
                        t.pop();
                    }
                    if t == "-0" {
                        t = "0".into();
                    }
                    s.push_str(&t);
                } else {
                    s.push_str("null");
                }
            }
            J::T(t) => zitieren(t, s),
            J::L(l) => {
                s.push('[');
                for (i, v) in l.iter().enumerate() {
                    if i > 0 {
                        s.push(',');
                    }
                    v.schreiben(s);
                }
                s.push(']');
            }
            J::O(o) => {
                s.push('{');
                for (i, (k, v)) in o.iter().enumerate() {
                    if i > 0 {
                        s.push(',');
                    }
                    zitieren(k, s);
                    s.push(':');
                    v.schreiben(s);
                }
                s.push('}');
            }
        }
    }

    pub fn feld(&self, k: &str) -> Option<&J> {
        match self {
            J::O(o) => o.iter().find(|(n, _)| n == k).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn pfad(&self, p: &[&str]) -> Option<&J> {
        let mut v = self;
        for k in p {
            v = v.feld(k)?;
        }
        Some(v)
    }

    pub fn als_text(&self) -> Option<&str> {
        match self {
            J::T(t) => Some(t),
            _ => None,
        }
    }

    pub fn als_zahl(&self) -> Option<i64> {
        match self {
            J::I(i) => Some(*i),
            J::Z(z) => Some(*z as i64),
            _ => None,
        }
    }

    pub fn als_liste(&self) -> &[J] {
        match self {
            J::L(l) => l,
            _ => &[],
        }
    }

    pub fn ist_null(&self) -> bool {
        matches!(self, J::Null)
    }

    pub fn text_von(&self, k: &str) -> String {
        self.feld(k).and_then(|v| v.als_text()).unwrap_or("").to_string()
    }
}

pub fn zitieren(t: &str, s: &mut String) {
    s.push('"');
    for c in t.chars() {
        match c {
            '"' => s.push_str("\\\""),
            '\\' => s.push_str("\\\\"),
            '\n' => s.push_str("\\n"),
            '\r' => s.push_str("\\r"),
            '\t' => s.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(s, "\\u{:04x}", c as u32);
            }
            c => s.push(c),
        }
    }
    s.push('"');
}

/// JSON-Text lesen; None bei jedem Fehler
pub fn lesen(text: &str) -> Option<J> {
    let mut p = Leser { b: text.as_bytes(), i: 0 };
    let v = p.wert(0)?;
    p.leer();
    if p.i == p.b.len() {
        Some(v)
    } else {
        None
    }
}

struct Leser<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Leser<'a> {
    fn leer(&mut self) {
        while self.i < self.b.len() && matches!(self.b[self.i], b' ' | b'\n' | b'\r' | b'\t') {
            self.i += 1;
        }
    }

    fn wert(&mut self, tiefe: u32) -> Option<J> {
        if tiefe > 64 {
            return None;
        }
        self.leer();
        match *self.b.get(self.i)? {
            b'{' => {
                self.i += 1;
                let mut o = Vec::new();
                self.leer();
                if self.b.get(self.i) == Some(&b'}') {
                    self.i += 1;
                    return Some(J::O(o));
                }
                loop {
                    self.leer();
                    let k = self.kette()?;
                    self.leer();
                    if self.b.get(self.i) != Some(&b':') {
                        return None;
                    }
                    self.i += 1;
                    let v = self.wert(tiefe + 1)?;
                    o.push((k, v));
                    self.leer();
                    match *self.b.get(self.i)? {
                        b',' => self.i += 1,
                        b'}' => {
                            self.i += 1;
                            return Some(J::O(o));
                        }
                        _ => return None,
                    }
                }
            }
            b'[' => {
                self.i += 1;
                let mut l = Vec::new();
                self.leer();
                if self.b.get(self.i) == Some(&b']') {
                    self.i += 1;
                    return Some(J::L(l));
                }
                loop {
                    l.push(self.wert(tiefe + 1)?);
                    self.leer();
                    match *self.b.get(self.i)? {
                        b',' => self.i += 1,
                        b']' => {
                            self.i += 1;
                            return Some(J::L(l));
                        }
                        _ => return None,
                    }
                }
            }
            b'"' => Some(J::T(self.kette()?)),
            b't' => self.wort("true", J::B(true)),
            b'f' => self.wort("false", J::B(false)),
            b'n' => self.wort("null", J::Null),
            _ => self.zahl(),
        }
    }

    fn wort(&mut self, w: &str, v: J) -> Option<J> {
        if self.b[self.i..].starts_with(w.as_bytes()) {
            self.i += w.len();
            Some(v)
        } else {
            None
        }
    }

    fn zahl(&mut self) -> Option<J> {
        let start = self.i;
        while self.i < self.b.len() && matches!(self.b[self.i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') {
            self.i += 1;
        }
        if start == self.i {
            return None;
        }
        let t = std::str::from_utf8(&self.b[start..self.i]).ok()?;
        if let Ok(i) = t.parse::<i64>() {
            return Some(J::I(i));
        }
        t.parse::<f64>().ok().map(J::Z)
    }

    fn hex4(&self, ab: usize) -> Option<u32> {
        let h = std::str::from_utf8(self.b.get(ab..ab + 4)?).ok()?;
        u32::from_str_radix(h, 16).ok()
    }

    fn kette(&mut self) -> Option<String> {
        if self.b.get(self.i) != Some(&b'"') {
            return None;
        }
        self.i += 1;
        let mut out: Vec<u8> = Vec::new();
        loop {
            let c = *self.b.get(self.i)?;
            self.i += 1;
            match c {
                b'"' => break,
                b'\\' => {
                    let e = *self.b.get(self.i)?;
                    self.i += 1;
                    match e {
                        b'"' => out.push(b'"'),
                        b'\\' => out.push(b'\\'),
                        b'/' => out.push(b'/'),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        b'n' => out.push(b'\n'),
                        b'r' => out.push(b'\r'),
                        b't' => out.push(b'\t'),
                        b'u' => {
                            let mut cp = self.hex4(self.i)?;
                            self.i += 4;
                            if (0xD800..0xDC00).contains(&cp)
                                && self.b.get(self.i) == Some(&b'\\')
                                && self.b.get(self.i + 1) == Some(&b'u')
                            {
                                if let Some(lo) = self.hex4(self.i + 2) {
                                    if (0xDC00..0xE000).contains(&lo) {
                                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                        self.i += 6;
                                    }
                                }
                            }
                            let ch = char::from_u32(cp).unwrap_or('\u{fffd}');
                            let mut buf = [0u8; 4];
                            out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                        }
                        _ => return None,
                    }
                }
                c => out.push(c),
            }
        }
        String::from_utf8(out).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hin_und_zurueck() {
        let j = J::o(vec![
            ("a", J::I(3)),
            ("b", J::t("Grüße \"x\"\n")),
            ("c", J::L(vec![J::B(true), J::Null, J::Z(1.5)])),
        ]);
        let t = j.text();
        assert_eq!(lesen(&t), Some(j));
        assert_eq!(lesen(r#"{"x":"ä😀"}"#).unwrap().text_von("x"), "ä😀");
        assert!(lesen("{\"a\":}").is_none());
    }
}
