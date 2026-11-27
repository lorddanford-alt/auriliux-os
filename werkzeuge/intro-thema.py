#!/usr/bin/env python3
"""Baut aus der Aufnahme des Laser-Intros das Boot-Thema für Plymouth (läuft beim Cloud-Bau im Fedora-Behälter).

  intro-thema.py <aufnahme-ordner> <logo.png> <ausgabe-ordner>

- nimmt die zugeschnittene Logo-Bühne (mit Rand für die Funken), 20 Bilder je Sekunde in Originalgeschwindigkeit
- gleiche Bilder werden nur einmal gespeichert; Farben werden reduziert (kleiner, das Thema liegt im initramfs)
- erzeugt Schild, Linie und Raute für die Festplatten-Passwortabfrage und das Plymouth-Skript
Fehlt die Aufnahme, wird ein ruhiges Thema mit dem fertigen Logo gebaut (nichts bricht ab).
"""
import glob
import hashlib
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROH, LOGO, AUS = sys.argv[1], sys.argv[2], sys.argv[3]
FPS = 20                                    # Plymouth zeichnet 50× je Sekunde, jedes 2,5. Mal ein neues Bild
MASSSTAB = 0.75                             # kleiner speichern (liegt im initramfs), Plymouth vergrößert beim Zeigen
BILDSCHIRM_CSS = 1280                       # aufgenommen mit 1280×800 CSS-Pixeln (wie der Mac), Faktor 2
REFERENZ = 2560                             # Maße der Schild-Bilder beziehen sich auf 2560 Pixel Breite
os.makedirs(AUS, exist_ok=True)


def schrift(groesse):
    for muster in ("/usr/share/fonts/google-noto*/NotoSansMono-Regular.ttf", "/usr/share/fonts/google-noto*/NotoSansMono*.ttf",
                   "/usr/share/fonts/**/NotoSansMono*.ttf", "/System/Library/Fonts/Menlo.ttc"):
        for f in sorted(glob.glob(muster, recursive=True)):
            try:
                return ImageFont.truetype(f, groesse)
            except OSError:
                pass
    return ImageFont.load_default()


def gesperrt(text, f, abstand):
    """Text mit Buchstabenabstand: Breite und Zeichner"""
    breiten = [f.getlength(z) for z in text]
    return sum(breiten) + abstand * (len(text) - 1), breiten


def schild_bilder():
    gold, hell, leise = (230, 189, 87, 255), (246, 220, 140, 255), (160, 142, 108, 255)
    # Überschrift + Hinweis
    f1, f2 = schrift(30), schrift(20)
    t1, t2 = "FESTPLATTE ENTSPERREN", "Passwort eingeben, dann Enter"
    b1, z1 = gesperrt(t1, f1, 9)
    b2, z2 = gesperrt(t2, f2, 2)
    w = int(max(b1, b2)) + 20
    img = Image.new("RGBA", (w, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for (text, f, abstand, breiten, y, farbe, b) in ((t1, f1, 9, z1, 0, gold, b1), (t2, f2, 2, z2, 58, leise, b2)):
        x = (w - b) / 2
        for z, bz in zip(text, breiten):
            d.text((x, y), z, font=f, fill=farbe)
            x += bz + abstand
    img.save(os.path.join(AUS, "titel.png"))
    # goldene Linie, an den Enden ausgeblendet
    feld = Image.new("RGBA", (760, 4), (0, 0, 0, 0))
    for x in range(760):
        a = min(1.0, x / 90, (759 - x) / 90)
        for y in range(4):
            feld.putpixel((x, y), (gold[0], gold[1], gold[2], int(255 * a * (1 if y in (1, 2) else 0.35))))
    feld.save(os.path.join(AUS, "feld.png"))
    # Raute für jedes getippte Zeichen
    r = Image.new("RGBA", (26, 26), (0, 0, 0, 0))
    ImageDraw.Draw(r).polygon([(13, 1), (25, 13), (13, 25), (1, 13)], fill=hell)
    r.save(os.path.join(AUS, "raute.png"))


def aufnahme():
    meta_pfad = os.path.join(ROH, "aufnahme.json")
    if not os.path.exists(meta_pfad):
        return None
    m = json.load(open(meta_pfad))
    F = m.get("zeitlupe", 1.0)
    bilder = sorted(m["bilder"], key=lambda b: b["t"])
    if len(bilder) < 10 or not m.get("fertig"):
        return None
    # Die Bilder sind schon auf die Logo-Bühne zugeschnitten (CSS-Ausschnitt, Faktor 2)
    breite_css = m["ausschnitt"]["width"]
    ende = (m["ende"] - m["start"]) * F
    zeiten = [(bb["t"] - m["start"]) * F for bb in bilder]
    folge, dateien, gesehen = [], {}, {}
    for k in range(int(math.ceil(ende * FPS)) + 1):
        t = k / FPS
        i = max([j for j, z in enumerate(zeiten) if z <= t] or [0])
        if i not in dateien:
            img = Image.open(os.path.join(ROH, bilder[i]["datei"])).convert("RGB")
            img = img.resize((round(img.width * MASSSTAB), round(img.height * MASSSTAB)), Image.LANCZOS)
            q = img.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
            h = hashlib.sha1(q.tobytes()).hexdigest()
            if h not in gesehen:
                nr = len(gesehen)
                q.save(os.path.join(AUS, f"intro-{nr}.png"), optimize=True)
                gesehen[h] = nr
            dateien[i] = gesehen[h]
        folge.append(dateien[i])
    anteil = breite_css / BILDSCHIRM_CSS
    # das letzte Bild auch als ruhiges Logo (falls Plymouth später neu zeichnet)
    return folge, anteil, (m["fertig"] - m["start"]) * F


SKRIPT = r'''# Auriliux OS – Boot-Intro: das Laser-Intro der Auriliux-Webseite (Bild für Bild aufgenommen),
# danach das fertige Goldlogo. Fragt das System nach dem Festplatten-Passwort, erscheint darunter ein
# goldenes Feld mit Rauten – sobald das Intro fertig ist.
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

global.anzahl = @ANZAHL@;
global.anteil = @ANTEIL@;
@FOLGE@
global.bild = -1;
global.takt = 0;
global.fertig = 0;
global.figur = Sprite();
global.figur.SetZ(10);
global.pw_aktiv = 0;
global.pw_punkte = 0;
global.pw_gebaut = 0;

fun lade(nr) {
    if (global.anzahl > 0)
        img = Image("intro-" + nr + ".png");
    else
        img = Image("logo.png");
    ziel = Window.GetWidth() * global.anteil;
    if (img.GetWidth() > ziel * 1.08 || img.GetWidth() < ziel * 0.92)
        img = img.Scale(ziel, img.GetHeight() * ziel / img.GetWidth());
    return img;
}

fun zeigen(img) {
    global.figur.SetImage(img);
    global.figur.SetX(Window.GetX() + Window.GetWidth() / 2 - img.GetWidth() / 2);
    global.figur.SetY(Window.GetY() + Window.GetHeight() * 0.44 - img.GetHeight() / 2);
}

fun skaliert(name) {
    img = Image(name);
    f = Window.GetWidth() / @REFERENZ@;
    if (f < 0.92 || f > 1.08)
        img = img.Scale(img.GetWidth() * f, img.GetHeight() * f);
    return img;
}

fun passwort_bauen() {
    t = skaliert("titel.png");
    l = skaliert("feld.png");
    global.pw_raute = skaliert("raute.png");
    global.pw_titel = Sprite(t);
    global.pw_feld = Sprite(l);
    y = Window.GetY() + Window.GetHeight() * 0.8;
    global.pw_titel.SetPosition(Window.GetX() + Window.GetWidth() / 2 - t.GetWidth() / 2, y - t.GetHeight() - Window.GetHeight() * 0.04, 20);
    global.pw_feld.SetPosition(Window.GetX() + Window.GetWidth() / 2 - l.GetWidth() / 2, y, 20);
    global.pw_y = y - global.pw_raute.GetHeight() - Window.GetHeight() * 0.012;
    global.pw_gebaut = 1;
}

fun passwort_zeichnen() {
    sichtbar = 0;
    if (global.pw_aktiv == 1 && global.fertig == 1)
        sichtbar = 1;
    if (global.pw_gebaut == 0) {
        if (sichtbar == 0)
            return;
        passwort_bauen();
    }
    global.pw_titel.SetOpacity(sichtbar);
    global.pw_feld.SetOpacity(sichtbar);
    zeigbar = global.pw_punkte;
    if (zeigbar > 24)
        zeigbar = 24;
    abstand = global.pw_raute.GetWidth() * 1.6;
    links = Window.GetX() + Window.GetWidth() / 2 - (zeigbar * abstand) / 2;
    for (i = 0; i < 24; i++) {
        if (!global.pw_rauten[i]) {
            global.pw_rauten[i] = Sprite(global.pw_raute);
            global.pw_rauten[i].SetZ(21);
        }
        global.pw_rauten[i].SetX(links + i * abstand);
        global.pw_rauten[i].SetY(global.pw_y);
        if (sichtbar == 1 && i < zeigbar)
            global.pw_rauten[i].SetOpacity(1);
        else
            global.pw_rauten[i].SetOpacity(0);
    }
}

# 50× je Sekunde aufgerufen; das Intro hat @FPS@ Bilder je Sekunde
fun auffrischen() {
    if (global.fertig == 1)
        return;
    global.takt = global.takt + 1;
    nr = Math.Int(global.takt * @FPS@ / 50);
    if (nr == global.bild)
        return;
    if (nr < global.anzahl) {
        zeigen(lade(global.folge[nr]));
        global.bild = nr;
    } else {
        global.fertig = 1;
        passwort_zeichnen();
    }
}

fun bei_passwort(frage, punkte) {
    global.pw_aktiv = 1;
    global.pw_punkte = punkte;
    passwort_zeichnen();
}

fun bei_normal() {
    global.pw_aktiv = 0;
    passwort_zeichnen();
}

if (global.anzahl == 0) {
    zeigen(lade(0));
    global.fertig = 1;
} else {
    zeigen(lade(global.folge[0]));
}
Plymouth.SetRefreshFunction(auffrischen);
Plymouth.SetDisplayPasswordFunction(bei_passwort);
Plymouth.SetDisplayNormalFunction(bei_normal);
'''

THEMA = """[Plymouth Theme]
Name=Auriliux
Description=Laser-Intro der Auriliux-Webseite, danach das Goldlogo
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/auriliux
ScriptFile=/usr/share/plymouth/themes/auriliux/auriliux.script
"""


def main():
    schild_bilder()
    # ruhiges Logo (Rückfall ohne Aufnahme): auf schwarz, Breite wie in der Aufnahme
    logo = Image.open(LOGO).convert("RGBA")
    flaeche = Image.new("RGB", logo.size, (0, 0, 0))
    flaeche.paste(logo, mask=logo.split()[3])
    flaeche.save(os.path.join(AUS, "logo.png"), optimize=True)
    a = None
    try:
        a = aufnahme()
    except Exception as e:  # Aufnahme kaputt → ruhiges Thema
        print("Aufnahme unbrauchbar:", e)
    if a:
        folge, anteil, dauer = a
        zeilen = "\n".join(f"global.folge[{k}] = {n};" for k, n in enumerate(folge))
        anzahl = len(folge)
    else:
        folge, anteil, dauer, zeilen, anzahl = [], 0.52, 0, "", 0
    s = SKRIPT.replace("@ANZAHL@", str(anzahl)).replace("@ANTEIL@", f"{anteil:.4f}").replace("@FOLGE@", zeilen).replace("@REFERENZ@", str(REFERENZ)).replace("@FPS@", str(FPS))
    open(os.path.join(AUS, "auriliux.script"), "w").write(s)
    open(os.path.join(AUS, "auriliux.plymouth"), "w").write(THEMA)
    # wie lange auf das Intro gewartet wird, bevor der Login kommt (Sekunden seit dem Einschalten)
    open(os.path.join(AUS, "dauer"), "w").write(str(int(math.ceil(anzahl / FPS)) + 4 if anzahl else 0))
    groesse = sum(os.path.getsize(os.path.join(AUS, f)) for f in os.listdir(AUS))
    print(f"Boot-Thema: {anzahl} Bilder ({len(set(folge))} verschiedene), {groesse / 1e6:.1f} MB, Intro {dauer:.1f} s")


main()
