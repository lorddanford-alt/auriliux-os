// Angeschlossene Geräte für den Geräte-Kreis in der Aufgaben-Leiste (wie am Mac):
// Laufwerke (USB-Sticks, Festplatten, Netz), USB- und Bluetooth-Geräte, Bildschirme, Netzteil.
// Neue USB-Laufwerke werden automatisch eingehängt; Auswerfen trennt sie sicher.
#pragma once
#include <QObject>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QFileSystemWatcher;
class QSocketNotifier;

class Geraete : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit Geraete(QObject *parent = nullptr);

    /// Liste im Hintergrund ermitteln – kommt über geladen(items)
    Q_INVOKABLE void laden();
    /// Laufwerk sicher trennen (alle Bereiche aushängen, dann ausschalten) – Ergebnis über erledigt()
    Q_INVOKABLE void auswerfen(const QString &kennung, const QString &geraet);
    /// Laufwerk einhängen – erledigt(kennung, fehler, pfad)
    Q_INVOKABLE void einhaengen(const QString &kennung, const QString &geraet);
    /// Bluetooth-Gerät verbinden / trennen
    Q_INVOKABLE void bluetooth(const QString &kennung, const QString &adresse, bool verbinden);

signals:
    void geladen(const QVariantList &items);
    void geaendert();                     // etwas wurde angesteckt / abgezogen / ein- oder ausgehängt
    void erledigt(const QString &kennung, const QString &fehler, const QString &pfad);

private:
    void beobachten();
    void automatischEinhaengen(const QVariantList &items);
    QTimer m_ruhe;                        // fasst viele Meldungen beim Anstecken zusammen
    QSet<QString> m_bekannt;              // schon gesehene Laufwerke (nur neue werden eingehängt)
    QSet<QString> m_ausgeworfen;          // vom Nutzer ausgeworfen – nicht wieder einhängen
    bool m_ersterLauf = true;
    QFileSystemWatcher *m_wache = nullptr;
    QSocketNotifier *m_mounts = nullptr;
};
