#include "klang.h"
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QtEndian>
#include <algorithm>
#include <cmath>
#include <random>
#include <vector>

namespace {
constexpr int RATE = 44100;
constexpr double PI = 3.14159265358979323846;

struct Ton {
    std::vector<double> s;
    explicit Ton(double sek) : s(size_t(sek * RATE), 0.0) {}
    void addiere(double ab, const std::vector<double> &t, double laut) {
        const size_t o = size_t(ab * RATE);
        for (size_t i = 0; i < t.size() && o + i < s.size(); ++i) s[o + i] += t[i] * laut;
    }
};

std::mt19937 &zufall() { static std::mt19937 z(4711); return z; }
double rauschen() { static std::uniform_real_distribution<double> v(-1.0, 1.0); return v(zufall()); }

/// kurzer metallischer Klick: Rauschstoß + gedämpfte Schwingungen
std::vector<double> klick(double dauer, double abkling, const std::vector<double> &freq, double rausch)
{
    std::vector<double> t(size_t(dauer * RATE));
    double tp = 0;
    for (size_t i = 0; i < t.size(); ++i) {
        const double x = double(i) / RATE;
        const double huelle = std::exp(-x / abkling);
        double w = 0;
        for (size_t k = 0; k < freq.size(); ++k) w += std::sin(2 * PI * freq[k] * x) / double(k + 1);
        tp += 0.35 * (rauschen() - tp);                     // etwas tiefpassgefiltertes Rauschen
        t[i] = huelle * (w * (1 - rausch) + tp * rausch * 2.2);
    }
    return t;
}

/// tiefer Schlag (Riegel, Tür)
std::vector<double> schlag(double dauer, double f0, double f1, double abkling)
{
    std::vector<double> t(size_t(dauer * RATE));
    double phase = 0, tp = 0;
    for (size_t i = 0; i < t.size(); ++i) {
        const double x = double(i) / RATE;
        const double f = f0 + (f1 - f0) * x / dauer;
        phase += 2 * PI * f / RATE;
        tp += 0.05 * (rauschen() - tp);
        t[i] = std::exp(-x / abkling) * (std::sin(phase) * 0.8 + std::sin(phase * 2.01) * 0.2 + tp * 1.5);
    }
    return t;
}

Ton erzeugen(const QString &name)
{
    if (name == QLatin1String("klick")) {
        Ton t(0.03);
        t.addiere(0, klick(0.03, 0.0025, {3100, 5200, 7900}, 0.45), 0.55);
        return t;
    }
    if (name == QLatin1String("rast")) {
        Ton t(0.16);
        t.addiere(0, klick(0.05, 0.006, {1450, 2900}, 0.5), 0.7);
        t.addiere(0.004, schlag(0.15, 180, 120, 0.035), 0.6);
        return t;
    }
    if (name == QLatin1String("fehler")) {
        Ton t(0.42);
        t.addiere(0, schlag(0.16, 140, 110, 0.05), 0.8);
        t.addiere(0.2, schlag(0.2, 120, 90, 0.06), 0.8);
        return t;
    }
    if (name == QLatin1String("ventil")) {
        // Ratsche: Klicks, die erst schneller und dann langsamer werden (wie das Drehen des Rads)
        Ton t(1.55);
        double ab = 0.0;
        for (int i = 0; ab < 1.45; ++i) {
            t.addiere(ab, klick(0.04, 0.005, {900 + 60.0 * (i % 3), 2300}, 0.6), 0.5);
            const double p = ab / 1.45;
            ab += 0.11 - 0.07 * std::sin(PI * p);
        }
        t.addiere(0, schlag(1.5, 60, 55, 0.8), 0.12);
        return t;
    }
    if (name == QLatin1String("riegel")) {
        Ton t(0.6);
        std::vector<double> glitt(size_t(0.45 * RATE));
        double tp = 0;
        for (size_t i = 0; i < glitt.size(); ++i) {
            const double x = double(i) / glitt.size();
            tp += 0.08 * (rauschen() - tp);
            glitt[i] = tp * std::sin(PI * x) * 2.0;
        }
        t.addiere(0, glitt, 0.5);
        t.addiere(0.42, schlag(0.18, 160, 95, 0.04), 0.9);
        t.addiere(0.42, klick(0.04, 0.004, {2100, 3400}, 0.4), 0.4);
        return t;
    }
    // Tür: schweres Aufschwingen – leises Knarren und tiefes Rauschen
    Ton t(1.4);
    double phase = 0, tp = 0;
    for (size_t i = 0; i < t.s.size(); ++i) {
        const double x = double(i) / RATE;
        const double huelle = std::sin(PI * std::min(1.0, x / 1.35)) * 0.9;
        phase += 2 * PI * (85 + 18 * std::sin(2 * PI * 2.3 * x)) / RATE;
        tp += 0.02 * (rauschen() - tp);
        const double knarren = (std::fmod(phase, 2 * PI) < 0.5 ? 1.0 : 0.0) * 0.08 * std::max(0.0, std::sin(PI * x / 0.7));
        t.s[i] = huelle * (std::sin(phase) * 0.25 + tp * 2.5 + knarren);
    }
    return t;
}

QByteArray wav(const Ton &t)
{
    QByteArray pcm;
    pcm.resize(qsizetype(t.s.size() * 2));
    double spitze = 0.0001;
    for (double v : t.s) spitze = std::max(spitze, std::abs(v));
    const double f = std::min(1.0, 0.85 / spitze);
    for (size_t i = 0; i < t.s.size(); ++i) {
        const qint16 v = qint16(std::lround(std::clamp(t.s[i] * f, -1.0, 1.0) * 32000));
        qToLittleEndian(v, pcm.data() + 2 * i);
    }
    QByteArray k("RIFF");
    auto u32 = [&k](quint32 v) { char b[4]; qToLittleEndian(v, b); k.append(b, 4); };
    auto u16 = [&k](quint16 v) { char b[2]; qToLittleEndian(v, b); k.append(b, 2); };
    u32(quint32(36 + pcm.size()));
    k.append("WAVEfmt ");
    u32(16); u16(1); u16(1); u32(RATE); u32(RATE * 2); u16(2); u16(16);
    k.append("data");
    u32(quint32(pcm.size()));
    return k + pcm;
}
} // namespace

QUrl Klang::datei(const QString &name) const
{
    static const QStringList bekannt{"klick", "rast", "fehler", "ventil", "riegel", "tuer"};
    if (!bekannt.contains(name)) return {};
    QString ordner = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (ordner.isEmpty()) ordner = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    ordner += QStringLiteral("/auriliux/klang");
    const QString pfad = ordner + '/' + name + QStringLiteral("-1.wav");
    if (!QFile::exists(pfad)) {
        QDir().mkpath(ordner);
        QFile f(pfad + QStringLiteral(".neu"));
        if (!f.open(QIODevice::WriteOnly)) return {};
        f.write(wav(erzeugen(name)));
        f.close();
        QFile::remove(pfad);
        if (!f.rename(pfad)) return {};
    }
    return QUrl::fromLocalFile(pfad);
}
