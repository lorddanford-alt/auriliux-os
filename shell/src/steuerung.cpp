#include "steuerung.h"
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QStorageInfo>
#include <QTimer>
#include <grp.h>
#include <pwd.h>
#include <unistd.h>

using NmEinstellungen = QMap<QString, QVariantMap>;
Q_DECLARE_METATYPE(NmEinstellungen)

namespace {
const QString NM = QStringLiteral("org.freedesktop.NetworkManager");
const QString NM_PFAD = QStringLiteral("/org/freedesktop/NetworkManager");
const QString EIGENSCHAFTEN = QStringLiteral("org.freedesktop.DBus.Properties");

QString lies(const QString &pfad) { QFile f(pfad); return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.read(256 * 1024)).trimmed() : QString(); }

QVariant eigenschaft(const QString &pfad, const QString &schnitt, const QString &name)
{
    QDBusInterface e(NM, pfad, EIGENSCHAFTEN, QDBusConnection::systemBus());
    const QDBusReply<QDBusVariant> r = e.call(QStringLiteral("Get"), schnitt, name);
    return r.isValid() ? r.value().variant() : QVariant();
}

QString wlanGeraet()
{
    QDBusInterface nm(NM, NM_PFAD, NM, QDBusConnection::systemBus());
    const QDBusReply<QList<QDBusObjectPath>> r = nm.call(QStringLiteral("GetDevices"));
    if (!r.isValid()) return {};
    for (const QDBusObjectPath &p : r.value())
        if (eigenschaft(p.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("DeviceType")).toUInt() == 2)
            return p.path();
    return {};
}

QString fehlerText(const QString &dbus)
{
    if (dbus.contains(QLatin1String("ermission"), Qt::CaseInsensitive) || dbus.contains(QLatin1String("authoriz"), Qt::CaseInsensitive))
        return QStringLiteral("Keine Berechtigung, Netze zu speichern");
    if (dbus.contains(QLatin1String("psk"), Qt::CaseInsensitive)) return QStringLiteral("Passwort ungültig (8 bis 63 Zeichen)");
    return QStringLiteral("Verbinden fehlgeschlagen: ") + dbus;
}
} // namespace

Steuerung::Steuerung(QObject *parent) : QObject(parent)
{
    qDBusRegisterMetaType<NmEinstellungen>();
}

QVariantList Steuerung::lichter() const
{
    QVariantList l;
    const QDir b(QStringLiteral("/sys/class/backlight"));
    for (const QString &n : b.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System))
        l << QVariantMap{{"art", "bildschirm"}, {"geraet", n}, {"wert", lies(b.filePath(n) + "/brightness").toInt()},
                         {"max", lies(b.filePath(n) + "/max_brightness").toInt()}};
    const QDir d(QStringLiteral("/sys/class/leds"));
    for (const QString &n : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System))
        if (n.contains(QLatin1String("kbd_backlight")))
            l << QVariantMap{{"art", "tastatur"}, {"geraet", n}, {"wert", lies(d.filePath(n) + "/brightness").toInt()},
                             {"max", lies(d.filePath(n) + "/max_brightness").toInt()}};
    return l;
}

QString Steuerung::licht(const QString &art, const QString &geraet, int wert)
{
    if (geraet.isEmpty() || geraet.contains('/') || geraet.startsWith('.')) return QStringLiteral("Unbekanntes Gerät");
    const QString klasse = art == QLatin1String("tastatur") ? QStringLiteral("leds") : QStringLiteral("backlight");
    // logind erlaubt das der aktiven Sitzung ohne Root
    QDBusInterface s(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1/session/auto"),
                     QStringLiteral("org.freedesktop.login1.Session"), QDBusConnection::systemBus());
    const QDBusMessage r = s.call(QStringLiteral("SetBrightness"), klasse, geraet, uint(qMax(0, wert)));
    if (r.type() != QDBusMessage::ErrorMessage) return {};
    // Rückfall: direkt schreiben, falls erlaubt
    QFile f(QStringLiteral("/sys/class/%1/%2/brightness").arg(klasse, geraet));
    if (f.open(QIODevice::WriteOnly) && f.write(QByteArray::number(qMax(0, wert))) > 0) return {};
    return QStringLiteral("Helligkeit lässt sich nicht ändern: ") + r.errorMessage();
}

void Steuerung::wlanVerbinden(const QString &ssid, const QString &passwort, const QString &sicherheit)
{
    const QString geraet = wlanGeraet();
    if (geraet.isEmpty()) { emit wlanErgebnis(ssid, false, QStringLiteral("Kein WLAN-Gerät gefunden")); return; }
    NmEinstellungen e;
    e.insert(QStringLiteral("connection"), QVariantMap{{QStringLiteral("type"), QStringLiteral("802-11-wireless")}, {QStringLiteral("id"), ssid}});
    e.insert(QStringLiteral("802-11-wireless"), QVariantMap{{QStringLiteral("ssid"), ssid.toUtf8()}, {QStringLiteral("mode"), QStringLiteral("infrastructure")}});
    if (!passwort.isEmpty()) {
        const bool nurWpa3 = sicherheit.contains(QLatin1String("WPA3")) && !sicherheit.contains(QLatin1String("WPA2")) && !sicherheit.contains(QLatin1String("WPA1"));
        e.insert(QStringLiteral("802-11-wireless-security"),
                 QVariantMap{{QStringLiteral("key-mgmt"), nurWpa3 ? QStringLiteral("sae") : QStringLiteral("wpa-psk")}, {QStringLiteral("psk"), passwort}});
    }
    QDBusMessage m = QDBusMessage::createMethodCall(NM, NM_PFAD, NM, QStringLiteral("AddAndActivateConnection"));
    m << QVariant::fromValue(e) << QVariant::fromValue(QDBusObjectPath(geraet)) << QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")));
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(m, 60000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, ssid] {
        const QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> r = *w;
        w->deleteLater();
        if (r.isError()) { emit wlanErgebnis(ssid, false, fehlerText(r.error().message())); return; }
        wlanBeobachten(ssid, r.argumentAt<0>().path(), r.argumentAt<1>().path(), 0);
    });
}

void Steuerung::wlanBeobachten(const QString &ssid, const QString &verbindung, const QString &aktiv, int runde)
{
    // Zustand der Verbindung: 1 baut auf, 2 steht, 3/4 abgebaut (z. B. falsches Passwort)
    const QVariant z = eigenschaft(aktiv, QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"), QStringLiteral("State"));
    const uint zustand = z.isValid() ? z.toUInt() : 4;
    if (zustand == 2) { emit wlanErgebnis(ssid, true, QStringLiteral("Verbunden mit „%1“").arg(ssid)); return; }
    if (zustand >= 3 || runde >= 80) {
        // fehlgeschlagen → nicht mit falschem Passwort gespeichert lassen
        QDBusInterface c(NM, verbindung, QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), QDBusConnection::systemBus());
        c.call(QStringLiteral("Delete"));
        emit wlanErgebnis(ssid, false, QStringLiteral("Keine Verbindung – Passwort prüfen"));
        return;
    }
    QTimer::singleShot(500, this, [=] { wlanBeobachten(ssid, verbindung, aktiv, runde + 1); });
}

QVariantMap Steuerung::info() const
{
    QVariantMap m;
    const QString modell = lies(QStringLiteral("/sys/class/dmi/id/product_name"));
    m["kennung"] = modell;
    m["modell"] = modell == QLatin1String("MacBookPro12,1") ? QStringLiteral("MacBook Pro 13″ (Anfang 2015)") : modell;
    QString cpu;
    int kerne = 0;
    for (const QString &z : lies(QStringLiteral("/proc/cpuinfo")).split('\n')) {
        if (z.startsWith(QLatin1String("model name"))) { ++kerne; if (cpu.isEmpty()) cpu = z.section(':', 1).trimmed(); }
    }
    cpu.replace(QLatin1String("(R)"), QString()).replace(QLatin1String("(TM)"), QString()).replace(QLatin1String(" CPU"), QString());
    m["prozessor"] = cpu.simplified();
    m["kerne"] = kerne;
    for (const QString &z : lies(QStringLiteral("/proc/meminfo")).split('\n'))
        if (z.startsWith(QLatin1String("MemTotal:"))) m["ram"] = z.section(':', 1).simplified().section(' ', 0, 0).toLongLong() * 1024;
    const QStorageInfo s(QDir::homePath());
    m["speicherGesamt"] = s.bytesTotal();
    m["speicherFrei"] = s.bytesAvailable();
    m["kern"] = lies(QStringLiteral("/proc/sys/kernel/osrelease"));
    for (const QString &z : lies(QStringLiteral("/usr/lib/os-release")).split('\n'))
        if (z.startsWith(QLatin1String("PRETTY_NAME="))) m["system"] = z.section('=', 1).remove('"');
    m["stand"] = lies(QStringLiteral("/usr/share/auriliux/stand"));
    return m;
}

QVariantMap Steuerung::benutzer() const
{
    QVariantMap m;
    const passwd *pw = getpwuid(getuid());
    if (!pw) return m;
    m["name"] = QString::fromLocal8Bit(pw->pw_name);
    const QString voll = QString::fromLocal8Bit(pw->pw_gecos ? pw->pw_gecos : "").section(',', 0, 0).trimmed();
    m["anzeige"] = voll.isEmpty() ? m["name"].toString() : voll;
    bool admin = getuid() == 0;
    int n = 64;
    QList<gid_t> gruppen(n);
    if (getgrouplist(pw->pw_name, pw->pw_gid, gruppen.data(), &n) >= 0) {
        for (int i = 0; i < n; ++i)
            if (const group *g = getgrgid(gruppen[i]); g && qstrcmp(g->gr_name, "wheel") == 0) admin = true;
    }
    m["admin"] = admin;
    return m;
}
