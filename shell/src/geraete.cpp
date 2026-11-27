#include "geraete.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSocketNotifier>
#include <QStorageInfo>
#include <QtConcurrent/QtConcurrentRun>
#include <fcntl.h>
#include <unistd.h>

namespace {
struct Ergebnis { QString text; int code = -1; };

// Programm ohne Shell starten und auf das Ende warten (läuft immer im Hintergrund-Thread)
Ergebnis fuehreAus(const QString &programm, const QStringList &args, int ms = 8000)
{
    QProcess p;
    p.setProcessChannelMode(QProcess::MergedChannels);
    p.start(programm, args);
    if (!p.waitForStarted(2000)) return {};
    if (!p.waitForFinished(ms)) { p.kill(); p.waitForFinished(500); return {QString::fromUtf8(p.readAll()), -1}; }
    return {QString::fromUtf8(p.readAll()), p.exitCode()};
}

QString lies(const QString &pfad) {
    QFile f(pfad);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.read(4096)).trimmed() : QString();
}

bool wahr(const QJsonValue &v) {        // lsblk liefert je nach Version true/false oder "1"/"0"
    return v.isBool() ? v.toBool() : (v.toString() == QLatin1String("1") || v.toString() == QLatin1String("true"));
}

QString artFuer(const QString &name)
{
    const QString n = name.toLower();
    if (n.contains("mouse") || n.contains("maus")) return "maus";
    if (n.contains("trackpad") || n.contains("touchpad")) return "trackpad";
    if (n.contains("keyboard") || n.contains("tastatur")) return "tastatur";
    if (n.contains("headphone") || n.contains("headset") || n.contains("airpods") || n.contains("kopfhörer")
        || n.contains("speaker") || n.contains("lautsprecher") || n.contains("audio")) return "audio";
    if (n.contains("iphone") || n.contains("ipad") || n.contains("phone")) return "telefon";
    if (n.contains("gamepad") || n.contains("controller") || n.contains("joystick")) return "controller";
    return {};
}

const QStringList einhaengbar{"vfat", "exfat", "ntfs", "ntfs3", "ext2", "ext3", "ext4", "btrfs", "xfs", "hfsplus", "iso9660", "udf", "f2fs"};

QVariantList laufwerke()
{
    QVariantList out;
    const Ergebnis r = fuehreAus("lsblk", {"-J", "-l", "-b", "-o", "NAME,PATH,PKNAME,TYPE,RM,HOTPLUG,TRAN,FSTYPE,LABEL,SIZE,MOUNTPOINT"}, 4000);
    const QJsonArray geraete = QJsonDocument::fromJson(r.text.toUtf8()).object().value("blockdevices").toArray();
    // Platten merken (Wechseldatenträger, USB)
    QHash<QString, QJsonObject> platten;
    for (const QJsonValue &v : geraete) { const QJsonObject o = v.toObject(); if (o.value("type").toString() == "disk") platten.insert(o.value("name").toString(), o); }
    for (const QJsonValue &v : geraete) {
        const QJsonObject o = v.toObject();
        const QString typ = o.value("type").toString(), fs = o.value("fstype").toString();
        if ((typ != "part" && typ != "disk") || fs.isEmpty() || fs == "swap" || fs == "crypto_LUKS") continue;
        const QJsonObject platte = typ == "disk" ? o : platten.value(o.value("pkname").toString());
        const bool wechsel = wahr(platte.value("rm")) || wahr(o.value("rm"));
        const bool steckbar = wechsel || wahr(platte.value("hotplug")) || wahr(o.value("hotplug")) || platte.value("tran").toString() == "usb";
        if (!steckbar) continue;                                   // eingebaute SSD nie zeigen
        const QString mp = o.value("mountpoint").toString();
        if (mp.isEmpty() && !einhaengbar.contains(fs)) continue;
        QVariantMap m;
        m.insert("kind", wechsel ? "stick" : "festplatte");
        const QString label = o.value("label").toString();
        const double groesse = o.value("size").toDouble();
        m.insert("name", !label.isEmpty() ? label : (wechsel ? QStringLiteral("USB-Stick") : QStringLiteral("Laufwerk")));
        m.insert("geraet", o.value("path").toString());
        m.insert("platte", platte.value("path").toString());
        m.insert("fs", fs);
        m.insert("eject", true);
        if (!mp.isEmpty()) {
            QStorageInfo si(mp);
            m.insert("path", mp);
            m.insert("total", double(si.bytesTotal()));
            m.insert("free", double(si.bytesAvailable()));
        } else {
            m.insert("path", QString());
            m.insert("total", groesse);
            m.insert("free", 0.0);
            m.insert("eingehaengt", false);
        }
        out << m;
    }
    // Netzlaufwerke
    for (const QStorageInfo &si : QStorageInfo::mountedVolumes()) {
        const QString t = QString::fromLatin1(si.fileSystemType());
        if (!(t.startsWith("nfs") || t == "cifs" || t == "smb3" || t == "fuse.sshfs" || t == "davfs")) continue;
        QVariantMap m;
        m.insert("kind", "netz"); m.insert("name", si.displayName()); m.insert("path", si.rootPath());
        m.insert("total", double(si.bytesTotal())); m.insert("free", double(si.bytesAvailable())); m.insert("eject", false);
        out << m;
    }
    return out;
}

QVariantList usbGeraete()
{
    QVariantList out;
    QDir d("/sys/bus/usb/devices");
    for (const QString &e : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (e.contains(':') || e.startsWith("usb")) continue;
        const QString basis = d.filePath(e);
        const QString produkt = lies(basis + "/product");
        if (produkt.isEmpty() || lies(basis + "/bDeviceClass") == "09") continue;
        const QString low = produkt.toLower();
        if (low.contains("hub") || low.contains("internal") || low.contains("bluetooth") || low.contains("facetime")
            || low.contains("card reader") || low.contains("host controller") || low.contains("ambient")) continue;
        // Schnittstellen ansehen: Speicher (08) zeigt schon die Laufwerksliste, Funk (e0) ist Bluetooth
        QString art;
        bool weg = false;
        for (const QString &s : QDir(basis).entryList({e + ":*"}, QDir::Dirs)) {
            const QString k = lies(basis + "/" + s + "/bInterfaceClass");
            if (k == "08" || k == "09" || k == "e0") weg = true;
            if (k == "03") {
                const QString prot = lies(basis + "/" + s + "/bInterfaceProtocol");
                if (prot == "01" && art.isEmpty()) art = "tastatur";
                if (prot == "02") art = "maus";
            }
        }
        if (weg) continue;
        const QString name = artFuer(produkt);
        QVariantMap m;
        m.insert("kind", !name.isEmpty() ? name : !art.isEmpty() ? art : QStringLiteral("usb"));
        m.insert("name", produkt);
        m.insert("via", "USB");
        m.insert("maker", lies(basis + "/manufacturer"));
        out << m;
    }
    return out;
}

QVariantList bluetoothGeraete()
{
    QVariantList out;
    if (QDir("/sys/class/bluetooth").entryList(QDir::AllEntries | QDir::NoDotAndDotDot).isEmpty()) return out;   // kein Funkchip aktiv
    const Ergebnis liste = fuehreAus("bluetoothctl", {"devices", "Paired"}, 2500);
    static const QRegularExpression zeile(QStringLiteral("^Device ([0-9A-F:]{17}) (.+)$"), QRegularExpression::MultilineOption);
    auto it = zeile.globalMatch(liste.text);
    while (it.hasNext()) {
        const auto t = it.next();
        const QString adr = t.captured(1), name = t.captured(2).trimmed();
        const QString info = fuehreAus("bluetoothctl", {"info", adr}, 2500).text;
        const bool verbunden = info.contains(QStringLiteral("Connected: yes"));
        QString art = artFuer(name);
        static const QRegularExpression symbol(QStringLiteral("Icon: (\\S+)"));
        const QString ic = symbol.match(info).captured(1);
        if (art.isEmpty()) {
            if (ic == "input-mouse") art = "maus";
            else if (ic == "input-keyboard") art = "tastatur";
            else if (ic == "input-gaming") art = "controller";
            else if (ic == "input-tablet") art = "trackpad";
            else if (ic.startsWith("audio")) art = "audio";
            else if (ic == "phone") art = "telefon";
            else art = "bluetooth";
        }
        static const QRegularExpression akku(QStringLiteral("Battery Percentage: \\S+ \\((\\d+)\\)"));
        const QString prozent = akku.match(info).captured(1);
        QVariantMap m;
        m.insert("kind", art); m.insert("name", name); m.insert("via", "Bluetooth");
        m.insert("connected", verbunden); m.insert("address", adr);
        m.insert("battery", prozent.isEmpty() ? QString() : prozent + "%");
        out << m;
    }
    return out;
}

QVariantList bildschirme()
{
    QVariantList out;
    QDir d("/sys/class/drm");
    for (const QString &e : d.entryList({"card*-*"}, QDir::Dirs | QDir::System)) {
        const QString anschluss = e.section('-', 1);
        if (anschluss.startsWith("eDP") || anschluss.startsWith("LVDS") || anschluss.startsWith("DSI") || anschluss.startsWith("Writeback")) continue;
        if (lies(d.filePath(e) + "/status") != "connected") continue;
        const QString typ = anschluss.startsWith("HDMI") ? "HDMI" : anschluss.startsWith("DP") ? "DisplayPort" : anschluss.section('-', 0, 0);
        QVariantMap m; m.insert("kind", "bildschirm"); m.insert("name", QStringLiteral("Bildschirm (%1)").arg(typ));
        out << m;
    }
    return out;
}

QVariantList netzteil()
{
    QVariantList out;
    QDir d("/sys/class/power_supply");
    bool laedt = false;
    for (const QString &e : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System))
        if (lies(d.filePath(e) + "/type") == "Battery" && lies(d.filePath(e) + "/status") == "Charging") laedt = true;
    for (const QString &e : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System)) {
        if (lies(d.filePath(e) + "/type") != "Mains" || lies(d.filePath(e) + "/online") != "1") continue;
        QVariantMap m; m.insert("kind", "strom"); m.insert("name", "Netzteil");
        m.insert("detail", laedt ? QStringLiteral("lädt") : QStringLiteral("verbunden")); m.insert("charging", laedt);
        out << m; break;
    }
    return out;
}

QVariantList beispiel()   // AURILIUX_GERAETE_DEMO=1 – zum Ansehen ohne echte Geräte (wie MOCK am Mac)
{
    auto m = [](std::initializer_list<std::pair<const char *, QVariant>> l) { QVariantMap r; for (auto &p : l) r.insert(p.first, p.second); return QVariant(r); };
    return {m({{"kind", "festplatte"}, {"name", "AURILIUX"}, {"path", "/run/media/du/AURILIUX"}, {"geraet", "/dev/sdb2"}, {"total", 2e12}, {"free", 7.4e11}, {"eject", true}}),
            m({{"kind", "stick"}, {"name", "USB-STICK"}, {"path", "/run/media/du/USB"}, {"geraet", "/dev/sdc1"}, {"total", 3.2e10}, {"free", 1.1e10}, {"eject", true}}),
            m({{"kind", "maus"}, {"name", "MX Master 3"}, {"via", "Bluetooth"}, {"battery", "80%"}, {"connected", true}, {"address", "CC:DD"}}),
            m({{"kind", "audio"}, {"name", "AirPods Pro"}, {"via", "Bluetooth"}, {"connected", false}, {"address", "AA:BB"}}),
            m({{"kind", "strom"}, {"name", "Netzteil"}, {"detail", "verbunden"}})};
}

QString freundlich(const QString &aus, const QString &was)
{
    if (aus.contains("busy", Qt::CaseInsensitive) || aus.contains("in use", Qt::CaseInsensitive))
        return QStringLiteral("Auswerfen nicht möglich: Ein Programm benutzt das Laufwerk noch. Schließe offene Dateien/Fenster darauf und versuche es nochmal.");
    if (aus.contains("Not authorized", Qt::CaseInsensitive))
        return QStringLiteral("%1 nicht erlaubt – keine Berechtigung.").arg(was);
    const QString z = aus.section('\n', 0, 0).trimmed();
    return QStringLiteral("%1 nicht möglich%2").arg(was, z.isEmpty() ? QString() : ": " + z.left(140));
}
} // namespace

Geraete::Geraete(QObject *parent) : QObject(parent)
{
    m_ruhe.setSingleShot(true);
    m_ruhe.setInterval(900);
    connect(&m_ruhe, &QTimer::timeout, this, [this] {
        emit geaendert();
        // neue Laufwerke einhängen
        auto *w = new QFutureWatcher<QVariantList>(this);
        connect(w, &QFutureWatcher<QVariantList>::finished, this, [this, w] { automatischEinhaengen(w->result()); w->deleteLater(); });
        w->setFuture(QtConcurrent::run(laufwerke));
    });
    beobachten();
    m_ruhe.start();      // beim Start einmal: schon steckende Laufwerke einhängen
}

void Geraete::beobachten()
{
    if (qEnvironmentVariableIsSet("AURILIUX_GERAETE_DEMO")) return;
    // Ein- und Aushängen: /proc/self/mounts meldet Änderungen als „Ausnahme“
    const int fd = ::open("/proc/self/mounts", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        m_mounts = new QSocketNotifier(fd, QSocketNotifier::Exception, this);
        connect(m_mounts, &QSocketNotifier::activated, this, [this, fd] { ::lseek(fd, 0, SEEK_SET); char b[256]; while (::read(fd, b, sizeof b) > 0) {} m_ruhe.start(); });
    }
    // Anstecken / Abziehen: neue Einträge unter /dev/disk/by-id, /sys/bus/usb/devices, Bildschirme
    m_wache = new QFileSystemWatcher(this);
    for (const QString &p : {QStringLiteral("/dev/disk/by-id"), QStringLiteral("/dev/disk"), QStringLiteral("/dev/input")})
        if (QFileInfo::exists(p)) m_wache->addPath(p);
    connect(m_wache, &QFileSystemWatcher::directoryChanged, this, [this](const QString &p) {
        if (p == QLatin1String("/dev/disk") && !m_wache->directories().contains("/dev/disk/by-id") && QFileInfo::exists("/dev/disk/by-id"))
            m_wache->addPath("/dev/disk/by-id");
        m_ruhe.start();
    });
}

void Geraete::automatischEinhaengen(const QVariantList &items)
{
    QSet<QString> jetzt;
    for (const QVariant &v : items) {
        const QVariantMap m = v.toMap();
        const QString g = m.value("geraet").toString();
        if (g.isEmpty()) continue;
        jetzt.insert(g);
        const bool neu = m_ersterLauf || !m_bekannt.contains(g);
        if (neu && m.value("eingehaengt", true).toBool() == false && !m_ausgeworfen.contains(g))
            einhaengen(QStringLiteral("auto"), g);
    }
    m_ausgeworfen.intersect(jetzt);   // abgezogen → beim nächsten Anstecken wieder einhängen
    m_bekannt = jetzt;
    m_ersterLauf = false;
}

void Geraete::laden()
{
    auto *w = new QFutureWatcher<QVariantList>(this);
    connect(w, &QFutureWatcher<QVariantList>::finished, this, [this, w] { emit geladen(w->result()); w->deleteLater(); });
    w->setFuture(QtConcurrent::run([] {
        if (qEnvironmentVariableIsSet("AURILIUX_GERAETE_DEMO")) return beispiel();
        QVariantList l = laufwerke();
        l += usbGeraete();
        l += bluetoothGeraete();
        l += bildschirme();
        l += netzteil();
        return l;
    }));
}

void Geraete::auswerfen(const QString &kennung, const QString &geraet)
{
    m_ausgeworfen.insert(geraet);
    auto *w = new QFutureWatcher<QString>(this);
    connect(w, &QFutureWatcher<QString>::finished, this, [this, w, kennung] { emit erledigt(kennung, w->result(), QString()); w->deleteLater(); });
    w->setFuture(QtConcurrent::run([geraet]() -> QString {
        if (qEnvironmentVariableIsSet("AURILIUX_GERAETE_DEMO")) return {};
        // zugehörige Platte und alle eingehängten Bereiche darauf finden
        const Ergebnis r = fuehreAus("lsblk", {"-J", "-l", "-o", "PATH,PKNAME,TYPE,MOUNTPOINT"}, 4000);
        const QJsonArray l = QJsonDocument::fromJson(r.text.toUtf8()).object().value("blockdevices").toArray();
        QString platte = geraet;
        for (const QJsonValue &v : l) {
            const QJsonObject o = v.toObject();
            if (o.value("path").toString() == geraet && o.value("type").toString() == "part") platte = "/dev/" + o.value("pkname").toString();
        }
        const QString plattenName = QFileInfo(platte).fileName();
        for (const QJsonValue &v : l) {
            const QJsonObject o = v.toObject();
            const bool dazu = o.value("path").toString() == platte || o.value("pkname").toString() == plattenName;
            if (!dazu || o.value("mountpoint").toString().isEmpty()) continue;
            const Ergebnis u = fuehreAus("udisksctl", {"unmount", "-b", o.value("path").toString(), "--no-user-interaction"});
            if (u.code != 0) return freundlich(u.text, QStringLiteral("Auswerfen"));
        }
        // Strom abschalten – klappt nicht bei jedem Gehäuse, dann ist es trotzdem sicher ausgehängt
        fuehreAus("udisksctl", {"power-off", "-b", platte, "--no-user-interaction"});
        return {};
    }));
}

void Geraete::einhaengen(const QString &kennung, const QString &geraet)
{
    auto *w = new QFutureWatcher<QPair<QString, QString>>(this);
    connect(w, &QFutureWatcher<QPair<QString, QString>>::finished, this, [this, w, kennung] {
        const auto e = w->result(); emit erledigt(kennung, e.first, e.second); w->deleteLater();
    });
    w->setFuture(QtConcurrent::run([geraet]() -> QPair<QString, QString> {
        if (qEnvironmentVariableIsSet("AURILIUX_GERAETE_DEMO")) return {QString(), QStringLiteral("/tmp")};
        const Ergebnis r = fuehreAus("udisksctl", {"mount", "-b", geraet, "--no-user-interaction"}, 15000);
        if (r.code != 0) return {freundlich(r.text, QStringLiteral("Einhängen")), QString()};
        static const QRegularExpression bei(QStringLiteral(" at (.+?)\\.?\\s*$"));
        return {QString(), bei.match(r.text.trimmed()).captured(1)};
    }));
}

void Geraete::bluetooth(const QString &kennung, const QString &adresse, bool verbinden)
{
    auto *w = new QFutureWatcher<QString>(this);
    connect(w, &QFutureWatcher<QString>::finished, this, [this, w, kennung] { emit erledigt(kennung, w->result(), QString()); w->deleteLater(); });
    w->setFuture(QtConcurrent::run([adresse, verbinden]() -> QString {
        if (qEnvironmentVariableIsSet("AURILIUX_GERAETE_DEMO")) return {};
        static const QRegularExpression ok(QStringLiteral("^[0-9A-F:]{17}$"));
        if (!ok.match(adresse).hasMatch()) return QStringLiteral("Gerät nicht gefunden");
        const Ergebnis r = fuehreAus("bluetoothctl", {verbinden ? "connect" : "disconnect", adresse}, 15000);
        const bool geklappt = r.code == 0 && (r.text.contains("successful") || r.text.contains("Successful"));
        if (geklappt) return {};
        return verbinden ? QStringLiteral("Verbinden hat nicht geklappt – ist das Gerät eingeschaltet und in der Nähe?")
                         : QStringLiteral("Trennen hat nicht geklappt");
    }));
}
