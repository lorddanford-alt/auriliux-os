#include "james.h"
#include "klang.h"
#include "programme.h"
#include "weckwort.h"
#include <QtConcurrent>
#include <QAudioDevice>
#include <QAudioFormat>
#include <QAudioOutput>
#include <QAudioSource>
#include <QBuffer>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QHttpMultiPart>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QMediaDevices>
#include <QMediaPlayer>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSoundEffect>
#include <QStandardPaths>
#include <QtEndian>
#include <cmath>
#include <cstring>
#include <QHash>
#include <cstdio>
#include <sys/stat.h>
#include <vector>

namespace {
constexpr int RATE = 16000;                 // Aufnahme für den Server: 16 kHz, mono, 16 bit
constexpr int RAHMEN = 480;                 // 30 ms

QString konfigOrdner() { return QDir::homePath() + QStringLiteral("/.config/auriliux"); }
QString konfigPfad() { return konfigOrdner() + QStringLiteral("/james.json"); }
QString schalterPfad() { return konfigOrdner() + QStringLiteral("/ki-schalter"); }
QString laufOrdner()
{
    QString r = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (r.isEmpty()) r = QDir::tempPath();
    return r + QStringLiteral("/auriliux");
}
QString steuerPfad() { return laufOrdner() + QStringLiteral("/james.sock"); }

/// kurzes Protokoll ohne Inhalte (was du sagst, bleibt privat): ~/.local/state/auriliux/james.log
void protokoll(const QString &s)
{
    const QString ordner = QDir::homePath() + QStringLiteral("/.local/state/auriliux");
    QDir().mkpath(ordner);
    const QString pfad = ordner + QStringLiteral("/james.log");
    if (QFileInfo(pfad).size() > 512 * 1024) { QFile::remove(pfad + QStringLiteral(".1")); QFile::rename(pfad, pfad + QStringLiteral(".1")); }
    QFile f(pfad);
    const QString z = QDateTime::currentDateTime().toString(Qt::ISODate) + QStringLiteral("  ") + s + '\n';
    if (f.open(QIODevice::Append | QIODevice::Text)) f.write(z.toUtf8());
    if (qEnvironmentVariableIsSet("AURILIUX_DIAGNOSE")) fprintf(stderr, "james: %s\n", qPrintable(s));
}

QByteArray wavKopf(qsizetype bytes)
{
    QByteArray k("RIFF");
    auto u32 = [&k](quint32 v) { char b[4]; qToLittleEndian(v, b); k.append(b, 4); };
    auto u16 = [&k](quint16 v) { char b[2]; qToLittleEndian(v, b); k.append(b, 2); };
    u32(quint32(36 + bytes));
    k.append("WAVEfmt ");
    u32(16); u16(1); u16(1); u32(RATE); u32(RATE * 2); u16(2); u16(16);
    k.append("data");
    u32(quint32(bytes));
    return k;
}

bool schreibeGeschuetzt(const QString &pfad, const QByteArray &inhalt)
{
    QDir().mkpath(QFileInfo(pfad).absolutePath());
    const mode_t alt = ::umask(077);                 // neue Datei nur für dich lesbar (0600)
    QSaveFile f(pfad);
    bool ok = f.open(QIODevice::WriteOnly) && f.write(inhalt) == inhalt.size() && f.commit();
    ::umask(alt);
    if (ok) QFile::setPermissions(pfad, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return ok;
}

QString lies(const QString &pfad)
{
    QFile f(pfad);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}
} // namespace

JamesDienst::JamesDienst(QObject *parent) : QObject(parent)
{
    m_netz = new QNetworkAccessManager(this);
    konfigLaden();
    schalterLesen();
    QDir().mkpath(konfigOrdner());
    m_wache = new QFileSystemWatcher(this);
    m_wache->addPath(konfigOrdner());
    auto neuBeobachten = [this] {
        for (const QString &p : {konfigPfad(), schalterPfad()})
            if (QFile::exists(p) && !m_wache->files().contains(p)) m_wache->addPath(p);
    };
    neuBeobachten();
    auto geaendert = [this, neuBeobachten] { konfigLaden(); schalterLesen(); neuBeobachten(); };
    connect(m_wache, &QFileSystemWatcher::directoryChanged, this, geaendert);
    connect(m_wache, &QFileSystemWatcher::fileChanged, this, geaendert);

    m_blasenUhr.setSingleShot(true);
    connect(&m_blasenUhr, &QTimer::timeout, this, [this] {
        if (m_zustand == QLatin1String("hinweis") || (m_zustand == QLatin1String("spricht") && !beschaeftigt())) blase({}, {});
    });
    m_ohrFrist.setSingleShot(true);
    connect(&m_ohrFrist, &QTimer::timeout, this, [this] {
        if (m_aufnehmen) return;
        ohrStoppen();
        if (m_zustand == QLatin1String("hoert") || m_zustand == QLatin1String("gespraech")) blase({}, {});
    });
    m_lauschTakt.setInterval(2000);
    connect(&m_lauschTakt, &QTimer::timeout, this, &JamesDienst::lauschenPruefen);
    connect(&m_probeTakt, &QTimer::timeout, this, [this] {
        if (!m_simuliert) { m_probeTakt.stop(); return; }
        const QByteArray stueck = m_probeTon.left(RAHMEN * 2);
        m_probeTon.remove(0, stueck.size());
        if (!stueck.isEmpty()) tonVerarbeiten(stueck);
        if (m_probeTon.isEmpty() && m_simuliert) ohrStoppen();
    });
    m_sprechWache.setSingleShot(true);
    connect(&m_sprechWache, &QTimer::timeout, this, &JamesDienst::teilGespielt);

    // Fenster: alle 10 s nachsehen, ob der Hintergrund-Dienst läuft (für die Anzeige „Stimme bereit“)
    auto *t = new QTimer(this);
    t->setInterval(10000);
    connect(t, &QTimer::timeout, this, &JamesDienst::dienstPruefen);
    t->start();
    QTimer::singleShot(0, this, &JamesDienst::dienstPruefen);
}

JamesDienst::~JamesDienst()
{
    if (m_lauf && m_lauf->state() != QProcess::NotRunning) {
        m_laufGrund = QStringLiteral("James beendet wurde");
        m_lauf->kill();
        m_lauf->waitForFinished(2000);
    }
}

// ════════ Einstellungen ════════

void JamesDienst::konfigLaden()
{
    const QJsonObject o = QJsonDocument::fromJson(lies(konfigPfad()).toUtf8()).object();
    const QString s = o.value(QStringLiteral("server")).toString(), t = o.value(QStringLiteral("token")).toString();
    if (s != m_server || t != m_token) {
        m_server = s; m_token = t;
        emit konfigGeaendert();
    }
}

void JamesDienst::schalterLesen()
{
    const bool weck = lies(konfigOrdner() + QStringLiteral("/james-weckwort")).trimmed() != QLatin1String("aus");
    if (weck != m_weckwortAn) {
        m_weckwortAn = weck;
        emit weckwortGeaendert();
        if (!weck) Weckwort::freigeben();
        if (m_istDienst) { protokoll(weck ? QStringLiteral("Weckwort an") : QStringLiteral("Weckwort aus")); QTimer::singleShot(0, this, &JamesDienst::lauschenPruefen); }
    }
    const bool neu = lies(schalterPfad()).trimmed() == QLatin1String("an");
    if (neu == m_an) return;
    m_an = neu;
    emit anGeaendert();
    if (!m_istDienst) return;
    protokoll(m_an ? QStringLiteral("Schalter an") : QStringLiteral("Schalter aus"));
    if (!m_an) {
        stoppen();
        blase({}, {});
        auftragAbbrechen(QStringLiteral("KI wurde ausgeschaltet"));
        Weckwort::freigeben();                            // Spracherkennung aus dem Arbeitsspeicher
    }
    QTimer::singleShot(0, this, &JamesDienst::lauschenPruefen);
    QTimer::singleShot(300, this, &JamesDienst::herzschlag);
}

void JamesDienst::setAn(bool an)
{
    if (QFile f(schalterPfad()); QDir().mkpath(konfigOrdner()) && f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(an ? "an" : "aus");
    schalterLesen();
}

QString JamesDienst::serverName() const
{
    const QUrl u(m_server);
    return u.host() + (u.path().size() > 1 ? u.path().chopped(u.path().endsWith('/') ? 1 : 0) : QString());
}

QString JamesDienst::einrichten(const QString &adresse, const QString &schluessel)
{
    QString a = adresse.trimmed();
    if (a.isEmpty()) return QStringLiteral("Bitte die Adresse deines Servers eingeben.");
    if (!a.contains(QStringLiteral("://"))) a.prepend(QStringLiteral("https://"));
    a.remove(QRegularExpression(QStringLiteral("/(index|api)\\.php.*$")));
    QUrl u(a);
    if (!u.isValid() || u.host().isEmpty()) return QStringLiteral("Diese Adresse ist ungültig.");
    const bool lokal = u.host() == QLatin1String("localhost") || u.host() == QLatin1String("127.0.0.1");
    if (u.scheme() != QLatin1String("https") && !(u.scheme() == QLatin1String("http") && lokal))
        return QStringLiteral("Bitte eine https-Adresse eingeben – nur so ist die Verbindung verschlüsselt.");
    u.setQuery(QString()); u.setFragment(QString()); u.setUserInfo(QString());
    QString s = u.toString();
    if (!s.endsWith('/')) s += '/';
    QString t = schluessel.trimmed();
    if (t.isEmpty()) {
        if (m_token.size() < 32) return QStringLiteral("Bitte den App-Schlüssel eingeben.");
        t = m_token;
    } else if (t.size() < 32 || t.contains(QRegularExpression(QStringLiteral("\\s")))) {
        return QStringLiteral("Der App-Schlüssel ist zu kurz (mindestens 32 Zeichen, ohne Leerzeichen).");
    }
    const QJsonObject o{{QStringLiteral("server"), s}, {QStringLiteral("token"), t}};
    if (!schreibeGeschuetzt(konfigPfad(), QJsonDocument(o).toJson()))
        return QStringLiteral("Konnte die Einstellungen nicht speichern.");
    m_server = s; m_token = t;
    emit konfigGeaendert();
    protokoll(QStringLiteral("Eingerichtet: ") + u.host());
    post(QStringLiteral("zustand"), {}, 15000, [this](const QVariantMap &o, int status) {
        if (o.value(QStringLiteral("ok")).toBool()) {
            const QString n = o.value(QStringLiteral("name")).toString();
            if (!n.isEmpty() && n != m_name) { m_name = n; emit nameGeaendert(); }
            emit einrichtungGeprueft(true, QStringLiteral("Verbunden mit %1 (Server-Version %2)").arg(m_name, o.value(QStringLiteral("version")).toString()));
        } else if (status == 401) {
            emit einrichtungGeprueft(false, QStringLiteral("Der Server lehnt den App-Schlüssel ab – bitte app_token aus config.php prüfen."));
        } else {
            emit einrichtungGeprueft(false, o.value(QStringLiteral("fehler")).toString());
        }
    });
    return {};
}

// ════════ Verbindung ════════

QNetworkRequest JamesDienst::anfrageBauen(const QString &aktion, const QString &zusatz, int timeoutMs) const
{
    QNetworkRequest r(QUrl(m_server + QStringLiteral("api.php?a=") + aktion + zusatz));
    r.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
    r.setRawHeader("X-KI-Token", m_token.toUtf8());          // manche Hoster entfernen „Authorization“
    r.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    r.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Auriliux-James/1.0"));
    r.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    r.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::SameOriginRedirectPolicy);
    if (timeoutMs > 0) r.setTransferTimeout(timeoutMs);
    return r;
}

void JamesDienst::verbindungMerken(bool ok, const QString &fehler)
{
    if (ok == m_verbunden && fehler == m_verbindungsFehler) return;
    m_verbunden = ok; m_verbindungsFehler = fehler;
    emit verbundenGeaendert();
}

void JamesDienst::post(const QString &aktion, const QVariantMap &daten, int timeoutMs, std::function<void(const QVariantMap &, int)> fertig)
{
    if (!eingerichtet()) {
        fertig({{QStringLiteral("ok"), false}, {QStringLiteral("fehler"), QStringLiteral("James ist noch nicht eingerichtet.")}}, 0);
        return;
    }
    QNetworkReply *a = m_netz->post(anfrageBauen(aktion, {}, timeoutMs), QJsonDocument(QJsonObject::fromVariantMap(daten)).toJson(QJsonDocument::Compact));
    connect(a, &QNetworkReply::finished, this, [this, a, fertig] {
        a->deleteLater();
        const int status = a->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonDocument d = QJsonDocument::fromJson(a->readAll());
        QVariantMap o = d.isObject() ? d.object().toVariantMap() : QVariantMap{};
        const bool netz = status == 0;
        if (o.isEmpty()) {
            o[QStringLiteral("ok")] = false;
            o[QStringLiteral("fehler")] = netz ? QStringLiteral("Server nicht erreichbar (%1)").arg(a->errorString())
                                               : QStringLiteral("Unerwartete Antwort vom Server (HTTP %1)").arg(status);
        }
        o[QStringLiteral("_status")] = status;
        verbindungMerken(!netz && status != 401, netz ? QStringLiteral("Server nicht erreichbar")
                                                      : status == 401 ? QStringLiteral("App-Schlüssel abgelehnt") : QString());
        fertig(o, status);
    });
}

void JamesDienst::anfrage(const QString &kennung, const QString &aktion, const QVariantMap &daten, const QString &zusatz)
{
    static const QRegularExpression name(QStringLiteral("^[a-z_]{2,40}$")), extra(QStringLiteral("^(&[a-z]{1,12}=[0-9A-Za-z_.%-]{0,200})*$"));
    if (!name.match(aktion).hasMatch() || !extra.match(zusatz).hasMatch()) {
        emit antwort(kennung, {{QStringLiteral("ok"), false}, {QStringLiteral("fehler"), QStringLiteral("Ungültige Anfrage")}});
        return;
    }
    if (zusatz.isEmpty()) {
        post(aktion, daten, 30000, [this, kennung](const QVariantMap &o, int) { emit antwort(kennung, o); });
        return;
    }
    // mit Zusatz (z. B. ältere Nachrichten): eigener Weg, damit der Zusatz in der Adresse landet
    if (!eingerichtet()) { emit antwort(kennung, {{QStringLiteral("ok"), false}}); return; }
    QNetworkReply *a = m_netz->post(anfrageBauen(aktion, zusatz, 30000), QJsonDocument(QJsonObject::fromVariantMap(daten)).toJson(QJsonDocument::Compact));
    connect(a, &QNetworkReply::finished, this, [this, a, kennung] {
        a->deleteLater();
        QVariantMap o = QJsonDocument::fromJson(a->readAll()).object().toVariantMap();
        if (o.isEmpty()) o[QStringLiteral("ok")] = false;
        emit antwort(kennung, o);
    });
}

QNetworkReply *JamesDienst::liveStarten(const QString &text, const QString &modus,
                                        std::function<void(const QVariantMap &)> zeile, std::function<void(const QString &, int)> ende)
{
    if (!eingerichtet()) {
        QTimer::singleShot(0, this, [ende] { ende(QStringLiteral("James ist noch nicht eingerichtet."), 0); });
        return nullptr;
    }
    const QJsonObject o{{QStringLiteral("text"), text}, {QStringLiteral("modus"), modus}};
    QNetworkReply *a = m_netz->post(anfrageBauen(QStringLiteral("senden_live"), {}, 120000), QJsonDocument(o).toJson(QJsonDocument::Compact));
    auto puffer = std::make_shared<QByteArray>();
    auto auswerten = [zeile](const QByteArray &roh) {
        const QByteArray z = roh.trimmed();
        if (z.isEmpty()) return;                                 // Fülltext gegen den Zwischenspeicher des Hosters
        const QJsonDocument d = QJsonDocument::fromJson(z);
        if (!d.isObject()) return;
        QVariantMap m = d.object().toVariantMap();
        if (!m.contains(QStringLiteral("t")) && m.contains(QStringLiteral("fehler"))) {   // Server lehnt ab (z. B. James aus)
            m[QStringLiteral("t")] = QStringLiteral("fehler");
            m[QStringLiteral("text")] = m.value(QStringLiteral("fehler"));
        }
        zeile(m);
    };
    connect(a, &QNetworkReply::readyRead, this, [a, puffer, auswerten] {
        puffer->append(a->readAll());
        qsizetype nl;
        while ((nl = puffer->indexOf('\n')) >= 0) {
            const QByteArray z = puffer->left(nl);
            puffer->remove(0, nl + 1);
            auswerten(z);
        }
        if (puffer->size() > 4 * 1024 * 1024) puffer->clear();
    });
    connect(a, &QNetworkReply::finished, this, [this, a, puffer, auswerten, ende] {
        a->deleteLater();
        puffer->append(a->readAll());
        auswerten(*puffer);
        puffer->clear();
        const int status = a->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const bool abgebrochen = a->error() == QNetworkReply::OperationCanceledError;
        if (!abgebrochen) verbindungMerken(status != 0 && status != 401, status == 0 ? QStringLiteral("Server nicht erreichbar") : QString());
        ende(abgebrochen ? QStringLiteral("abgebrochen") : status == 0 ? a->errorString() : QString(), status);
    });
    return a;
}

void JamesDienst::senden(const QString &text)
{
    if (m_chat) m_chat->abort();
    m_chat = liveStarten(text.left(20000), QStringLiteral("chat"),
        [this](const QVariantMap &o) {
            const QString t = o.value(QStringLiteral("t")).toString();
            if (t == QLatin1String("text") || t == QLatin1String("fertig") || t == QLatin1String("fehler")) emit live(t, o);
        },
        [this](const QString &f, int status) {
            emit live(QStringLiteral("ende"), {{QStringLiteral("fehler"), f}, {QStringLiteral("status"), status}});
        });
}

void JamesDienst::sendenAbbrechen()
{
    if (m_chat) m_chat->abort();
}

void JamesDienst::webseite() const
{
    if (m_server.isEmpty()) return;
    const QString ziel = m_server + QStringLiteral("index.php");
    if (!QProcess::startDetached(QStringLiteral("google-chrome-stable"), {QStringLiteral("--app=") + ziel}))
        QProcess::startDetached(QStringLiteral("xdg-open"), {ziel});
}

// ════════ Steuerung über den Socket ════════

int JamesDienst::befehlSenden(const QString &b)
{
    QLocalSocket s;
    s.connectToServer(steuerPfad());
    if (!s.waitForConnected(800)) { fprintf(stderr, "James-Dienst läuft nicht.\n"); return 3; }
    s.write(b.toUtf8().left(4000) + '\n');
    s.flush();
    s.waitForBytesWritten(800);
    QByteArray r;
    while (s.waitForReadyRead(1500)) { r += s.readAll(); if (r.contains('\n')) break; }
    fprintf(stdout, "%s", r.constData());
    return r.startsWith("ok") ? 0 : 1;
}

bool JamesDienst::befehl(const QString &b)
{
    QLocalSocket s;
    s.connectToServer(steuerPfad());
    if (!s.waitForConnected(400)) {
        if (m_dienstLaeuft) { m_dienstLaeuft = false; emit dienstGeaendert(); }
        return false;
    }
    s.write(b.toUtf8().left(4000) + '\n');
    s.waitForBytesWritten(400);
    s.waitForReadyRead(800);
    return s.readAll().startsWith("ok");
}

void JamesDienst::dienstPruefen()
{
    if (m_istDienst) return;
    QLocalSocket s;
    s.connectToServer(steuerPfad());
    const bool laeuft = s.waitForConnected(150);
    s.abort();
    if (laeuft != m_dienstLaeuft) { m_dienstLaeuft = laeuft; emit dienstGeaendert(); }
}

void JamesDienst::dienst()
{
    if (m_istDienst) return;
    {
        QLocalSocket s;
        s.connectToServer(steuerPfad());
        if (s.waitForConnected(300)) {
            fprintf(stderr, "James-Dienst läuft schon.\n");
            QMetaObject::invokeMethod(QCoreApplication::instance(), [] { QCoreApplication::exit(0); }, Qt::QueuedConnection);
            return;
        }
    }
    m_istDienst = true;
    QDir().mkpath(laufOrdner());
    QFile::setPermissions(laufOrdner(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    QLocalServer::removeServer(steuerPfad());
    m_steuerung = new QLocalServer(this);
    m_steuerung->setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_steuerung->listen(steuerPfad())) protokoll(QStringLiteral("Steuerung nicht möglich: ") + m_steuerung->errorString());
    connect(m_steuerung, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *s = m_steuerung->nextPendingConnection()) {
            connect(s, &QLocalSocket::disconnected, s, &QObject::deleteLater);
            connect(s, &QLocalSocket::readyRead, this, [this, s] {
                if (!s->canReadLine()) { if (s->bytesAvailable() > 8000) s->abort(); return; }
                const QString b = QString::fromUtf8(s->readLine()).trimmed();
                QJsonObject st{{QStringLiteral("zustand"), m_zustand}, {QStringLiteral("an"), m_an},
                               {QStringLiteral("verbunden"), m_verbunden}, {QStringLiteral("auftrag"), m_auftragText},
                               {QStringLiteral("lauscht"), m_lauscht}, {QStringLiteral("weckwort"), Weckwort::verfuegbar() && m_weckwortAn}};
                s->write("ok " + QJsonDocument(st).toJson(QJsonDocument::Compact) + '\n');
                s->flush();
                s->disconnectFromServer();
                befehlAusfuehren(b);
            });
        }
    });
    m_dienstLaeuft = true;
    emit dienstGeaendert();

    // Ruhezustand: vorher alles anhalten (logind meldet es)
    QDBusConnection::systemBus().connect(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                                         QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("PrepareForSleep"),
                                         this, SLOT(schlafSignal(bool)));
    m_seitImpuls.start();
    m_takt.setInterval(30000);
    m_takt.setTimerType(Qt::VeryCoarseTimer);
    connect(&m_takt, &QTimer::timeout, this, &JamesDienst::herzschlag);
    m_takt.start();
    QTimer::singleShot(2500, this, &JamesDienst::herzschlag);
    m_lauschTakt.start();
    protokoll(QStringLiteral("Dienst gestartet") + (Weckwort::verfuegbar() ? QStringLiteral(" (Weckwort eingebaut)") : QString()));
}

void JamesDienst::schlafSignal(bool schlaeft)
{
    m_schlaeft = schlaeft;
    if (schlaeft) {
        protokoll(QStringLiteral("Ruhezustand"));
        auftragAbbrechen(QStringLiteral("der Rechner in den Ruhezustand ging"));
        stoppen();
        blase({}, {});
    } else {
        QTimer::singleShot(3000, this, &JamesDienst::herzschlag);
    }
}

void JamesDienst::befehlAusfuehren(const QString &b)
{
    if (!m_istDienst) return;
    if (b == QLatin1String("hoeren")) hoerenUmschalten();
    else if (b == QLatin1String("stopp")) { stoppen(); blase({}, {}); }
    else if (b.startsWith(QLatin1String("vorlesen "))) vorlesenId(b.mid(9).toInt());
    else if (b.startsWith(QLatin1String("probe-wav ")) && qEnvironmentVariableIsSet("AURILIUX_VORSCHAU")) probeWav(b.mid(10).trimmed());
    else if (b == QLatin1String("probe") && qEnvironmentVariableIsSet("AURILIUX_VORSCHAU")) {
        // Bau-Prüfung ohne Mikrofon: 1,2 s Ton als „Aufnahme“ an den Server (die Attrappe schreibt einen festen Satz ab)
        QByteArray pcm(RATE * 12 / 10 * 2, Qt::Uninitialized);
        for (int i = 0; i < RATE * 12 / 10; ++i)
            qToLittleEndian(qint16(6000 * std::sin(2 * 3.14159265 * 220 * i / RATE)), pcm.data() + 2 * i);
        abschreiben(pcm);
    }
}

bool JamesDienst::beschaeftigt() const
{
    return m_spielt || m_denkt || !m_teile.isEmpty() || !m_live.isNull();
}

void JamesDienst::blase(const QString &zustand, const QString &text, int sekunden)
{
    m_zustand = zustand;
    m_blasenText = text;
    emit blaseGeaendert();
    if (sekunden > 0) m_blasenUhr.start(sekunden * 1000);
    else m_blasenUhr.stop();
}

void JamesDienst::blaseGeklickt()
{
    stoppen();
    blase({}, {});
    QProcess::startDetached(QStringLiteral("auriliux-shell"), {QStringLiteral("james")});
}

void JamesDienst::blaseSchliessen()
{
    stoppen();
    blase({}, {});
}

// ════════ Herzschlag, Impuls, Aktionen ════════

void JamesDienst::herzschlag()
{
    if (!m_istDienst || !eingerichtet()) return;
    // Sicherung: hängt James seit 3 Minuten in „denkt/spricht“, zurücksetzen
    m_beschaeftigtTakte = beschaeftigt() ? m_beschaeftigtTakte + 1 : 0;
    if (m_beschaeftigtTakte >= 6) { protokoll(QStringLiteral("Sicherung: hing in denkt/spricht – zurückgesetzt")); stoppen(); blase({}, {}); m_beschaeftigtTakte = 0; }

    const bool schalter = m_an;
    const QVariantMap d{{QStringLiteral("anwesend"), !m_schlaeft}, {QStringLiteral("schalter"), schalter},
                        {QStringLiteral("leerlauf"), 0}, {QStringLiteral("gesperrt"), QFile::exists(laufOrdner() + QStringLiteral("/gesperrt"))},
                        {QStringLiteral("app"), m_vorne.left(80)}, {QStringLiteral("system"), QStringLiteral("Auriliux OS")}};
    post(QStringLiteral("herzschlag"), d, 30000, [this, schalter](const QVariantMap &o, int) {
        if (!o.value(QStringLiteral("ok")).toBool()) { m_darfHandeln = false; return; }
        m_darfHandeln = o.value(QStringLiteral("darf_handeln")).toBool() && schalter && !m_schlaeft;
        m_impulsMinuten = o.value(QStringLiteral("impuls_minuten"), 60).toInt();
        const QString n = o.value(QStringLiteral("name")).toString();
        if (!n.isEmpty() && n != m_name) { m_name = n; emit nameGeaendert(); }
        for (const QVariant &v : o.value(QStringLiteral("abbrechen")).toList())
            if (m_lauf && v.toInt() == m_laufId) auftragAbbrechen(QStringLiteral("du ihn abgebrochen hast"));
        const QVariantMap st = o.value(QStringLiteral("stimme")).toMap();
        if (!st.isEmpty()) {
            m_mikroAn = st.value(QStringLiteral("mikro_an"), true).toBool();
            const QString w = st.value(QStringLiteral("weckwort")).toString();
            m_weckwort = w.isEmpty() ? m_name : w;
            m_pause = qBound(0.8, st.value(QStringLiteral("pause_sekunden"), 4).toDouble(), 15.0);
            m_gespraechSekunden = st.value(QStringLiteral("gespraech_sekunden"), 20).toDouble();
            m_vorlesen = st.value(QStringLiteral("vorlesen"), true).toBool();
        }
        aktionen(o.value(QStringLiteral("aktionen")));
        if (!m_darfHandeln) return;
        if (!m_lauf && o.value(QStringLiteral("auftrag_wartet")).toBool()) auftragHolen();
        if (m_impulsMinuten > 0 && !m_impulsLaeuft && !beschaeftigt() && !m_quelle && m_zustand.isEmpty()
            && m_seitImpuls.elapsed() >= qint64(m_impulsMinuten) * 60000)
            impuls();
    });
}

void JamesDienst::impuls()
{
    m_impulsLaeuft = true;
    m_seitImpuls.restart();
    post(QStringLiteral("impuls"), {}, 300000, [this](const QVariantMap &o, int) {
        m_impulsLaeuft = false;
        aktionen(o.value(QStringLiteral("aktionen")));
        const QString text = o.value(QStringLiteral("nachricht")).toMap().value(QStringLiteral("text")).toString();
        if (text.isEmpty() || !m_an || beschaeftigt() || m_quelle) return;
        protokoll(QStringLiteral("Impuls (%1 Zeichen)").arg(text.size()));
        sprich(text);
    });
}

void JamesDienst::aktionen(const QVariant &roh)
{
    const QVariantList l = roh.toList();
    if (l.isEmpty() || !m_an) return;
    for (const QVariant &v : l) {
        const QVariantMap a = v.toMap();
        const QString art = a.value(QStringLiteral("art")).toString(), ziel = a.value(QStringLiteral("ziel")).toString().left(2000);
        protokoll(QStringLiteral("Aktion: ") + art);
        if (art == QLatin1String("webseite")) {
            const QUrl u(ziel);
            if (u.isValid() && (u.scheme() == QLatin1String("https") || u.scheme() == QLatin1String("http")))
                QProcess::startDetached(QStringLiteral("xdg-open"), {u.toString()});
        } else if (art == QLatin1String("app")) {
            if (!programmOeffnen(ziel)) blase(QStringLiteral("hinweis"), QStringLiteral("Programm „%1“ nicht gefunden.").arg(ziel.left(60)), 6);
        } else if (art == QLatin1String("hinweis")) {
            blase(QStringLiteral("hinweis"), ziel.left(600), 10);
        }
    }
}

bool JamesDienst::programmOeffnen(const QString &name)
{
    // James kennt noch die Mac-Namen – die gleichen Programme unter Auriliux
    static const QHash<QString, QString> ersatz{
        {QStringLiteral("safari"), QStringLiteral("google chrome")}, {QStringLiteral("chrome"), QStringLiteral("google chrome")},
        {QStringLiteral("browser"), QStringLiteral("google chrome")}, {QStringLiteral("finder"), QStringLiteral("wabenfinder")},
        {QStringLiteral("dateien"), QStringLiteral("wabenfinder")}, {QStringLiteral("systemeinstellungen"), QStringLiteral("zentrale")},
        {QStringLiteral("einstellungen"), QStringLiteral("zentrale")}, {QStringLiteral("system settings"), QStringLiteral("zentrale")},
        {QStringLiteral("terminal"), QStringLiteral("foot")}, {QStringLiteral("time machine"), QStringLiteral("tresor")},
        {QStringLiteral("aktivitätsanzeige"), QStringLiteral("guardian")},
    };
    QString g = name.trimmed().toLower();
    g.remove(QRegularExpression(QStringLiteral("\\.(app|desktop)$")));
    g = ersatz.value(g, g);
    if (g.isEmpty()) return false;
    Programme p;
    QString treffer;
    for (const QVariant &v : p.liste()) {
        const QVariantMap e = v.toMap();
        const QString n = e.value(QStringLiteral("name")).toString().toLower(), k = e.value(QStringLiteral("kennung")).toString().toLower();
        if (n == g || k == g) { treffer = e.value(QStringLiteral("datei")).toString(); break; }
        if (treffer.isEmpty() && (n.startsWith(g) || k.endsWith(g))) treffer = e.value(QStringLiteral("datei")).toString();
    }
    return !treffer.isEmpty() && p.starten(treffer);
}

// ════════ Ohr: zuhören auf Knopfdruck (Super+J, Klick) und direkt nach einer Antwort ════════
// Das Mikrofon ist nur dann offen – sonst nie. Erkannt wird, wann du sprichst (Lautstärke im Vergleich
// zum Raumgeräusch); leiser als deine gelernte Stimme (Fernseher, Video) zählt nicht als Sprechen.
// Was du gesagt hast, schreibt der Server genau ab (ElevenLabs), dann antwortet James.

void JamesDienst::hoerenUmschalten()
{
    if (beschaeftigt()) { stoppen(); ohrStarten(8, Knopf); return; }
    if ((m_quelle || m_simuliert) && m_ohrArt != Lauschen) { ohrStoppen(); blase({}, {}); return; }
    ohrStarten(8, Knopf);
}

void JamesDienst::ohrStarten(double warteSekunden, int art)
{
    const bool still = art == Lauschen;                 // beim stillen Lauschen keine Hinweise
    if (!m_an) { if (!still) blase(QStringLiteral("hinweis"), m_name + QStringLiteral(" ist ausgeschaltet – Schalter oben in der Goldleiste."), 6); return; }
    if (!eingerichtet()) { if (!still) blase(QStringLiteral("hinweis"), m_name + QStringLiteral(" ist noch nicht eingerichtet – öffne das James-Fenster."), 8); return; }
    if (!m_mikroAn) { if (!still) blase(QStringLiteral("hinweis"), QStringLiteral("Das Mikrofon ist in den James-Einstellungen ausgeschaltet."), 6); return; }
    ohrStoppen();
    const QAudioDevice geraet = QMediaDevices::defaultAudioInput();
    if (geraet.isNull()) { if (!still) blase(QStringLiteral("hinweis"), QStringLiteral("Kein Mikrofon gefunden."), 6); return; }
    QAudioFormat f;
    f.setSampleRate(RATE);
    f.setChannelCount(1);
    f.setSampleFormat(QAudioFormat::Int16);
    if (!geraet.isFormatSupported(f)) f = geraet.preferredFormat();
    m_quellRate = qMax(8000, f.sampleRate());
    m_quellKanaele = qMax(1, f.channelCount());
    switch (f.sampleFormat()) {
    case QAudioFormat::Float: m_quellArt = 1; break;
    case QAudioFormat::Int32: m_quellArt = 2; break;
    case QAudioFormat::UInt8: m_quellArt = 3; break;
    default: m_quellArt = 0;
    }
    m_quelle = new QAudioSource(geraet, f, this);
    m_quelle->setBufferSize(qMax(4096, m_quellRate * f.bytesPerFrame() / 5));
    m_strom = m_quelle->start();
    if (!m_strom) {
        m_quelle->deleteLater(); m_quelle = nullptr;
        if (!still) blase(QStringLiteral("hinweis"), QStringLiteral("Das Mikrofon lässt sich nicht öffnen."), 6);
        return;
    }
    connect(m_strom, &QIODevice::readyRead, this, &JamesDienst::tonDaten);
    m_vorlauf.clear(); m_aufnahme.clear();
    m_aufnehmen = false; m_gespraech = art == Gespraech; m_ohrArt = art;
    m_lautFolge = 0; m_rahmenProben = 0; m_rahmenSumme = 0; m_resteZeit = 0;
    m_stilleSek = m_aufnahmeSek = m_sprachSek = m_lernSumme = 0; m_lernAnzahl = 0;
    m_ruheSek = 0; m_ruheBeimStart = 0; m_wartePause = false; m_anJames = false; m_segmentGeprueft = false;
    m_stimme *= 0.8;                                      // gelernte Stimme langsam vergessen
    if (art == Lauschen) {
        if (!m_lauscht) { m_lauscht = true; emit weckwortGeaendert(); protokoll(QStringLiteral("Lauscht auf das Weckwort")); }
        return;
    }
    if (m_lauscht) { m_lauscht = false; emit weckwortGeaendert(); }
    m_ohrFrist.start(int(warteSekunden * 1000));
    if (art == Gespraech) blase(QStringLiteral("gespraech"), m_blasenText);
    else { blase(QStringLiteral("hoert"), QStringLiteral("Ich höre …")); klang(QStringLiteral("hoeren")); }
    protokoll(art == Gespraech ? QStringLiteral("Ohr offen (Gespräch)") : QStringLiteral("Ohr offen"));
}

void JamesDienst::ohrStoppen()
{
    m_ohrFrist.stop();
    m_probeTakt.stop();
    m_simuliert = false;
    if (m_quelle) {
        m_quelle->stop();
        m_quelle->deleteLater();
        m_quelle = nullptr;
    }
    m_strom = nullptr;
    m_aufnehmen = false;
    m_anJames = false;
    m_ohrArt = Knopf;
    if (m_lauscht) { m_lauscht = false; emit weckwortGeaendert(); }
    if (m_pegel != 0) { m_pegel = 0; emit pegelGeaendert(); }
}

// ════════ Weckwort: still lauschen, Schnipsel auf diesem Rechner prüfen ════════
// Das Mikrofon bleibt offen, solange James an ist und nichts anderes tut. Beginnt jemand nach einer kleinen
// Pause zu sprechen, prüft die eingebaute Spracherkennung die ersten ~2 Sekunden auf „James“. Nur dann geht
// die ganze Nachricht an deinen Server – sonst wird der Schnipsel sofort verworfen.

bool JamesDienst::weckwortVerfuegbar() const { return Weckwort::verfuegbar(); }

void JamesDienst::setWeckwortAn(bool an)
{
    if (QFile f(konfigOrdner() + QStringLiteral("/james-weckwort")); QDir().mkpath(konfigOrdner()) && f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(an ? "an" : "aus");
    schalterLesen();
}

void JamesDienst::lauschenPruefen()
{
    if (!m_istDienst) return;
    const bool gesperrt = QFile::exists(laufOrdner() + QStringLiteral("/gesperrt"));
    const bool soll = m_weckwortAn && Weckwort::verfuegbar() && m_an && eingerichtet() && m_mikroAn && !m_schlaeft && !gesperrt;
    const bool frei = !beschaeftigt() && (m_zustand.isEmpty() || m_zustand == QLatin1String("hinweis"));
    if (soll && frei && !m_quelle && !m_simuliert) ohrStarten(0, Lauschen);
    else if (!soll && m_ohrArt == Lauschen && (m_quelle || m_simuliert)) ohrStoppen();
}

void JamesDienst::segmentVerwerfen()
{
    m_aufnehmen = false;
    m_aufnahme.clear();
    m_vorlauf.clear();
    m_anJames = false;
    m_wartePause = true;                 // nächster Schnipsel erst nach einer kleinen Sprechpause
    m_ruheSek = 0;
    m_lautFolge = 0;
}

void JamesDienst::weckwortPruefen(const QByteArray &pcm16)
{
    m_segmentGeprueft = true;
    // höchstens eine Prüfung gleichzeitig und nicht öfter als alle 1,5 s (schont den Prozessor)
    if (m_pruefungLaeuft || (m_letztePruefung.isValid() && m_letztePruefung.elapsed() < 1500)) {
        if (m_aufnehmen) segmentVerwerfen();
        return;
    }
    m_pruefungLaeuft = true;
    m_letztePruefung.start();
    const int seg = m_segment;
    const QByteArray stueck = pcm16.left(RATE * 2 * 3);
    QtConcurrent::run([stueck] { double s = 0; const QString t = Weckwort::erkennen(stueck, &s); return qMakePair(t, s); })
        .then(this, [this, seg](const QPair<QString, double> &e) {
            m_pruefungLaeuft = false;
            const bool ja = Weckwort::enthaelt(e.first, m_weckwort);
            protokoll(QStringLiteral("Weckwort-Prüfung: %1 (%2 s)").arg(ja ? QStringLiteral("ja") : QStringLiteral("nein")).arg(e.second, 0, 'f', 2));
            if (m_wartendSegment == seg && !m_wartend.isEmpty()) {          // Schnipsel ist schon zu Ende
                const QByteArray w = m_wartend;
                m_wartend.clear(); m_wartendSegment = -1;
                if (ja && m_ohrArt == Lauschen && m_an) { ohrStoppen(); abschreiben(w); }
                return;
            }
            if (seg != m_segment || !m_aufnehmen || m_ohrArt != Lauschen) return;
            if (ja) {
                m_anJames = true;
                blase(QStringLiteral("hoert"), QStringLiteral("Ich höre zu …"));
            } else {
                segmentVerwerfen();
            }
        });
}

void JamesDienst::probeWav(const QString &pfad)
{
    // Bau-Prüfung ohne Mikrofon: eine WAV-Datei wird in Echtzeit so eingespeist, als käme sie vom Mikrofon
    const QByteArray ton = Weckwort::wavLesen(pfad);
    if (ton.isEmpty()) { protokoll(QStringLiteral("Probe: WAV unlesbar")); return; }
    stoppen();
    ohrStoppen();
    m_vorlauf.clear(); m_aufnahme.clear();
    m_aufnehmen = false; m_gespraech = false; m_ohrArt = Lauschen; m_simuliert = true;
    m_lautFolge = 0; m_rahmenProben = 0; m_rahmenSumme = 0;
    m_stilleSek = m_aufnahmeSek = m_sprachSek = m_lernSumme = 0; m_lernAnzahl = 0;
    m_ruheSek = 1; m_ruheBeimStart = 0; m_wartePause = false; m_anJames = false; m_segmentGeprueft = false;
    m_probeTon = QByteArray(RATE * 2 / 2, '\0') + ton + QByteArray(RATE * 2 * 5, '\0');      // Stille davor und danach
    m_lauscht = true; emit weckwortGeaendert();
    m_probeTakt.start(30);
}

void JamesDienst::tonDaten()
{
    if (!m_strom) return;
    const QByteArray roh = m_strom->readAll();
    const int bps = m_quellArt == 0 ? 2 : m_quellArt == 3 ? 1 : 4;
    const int rahmen = int(roh.size() / (bps * m_quellKanaele));
    if (rahmen <= 0) return;
    std::vector<float> mono(size_t(rahmen), 0.f);
    const char *p = roh.constData();
    for (int i = 0; i < rahmen; ++i) {
        float s = 0;
        for (int k = 0; k < m_quellKanaele; ++k, p += bps) {
            switch (m_quellArt) {
            case 0: s += qFromLittleEndian<qint16>(p) / 32768.f; break;
            case 1: { float v; memcpy(&v, p, 4); s += v; break; }
            case 2: s += float(qFromLittleEndian<qint32>(p) / 2147483648.0); break;
            default: s += (quint8(*p) - 128) / 128.f;
            }
        }
        mono[size_t(i)] = s / m_quellKanaele;
    }
    QByteArray pcm;
    if (m_quellRate == RATE) {
        pcm.resize(rahmen * 2);
        for (int i = 0; i < rahmen; ++i) qToLittleEndian(qint16(qBound(-32767.f, mono[size_t(i)] * 32767.f, 32767.f)), pcm.data() + 2 * i);
    } else {
        const double schritt = double(m_quellRate) / RATE;
        double pos = qMax(0.0, m_resteZeit);
        pcm.reserve(int(rahmen / schritt + 2) * 2);
        while (pos < rahmen - 1) {
            const int i = int(pos);
            const double a = pos - i;
            const float v = float(mono[size_t(i)] * (1 - a) + mono[size_t(i) + 1] * a);
            char b[2]; qToLittleEndian(qint16(qBound(-32767.f, v * 32767.f, 32767.f)), b);
            pcm.append(b, 2);
            pos += schritt;
        }
        m_resteZeit = pos - rahmen;
    }
    tonVerarbeiten(pcm);
}

void JamesDienst::tonVerarbeiten(const QByteArray &pcm16)
{
    if (m_aufnehmen) m_aufnahme.append(pcm16);
    else {
        m_vorlauf.append(pcm16);
        if (m_vorlauf.size() > RATE * 2 * 4 / 10) m_vorlauf.remove(0, m_vorlauf.size() - RATE * 2 * 4 / 10);   // 0,4 s Vorlauf
    }
    const int n = int(pcm16.size() / 2);
    for (int i = 0; i < n && (m_quelle || m_simuliert); ++i) {
        const double v = qFromLittleEndian<qint16>(pcm16.constData() + 2 * i) / 32768.0;
        m_rahmenSumme += v * v;
        if (++m_rahmenProben < RAHMEN) continue;
        const double rms = std::sqrt(m_rahmenSumme / RAHMEN);
        m_rahmenSumme = 0; m_rahmenProben = 0;
        const qreal neu = qMin(1.0, rms * 14);
        if (std::abs(neu - m_pegel) > 0.02) { m_pegel = neu; emit pegelGeaendert(); }

        bool laut = rms > qMax(0.012, m_rauschen * 3.0);
        if (laut && m_stimme > 0 && rms < m_stimme * 0.35) laut = false;     // viel leiser als du: Fernseher/Video
        if (!m_aufnehmen) {
            if (!laut) m_rauschen = rms < m_rauschen ? m_rauschen * 0.9 + rms * 0.1 : qMin(0.05, m_rauschen * 0.995 + rms * 0.005);
            if (laut) { if (m_lautFolge == 0) m_ruheBeimStart = m_ruheSek; m_ruheSek = 0; }
            else m_ruheSek += 0.03;
            m_lautFolge = laut ? m_lautFolge + 1 : 0;
            // ~90 ms Sprache → Aufnahme beginnt (mit Vorlauf); beim Lauschen nach einem verworfenen Schnipsel
            // erst wieder, wenn davor kurz Ruhe war (Weckwort steht am Satzanfang)
            if (m_lautFolge >= 3 && (!m_wartePause || m_ruheBeimStart >= 0.4)) {
                m_aufnehmen = true;
                m_wartePause = false;
                m_aufnahme = m_vorlauf;
                m_vorlauf.clear();
                m_ohrFrist.stop();
                m_stilleSek = 0; m_aufnahmeSek = 0; m_sprachSek = 0;
                m_anJames = false; m_segmentGeprueft = false; ++m_segment;
                if (m_ohrArt != Lauschen) blase(QStringLiteral("hoert"), QStringLiteral("Ich höre zu …"));
            }
            continue;
        }
        m_aufnahmeSek += 0.03;
        if (laut) {
            m_stilleSek = 0;
            m_sprachSek += 0.03;
            if (m_aufnahmeSek < 2.0) { m_lernSumme += rms; ++m_lernAnzahl; }
            else if (m_lernAnzahl > 10) { m_stimme = m_lernSumme / m_lernAnzahl; m_lernAnzahl = -1000000; }
        } else {
            m_stilleSek += 0.03;
        }
        // Lauschen: nach gut 2 s den Anfang auf „James“ prüfen (läuft nebenher weiter)
        if (m_ohrArt == Lauschen && !m_segmentGeprueft && !m_anJames && m_aufnahmeSek >= 2.2) weckwortPruefen(m_aufnahme);
        if (!m_aufnehmen) continue;                       // Schnipsel wurde gerade verworfen
        // ohne Weckwort nicht ewig mitschneiden (z. B. Fernseher): nach 8 s verwerfen
        if (m_ohrArt == Lauschen && !m_anJames && m_aufnahmeSek >= 8 && !m_pruefungLaeuft) { segmentVerwerfen(); continue; }
        if (m_stilleSek >= qBound(0.8, m_pause, 4.0) || m_aufnahmeSek >= 60) { aufnahmeFertig(); return; }
    }
}

void JamesDienst::aufnahmeFertig()
{
    QByteArray pcm = m_aufnahme;
    const double sprache = m_sprachSek;
    const int stilleBytes = int(qMax(0.0, m_stilleSek - 0.25) * RATE) * 2;
    if (stilleBytes > 0 && stilleBytes < pcm.size()) pcm.chop(stilleBytes);
    const bool gespraech = m_gespraech;
    if (m_ohrArt == Lauschen) {
        const bool anJames = m_anJames, geprueft = m_segmentGeprueft;
        const int seg = m_segment;
        m_aufnehmen = false; m_aufnahme.clear(); m_vorlauf.clear(); m_stilleSek = 0; m_lautFolge = 0; m_ruheSek = 0.3;
        if (sprache < 0.3) return;                         // nur ein Geräusch – weiter lauschen
        if (anJames) { ohrStoppen(); abschreiben(pcm); return; }
        m_wartend = pcm; m_wartendSegment = seg;          // Ergebnis der Prüfung entscheidet
        if (!geprueft) weckwortPruefen(pcm);
        if (!m_pruefungLaeuft) { m_wartend.clear(); m_wartendSegment = -1; }
        return;
    }
    ohrStoppen();
    if (sprache < 0.35) {                                  // nur ein Geräusch
        if (gespraech) blase({}, {});
        else blase(QStringLiteral("hinweis"), QStringLiteral("Ich habe nichts verstanden."), 3);
        return;
    }
    abschreiben(pcm);
}

void JamesDienst::abschreiben(const QByteArray &pcm16)
{
    if (!eingerichtet()) return;
    stoppen();
    const int runde = m_runde;
    m_denkt = true;
    blase(QStringLiteral("denkt"), QStringLiteral("Ich schreibe mit …"));
    auto *mp = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    QHttpPart teil;
    teil.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("audio/wav"));
    teil.setHeader(QNetworkRequest::ContentDispositionHeader, QStringLiteral("form-data; name=\"audio\"; filename=\"nachricht.wav\""));
    teil.setBody(wavKopf(pcm16.size()) + pcm16);
    mp->append(teil);
    QNetworkRequest r = anfrageBauen(QStringLiteral("zuhoeren"), {}, 40000);
    r.setHeader(QNetworkRequest::ContentTypeHeader, QByteArray("multipart/form-data; boundary=") + mp->boundary());
    QElapsedTimer uhr; uhr.start();
    QNetworkReply *a = m_netz->post(r, mp);
    mp->setParent(a);
    m_live = a;
    const double sek = pcm16.size() / 2.0 / RATE;
    connect(a, &QNetworkReply::finished, this, [this, a, runde, uhr, sek] {
        a->deleteLater();
        if (runde != m_runde) return;
        m_live = nullptr;
        m_denkt = false;
        const QVariantMap o = QJsonDocument::fromJson(a->readAll()).object().toVariantMap();
        const QString text = o.value(QStringLiteral("text")).toString().trimmed();
        protokoll(QStringLiteral("Abgeschrieben: %1 s Ton in %2 s").arg(sek, 0, 'f', 1).arg(uhr.elapsed() / 1000.0, 0, 'f', 1));
        if (text.isEmpty()) {
            const QString f = o.value(QStringLiteral("fehler")).toString();
            blase(QStringLiteral("hinweis"), f.isEmpty() ? QStringLiteral("Ich habe nichts verstanden.") : f.left(300), 6);
            return;
        }
        gehoert(text);
    });
}

void JamesDienst::gehoert(QString text)
{
    if (!m_an) return;
    // „James, …“ / „Hey James …“ am Anfang weglassen
    const QString w = QRegularExpression::escape(m_weckwort.toLower());
    text.remove(QRegularExpression(QStringLiteral("^\\s*((hey|hallo|okay|ok|hi)[\\s,]+)?(%1|james)\\b[\\s,.!?:;–-]*").arg(w),
                                   QRegularExpression::CaseInsensitiveOption));
    text = text.trimmed();
    if (!text.isEmpty()) text[0] = text.at(0).toUpper();
    if (text.size() < 2) {
        ohrStarten(qMax(8.0, m_gespraechSekunden), Knopf);
        blase(QStringLiteral("hoert"), QStringLiteral("Ja? Ich höre …"));
        return;
    }
    QString klein = text.toLower();
    klein.remove(QRegularExpression(QStringLiteral("[.!?]+$")));
    static const QStringList ende{QStringLiteral("danke"), QStringLiteral("danke dir"), QStringLiteral("das wars"), QStringLiteral("das war's"),
                                  QStringLiteral("tschüss"), QStringLiteral("ende"), QStringLiteral("stopp"), QStringLiteral("stop"),
                                  QStringLiteral("passt"), QStringLiteral("alles klar danke"), QStringLiteral("gut danke")};
    if (ende.contains(klein)) { blase(QStringLiteral("spricht"), QStringLiteral("Gern."), 2); return; }
    stimmeSenden(text);
}

void JamesDienst::klang(const QString &name)
{
    const QUrl u = Klang().datei(name);
    if (u.isEmpty()) return;
    if (!m_ton) m_ton = new QSoundEffect(this);
    m_ton->setSource(u);
    m_ton->setVolume(0.45f);
    m_ton->play();
}

// ════════ Mund: Antworten Satz für Satz vorlesen (Stimme vom Server) ════════

void JamesDienst::stimmeSenden(const QString &frage)
{
    stoppen();
    const int runde = m_runde;
    m_denkt = true;
    m_streamFertig = false;
    m_liveText.clear();
    m_vorher.clear();
    blase(QStringLiteral("denkt"), QStringLiteral("„") + frage.left(300) + QStringLiteral("“"));
    protokoll(QStringLiteral("Frage (%1 Zeichen)").arg(frage.size()));
    const QList<QPair<int, QString>> zwischen{{6000, QStringLiteral("Ich denke noch nach …")},
                                             {16000, QStringLiteral("Dauert etwas länger – ich bin noch dran …")},
                                             {40000, QStringLiteral("Immer noch dabei … Super+J bricht ab.")}};
    for (const auto &z : zwischen)
        QTimer::singleShot(z.first, this, [this, runde, t = z.second] {
            if (runde == m_runde && m_denkt && !m_spielt && m_teile.isEmpty() && m_liveText.isEmpty()) blase(QStringLiteral("denkt"), t);
        });
    m_live = liveStarten(frage, QStringLiteral("stimme"),
        [this, runde](const QVariantMap &o) {
            if (runde != m_runde) return;
            const QString t = o.value(QStringLiteral("t")).toString();
            if (t == QLatin1String("text")) {
                m_liveText += o.value(QStringLiteral("d")).toString();
                blase(QStringLiteral("spricht"), vorlesbar(m_liveText));
            } else if (t == QLatin1String("satz")) {
                teilDazu(o.value(QStringLiteral("text")).toString(), runde);
            } else if (t == QLatin1String("fertig")) {
                aktionen(o.value(QStringLiteral("aktionen")));
            } else if (t == QLatin1String("fehler")) {
                blase(QStringLiteral("hinweis"), o.value(QStringLiteral("text")).toString().left(400), 8);
            }
        },
        [this, runde](const QString &fehler, int) {
            if (runde != m_runde) return;
            m_live = nullptr;
            if (!fehler.isEmpty() && m_teile.isEmpty() && !m_spielt && m_liveText.isEmpty())
                blase(QStringLiteral("hinweis"), QStringLiteral("Keine Verbindung zum Server."), 8);
            m_denkt = false;
            m_streamFertig = true;
            weiterSprechen(runde);
        });
}

void JamesDienst::sprich(const QString &text)
{
    stoppen();
    const int runde = m_runde;
    m_streamFertig = true;
    blase(QStringLiteral("spricht"), vorlesbar(text));
    teilDazu(text, runde);
}

void JamesDienst::vorlesenId(int id)
{
    if (id <= 0 || !m_an) return;
    stoppen();
    const int runde = m_runde;
    m_streamFertig = true;
    blase(QStringLiteral("spricht"), QStringLiteral("Ich lese die Nachricht vor …"));
    auto t = std::make_shared<Teil>();
    m_teile.append(t);
    audioHolen({{QStringLiteral("id"), id}}, [this, t, runde](const QByteArray &d) {
        if (runde != m_runde) return;
        if (d.isEmpty()) { m_teile.clear(); blase(QStringLiteral("hinweis"), QStringLiteral("Für diese Nachricht gibt es keine Stimme (Stimme auf dem Server eingerichtet?)."), 6); return; }
        t->daten = d; t->geladen = true;
        weiterSprechen(runde);
    });
}

void JamesDienst::audioHolen(const QVariantMap &daten, std::function<void(const QByteArray &)> fertig)
{
    if (!eingerichtet()) { fertig({}); return; }
    QNetworkReply *a = m_netz->post(anfrageBauen(QStringLiteral("sprechen"), {}, 60000), QJsonDocument(QJsonObject::fromVariantMap(daten)).toJson(QJsonDocument::Compact));
    connect(a, &QNetworkReply::finished, this, [a, fertig] {
        a->deleteLater();
        const int status = a->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const bool ok = status == 200 && a->header(QNetworkRequest::ContentTypeHeader).toString().contains(QLatin1String("audio"));
        if (!ok) protokoll(QStringLiteral("Stimme: kein Ton vom Server (HTTP %1)").arg(status));
        fertig(ok ? a->readAll() : QByteArray());
    });
}

void JamesDienst::teilDazu(const QString &text, int runde)
{
    if (text.trimmed().isEmpty()) return;
    auto t = std::make_shared<Teil>();
    t->text = text;
    m_teile.append(t);
    if (m_vorlesen) {
        audioHolen({{QStringLiteral("text"), text}, {QStringLiteral("vorher"), m_vorher}}, [this, t, runde](const QByteArray &d) {
            if (runde != m_runde) return;
            t->daten = d; t->geladen = true;
            weiterSprechen(runde);
        });
    } else {
        t->geladen = true;
        weiterSprechen(runde);
    }
    m_vorher = text;
}

static int lesezeit(const QString &t) { return qBound(1500, int(t.size() * 60), 12000); }

void JamesDienst::weiterSprechen(int runde)
{
    if (runde != m_runde || m_spielt) return;
    if (!m_teile.isEmpty() && m_teile.first()->geladen) {
        const auto t = m_teile.takeFirst();
        m_spielt = true;
        m_spielRunde = runde;
        m_aktuellerText = t->text;
        if (!t->daten.isEmpty()) {
            if (!m_spieler) {
                m_ausgabe = new QAudioOutput(this);
                m_spieler = new QMediaPlayer(this);
                m_spieler->setAudioOutput(m_ausgabe);
                connect(m_spieler, &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus s) {
                    if (m_spielt && (s == QMediaPlayer::EndOfMedia || s == QMediaPlayer::InvalidMedia)) teilGespielt();
                });
                connect(m_spieler, &QMediaPlayer::errorOccurred, this, [this](QMediaPlayer::Error, const QString &f) {
                    protokoll(QStringLiteral("Wiedergabe: ") + f);
                    if (m_spielt) m_sprechWache.start(lesezeit(m_aktuellerText));    // dann wenigstens Zeit zum Lesen
                });
            }
            m_spieler->stop();
            if (m_puffer) m_puffer->deleteLater();
            m_puffer = new QBuffer(this);
            m_puffer->setData(t->daten);
            m_puffer->open(QIODevice::ReadOnly);
            m_spieler->setSourceDevice(m_puffer, QUrl(QStringLiteral("satz.mp3")));
            m_spieler->play();
            m_sprechWache.start(qMax(10000, lesezeit(t->text) * 3));                  // Sicherung, falls das Ende nie gemeldet wird
        } else {
            m_sprechWache.start(lesezeit(t->text));
        }
    } else if (m_teile.isEmpty() && m_streamFertig && !m_denkt) {
        antwortFertig();
    }
}

void JamesDienst::teilGespielt()
{
    if (!m_spielt) return;
    m_spielt = false;
    m_sprechWache.stop();
    if (m_spielRunde == m_runde) weiterSprechen(m_runde);
}

void JamesDienst::antwortFertig()
{
    m_vorher.clear();
    const int runde = m_runde;
    protokoll(QStringLiteral("Antwort fertig"));
    // kurz warten (Nachhall), dann direkt weiter zuhören – du kannst ohne Super+J antworten
    QTimer::singleShot(400, this, [this, runde] {
        if (runde != m_runde || beschaeftigt() || m_quelle) return;
        if (m_an && m_gespraechSekunden > 0 && m_mikroAn) ohrStarten(m_gespraechSekunden, Gespraech);
        else m_blasenUhr.start(6000);
    });
}

void JamesDienst::stoppen()
{
    ++m_runde;
    if (m_live) { QNetworkReply *a = m_live; m_live = nullptr; a->abort(); }
    m_teile.clear();
    m_spielt = false;
    m_streamFertig = true;
    m_denkt = false;
    m_liveText.clear();
    m_vorher.clear();
    if (m_spieler) m_spieler->stop();
    m_sprechWache.stop();
    ohrStoppen();
}

QString JamesDienst::vorlesbar(const QString &t)
{
    QString s = t;
    s.remove(QRegularExpression(QStringLiteral("```[\\s\\S]*?(```|$)")));
    s.replace(QRegularExpression(QStringLiteral("\\[([^\\]]+)\\]\\([^)]+\\)")), QStringLiteral("\\1"));
    s.remove(QRegularExpression(QStringLiteral("[*_`#>]+")));
    s.replace(QRegularExpression(QStringLiteral("^\\s*[-•]\\s+"), QRegularExpression::MultilineOption), QString());
    s.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));
    return s.trimmed();
}

// ════════ Aufträge an Claude Code ════════

void JamesDienst::auftragHolen()
{
    post(QStringLiteral("auftrag_abholen"), {}, 30000, [this](const QVariantMap &o, int) {
        const QVariantMap a = o.value(QStringLiteral("auftrag")).toMap();
        if (!m_lauf && a.value(QStringLiteral("id")).toInt() > 0) auftragStarten(a);
    });
}

void JamesDienst::auftragMelden(int id, const QString &status, const QString &text)
{
    post(QStringLiteral("auftrag_melden"), {{QStringLiteral("id"), id}, {QStringLiteral("status"), status}, {QStringLiteral("ergebnis"), text.right(30000)}},
         30000, [](const QVariantMap &, int) {});
}

void JamesDienst::auftragStarten(const QVariantMap &a)
{
    const int id = a.value(QStringLiteral("id")).toInt();
    const QString titel = a.value(QStringLiteral("titel")).toString(), beschreibung = a.value(QStringLiteral("beschreibung")).toString();
    const QString home = QDir(QDir::homePath()).canonicalPath();
    QString pfad = a.value(QStringLiteral("ordner")).toString().trimmed();
    if (pfad.isEmpty()) pfad = QStringLiteral("~/System_2.0");
    if (pfad.startsWith('~')) pfad = home + pfad.mid(1);
    // nur im Benutzerordner, nie in versteckten Ordnern (.config, .ssh, .local …)
    auto erlaubt = [&home](const QString &p) {
        const QString c = QDir::cleanPath(p);
        if (c != home && !c.startsWith(home + '/')) return false;
        for (const QString &teil : QDir(home).relativeFilePath(c).split('/'))
            if (teil.startsWith('.')) return false;
        return true;
    };
    pfad = QDir::cleanPath(QFileInfo(pfad).absoluteFilePath());
    if (!erlaubt(pfad)) {
        auftragMelden(id, QStringLiteral("fehler"), QStringLiteral("Abgelehnt: Aufträge dürfen nur in deinem Benutzerordner laufen, nicht in versteckten Ordnern (%1).").arg(pfad));
        return;
    }
    QDir().mkpath(pfad);
    const QString echt = QFileInfo(pfad).canonicalFilePath();         // Verweise auflösen und nochmal prüfen
    if (echt.isEmpty() || !erlaubt(echt)) {
        auftragMelden(id, QStringLiteral("fehler"), QStringLiteral("Abgelehnt: %1 führt aus deinem Benutzerordner heraus.").arg(pfad));
        return;
    }
    QString claude;
    for (const QString &p : {home + QStringLiteral("/.local/bin/claude"), home + QStringLiteral("/.claude/local/claude"),
                             QStringLiteral("/usr/local/bin/claude"), QStringLiteral("/usr/bin/claude")})
        if (QFileInfo(p).isExecutable()) { claude = p; break; }
    if (claude.isEmpty()) claude = QStandardPaths::findExecutable(QStringLiteral("claude"));
    if (claude.isEmpty()) {
        auftragMelden(id, QStringLiteral("fehler"), QStringLiteral("Claude Code ist auf diesem Rechner noch nicht installiert. Einmalig im Terminal installieren (Anleitung: code.claude.com), danach „claude“ starten und mit /login anmelden."));
        return;
    }
    const QString anweisung = QStringLiteral(
        "Auftrag #%1 von James (dem KI-Assistenten deines Besitzers): %2\n\n%3\n\n"
        "Arbeite nur in diesem Ordner (%4). Wenn etwas unklar oder riskant ist, ändere nichts Destruktives, sondern beschreibe es.\n"
        "Schließe mit einer kurzen Zusammenfassung auf Deutsch: was du getan hast, was offen ist, wie man es prüft.")
        .arg(id).arg(titel, beschreibung, echt);
    m_lauf = new QProcess(this);
    m_lauf->setProgram(claude);
    m_lauf->setArguments({QStringLiteral("-p"), anweisung, QStringLiteral("--output-format"), QStringLiteral("text"),
                          QStringLiteral("--permission-mode"), QStringLiteral("acceptEdits")});
    m_lauf->setWorkingDirectory(echt);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("PATH"), home + QStringLiteral("/.local/bin:/usr/local/bin:/usr/bin:/bin"));
    m_lauf->setProcessEnvironment(env);
    m_lauf->setStandardInputFile(QProcess::nullDevice());
    m_laufId = id;
    m_laufGrund.clear();
    m_laufAus.clear(); m_laufFehler.clear();
    connect(m_lauf, &QProcess::readyReadStandardOutput, this, [this] { m_laufAus.append(m_lauf->readAllStandardOutput()); if (m_laufAus.size() > (1 << 20)) m_laufAus = m_laufAus.right(1 << 19); });
    connect(m_lauf, &QProcess::readyReadStandardError, this, [this] { m_laufFehler.append(m_lauf->readAllStandardError()); if (m_laufFehler.size() > (1 << 20)) m_laufFehler = m_laufFehler.right(1 << 19); });
    connect(m_lauf, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) { auftragFertig(code); });
    connect(m_lauf, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        const int i = m_laufId;
        m_lauf->deleteLater(); m_lauf = nullptr; m_auftragText.clear(); emit auftragGeaendert();
        auftragMelden(i, QStringLiteral("fehler"), QStringLiteral("Claude Code konnte nicht starten."));
    });
    m_laufUhr.start();
    m_lauf->start();
    m_auftragText = QStringLiteral("Auftrag #%1 · %2").arg(id).arg(titel.left(80));
    emit auftragGeaendert();
    protokoll(QStringLiteral("Auftrag #%1 gestartet").arg(id));
    if (m_zustand.isEmpty()) blase(QStringLiteral("hinweis"), QStringLiteral("Ich arbeite an Auftrag #%1 „%2“.").arg(id).arg(titel.left(80)), 6);
    QPointer<QProcess> lauf = m_lauf;
    QTimer::singleShot(3600 * 1000, this, [this, lauf] { if (lauf && lauf == m_lauf) auftragAbbrechen(QStringLiteral("das Zeitlimit von 60 Minuten erreicht war")); });
}

void JamesDienst::auftragAbbrechen(const QString &grund)
{
    if (!m_lauf || m_lauf->state() == QProcess::NotRunning) return;
    m_laufGrund = grund;
    protokoll(QStringLiteral("Auftrag #%1 abgebrochen: ").arg(m_laufId) + grund);
    m_lauf->terminate();
    QPointer<QProcess> lauf = m_lauf;
    QTimer::singleShot(5000, this, [lauf] { if (lauf && lauf->state() != QProcess::NotRunning) lauf->kill(); });
}

void JamesDienst::auftragFertig(int code)
{
    if (!m_lauf) return;
    m_laufAus.append(m_lauf->readAllStandardOutput());
    m_laufFehler.append(m_lauf->readAllStandardError());
    const QString aus = QString::fromUtf8(m_laufAus).trimmed(), fehler = QString::fromUtf8(m_laufFehler).trimmed();
    QString text = aus;
    if ((aus + fehler).contains(QLatin1String("Not logged in")) || (aus + fehler).contains(QLatin1String("/login")))
        text.prepend(QStringLiteral("Claude Code ist auf diesem Rechner noch nicht angemeldet. Einmalig: Terminal öffnen, „claude“ eingeben und mit /login dein Claude-Konto verbinden.\n\n"));
    if (!fehler.isEmpty()) text += (text.isEmpty() ? QString() : QStringLiteral("\n\n")) + QStringLiteral("Meldungen:\n") + fehler.right(3000);
    QString status;
    if (!m_laufGrund.isEmpty()) { status = QStringLiteral("unterbrochen"); text.prepend(QStringLiteral("Unterbrochen, weil %1.\n\n").arg(m_laufGrund)); }
    else status = code == 0 ? QStringLiteral("erledigt") : QStringLiteral("fehler");
    text += QStringLiteral("\n\n(Dauer: %1 min, Exit-Code %2, Auriliux OS)").arg(m_laufUhr.elapsed() / 60000).arg(code);
    const int id = m_laufId;
    m_lauf->deleteLater();
    m_lauf = nullptr;
    m_auftragText.clear();
    emit auftragGeaendert();
    protokoll(QStringLiteral("Auftrag #%1 → %2").arg(id).arg(status));
    auftragMelden(id, status, text);
    if (m_zustand.isEmpty() && m_an)
        blase(QStringLiteral("hinweis"), status == QLatin1String("erledigt") ? QStringLiteral("Auftrag #%1 ist fertig.").arg(id)
                                                                            : QStringLiteral("Auftrag #%1: %2.").arg(id).arg(status), 8);
}
