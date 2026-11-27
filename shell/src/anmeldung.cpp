#include "anmeldung.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>
#include <QThread>
#include <QtConcurrent/QtConcurrentRun>
#include <cstring>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

namespace {
QString merkDatei() { return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/auriliux-anmeldung"); }

// ── greetd: Nachricht = 4 Byte Länge (Maschinen-Reihenfolge) + JSON ──
bool senden(int fd, const QJsonObject &o)
{
    const QByteArray j = QJsonDocument(o).toJson(QJsonDocument::Compact);
    const quint32 n = quint32(j.size());
    return ::write(fd, &n, 4) == 4 && ::write(fd, j.constData(), size_t(j.size())) == j.size();
}

bool alles(int fd, char *b, size_t n)
{
    size_t da = 0;
    while (da < n) {
        const ssize_t r = ::read(fd, b + da, n - da);
        if (r <= 0) return false;
        da += size_t(r);
    }
    return true;
}

QJsonObject empfangen(int fd)
{
    quint32 n = 0;
    if (!alles(fd, reinterpret_cast<char *>(&n), 4) || n > 1024 * 1024) return {};
    QByteArray j(int(n), '\0');
    if (!alles(fd, j.data(), n)) return {};
    return QJsonDocument::fromJson(j).object();
}

QString deutsch(const QString &t)
{
    if (t.contains(QLatin1String("expired"), Qt::CaseInsensitive)) return QStringLiteral("Das Passwort ist abgelaufen.");
    if (t.contains(QLatin1String("locked"), Qt::CaseInsensitive) || t.contains(QLatin1String("Maximum"), Qt::CaseInsensitive))
        return QStringLiteral("Zu viele Versuche – kurz warten und noch einmal.");
    return t;
}

/// leerer Text = Erfolg (Sitzung ist bestellt), sonst Fehlermeldung
QString greetd(const QString &benutzer, const QString &passwort)
{
    const QByteArray pfad = qgetenv("GREETD_SOCK");
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return QStringLiteral("Anmeldedienst nicht erreichbar");
    sockaddr_un a{};
    a.sun_family = AF_UNIX;
    std::strncpy(a.sun_path, pfad.constData(), sizeof(a.sun_path) - 1);
    if (::connect(fd, reinterpret_cast<sockaddr *>(&a), sizeof a) != 0) { ::close(fd); return QStringLiteral("Anmeldedienst nicht erreichbar"); }
    timeval tv{30, 0};
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

    QString ergebnis = QStringLiteral("Anmeldung fehlgeschlagen");
    QJsonObject r;
    if (senden(fd, {{"type", "create_session"}, {"username", benutzer}})) r = empfangen(fd);
    for (int runde = 0; runde < 12 && !r.isEmpty(); ++runde) {
        const QString typ = r.value("type").toString();
        if (typ == QLatin1String("success")) {
            // Passwort stimmt → Sitzung bestellen; greetd startet sie, sobald die Anmeldung sich beendet
            const QJsonObject start{{"type", "start_session"},
                                    {"cmd", QJsonArray{"labwc"}},
                                    {"env", QJsonArray{"XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=labwc", "XDG_CURRENT_DESKTOP=labwc:wlroots"}}};
            if (senden(fd, start)) {
                const QJsonObject s = empfangen(fd);
                if (s.value("type").toString() == QLatin1String("success")) { ::close(fd); return {}; }
                ergebnis = deutsch(s.value("description").toString());
            }
            break;
        }
        if (typ == QLatin1String("error")) {
            ergebnis = r.value("error_type").toString() == QLatin1String("auth_error") ? QStringLiteral("Passwort falsch")
                                                                                      : deutsch(r.value("description").toString());
            break;
        }
        if (typ == QLatin1String("auth_message")) {
            const QString art = r.value("auth_message_type").toString();
            QJsonObject antwort{{"type", "post_auth_message_response"}};
            if (art == QLatin1String("secret")) antwort.insert("response", passwort);
            else if (art == QLatin1String("visible")) antwort.insert("response", benutzer);
            if (!senden(fd, antwort)) break;
            r = empfangen(fd);
            continue;
        }
        break;
    }
    senden(fd, {{"type", "cancel_session"}});
    empfangen(fd);
    ::close(fd);
    return ergebnis.isEmpty() ? QStringLiteral("Anmeldung fehlgeschlagen") : ergebnis;
}
} // namespace

Anmeldung::Anmeldung(QObject *parent) : QObject(parent)
{
    // normale Benutzer aus /etc/passwd (mit echter Anmelde-Shell)
    QFile f(QStringLiteral("/etc/passwd"));
    if (f.open(QIODevice::ReadOnly)) {
        for (const QByteArray &z : f.readAll().split('\n')) {
            const QList<QByteArray> t = z.split(':');
            if (t.size() < 7) continue;
            const uint uid = t[2].toUInt();
            const QString shell = QString::fromUtf8(t[6]);
            if (uid < 1000 || uid >= 60000 || shell.endsWith(QLatin1String("nologin")) || shell.endsWith(QLatin1String("false"))) continue;
            const QString name = QString::fromUtf8(t[0]);
            QString voll = QString::fromUtf8(t[4]).section(',', 0, 0).trimmed();
            m_benutzer << QVariantMap{{"name", name}, {"anzeige", voll.isEmpty() ? name : voll}};
        }
    }
    if (m_benutzer.isEmpty() && !qEnvironmentVariableIsSet("GREETD_SOCK"))
        m_benutzer << QVariantMap{{"name", "nutzer"}, {"anzeige", "Auriliux"}};   // Vorschau
    QFile m(merkDatei());
    if (m.open(QIODevice::ReadOnly)) m_letzter = QString::fromUtf8(m.readAll()).trimmed();
}

void Anmeldung::anmelden(const QString &benutzer, const QString &passwort)
{
    if (m_beschaeftigt) return;
    m_beschaeftigt = true;
    emit beschaeftigtGeaendert();
    auto *w = new QFutureWatcher<QString>(this);
    connect(w, &QFutureWatcher<QString>::finished, this, [this, w, benutzer] {
        const QString f = w->result();
        w->deleteLater();
        m_beschaeftigt = false;
        emit beschaeftigtGeaendert();
        if (f.isEmpty()) {
            QDir().mkpath(QFileInfo(merkDatei()).absolutePath());
            QFile m(merkDatei());
            if (m.open(QIODevice::WriteOnly | QIODevice::Truncate)) m.write(benutzer.toUtf8());
            emit erfolg();
        } else {
            emit fehler(f);
        }
    });
    w->setFuture(QtConcurrent::run([benutzer, passwort]() -> QString {
        if (!qEnvironmentVariableIsSet("GREETD_SOCK")) {          // Vorschau ohne greetd
            QThread::msleep(500);
            return passwort == QLatin1String("auriliux") ? QString() : QStringLiteral("Passwort falsch");
        }
        return greetd(benutzer, passwort);
    }));
}

void Anmeldung::energie(const QString &was)
{
    if (!qEnvironmentVariableIsSet("GREETD_SOCK")) return;
    const QString befehl = was == QLatin1String("aus") ? QStringLiteral("poweroff")
                         : was == QLatin1String("neustart") ? QStringLiteral("reboot") : QStringLiteral("suspend");
    QProcess::startDetached(QStringLiteral("systemctl"), {befehl});
}

bool feststelltasteAn()
{
    const QDir d(QStringLiteral("/sys/class/leds"));
    for (const QString &n : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (!n.endsWith(QLatin1String("capslock"))) continue;
        QFile f(d.filePath(n) + QStringLiteral("/brightness"));
        if (f.open(QIODevice::ReadOnly) && f.readAll().trimmed() != "0") return true;
    }
    return false;
}

bool Anmeldung::grossschreibung() const { return feststelltasteAn(); }
