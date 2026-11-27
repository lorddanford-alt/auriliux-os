// Steuerung für die Zentrale (Einstellungen): Dinge, die nicht über ein einfaches Programm gehen.
//   · Helligkeit von Bildschirm und Tastatur über logind (ohne Root, nur in der eigenen Sitzung)
//   · WLAN mit Passwort über NetworkManager direkt – das Passwort steht nie in einer Befehlszeile
//   · Systeminfos und Benutzer
#pragma once
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class Steuerung : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit Steuerung(QObject *parent = nullptr);

    /// regelbare Lichter: [{art: "bildschirm"|"tastatur", geraet, wert, max}]
    Q_INVOKABLE QVariantList lichter() const;
    /// Helligkeit setzen → leerer Text = gut, sonst Fehlermeldung
    Q_INVOKABLE QString licht(const QString &art, const QString &geraet, int wert);
    /// WLAN verbinden (Passwort leer = offenes Netz) → wlanErgebnis(ssid, ok, text)
    Q_INVOKABLE void wlanVerbinden(const QString &ssid, const QString &passwort, const QString &sicherheit);
    /// Modell, Prozessor, Arbeitsspeicher, Speicher, Kern, System, Stand
    Q_INVOKABLE QVariantMap info() const;
    /// angemeldeter Benutzer: name, anzeige, admin
    Q_INVOKABLE QVariantMap benutzer() const;

signals:
    void wlanErgebnis(const QString &ssid, bool ok, const QString &text);

private:
    void wlanBeobachten(const QString &ssid, const QString &verbindung, const QString &aktiv, int runde);
};
