// Macht ein QML-Fenster zu einer festen Bildschirm-Ebene (Wayland „layer shell“): oben verankert, reserviert Platz usw.
#pragma once
#include <QObject>
#include <QtQml/qqmlregistration.h>
#include <QQuickWindow>

class Ebene : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    enum Kante { Oben = 1, Unten = 2, Links = 4, Rechts = 8 };
    Q_ENUM(Kante)
    enum Schicht { Hintergrund = 0, Unterhalb = 1, Darueber = 2, Ganzoben = 3 };
    Q_ENUM(Schicht)

    explicit Ebene(QObject *parent = nullptr) : QObject(parent) {}

    /// Muss vor dem ersten Anzeigen aufgerufen werden.
    /// kanten: Oben|Unten|Links|Rechts · zone: freizuhaltender Platz (-1 = nichts verdrängen)
    /// tastatur: 0 keine, 1 exklusiv, 2 bei Bedarf · abstaende: oben, rechts, unten, links
    Q_INVOKABLE void einrichten(QQuickWindow *fenster, int kanten, int schicht, int zone, int tastatur,
                                int abstandOben = 0, int abstandRechts = 0, int abstandUnten = 0, int abstandLinks = 0,
                                const QString &name = QString());
    /// Nur diese Rechtecke nehmen Maus-Klicks an – alles andere geht durch zu den Fenstern dahinter.
    /// bereiche: Liste von {x, y, w, h}; leere Liste = ganzes Fenster
    Q_INVOKABLE void klickBereich(QQuickWindow *fenster, const QVariantList &bereiche);
    /// Schicht und Tastatur später umstellen (z. B. Aufgaben-Leiste beim Aufklappen nach vorne holen)
    Q_INVOKABLE void schicht(QQuickWindow *fenster, int schicht);
    Q_INVOKABLE void tastatur(QQuickWindow *fenster, int tastatur);
};
