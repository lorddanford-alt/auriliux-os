#include "programme.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIcon>
#include <QProcess>
#include <QStandardPaths>
#include <QTextStream>
#include <QLocale>
#include <QRandomGenerator>

namespace {
struct Eintrag { QString name, symbol, exec, datei, wmKlasse, kategorie; bool zeigen = true; };

Eintrag lese(const QString &pfad)
{
    Eintrag e; e.datei = pfad;
    QFile f(pfad);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) { e.zeigen = false; return e; }
    QTextStream s(&f);
    bool imEintrag = false;
    QString nameDe;
    while (!s.atEnd()) {
        const QString z = s.readLine().trimmed();
        if (z.startsWith('[')) { imEintrag = (z == QLatin1String("[Desktop Entry]")); continue; }
        if (!imEintrag || z.startsWith('#')) continue;
        const int g = z.indexOf('=');
        if (g < 0) continue;
        const QString k = z.left(g).trimmed(), v = z.mid(g + 1).trimmed();
        if (k == QLatin1String("Name")) e.name = v;
        else if (k == QLatin1String("Name[de]")) nameDe = v;
        else if (k == QLatin1String("Icon")) e.symbol = v;
        else if (k == QLatin1String("Exec")) e.exec = v;
        else if (k == QLatin1String("StartupWMClass")) e.wmKlasse = v;
        else if (k == QLatin1String("Categories")) e.kategorie = v.section(';', 0, 0);
        else if ((k == QLatin1String("NoDisplay") || k == QLatin1String("Hidden")) && v == QLatin1String("true")) e.zeigen = false;
        else if (k == QLatin1String("Type") && v != QLatin1String("Application")) e.zeigen = false;
    }
    if (!nameDe.isEmpty()) e.name = nameDe;
    if (e.name.isEmpty() || e.exec.isEmpty()) e.zeigen = false;
    return e;
}

QStringList ordner()
{
    QStringList l = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    l << QStringLiteral("/var/lib/flatpak/exports/share/applications")
      << QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications");
    l.removeDuplicates();
    return l;
}

QString kategorieDeutsch(const QString &k)
{
    static const QHash<QString, QString> t{
        {"Network", "Internet"}, {"WebBrowser", "Internet"}, {"Office", "Büro"}, {"Graphics", "Grafik"},
        {"AudioVideo", "Medien"}, {"Audio", "Medien"}, {"Video", "Medien"}, {"Development", "Entwicklung"},
        {"Game", "Spiele"}, {"Settings", "Einstellungen"}, {"System", "System"}, {"Utility", "Werkzeug"},
        {"Education", "Lernen"}, {"Science", "Wissenschaft"}};
    return t.value(k, QStringLiteral("Programm"));
}
} // namespace

Programme::Programme(QObject *parent) : QObject(parent) { neuEinlesen(); }

void Programme::neuEinlesen()
{
    QHash<QString, QVariantMap> nachName;   // gleiche Datei-Namen: der erste Ordner gewinnt (Benutzer vor System)
    for (const QString &o : ordner()) {
        const auto dateien = QDir(o).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &fi : dateien) {
            if (nachName.contains(fi.fileName())) continue;
            const Eintrag e = lese(fi.absoluteFilePath());
            QVariantMap m;
            m.insert("name", e.name); m.insert("symbol", e.symbol); m.insert("datei", e.datei);
            m.insert("kennung", fi.completeBaseName()); m.insert("wmKlasse", e.wmKlasse);
            m.insert("ort", kategorieDeutsch(e.kategorie)); m.insert("zeigen", e.zeigen);
            nachName.insert(fi.fileName(), m);
        }
    }
    QVariantList l;
    for (const auto &m : std::as_const(nachName)) if (m.value("zeigen").toBool()) l << m;
    std::sort(l.begin(), l.end(), [](const QVariant &a, const QVariant &b) {
        return QString::localeAwareCompare(a.toMap().value("name").toString(), b.toMap().value("name").toString()) < 0;
    });
    m_liste = l;
    emit listeGeaendert();
}

QVariantMap Programme::info(const QString &appId) const
{
    if (appId.isEmpty()) return {};
    for (const QVariant &v : m_liste) {
        const QVariantMap m = v.toMap();
        if (m.value("kennung").toString().compare(appId, Qt::CaseInsensitive) == 0
            || m.value("wmKlasse").toString().compare(appId, Qt::CaseInsensitive) == 0
            || m.value("kennung").toString().endsWith('.' + appId, Qt::CaseInsensitive))
            return m;
    }
    return {};
}

bool Programme::starten(const QString &datei) const
{
    const Eintrag e = lese(datei);
    if (e.exec.isEmpty()) return false;
    // Platzhalter (%f, %u, …) entfernen, %% → %
    QString cmd = e.exec;
    static const QStringList platzhalter{"%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%i", "%c", "%k", "%v", "%m"};
    for (const QString &p : platzhalter) cmd.remove(p);
    cmd.replace(QLatin1String("%%"), QLatin1String("%"));
    QStringList teile = QProcess::splitCommand(cmd.trimmed());
    if (teile.isEmpty()) return false;
    const QString prog = teile.takeFirst();
    // Jedes Programm in einen eigenen Bereich (systemd-Scope) – so kann der Herzschlag dem vorderen Programm
    // Vorrang geben und im Vollbild die anderen einfrieren. Name: app-auriliux-<kennung>-<zufall>.scope
    static const bool mitBereich = !QStandardPaths::findExecutable(QStringLiteral("systemd-run")).isEmpty()
        && QFileInfo::exists(qEnvironmentVariable("XDG_RUNTIME_DIR") + QStringLiteral("/systemd/private"));
    if (mitBereich) {
        QString k;
        for (const QChar c : QFileInfo(datei).completeBaseName())
            k += (c.unicode() < 128 && (c.isLetterOrNumber() || c == '.' || c == '_' || c == '-')) ? c : QChar('_');
        const QString einheit = QStringLiteral("app-auriliux-%1-%2").arg(k).arg(QRandomGenerator::global()->bounded(100000, 999999));
        QStringList a{"--user", "--scope", "--quiet", "--collect", "--slice=app.slice", "--unit=" + einheit, "--", prog};
        a += teile;
        if (QProcess::startDetached(QStringLiteral("systemd-run"), a)) return true;
    }
    return QProcess::startDetached(prog, teile);
}

QPixmap SymbolBild::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    const int k = requestedSize.width() > 0 ? requestedSize.width() : 64;
    QIcon icon = id.startsWith('/') ? QIcon(id) : QIcon::fromTheme(id);
    if (icon.isNull()) icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
    QPixmap p = icon.pixmap(QSize(k, k));
    if (size) *size = p.size();
    return p;
}
