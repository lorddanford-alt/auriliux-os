#include "waechter.h"
#include <algorithm>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QHash>
#include <QJsonDocument>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QThread>
#include <QtConcurrent/QtConcurrentRun>
#include <csignal>
#include <cstring>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

namespace {
QString guardianStatus() { return qEnvironmentVariable("AURILIUX_GUARDIAN_STATUS", QStringLiteral("/run/auriliux/guardian/status.json")); }
QString herzStatus() { return qEnvironmentVariable("AURILIUX_HERZ_STATUS", QStringLiteral("/run/auriliux/herzschlag/status.json")); }
const char *steuerung = "/run/auriliux/guardian/steuerung.sock";

QString lies(const QString &pfad, qint64 max = 256 * 1024)
{
    QFile f(pfad);
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QString::fromUtf8(f.read(max));
}

qint64 zahlNach(const QString &text, const QString &name)
{
    for (const QString &z : text.split('\n'))
        if (z.startsWith(name)) return z.mid(name.size()).trimmed().section(' ', 0, 0).toLongLong();
    return 0;
}

/// „app-auriliux-google-chrome-48213.scope“ → „google-chrome“
QString kennungAusCgroup(const QString &cgroup)
{
    const QString n = cgroup.trimmed().section('/', -1);
    if (!n.startsWith(QLatin1String("app-auriliux-")) || !n.endsWith(QLatin1String(".scope"))) return {};
    QString rest = n.mid(13, n.size() - 13 - 6);
    const int i = rest.lastIndexOf('-');
    return i > 0 ? rest.left(i) : QString();
}

QVariantMap senden(const QStringList &teile)
{
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return {{"ok", false}, {"fehler", QStringLiteral("Kein Socket")}};
    sockaddr_un a{};
    a.sun_family = AF_UNIX;
    std::strncpy(a.sun_path, steuerung, sizeof(a.sun_path) - 1);
    if (::connect(fd, reinterpret_cast<sockaddr *>(&a), sizeof a) != 0) {
        ::close(fd);
        return {{"ok", false}, {"fehler", QStringLiteral("Der Guardian-Dienst läuft nicht.")}};
    }
    timeval tv{6, 0};
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    QStringList sauber;
    for (QString t : teile) sauber << t.replace('\t', ' ').replace('\n', ' ');
    const QByteArray zeile = sauber.join('\t').toUtf8() + '\n';
    if (::write(fd, zeile.constData(), size_t(zeile.size())) != zeile.size()) {
        ::close(fd);
        return {{"ok", false}, {"fehler", QStringLiteral("Senden fehlgeschlagen")}};
    }
    QByteArray antwort;
    char b[8192];
    ssize_t n;
    while ((n = ::read(fd, b, sizeof b)) > 0) {
        antwort.append(b, n);
        if (antwort.contains('\n') || antwort.size() > 8 * 1024 * 1024) break;
    }
    ::close(fd);
    const QVariantMap m = QJsonDocument::fromJson(antwort.trimmed()).toVariant().toMap();
    if (m.isEmpty()) return {{"ok", false}, {"fehler", QStringLiteral("Keine Antwort vom Guardian")}};
    return m;
}

// ── Übersicht ──
QVariantMap uebersicht()
{
    auto cpuZaehler = [] {
        const QStringList z = lies("/proc/stat").section('\n', 0, 0).split(' ', Qt::SkipEmptyParts);
        qint64 leer = 0, ges = 0;
        for (int i = 1; i < z.size() && i <= 8; ++i) { const qint64 v = z[i].toLongLong(); ges += v; if (i == 4 || i == 5) leer += v; }
        return qMakePair(ges, leer);
    };
    const auto a = cpuZaehler();
    QThread::msleep(1000);
    const auto b = cpuZaehler();
    const double cpu = b.first > a.first ? 1.0 - double(b.second - a.second) / double(b.first - a.first) : 0.0;

    const QString mem = lies("/proc/meminfo");
    const qint64 gesamt = zahlNach(mem, "MemTotal:") * 1024, frei = zahlNach(mem, "MemAvailable:") * 1024;
    const qint64 swap = (zahlNach(mem, "SwapTotal:") - zahlNach(mem, "SwapFree:")) * 1024;
    QStorageInfo platte(QDir::homePath());

    QVariantMap akku;
    for (const QString &n : QDir("/sys/class/power_supply").entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        const QString p = "/sys/class/power_supply/" + n + "/";
        if (lies(p + "type").trimmed() != QLatin1String("Battery")) continue;
        double voll = lies(p + "energy_full").toDouble(), design = lies(p + "energy_full_design").toDouble();
        if (design <= 0) { voll = lies(p + "charge_full").toDouble(); design = lies(p + "charge_full_design").toDouble(); }
        akku = {{"pct", lies(p + "capacity").trimmed().toInt()}, {"cycles", lies(p + "cycle_count").trimmed().toInt()},
                {"health", design > 0 ? voll / design : 0.0}, {"charging", lies(p + "status").trimmed() == QLatin1String("Charging")}};
        break;
    }
    QString cpuName;
    for (const QString &z : lies("/proc/cpuinfo", 16384).split('\n'))
        if (z.startsWith(QLatin1String("model name"))) { cpuName = z.section(':', 1).trimmed(); break; }
    cpuName.remove(QStringLiteral("(R)")).remove(QStringLiteral("(TM)")).remove(QStringLiteral(" CPU"));
    QString os;
    for (const QString &z : lies("/etc/os-release").split('\n'))
        if (z.startsWith(QLatin1String("PRETTY_NAME="))) os = z.mid(12).remove('"');
    return {{"cpu", cpu}, {"cores", QThread::idealThreadCount()}, {"ramUsed", double(gesamt - frei)}, {"ramTotal", double(gesamt)},
            {"swapUsed", double(swap)}, {"diskFree", double(platte.bytesAvailable())}, {"diskTotal", double(platte.bytesTotal())},
            {"battery", akku}, {"uptime", lies("/proc/uptime").section(' ', 0, 0).toDouble()},
            {"model", lies("/sys/class/dmi/id/product_name").trimmed()}, {"cpuName", cpuName}, {"os", os}};
}

// ── Prozesse (Hilfsprozesse werden ihrem Programm zugerechnet) ──
struct Probe { qint64 zeit = 0; qint64 rss = 0; uint uid = 0; QString name, kennung; };

QHash<int, Probe> proben()
{
    QHash<int, Probe> h;
    const long seite = ::sysconf(_SC_PAGESIZE);
    for (const QString &e : QDir("/proc").entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool zahl = false;
        const int pid = e.toInt(&zahl);
        if (!zahl) continue;
        const QString st = lies("/proc/" + e + "/stat", 4096);
        const int auf = st.indexOf('('), zu = st.lastIndexOf(')');
        if (auf < 0 || zu < 0) continue;
        const QStringList f = st.mid(zu + 2).split(' ', Qt::SkipEmptyParts);
        if (f.size() < 22) continue;
        Probe p;
        p.zeit = f[11].toLongLong() + f[12].toLongLong();
        p.rss = f[21].toLongLong() * seite;
        p.name = st.mid(auf + 1, zu - auf - 1);
        p.uid = QFileInfo("/proc/" + e).ownerId();
        p.kennung = kennungAusCgroup(lies("/proc/" + e + "/cgroup", 4096).section('\n', 0, 0));
        h.insert(pid, p);
    }
    return h;
}

QVariantList prozesse()
{
    const auto a = proben();
    QThread::msleep(1500);
    const auto b = proben();
    const double tick = double(::sysconf(_SC_CLK_TCK)) * 1.5;
    const uint ich = ::getuid();
    QHash<QString, QVariantMap> gruppen;
    for (auto it = b.cbegin(); it != b.cend(); ++it) {
        const Probe &p = it.value();
        const double cpu = a.contains(it.key()) ? double(p.zeit - a.value(it.key()).zeit) / tick * 100.0 : 0.0;
        const QString schl = p.kennung.isEmpty() ? p.name + '|' + QString::number(p.uid) : "app:" + p.kennung;
        QVariantMap g = gruppen.value(schl);
        if (g.isEmpty()) {
            g = {{"key", schl}, {"name", p.name}, {"kennung", p.kennung}, {"cpu", 0.0}, {"rss", 0.0}, {"count", 0},
                 {"pids", QVariantList()}, {"eigen", p.uid == ich}, {"system", p.uid < 1000}};
        }
        g["cpu"] = g["cpu"].toDouble() + qMax(0.0, cpu);
        g["rss"] = g["rss"].toDouble() + double(p.rss);
        g["count"] = g["count"].toInt() + 1;
        QVariantList pids = g["pids"].toList();
        pids << it.key();
        g["pids"] = pids;
        gruppen.insert(schl, g);
    }
    QVariantList l;
    for (const auto &g : std::as_const(gruppen))
        if (g["cpu"].toDouble() > 0.3 || g["rss"].toDouble() > 150e6) l << g;
    std::sort(l.begin(), l.end(), [](const QVariant &x, const QVariant &y) { return x.toMap()["cpu"].toDouble() > y.toMap()["cpu"].toDouble(); });
    return l.mid(0, 40);
}

// ── Autostarts ──
QString desktopName(const QString &pfad)
{
    QString name, de;
    bool versteckt = false;
    for (const QString &z : lies(pfad, 65536).split('\n')) {
        if (z.startsWith(QLatin1String("Name="))) name = z.mid(5).trimmed();
        else if (z.startsWith(QLatin1String("Name[de]="))) de = z.mid(9).trimmed();
        else if (z.trimmed() == QLatin1String("Hidden=true")) versteckt = true;
    }
    if (!de.isEmpty()) name = de;
    if (name.isEmpty()) name = QFileInfo(pfad).completeBaseName();
    return versteckt ? name + QStringLiteral(" (ausgeblendet)") : name;
}

QVariantList autostarts()
{
    QVariantList l;
    const QString heim = QDir::homePath();
    auto zeilen = [&](const QString &datei, const QString &bereich, bool geschuetzt) {
        for (QString z : lies(datei).split('\n')) {
            z = z.trimmed();
            if (z.isEmpty() || z.startsWith('#')) continue;
            QString prog = z.section(' ', 0, 0);
            if (prog == QLatin1String("exec")) prog = z.section(' ', 1, 1);
            QString name = QFileInfo(prog).fileName();
            const QString rest = z.section(' ', 1, 1);
            if (name == QLatin1String("auriliux-shell") && !rest.isEmpty()) name = "Auriliux " + rest.left(1).toUpper() + rest.mid(1);
            if (name.isEmpty()) continue;
            l << QVariantMap{{"name", name}, {"pfad", datei}, {"befehl", z}, {"bereich", bereich}, {"geschuetzt", geschuetzt}, {"aktiv", true}};
        }
    };
    zeilen("/etc/xdg/labwc/autostart", "auriliux", true);
    zeilen(heim + "/.config/labwc/autostart", "eigen", false);
    // eigene systemd-Dienste
    QDirIterator it(heim + "/.config/systemd/user", {"*.service", "*.timer"}, QDir::Files | QDir::System, QDirIterator::Subdirectories);
    QSet<QString> gesehen;
    while (it.hasNext()) {
        const QString p = it.next();
        if (!p.contains(QLatin1String(".wants/"))) continue;
        const QString einheit = QFileInfo(p).fileName();
        if (gesehen.contains(einheit)) continue;
        gesehen.insert(einheit);
        l << QVariantMap{{"name", einheit}, {"pfad", p}, {"einheit", einheit}, {"bereich", "dienst"}, {"geschuetzt", false}, {"aktiv", true}};
    }
    // XDG-Autostarts (labwc startet sie nicht von selbst – nur zur Übersicht)
    for (const auto &[ordner, bereich] : {qMakePair(heim + "/.config/autostart", QStringLiteral("xdg-eigen")), qMakePair(QStringLiteral("/etc/xdg/autostart"), QStringLiteral("xdg-system"))})
        for (const QFileInfo &fi : QDir(ordner).entryInfoList({"*.desktop"}, QDir::Files))
            l << QVariantMap{{"name", desktopName(fi.absoluteFilePath())}, {"pfad", fi.absoluteFilePath()}, {"bereich", bereich},
                             {"geschuetzt", bereich == QLatin1String("xdg-system")}, {"aktiv", false}};
    return l;
}

// ── Speicher ──
qint64 ordnerGroesse(const QString &pfad, int grenze)
{
    QFileInfo fi(pfad);
    if (!fi.isDir()) return fi.size();
    qint64 s = 0;
    int n = 0;
    QDirIterator it(pfad, QDir::Files | QDir::Hidden | QDir::System | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (it.hasNext() && n++ < grenze) { it.next(); s += it.fileInfo().size(); }
    return s;
}

QVariantMap speicher()
{
    QVariantList grosse;
    const QString dl = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    for (const QFileInfo &fi : QDir(dl).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot)) {
        const qint64 g = ordnerGroesse(fi.absoluteFilePath(), 50000);
        if (g < 50'000'000) continue;
        QDateTime d = fi.birthTime().isValid() ? fi.birthTime() : fi.lastModified();
        grosse << QVariantMap{{"name", fi.fileName()}, {"pfad", fi.absoluteFilePath()}, {"groesse", double(g)}, {"datum", double(d.toMSecsSinceEpoch())}};
    }
    std::sort(grosse.begin(), grosse.end(), [](const QVariant &a, const QVariant &b) { return a.toMap()["groesse"].toDouble() > b.toMap()["groesse"].toDouble(); });
    QStorageInfo platte(QDir::homePath());
    return {{"downloads", grosse.mid(0, 25)}, {"ordner", dl},
            {"cache", double(ordnerGroesse(QDir::homePath() + "/.cache", 200000))},
            {"papierkorb", double(ordnerGroesse(QDir::homePath() + "/.local/share/Trash/files", 200000))},
            {"frei", double(platte.bytesAvailable())}, {"gesamt", double(platte.bytesTotal())}};
}
} // namespace

Waechter::Waechter(QObject *parent) : QObject(parent)
{
    m_ruhe.setSingleShot(true);
    m_ruhe.setInterval(80);
    connect(&m_ruhe, &QTimer::timeout, this, &Waechter::einlesen);
    m_suche.setInterval(10000);
    connect(&m_suche, &QTimer::timeout, this, [this] { wachen(); einlesen(); });
    m_suche.start();
    wachen();
    einlesen();
}

void Waechter::wachen()
{
    if (!m_wache) {
        m_wache = new QFileSystemWatcher(this);
        connect(m_wache, &QFileSystemWatcher::directoryChanged, this, [this] { m_ruhe.start(); });
        connect(m_wache, &QFileSystemWatcher::fileChanged, this, [this] { m_ruhe.start(); });
    }
    for (const QString &d : {QFileInfo(guardianStatus()).absolutePath(), QFileInfo(herzStatus()).absolutePath()})
        if (QFileInfo(d).isDir() && !m_wache->directories().contains(d)) m_wache->addPath(d);
}

void Waechter::einlesen()
{
    QFile g(guardianStatus());
    const QByteArray roh = g.open(QIODevice::ReadOnly) ? g.readAll() : QByteArray();
    if (roh != m_statusRoh) {
        m_statusRoh = roh;
        m_status = roh.isEmpty() ? QVariantMap() : QJsonDocument::fromJson(roh).toVariant().toMap();
        emit statusGeaendert();
    }
    QFile h(herzStatus());
    QByteArray hroh = h.open(QIODevice::ReadOnly) ? h.readAll() : QByteArray();
    // Herzschlag schreibt mindestens alle 10 s – ältere Daten heißen: Dienst steht
    if (!hroh.isEmpty() && QFileInfo(herzStatus()).lastModified().secsTo(QDateTime::currentDateTime()) > 60
        && !qEnvironmentVariableIsSet("AURILIUX_VORSCHAU"))
        hroh.clear();
    if (hroh != m_herzRoh) {
        m_herzRoh = hroh;
        m_herz = hroh.isEmpty() ? QVariantMap() : QJsonDocument::fromJson(hroh).toVariant().toMap();
        emit herzGeaendert();
    }
}

void Waechter::befehl(const QString &kennung, const QStringList &teile)
{
    auto *w = new QFutureWatcher<QVariantMap>(this);
    connect(w, &QFutureWatcher<QVariantMap>::finished, this, [this, w, kennung] {
        emit antwort(kennung, w->result());
        w->deleteLater();
        m_ruhe.start();
    });
    w->setFuture(QtConcurrent::run([teile] { return senden(teile); }));
}

void Waechter::laden(const QString &art)
{
    auto *w = new QFutureWatcher<QVariant>(this);
    connect(w, &QFutureWatcher<QVariant>::finished, this, [this, w, art] { emit geladen(art, w->result()); w->deleteLater(); });
    w->setFuture(QtConcurrent::run([art]() -> QVariant {
        if (art == QLatin1String("uebersicht")) return uebersicht();
        if (art == QLatin1String("prozesse")) return prozesse();
        if (art == QLatin1String("autostarts")) return autostarts();
        if (art == QLatin1String("speicher")) return speicher();
        return {};
    }));
}

int Waechter::beenden(const QVariantList &pids)
{
    int n = 0;
    const uint ich = ::getuid();
    for (const QVariant &v : pids) {
        const int pid = v.toInt();
        if (pid <= 1 || pid == ::getpid()) continue;
        if (QFileInfo("/proc/" + QString::number(pid)).ownerId() != ich) continue;   // nur eigene
        if (::kill(pid, SIGTERM) == 0) ++n;
    }
    return n;
}

QString Waechter::dienstAbschalten(const QString &einheit)
{
    for (const QChar c : einheit)
        if (!(c.isLetterOrNumber() || c == '-' || c == '_' || c == '.' || c == '@')) return QStringLiteral("Ungültiger Name");
    QProcess p;
    p.start(QStringLiteral("systemctl"), {"--user", "disable", "--now", einheit});
    if (!p.waitForFinished(10000) || p.exitCode() != 0) return QStringLiteral("Abschalten fehlgeschlagen");
    return {};
}

void Waechter::vorneMelden(const QString &kennung, bool vollbild)
{
    const QString inhalt = kennung + '\n' + (vollbild ? '1' : '0') + '\n';
    if (inhalt == m_vorne) return;
    m_vorne = inhalt;
    const QString lauf = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (lauf.isEmpty()) return;
    QDir().mkpath(lauf + "/auriliux");
    QFile f(lauf + "/auriliux/vorne");
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) f.write(inhalt.toUtf8());
}
