#include "weckwort.h"
#include <QElapsedTimer>
#include <QFile>
#include <QMutex>
#include <QRegularExpression>
#include <QtEndian>
#include <cmath>
#include <cstdio>
#include <vector>
#ifdef AURILIUX_WECKWORT
#include "whisper.h"
#endif

namespace {
constexpr int RATE = 16000;
const char *const MODELL = "/usr/share/auriliux/james/ggml-base-q5_1.bin";
QMutex sperre;
#ifdef AURILIUX_WECKWORT
whisper_context *kontext = nullptr;
#endif
QString modellPfad()
{
    const QString eigen = qEnvironmentVariable("AURILIUX_WECKWORT_MODELL");
    return eigen.isEmpty() ? QString::fromLatin1(MODELL) : eigen;
}
} // namespace

bool Weckwort::verfuegbar()
{
#ifdef AURILIUX_WECKWORT
    return QFile::exists(modellPfad());
#else
    return false;
#endif
}

QString Weckwort::erkennen(const QByteArray &pcm16, double *sekunden)
{
#ifdef AURILIUX_WECKWORT
    QMutexLocker l(&sperre);
    QElapsedTimer uhr;
    uhr.start();
    if (!kontext) {
        whisper_log_set([](enum ggml_log_level, const char *, void *) {}, nullptr);      // keine Ausgaben
        whisper_context_params cp = whisper_context_default_params();
        cp.use_gpu = false;
        cp.flash_attn = false;
        kontext = whisper_init_from_file_with_params(modellPfad().toLocal8Bit().constData(), cp);
        if (!kontext) return {};
    }
    const int n = int(pcm16.size() / 2);
    std::vector<float> ton(size_t(qMax(n, RATE)), 0.f);          // mindestens 1 s (Rest Stille)
    for (int i = 0; i < n; ++i) ton[size_t(i)] = qFromLittleEndian<qint16>(pcm16.constData() + 2 * i) / 32768.f;
    whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.n_threads = 2;                                              // der i5 hat zwei Kerne
    p.language = "de";
    p.translate = false;
    p.detect_language = false;
    p.no_context = true;
    p.no_timestamps = true;
    p.single_segment = true;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_special = false;
    p.print_timestamps = false;
    p.suppress_blank = true;
    p.temperature = 0.f;
    p.temperature_inc = 0.f;                                      // kein zweiter Durchgang – schneller
    p.max_tokens = 24;
    // nur so viel „Hörfenster“ rechnen, wie der Schnipsel lang ist (spart den Großteil der Arbeit)
    p.audio_ctx = qBound(128, int(std::ceil(double(ton.size()) / RATE / 30.0 * 1500.0)) + 32, 1500);
    if (whisper_full(kontext, p, ton.data(), int(ton.size())) != 0) return {};
    QString text;
    for (int i = 0; i < whisper_full_n_segments(kontext); ++i)
        text += QString::fromUtf8(whisper_full_get_segment_text(kontext, i));
    if (sekunden) *sekunden = uhr.elapsed() / 1000.0;
    return text.trimmed();
#else
    Q_UNUSED(pcm16);
    if (sekunden) *sekunden = 0;
    return {};
#endif
}

bool Weckwort::enthaelt(const QString &text, const QString &weckwort)
{
    QString t = text.toLower();
    t.replace(QRegularExpression(QStringLiteral("[^\\p{L}\\s']")), QStringLiteral(" "));
    QStringList woerter{QStringLiteral("james"), QStringLiteral("jaymes"), QStringLiteral("jäims"), QStringLiteral("jems"),
                        QStringLiteral("dschejms"), QStringLiteral("dschems"), QStringLiteral("tschems"), QStringLiteral("chames"),
                        QStringLiteral("jeims"), QStringLiteral("dschäims"), QStringLiteral("dschims"), QStringLiteral("jaims")};
    const QString w = weckwort.trimmed().toLower();
    if (!w.isEmpty() && !woerter.contains(w)) woerter << w;
    for (const QString &x : woerter)
        if (t.contains(QRegularExpression(QStringLiteral("(^|\\s)") + QRegularExpression::escape(x) + QStringLiteral("('s)?(\\s|$)"))))
            return true;
    return false;
}

void Weckwort::freigeben()
{
#ifdef AURILIUX_WECKWORT
    QMutexLocker l(&sperre);
    if (kontext) { whisper_free(kontext); kontext = nullptr; }
#endif
}

QByteArray Weckwort::wavLesen(const QString &pfad)
{
    QFile f(pfad);
    if (!f.open(QIODevice::ReadOnly)) return {};
    const QByteArray d = f.readAll();
    if (d.size() < 44 || !d.startsWith("RIFF") || d.mid(8, 4) != "WAVE") return {};
    int kanaele = 1, rate = RATE, bits = 16;
    qsizetype pos = 12, daten = -1, laenge = 0;
    while (pos + 8 <= d.size()) {
        const QByteArray id = d.mid(pos, 4);
        const quint32 groesse = qFromLittleEndian<quint32>(d.constData() + pos + 4);
        if (id == "fmt " && pos + 24 <= d.size()) {
            kanaele = qFromLittleEndian<quint16>(d.constData() + pos + 10);
            rate = int(qFromLittleEndian<quint32>(d.constData() + pos + 12));
            bits = qFromLittleEndian<quint16>(d.constData() + pos + 22);
        } else if (id == "data") {
            daten = pos + 8;
            laenge = qMin<qsizetype>(groesse, d.size() - daten);
            break;
        }
        pos += 8 + groesse + (groesse & 1);
    }
    if (daten < 0 || bits != 16 || kanaele < 1 || rate < 4000) return {};
    const qsizetype rahmen = laenge / (2 * kanaele);
    std::vector<float> mono(size_t(rahmen));
    for (qsizetype i = 0; i < rahmen; ++i) {
        float s = 0;
        for (int k = 0; k < kanaele; ++k) s += qFromLittleEndian<qint16>(d.constData() + daten + 2 * (i * kanaele + k));
        mono[size_t(i)] = s / kanaele;
    }
    QByteArray aus;
    const double schritt = double(rate) / RATE;
    for (double p = 0; p < rahmen - 1; p += schritt) {
        const qsizetype i = qsizetype(p);
        const double a = p - i;
        char b[2];
        qToLittleEndian(qint16(qBound(-32767.0, mono[size_t(i)] * (1 - a) + mono[size_t(i) + 1] * a, 32767.0)), b);
        aus.append(b, 2);
    }
    return aus;
}

int Weckwort::test(int argc, char **argv)
{
    if (!verfuegbar()) { printf("Weckwort: nicht eingebaut oder Modell fehlt (%s)\n", qPrintable(modellPfad())); return 2; }
    int fehler = 0;
    for (int i = 2; i < argc; ++i) {
        // Name der Datei verrät die Erwartung: …-ja.wav enthält „James“, …-nein.wav nicht
        const QString pfad = QString::fromLocal8Bit(argv[i]);
        const QByteArray pcm = wavLesen(pfad);
        double sek = 0;
        const QString t = erkennen(pcm.left(RATE * 2 * 3), &sek);
        const bool ja = enthaelt(t, QStringLiteral("James"));
        const bool erwartet = !pfad.contains(QLatin1String("-nein"));
        if (ja != erwartet) ++fehler;
        printf("%s  %.1f s Ton  →  „%s“  →  %s (%.2f s gerechnet)%s\n", qPrintable(pfad), pcm.size() / 2.0 / RATE, qPrintable(t),
               ja ? "WECKWORT" : "kein Weckwort", sek, ja == erwartet ? "" : "  ← UNERWARTET");
        fflush(stdout);
    }
    printf("Weckwort-Prüfung: %d unerwartet\n", fehler);
    freigeben();
    return 0;
}
