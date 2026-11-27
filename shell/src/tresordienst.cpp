#include "tresordienst.h"
#include <QFile>
#include <QFileInfo>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QJsonDocument>
#include <QProcess>
#include <QtConcurrent/QtConcurrentRun>
#include <cstring>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

namespace {
const char *const STEUERUNG = "/run/auriliux/tresor/steuerung.sock";
const char *const STATUS = "/run/auriliux/tresor/status.json";

QVariantMap senden(const QStringList &teile)
{
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return {{"ok", false}, {"fehler", QStringLiteral("Kein Socket")}};
    sockaddr_un a{};
    a.sun_family = AF_UNIX;
    std::strncpy(a.sun_path, STEUERUNG, sizeof(a.sun_path) - 1);
    if (::connect(fd, reinterpret_cast<sockaddr *>(&a), sizeof a) != 0) {
        ::close(fd);
        return {{"ok", false}, {"fehler", QStringLiteral("Der Tresor-Dienst läuft nicht.")}};
    }
    // Zurückholen großer Ordner kann dauern
    timeval tv{900, 0};
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    timeval tv2{6, 0};
    ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv2, sizeof tv2);
    QStringList sauber;
    for (QString t : teile) sauber << t.replace('\t', ' ').replace('\n', ' ');
    const QByteArray zeile = sauber.join('\t').toUtf8() + '\n';
    if (::write(fd, zeile.constData(), size_t(zeile.size())) != zeile.size()) {
        ::close(fd);
        return {{"ok", false}, {"fehler", QStringLiteral("Senden fehlgeschlagen")}};
    }
    QByteArray antwort;
    char b[16384];
    ssize_t n;
    while ((n = ::read(fd, b, sizeof b)) > 0) {
        antwort.append(b, n);
        if (antwort.endsWith('\n') || antwort.size() > 32 * 1024 * 1024) break;
    }
    ::close(fd);
    const QVariantMap m = QJsonDocument::fromJson(antwort.trimmed()).toVariant().toMap();
    if (m.isEmpty()) return {{"ok", false}, {"fehler", QStringLiteral("Keine Antwort vom Tresor")}};
    return m;
}
} // namespace

TresorDienst::TresorDienst(QObject *parent) : QObject(parent)
{
    m_ruhe.setSingleShot(true);
    m_ruhe.setInterval(150);
    connect(&m_ruhe, &QTimer::timeout, this, &TresorDienst::lesen);
    m_wache = new QFileSystemWatcher(this);
    m_wache->addPath(QFileInfo(QString::fromLatin1(STATUS)).absolutePath());
    if (QFile::exists(QString::fromLatin1(STATUS))) m_wache->addPath(QString::fromLatin1(STATUS));
    connect(m_wache, &QFileSystemWatcher::directoryChanged, this, [this] { m_ruhe.start(); });
    connect(m_wache, &QFileSystemWatcher::fileChanged, this, [this] { m_ruhe.start(); });
    // falls der Dienst erst später startet
    auto *t = new QTimer(this);
    t->setInterval(5000);
    connect(t, &QTimer::timeout, this, &TresorDienst::lesen);
    t->start();
    lesen();
}

void TresorDienst::lesen()
{
    QVariantMap neu;
    QFile f(QString::fromLatin1(STATUS));
    if (f.open(QIODevice::ReadOnly)) neu = QJsonDocument::fromJson(f.readAll()).toVariant().toMap();
    if (qEnvironmentVariable("AURILIUX_VORSCHAU").startsWith(QLatin1String("tresor")) && neu.isEmpty()) {
        // Vorschau beim Bau: Beispielwerte
        const qint64 jetzt = QDateTime::currentMSecsSinceEpoch();
        neu = {{"schnappschuesse", QVariantMap{{"moeglich", true}, {"grund", ""}, {"anzahl", 31}, {"letzter", jetzt - 1260000}, {"fehler", ""}}},
               {"sicherung", QVariantMap{{"laufwerk", true}, {"eingerichtet", true}, {"laeuft", false}, {"prozent", 0}, {"letzte", jetzt - 3 * 3600000},
                                         {"ergebnis", "ok"}, {"anzahl", 12}}},
               {"code", QVariantMap{{"gesetzt", qEnvironmentVariable("AURILIUX_VORSCHAU") != QLatin1String("tresor-neu")}, {"gesperrtBis", 0}}}};
    }
    if (QFile::exists(QString::fromLatin1(STATUS)) && !m_wache->files().contains(QString::fromLatin1(STATUS)))
        m_wache->addPath(QString::fromLatin1(STATUS));
    if (neu != m_status) {
        m_status = neu;
        emit statusGeaendert();
    }
}

void TresorDienst::befehl(const QString &kennung, const QStringList &teile)
{
    auto *w = new QFutureWatcher<QVariantMap>(this);
    connect(w, &QFutureWatcher<QVariantMap>::finished, this, [this, w, kennung] {
        emit antwort(kennung, w->result());
        w->deleteLater();
        m_ruhe.start();
    });
    w->setFuture(QtConcurrent::run([teile] { return senden(teile); }));
}

void TresorDienst::zeigen(const QString &pfad)
{
    const QFileInfo i(pfad);
    QProcess::startDetached(QStringLiteral("auriliux-shell"), {QStringLiteral("wabenfinder"), i.isDir() ? i.absoluteFilePath() : i.absolutePath()});
}
