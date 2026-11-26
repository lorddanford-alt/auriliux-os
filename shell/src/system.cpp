#include "system.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QTimer>

QString System::lies(const QString &pfad) const
{
    QFile f(pfad);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.read(64 * 1024));
}

QStringList System::liste(const QString &ordner) const
{
    return QDir(ordner).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System, QDir::Name);
}

bool System::gibt(const QString &pfad) const
{
    return QFileInfo::exists(pfad);
}

QString System::umgebung(const QString &name) const
{
    return qEnvironmentVariable(name.toUtf8().constData());
}

static QString einstellungsPfad(const QString &name)
{
    // nur einfache Dateinamen, kein Wechsel in andere Ordner
    if (name.isEmpty() || name.contains('/') || name.startsWith('.')) return {};
    return QDir::homePath() + QStringLiteral("/.config/auriliux/") + name;
}

bool System::schreibe(const QString &name, const QString &text) const
{
    const QString p = einstellungsPfad(name);
    if (p.isEmpty()) return false;
    QDir().mkpath(QFileInfo(p).absolutePath());
    QFile f(p);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    return f.write(text.toUtf8()) >= 0;
}

QString System::einstellung(const QString &name) const
{
    const QString p = einstellungsPfad(name);
    return p.isEmpty() ? QString() : lies(p);
}

bool System::starte(const QString &programm, const QStringList &argumente) const
{
    return QProcess::startDetached(programm, argumente);
}

void System::frage(const QString &kennung, const QString &programm, const QStringList &argumente)
{
    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::finished, this, [this, p, kennung](int code, QProcess::ExitStatus) {
        emit antwort(kennung, QString::fromUtf8(p->readAll()), code);
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, kennung](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            emit antwort(kennung, QString(), -1);
            p->deleteLater();
        }
    });
    // nie länger als 5 s hängen lassen
    QTimer::singleShot(5000, p, [p] { if (p->state() != QProcess::NotRunning) p->kill(); });
    p->start(programm, argumente);
}
