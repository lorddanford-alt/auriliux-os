#include "charakterspeicher.h"
#include <QBuffer>
#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QImageReader>
#include <QMutex>
#include <QPainter>
#include <QPainterPath>
#include <QSaveFile>
#include <QStandardPaths>
#include <algorithm>

namespace {
QString datei()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/auriliux/charakter.json");
}

// Bilder für die Rauten-Anzeige (Schlüssel → Bild), höchstens einige hundert
QMutex sperre;
QHash<QString, QImage> &rauten() { static QHash<QString, QImage> h; return h; }
} // namespace

QString CharakterSpeicher::laden() const
{
    QFile f(datei());
    if (!f.open(QIODevice::ReadOnly) || f.size() > 64 * 1024 * 1024) return {};
    return QString::fromUtf8(f.readAll());
}

bool CharakterSpeicher::speichern(const QString &json) const
{
    if (json.isEmpty()) return false;
    QDir().mkpath(QFileInfo(datei()).absolutePath());
    QSaveFile f(datei());
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    f.write(json.toUtf8());
    return f.commit();
}

QVariantList CharakterSpeicher::bilder() const
{
    const QStringList orte{QStandardPaths::writableLocation(QStandardPaths::PicturesLocation),
                           QStandardPaths::writableLocation(QStandardPaths::DesktopLocation),
                           QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)};
    QList<QFileInfo> l;
    for (const QString &o : orte) {
        if (o.isEmpty() || o == QDir::homePath()) continue;
        QDirIterator it(o, {"*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG"}, QDir::Files, QDirIterator::Subdirectories);
        int n = 0;
        while (it.hasNext() && n < 400) { it.next(); l << it.fileInfo(); ++n; }
    }
    std::sort(l.begin(), l.end(), [](const QFileInfo &a, const QFileInfo &b) { return a.lastModified() > b.lastModified(); });
    QVariantList r;
    for (const QFileInfo &f : l.mid(0, 120))
        r << QVariantMap{{"pfad", f.absoluteFilePath()}, {"name", f.fileName()}};
    return r;
}

QString CharakterSpeicher::bildEinlesen(const QString &pfad) const
{
    QImageReader r(pfad);
    r.setAutoTransform(true);
    const QSize s = r.size();
    if (s.isValid() && s.width() * qint64(s.height()) > 80'000'000) return {};      // riesige Bilder ablehnen
    QImage b = r.read();
    if (b.isNull()) return {};
    // mittig ausfüllen (wie object-fit: cover)
    const int k = qMin(b.width(), b.height());
    b = b.copy((b.width() - k) / 2, (b.height() - k) / 2, k, k).scaled(256, 256, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    QByteArray daten;
    QBuffer puffer(&daten);
    puffer.open(QIODevice::WriteOnly);
    b.convertToFormat(QImage::Format_RGB32).save(&puffer, "JPEG", 86);
    return QStringLiteral("data:image/jpeg;base64,") + QString::fromLatin1(daten.toBase64());
}

QString CharakterSpeicher::raute(const QString &dataUrl) const
{
    if (!dataUrl.startsWith(QLatin1String("data:image/"))) return {};
    const QString schluessel = QString::fromLatin1(QCryptographicHash::hash(dataUrl.toUtf8(), QCryptographicHash::Md5).toHex());
    QMutexLocker l(&sperre);
    if (!rauten().contains(schluessel)) {
        const int komma = dataUrl.indexOf(',');
        QImage b;
        b.loadFromData(QByteArray::fromBase64(dataUrl.mid(komma + 1).toLatin1()));
        if (b.isNull()) return {};
        if (rauten().size() > 600) rauten().clear();
        rauten().insert(schluessel, b);
    }
    return QStringLiteral("image://raute/") + schluessel;
}

QImage RautenBild::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    QImage quelle;
    {
        QMutexLocker l(&sperre);
        quelle = rauten().value(id.section('/', 0, 0));
    }
    const int g = requestedSize.width() > 0 ? requestedSize.width() : 160;
    QImage aus(g, g, QImage::Format_ARGB32_Premultiplied);
    aus.fill(Qt::transparent);
    if (!quelle.isNull()) {
        QPainter p(&aus);
        p.setRenderHint(QPainter::Antialiasing);
        p.setRenderHint(QPainter::SmoothPixmapTransform);
        QPainterPath raute;
        raute.moveTo(g / 2.0, 0); raute.lineTo(g, g / 2.0); raute.lineTo(g / 2.0, g); raute.lineTo(0, g / 2.0); raute.closeSubpath();
        p.setClipPath(raute);
        const int k = qMin(quelle.width(), quelle.height());
        // wie am Mac: das Bild füllt das Quadrat um die Raute, sichtbar ist nur die Raute
        p.drawImage(QRect(0, 0, g, g), quelle, QRect((quelle.width() - k) / 2, (quelle.height() - k) / 2, k, k));
    }
    if (size) *size = aus.size();
    return aus;
}
