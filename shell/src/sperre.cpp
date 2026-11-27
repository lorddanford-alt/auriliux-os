#include "sperre.h"
#include "anmeldung.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QGuiApplication>
#include <QProcess>
#include <QScreen>
#include <QThread>
#include <QTime>
#include <QtConcurrent/QtConcurrentRun>
#include <QtGui/qguiapplication_platform.h>
#include <QtWaylandClient/qwaylandclientextension.h>
#include <QtWaylandClient/private/qwaylandscreen_p.h>
#include <QtWaylandClient/private/qwaylandshellintegration_p.h>
#include <QtWaylandClient/private/qwaylandshellsurface_p.h>
#include <QtWaylandClient/private/qwaylandwindow_p.h>
#include <wayland-client.h>
#include <security/pam_appl.h>
#include <pwd.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "qwayland-ext-session-lock-v1.h"

// ── Wayland: Sperr-Verwalter (global), die Sperre selbst und je Bildschirm eine Sperrfläche ──
class SperrVerwalter : public QWaylandClientExtensionTemplate<SperrVerwalter>, public QtWayland::ext_session_lock_manager_v1
{
public:
    SperrVerwalter() : QWaylandClientExtensionTemplate<SperrVerwalter>(1) { initialize(); }
};

class SperrObjekt : public QtWayland::ext_session_lock_v1
{
public:
    explicit SperrObjekt(Sperre *s) : m_s(s) {}
protected:
    void ext_session_lock_v1_locked() override { m_s->istGesperrt(); }
    void ext_session_lock_v1_finished() override { m_s->istBeendet(); }
private:
    Sperre *m_s;
};

class SperrFlaeche : public QtWaylandClient::QWaylandShellSurface, public QtWayland::ext_session_lock_surface_v1
{
public:
    SperrFlaeche(QtWayland::ext_session_lock_v1 *sperre, QtWaylandClient::QWaylandWindow *w) : QWaylandShellSurface(w)
    {
        auto *bs = dynamic_cast<QtWaylandClient::QWaylandScreen *>(w->window()->screen()->handle());
        if (!bs || !bs->output() || !sperre->object()) {   // Platzhalter-Bildschirm ist kein QWaylandScreen
            fprintf(stderr, "auriliux-shell sperre: Bildschirm ohne Ausgabe – keine Sperrfläche\n");
            return;
        }
        init(sperre->get_lock_surface(w->wlSurface(), bs->output()));
    }
    ~SperrFlaeche() override { if (object()) destroy(); }

    // erst nach dem ersten „configure“ darf gezeichnet werden, und nie ohne Bild übergeben (sonst Protokollfehler)
    bool isExposed() const override { return m_konfiguriert; }
    bool commitSurfaceRole() const override { return false; }
    void applyConfigure() override { window()->resizeFromApplyConfigure(m_groesse); }

protected:
    void ext_session_lock_surface_v1_configure(uint32_t serial, uint32_t breite, uint32_t hoehe) override
    {
        ack_configure(serial);
        m_groesse = QSize(int(breite), int(hoehe));
        window()->resizeFromApplyConfigure(m_groesse);
        if (!m_konfiguriert) {
            m_konfiguriert = true;
            window()->updateExposure();
        }
    }

private:
    QSize m_groesse;
    bool m_konfiguriert = false;
};

class SperrIntegration : public QtWaylandClient::QWaylandShellIntegration
{
public:
    explicit SperrIntegration(QtWayland::ext_session_lock_v1 *s) : m_s(s) {}
    bool initialize(QtWaylandClient::QWaylandDisplay *) override { return true; }
    QtWaylandClient::QWaylandShellSurface *createShellSurface(QtWaylandClient::QWaylandWindow *w) override
    {
        return new SperrFlaeche(m_s, w);
    }
private:
    QtWayland::ext_session_lock_v1 *m_s;
};

namespace {
void beenden(int code)
{
    // erst ausführen, wenn die Ereignis-Schleife läuft (vorher wäre exit() wirkungslos)
    QMetaObject::invokeMethod(qApp, [code] { QCoreApplication::exit(code); }, Qt::QueuedConnection);
}

QString marke() { return qEnvironmentVariable("XDG_RUNTIME_DIR", QStringLiteral("/tmp")) + QStringLiteral("/auriliux/gesperrt"); }

// ── PAM: Passwort des angemeldeten Benutzers prüfen ──
int gespraech(int n, const pam_message **nachricht, pam_response **antwort, void *daten)
{
    if (n <= 0 || n > PAM_MAX_NUM_MSG) return PAM_CONV_ERR;
    auto *r = static_cast<pam_response *>(calloc(size_t(n), sizeof(pam_response)));
    if (!r) return PAM_BUF_ERR;
    const auto *d = static_cast<const QByteArray *>(daten);     // [0] Passwort, [1] Benutzer
    for (int i = 0; i < n; ++i) {
        const int art = nachricht[i]->msg_style;
        if (art == PAM_PROMPT_ECHO_OFF || art == PAM_PROMPT_ECHO_ON) {
            r[i].resp = strdup((art == PAM_PROMPT_ECHO_OFF ? d[0] : d[1]).constData());
            if (!r[i].resp) {
                for (int j = 0; j < i; ++j) free(r[j].resp);
                free(r);
                return PAM_BUF_ERR;
            }
        }
    }
    *antwort = r;
    return PAM_SUCCESS;
}

int pruefen(const QByteArray &benutzer, const QByteArray &passwort)
{
    QByteArray daten[2] = {passwort, benutzer};
    pam_conv c{gespraech, daten};
    pam_handle_t *h = nullptr;
    int r = pam_start("auriliux-sperre", benutzer.constData(), &c, &h);
    if (r != PAM_SUCCESS) return r;
    r = pam_authenticate(h, 0);
    if (r == PAM_SUCCESS) pam_setcred(h, PAM_REFRESH_CRED);
    pam_end(h, r);
    return r;
}

QString pamText(int r)
{
    switch (r) {
    case PAM_AUTH_ERR: return QStringLiteral("Passwort falsch");
    case PAM_MAXTRIES: case PAM_PERM_DENIED: return QStringLiteral("Zu viele Versuche – kurz warten und noch einmal.");
    case PAM_USER_UNKNOWN: return QStringLiteral("Benutzer unbekannt");
    case PAM_CRED_INSUFFICIENT: case PAM_AUTHINFO_UNAVAIL: return QStringLiteral("Passwort kann gerade nicht geprüft werden");
    default: return QStringLiteral("Prüfung fehlgeschlagen (PAM %1)").arg(r);
    }
}
} // namespace

Sperre::Sperre(QObject *parent) : QObject(parent)
{
    if (const passwd *pw = getpwuid(getuid())) {
        m_benutzer = QString::fromLocal8Bit(pw->pw_name);
        const QString voll = QString::fromLocal8Bit(pw->pw_gecos ? pw->pw_gecos : "").section(',', 0, 0).trimmed();
        m_anzeige = voll.isEmpty() ? m_benutzer : voll;
    }
    if (qEnvironmentVariableIsSet("AURILIUX_VORSCHAU")) m_anzeige = QStringLiteral("Auriliux");
    m_seit = QTime::currentTime().toString(QStringLiteral("HH:mm"));
}

Sperre::~Sperre() = default;   // Wayland-Objekte bleiben bis zum Programmende (ein Abbau würde nichts entsperren)

bool Sperre::einrichten(QQuickWindow *fenster, const QString &bildschirm)
{
    if (!fenster) return false;
    if (!m_verwalter) {
        m_verwalter = new SperrVerwalter;
        if (!m_verwalter->isActive()) {
            fprintf(stderr, "auriliux-shell sperre: Der Fenster-Manager bietet keine Bildschirmsperre (ext-session-lock)\n");
            beenden(4);
            return false;
        }
        m_sperre = new SperrObjekt(this);
        m_sperre->init(m_verwalter->lock());
        m_integration = new SperrIntegration(m_sperre);
    }
    QScreen *s = nullptr;
    for (QScreen *b : QGuiApplication::screens())
        if (b->name() == bildschirm) s = b;
    if (!s) s = QGuiApplication::primaryScreen();
    if (!s) return false;

    fenster->setScreen(s);
    fenster->setGeometry(s->geometry());
    fenster->create();
    auto *ww = dynamic_cast<QtWaylandClient::QWaylandWindow *>(fenster->handle());
    if (!ww) {
        fprintf(stderr, "auriliux-shell sperre: kein Wayland-Fenster\n");
        beenden(4);
        return false;
    }
    ww->setShellIntegration(m_integration);
    // Passwortfeld dort zeigen, wo die Tastatur gerade ist
    connect(fenster, &QWindow::activeChanged, this, [this, fenster, bildschirm] {
        if (fenster->isActive() && m_aktiv != bildschirm) { m_aktiv = bildschirm; emit aktivGeaendert(); }
        else if (!fenster->isActive() && m_aktiv == bildschirm) { m_aktiv.clear(); emit aktivGeaendert(); }
    });
    return true;
}

void Sperre::istGesperrt()
{
    m_gesperrt = true;
    emit gesperrtGeaendert();
    QDir().mkpath(QFileInfo(marke()).absolutePath());
    QFile m(marke());
    if (m.open(QIODevice::WriteOnly | QIODevice::Truncate)) m.write(QByteArray::number(qint64(getpid())));
    fprintf(stderr, "auriliux-shell sperre: gesperrt\n");
    if (m_passwortRichtig) aufheben();
}

void Sperre::istBeendet()
{
    // Fenster-Manager verweigert (schon gesperrt) oder hat die Sperre selbst beendet
    fprintf(stderr, "auriliux-shell sperre: %s\n", m_gesperrt ? "Sperre vom Fenster-Manager beendet" : "Sperre verweigert (schon gesperrt?)");
    if (m_gesperrt) QFile::remove(marke());
    m_gesperrt = false;
    emit gesperrtGeaendert();
    beenden(3);
}

void Sperre::entsperren(const QString &passwort)
{
    if (m_beschaeftigt || m_aufgehoben || m_passwortRichtig) return;
    m_beschaeftigt = true;
    emit beschaeftigtGeaendert();
    // nach mehreren Fehlversuchen immer länger warten (zusätzlich zur Wartezeit von PAM)
    const int warten = m_fehlversuche >= 3 ? qMin(30, (m_fehlversuche - 2) * 3) : 0;
    auto *w = new QFutureWatcher<int>(this);
    connect(w, &QFutureWatcher<int>::finished, this, [this, w] {
        const int r = w->result();
        w->deleteLater();
        m_beschaeftigt = false;
        emit beschaeftigtGeaendert();
        if (r == PAM_SUCCESS) {
            m_passwortRichtig = true;
            m_fehlversuche = 0;
            emit erfolg();
        } else {
            ++m_fehlversuche;
            fprintf(stderr, "auriliux-shell sperre: Anmeldung abgelehnt (PAM %d)\n", r);
            emit fehler(pamText(r));
        }
    });
    w->setFuture(QtConcurrent::run([benutzer = m_benutzer.toLocal8Bit(), pw = passwort.toUtf8(), warten]() mutable {
        if (warten > 0) QThread::sleep(warten);
        const int r = pruefen(benutzer, pw);
        explicit_bzero(pw.data(), size_t(pw.size()));
        return r;
    }));
}

void Sperre::aufheben()
{
    if (!m_passwortRichtig || m_aufgehoben || !m_sperre) return;
    if (!m_gesperrt) return;          // „locked“ kommt noch – dann geht es von dort aus weiter
    m_aufgehoben = true;
    m_sperre->unlock_and_destroy();
    if (auto *wa = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>())
        wl_display_roundtrip(wa->display());
    QFile::remove(marke());
    fprintf(stderr, "auriliux-shell sperre: entsperrt\n");
    beenden(0);
}

void Sperre::energie(const QString &was)
{
    const QString befehl = was == QLatin1String("aus") ? QStringLiteral("poweroff")
                         : was == QLatin1String("neustart") ? QStringLiteral("reboot") : QStringLiteral("suspend");
    QProcess::startDetached(QStringLiteral("systemctl"), {befehl});
}

bool Sperre::grossschreibung() const { return feststelltasteAn(); }
