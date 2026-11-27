// Sperrwache (läuft unsichtbar in der Sitzung): sperrt den Bildschirm
//   · nach einigen Minuten ohne Eingabe (Wayland „ext-idle-notify“, Videos im Vollbild halten wach),
//   · bevor der Mac in den Ruhezustand geht (Deckel zu) – logind wartet, bis die Sperre steht,
//   · bei „loginctl lock-session“.
// Einstellung: ~/.config/auriliux/sperre.conf → sperren_nach_minuten=5 (0 = nie automatisch)
#pragma once
#include <QObject>
#include <QDBusUnixFileDescriptor>

class LeerlaufMelder;
class Leerlauf;

class Sperrwache : public QObject
{
    Q_OBJECT
public:
    explicit Sperrwache(QObject *parent = nullptr);
    static bool istGesperrt();

public slots:
    void sperren();
    void schlaf(bool beginnt);

private:
    void hemmen();
    void leerlaufEinrichten();
    int m_minuten = -1;
    QDBusUnixFileDescriptor m_hemmer;   // hält den Ruhezustand kurz auf, bis die Sperre steht
    LeerlaufMelder *m_melder = nullptr;
    Leerlauf *m_leerlauf = nullptr;
    qint64 m_letzterStart = 0;
};
