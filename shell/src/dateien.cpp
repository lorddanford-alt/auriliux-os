#include "dateien.h"
#include <QClipboard>
#include <QCollator>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QIcon>
#include <QGuiApplication>
#include <QImageReader>
#include <QMimeDatabase>
#include <QStandardPaths>
#include <QThread>
#include <QUrl>
#include <QtConcurrent/QtConcurrentRun>
#include <QFutureWatcher>

namespace {
const QStringList bildEndungen{"jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "tif", "tiff"};

QString artDeutsch(const QFileInfo &fi)
{
    static const QHash<QString, QString> t{
        {"txt", "Textdokument"}, {"pdf", "PDF-Dokument"}, {"jpg", "JPEG-Bild"}, {"jpeg", "JPEG-Bild"}, {"png", "PNG-Bild"},
        {"gif", "GIF-Bild"}, {"webp", "WebP-Bild"}, {"mp4", "MPEG-4-Film"}, {"mov", "QuickTime-Film"}, {"mkv", "Film"},
        {"mp3", "MP3-Audio"}, {"wav", "WAV-Audio"}, {"docx", "Word-Dokument"}, {"xlsx", "Excel-Tabelle"},
        {"pptx", "PowerPoint"}, {"zip", "ZIP-Archiv"}, {"html", "HTML-Dokument"}, {"md", "Markdown"},
        {"json", "JSON-Daten"}, {"sh", "Skript"}, {"py", "Python-Skript"}, {"iso", "Abbild"}};
    const QString e = fi.suffix().toLower();
    return t.value(e, e.isEmpty() ? QStringLiteral("Dokument") : e.toUpper() + QStringLiteral("-Datei"));
}

QVariantMap eintrag(const QFileInfo &fi, bool zaehlen, bool symbole = false)
{
    QVariantMap m;
    m.insert("name", fi.fileName());
    m.insert("path", fi.absoluteFilePath());
    m.insert("dir", fi.isDir());
    m.insert("mtime", fi.lastModified().toMSecsSinceEpoch());
    if (fi.isDir()) {
        m.insert("kind", QStringLiteral("Ordner"));
        if (zaehlen) {
            QDir d(fi.absoluteFilePath());
            m.insert("count", d.isReadable() ? int(d.entryList(QDir::AllEntries | QDir::NoDotAndDotDot).size()) : -1);
        }
    } else {
        const QString e = fi.suffix().toLower();
        m.insert("ext", e);
        m.insert("size", fi.size());
        m.insert("kind", artDeutsch(fi));
        m.insert("image", bildEndungen.contains(e));
        if (symbole) {
            if (e == QLatin1String("desktop")) {
                // Programm-Verknüpfung auf dem Schreibtisch: Name und Symbol aus der Datei
                QString name, nameDe, symbol;
                QFile f(fi.absoluteFilePath());
                if (f.open(QIODevice::ReadOnly)) {
                    bool gruppe = false;
                    for (const QByteArray &roh : f.read(32768).split('\n')) {
                        const QString z = QString::fromUtf8(roh).trimmed();
                        if (z.startsWith('[')) { gruppe = z == QLatin1String("[Desktop Entry]"); continue; }
                        if (!gruppe) continue;
                        if (z.startsWith(QLatin1String("Name="))) name = z.mid(5);
                        else if (z.startsWith(QLatin1String("Name[de]="))) nameDe = z.mid(9);
                        else if (z.startsWith(QLatin1String("Icon="))) symbol = z.mid(5);
                    }
                }
                const QString titel = !nameDe.isEmpty() ? nameDe : name;
                m.insert("titel", titel.isEmpty() ? fi.completeBaseName() : titel);
                m.insert("symbol", symbol.isEmpty() ? QStringLiteral("application-x-executable") : symbol);
                m.insert("programm", true);
                // Sicherheit wie unter Linux üblich: nur ausführbar markierte Verknüpfungen dürfen starten
                m.insert("vertraut", fi.isExecutable());
            } else {
                static QMimeDatabase db;
                const QMimeType t = db.mimeTypeForFile(fi, QMimeDatabase::MatchExtension);
                QString sym = t.iconName();
                if (!QIcon::hasThemeIcon(sym)) sym = t.genericIconName();
                if (!QIcon::hasThemeIcon(sym)) sym = QStringLiteral("text-x-generic");
                m.insert("symbol", sym);
            }
        }
    }
    return m;
}

bool nameOk(const QString &n) { return !n.isEmpty() && !n.contains('/') && n != "." && n != ".."; }
} // namespace

QString Dateien::heim() const { return QDir::homePath(); }

QString Dateien::schreibtisch() const
{
    const QString p = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    QDir().mkpath(p);
    return p;
}

QVariantList Dateien::orte() const
{
    QVariantList l;
    auto ort = [&l](const QString &id, const QString &name, const QString &pfad) {
        if (!QFileInfo::exists(pfad)) return;
        QVariantMap m; m.insert("id", id); m.insert("name", name); m.insert("path", pfad); l << m;
    };
    ort("home", QFileInfo(QDir::homePath()).fileName(), QDir::homePath());
    auto std = [](QStandardPaths::StandardLocation s) { return QStandardPaths::writableLocation(s); };
    ort("desktop", "Schreibtisch", std(QStandardPaths::DesktopLocation));
    ort("documents", "Dokumente", std(QStandardPaths::DocumentsLocation));
    ort("downloads", "Downloads", std(QStandardPaths::DownloadLocation));
    ort("pictures", "Bilder", std(QStandardPaths::PicturesLocation));
    ort("music", "Musik", std(QStandardPaths::MusicLocation));
    ort("movies", "Videos", std(QStandardPaths::MoviesLocation));
    ort("trash", "Papierkorb", papierkorbOrdner());
    return l;
}

QString Dateien::papierkorbOrdner() const
{
    const QString p = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Trash/files");
    QDir().mkpath(p);
    return p;
}

QVariantMap Dateien::liste(const QString &pfad) const
{
    QVariantMap r;
    QDir d(pfad.isEmpty() ? QDir::homePath() : pfad);
    r.insert("path", d.absolutePath());
    r.insert("name", d.absolutePath() == "/" ? QStringLiteral("Auriliux") : d.dirName());
    QDir oben(d); r.insert("parent", oben.cdUp() && d.absolutePath() != "/" ? oben.absolutePath() : QString());
    if (!d.exists()) { r.insert("error", QStringLiteral("Ordner gibt es nicht mehr")); r.insert("items", QVariantList()); return r; }
    if (!d.isReadable()) { r.insert("error", QStringLiteral("Kein Zugriff auf diesen Ordner")); r.insert("items", QVariantList()); return r; }
    QVariantList items;
    const auto infos = d.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot, QDir::NoSort);   // versteckte Dateien (.xyz) wie am Mac nicht zeigen
    for (const QFileInfo &fi : infos) items << eintrag(fi, true, true);
    r.insert("items", items);
    return r;
}

QString Dateien::neuerOrdner(const QString &eltern, const QString &name) const
{
    if (!nameOk(name)) return QStringLiteral("Ungültiger Name");
    QDir d(eltern);
    if (d.exists(name)) return QStringLiteral("„%1“ gibt es hier schon.").arg(name);
    return d.mkdir(name) ? QString() : QStringLiteral("Ordner konnte nicht erstellt werden");
}

QString Dateien::neueDatei(const QString &eltern, const QString &name) const
{
    if (!nameOk(name)) return QStringLiteral("Ungültiger Name");
    const QString p = QDir(eltern).filePath(name);
    if (QFileInfo::exists(p)) return QStringLiteral("„%1“ gibt es hier schon.").arg(name);
    QFile f(p);
    return f.open(QIODevice::WriteOnly | QIODevice::NewOnly) ? QString() : QStringLiteral("Datei konnte nicht erstellt werden");
}

QString Dateien::umbenennen(const QString &pfad, const QString &name) const
{
    if (!nameOk(name)) return QStringLiteral("Ungültiger Name");
    const QFileInfo fi(pfad);
    const QString ziel = fi.dir().filePath(name);
    if (QFileInfo::exists(ziel)) return QStringLiteral("„%1“ gibt es hier schon.").arg(name);
    return QFile::rename(pfad, ziel) ? QString() : QStringLiteral("Umbenennen nicht möglich");
}

QString Dateien::inPapierkorb(const QString &pfad) const
{
    QString ziel;
    return QFile::moveToTrash(pfad, &ziel) ? QString() : QStringLiteral("Konnte nicht in den Papierkorb gelegt werden");
}

bool Dateien::oeffnen(const QString &pfad) const { return QDesktopServices::openUrl(QUrl::fromLocalFile(pfad)); }

void Dateien::pfadKopieren(const QString &pfad) const { QGuiApplication::clipboard()->setText(pfad); }

void Dateien::suchen(const QString &wurzel, const QString &text)
{
    const QString q = text.trimmed();
    auto *w = new QFutureWatcher<QVariantList>(this);
    connect(w, &QFutureWatcher<QVariantList>::finished, this, [this, w, q] { emit gefunden(q, w->result()); w->deleteLater(); });
    w->setFuture(QtConcurrent::run([wurzel, q]() {
        QVariantList out;
        QDirIterator it(wurzel, QDir::AllEntries | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        int geprueft = 0;
        while (it.hasNext() && out.size() < 240 && geprueft < 200000) {
            it.next(); ++geprueft;
            const QFileInfo fi = it.fileInfo();
            if (fi.fileName().contains(q, Qt::CaseInsensitive)) out << eintrag(fi, false);
        }
        return out;
    }));
}

QString Dateien::verschieben(const QString &pfad, const QString &zielOrdner) const
{
    const QFileInfo fi(pfad);
    if (!fi.exists()) return QStringLiteral("Gibt es nicht mehr");
    const QString ziel = QDir(zielOrdner).filePath(fi.fileName());
    if (QFileInfo(zielOrdner).absoluteFilePath() == fi.absolutePath()) return {};
    if ((QFileInfo(zielOrdner).absoluteFilePath() + '/').startsWith(fi.absoluteFilePath() + '/'))
        return QStringLiteral("Ein Ordner passt nicht in sich selbst");
    if (QFileInfo::exists(ziel)) return QStringLiteral("„%1“ gibt es dort schon.").arg(fi.fileName());
    return QFile::rename(pfad, ziel) ? QString() : QStringLiteral("Verschieben nicht möglich");
}

void Dateien::kopieren(const QString &kennung, const QString &pfad, const QString &zielOrdner)
{
    auto *w = new QFutureWatcher<QString>(this);
    connect(w, &QFutureWatcher<QString>::finished, this, [this, w, kennung] { emit kopiert(kennung, w->result()); w->deleteLater(); });
    w->setFuture(QtConcurrent::run([pfad, zielOrdner]() -> QString {
        const QFileInfo fi(pfad);
        const QString ziel = QDir(zielOrdner).filePath(fi.fileName());
        if (QFileInfo::exists(ziel)) return QStringLiteral("„%1“ gibt es dort schon.").arg(fi.fileName());
        if (!fi.isDir()) return QFile::copy(pfad, ziel) ? QString() : QStringLiteral("Kopieren nicht möglich");
        if (!QDir().mkpath(ziel)) return QStringLiteral("Kopieren nicht möglich");
        QDirIterator it(pfad, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden, QDirIterator::Subdirectories);
        const QDir quelle(pfad);
        while (it.hasNext()) {
            it.next();
            const QString neu = QDir(ziel).filePath(quelle.relativeFilePath(it.filePath()));
            if (it.fileInfo().isDir() && !it.fileInfo().isSymLink()) { if (!QDir().mkpath(neu)) return QStringLiteral("Kopieren abgebrochen"); }
            else if (!QFile::copy(it.filePath(), neu)) return QStringLiteral("Kopieren abgebrochen bei „%1“").arg(it.fileName());
        }
        return {};
    }));
}

void Dateien::beobachte(const QString &pfad)
{
    if (!m_wache) {
        m_wache = new QFileSystemWatcher(this);
        connect(m_wache, &QFileSystemWatcher::directoryChanged, this, &Dateien::ordnerGeaendert);
    }
    if (!m_wache->directories().contains(pfad)) m_wache->addPath(pfad);
}

QImage VorschauBild::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QString pfad = QUrl::fromPercentEncoding(id.toUtf8());
    QImageReader r(pfad);
    r.setAutoTransform(true);
    const int k = requestedSize.width() > 0 ? requestedSize.width() : 140;
    const QSize s = r.size();
    if (s.isValid() && (s.width() > k || s.height() > k)) {
        // so verkleinern, dass das Bild den Platz ausfüllt (wie object-fit: cover)
        const qreal f = qMax(qreal(k) / s.width(), qreal(k) / s.height());
        r.setScaledSize(QSize(qMax(1, qRound(s.width() * f)), qMax(1, qRound(s.height() * f))));
    }
    QImage img = r.read();
    if (size) *size = img.size();
    return img;
}
