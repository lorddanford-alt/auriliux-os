// Weckwort „James“: erkennt auf diesem Rechner selbst – ohne Internet –, ob in einem kurzen Sprachschnipsel
// „James“ gesagt wurde (Spracherkennung whisper.cpp mit dem Modell ggml-base-q5_1 in /usr/share/auriliux/james).
// Erst wenn das Weckwort erkannt ist, geht die Aufnahme an deinen Server; alles andere bleibt hier und wird verworfen.
#pragma once
#include <QByteArray>
#include <QString>

namespace Weckwort {
/// eingebaut und Modell vorhanden?
bool verfuegbar();
/// Text eines Schnipsels (16 kHz, mono, 16 bit). Dauert 0,2–1 s → nur in einem Hintergrund-Thread aufrufen.
QString erkennen(const QByteArray &pcm16, double *sekunden = nullptr);
/// kommt das Weckwort (oder eine typische Verhörung davon) im Text vor?
bool enthaelt(const QString &text, const QString &weckwort);
/// Modell aus dem Arbeitsspeicher nehmen (z. B. wenn James ausgeschaltet wird)
void freigeben();
/// Prüfung im Bau: auriliux-shell james-weckwort-test <wav> … (gibt erkannten Text und Treffer aus)
int test(int argc, char **argv);
/// WAV-Datei (16 bit PCM, beliebige Abtastrate/Kanäle) als 16 kHz mono 16 bit
QByteArray wavLesen(const QString &pfad);
}
