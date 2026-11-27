#include "sperrwache.h"
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QSettings>
#include <QTimer>
#include <QtGui/qguiapplication_platform.h>
#include <QtWaylandClient/qwaylandclientextension.h>
#include <functional>
#include <csignal>
#include <cstdio>
#include <unistd.h>
#include "qwayland-ext-idle-notify-v1.h"

class LeerlaufMelder : public QWaylandClientExtensionTemplate<LeerlaufMelder>, public QtWayland::ext_idle_notifier_v1
{
public:
    LeerlaufMelder() : QWaylandClientExtensionTemplate<LeerlaufMelder>(1) { initialize(); }
};

class Leerlauf : public QtWayland::ext_idle_notification_v1
{
public:
    explicit Leerlauf(std::function<void()> f) : m_f(std::move(f)) {}
protected:
    void ext_idle_notification_v1_idled() override { m_f(); }
    void ext_idle_notification_v1_resumed() override {}
private:
    std::function<void()> m_f;
};

namespace {
const QString LOGIN = QStringLiteral("org.freedesktop.login1");
const QString PFAD = QStringLiteral("/org/freedesktop/login1");
const QString VERWALTUNG = QStringLiteral("org.freedesktop.login1.Manager");
const QString SPERREN = QStringLiteral("/usr/libexec/auriliux/sperren");
}

Sperrwache::Sperrwache(QObject *parent) : QObject(parent)
{
    // 1) Leerlauf
    const QSettings e(QDir::homePath() + QStringLiteral("/.config/auriliux/sperre.conf"), QSettings::IniFormat);
    const int minuten = qBound(0, e.value(QStringLiteral("sperren_nach_minuten"), 5).toInt(), 24 * 60);
    auto *wa = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
    m_melder = new LeerlaufMelder;
    if (minuten > 0 && m_melder->isActive() && wa && wa->seat()) {
        m_leerlauf = new Leerlauf([this] { sperren(); });
        m_leerlauf->init(m_melder->get_idle_notification(uint32_t(minuten) * 60000u, wa->seat()));
        fprintf(stderr, "auriliux-shell sperrwache: sperrt nach %d Minuten ohne Eingabe\n", minuten);
    } else {
        fprintf(stderr, "auriliux-shell sperrwache: kein automatisches Sperren bei Leerlauf (%s)\n",
                minuten == 0 ? "abgeschaltet" : "Fenster-Manager meldet keinen Leerlauf");
    }

    // 2) logind: „loginctl lock-session“ und Ruhezustand
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        fprintf(stderr, "auriliux-shell sperrwache: kein Systembus – Sperren vor dem Ruhezustand nicht möglich\n");
        return;
    }
    QDBusInterface v(LOGIN, PFAD, VERWALTUNG, bus);
    QString sitzung;
    const QDBusReply<QDBusObjectPath> s = v.call(QStringLiteral("GetSessionByPID"), uint(getpid()));
    if (s.isValid()) sitzung = s.value().path();
    else if (const QString id = qEnvironmentVariable("XDG_SESSION_ID"); !id.isEmpty()) {
        const QDBusReply<QDBusObjectPath> s2 = v.call(QStringLiteral("GetSession"), id);
        if (s2.isValid()) sitzung = s2.value().path();
    }
    if (!sitzung.isEmpty())
        bus.connect(LOGIN, sitzung, QStringLiteral("org.freedesktop.login1.Session"), QStringLiteral("Lock"), this, SLOT(sperren()));
    else
        fprintf(stderr, "auriliux-shell sperrwache: Sitzung bei logind nicht gefunden\n");
    bus.connect(LOGIN, PFAD, VERWALTUNG, QStringLiteral("PrepareForSleep"), this, SLOT(schlaf(bool)));
    hemmen();
}

bool Sperrwache::istGesperrt()
{
    QFile m(qEnvironmentVariable("XDG_RUNTIME_DIR", QStringLiteral("/tmp")) + QStringLiteral("/auriliux/gesperrt"));
    if (!m.open(QIODevice::ReadOnly)) return false;
    const qint64 pid = m.readAll().trimmed().toLongLong();
    return pid > 0 && ::kill(pid_t(pid), 0) == 0;
}

void Sperrwache::sperren()
{
    // doppelte Auslöser (Leerlauf + Deckel zu) kurz hintereinander nur einmal
    const qint64 jetzt = QDateTime::currentMSecsSinceEpoch();
    if (istGesperrt() || jetzt - m_letzterStart < 3000) return;
    m_letzterStart = jetzt;
    QProcess::startDetached(SPERREN, {});
}

void Sperrwache::schlaf(bool beginnt)
{
    if (!beginnt) { hemmen(); return; }      // aufgewacht → für das nächste Mal wieder aufhalten
    sperren();
    // höchstens 3 Sekunden warten, bis die Sperre steht – dann darf der Mac schlafen
    auto *uhr = new QElapsedTimer;
    uhr->start();
    auto *t = new QTimer(this);
    t->setInterval(100);
    connect(t, &QTimer::timeout, this, [this, t, uhr] {
        if (!istGesperrt() && uhr->elapsed() < 3000) return;
        t->stop();
        t->deleteLater();
        delete uhr;
        QTimer::singleShot(300, this, [this] { m_hemmer = QDBusUnixFileDescriptor(); });   // ein Bild Zeit zum Zeichnen
    });
    t->start();
}

void Sperrwache::hemmen()
{
    if (m_hemmer.isValid()) return;
    QDBusInterface v(LOGIN, PFAD, VERWALTUNG, QDBusConnection::systemBus());
    const QDBusReply<QDBusUnixFileDescriptor> r = v.call(QStringLiteral("Inhibit"), QStringLiteral("sleep"), QStringLiteral("Auriliux"),
                                                         QStringLiteral("Bildschirm vor dem Ruhezustand sperren"), QStringLiteral("delay"));
    if (r.isValid()) m_hemmer = r.value();
    else fprintf(stderr, "auriliux-shell sperrwache: Ruhezustand lässt sich nicht aufhalten: %s\n", qPrintable(r.error().message()));
}
