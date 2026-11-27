// Daten des Charakter-Fensters: ~/.local/share/auriliux/charakter.json – gleiches Format wie am Mac
// (Wabenfinder › Charakter), die Datei lässt sich also einfach herüberkopieren.
// Bilder für Fähigkeiten werden auf 256 px verkleinert und direkt in der Datei gespeichert.
#pragma once
#include <QObject>
#include <QQuickImageProvider>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class CharakterSpeicher : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit CharakterSpeicher(QObject *parent = nullptr) : QObject(parent) {}

    /// gespeicherter Stand (JSON-Text), leer = noch nichts angelegt
    Q_INVOKABLE QString laden() const;
    /// sicher speichern (erst neue Datei, dann austauschen; nur für dich lesbar)
    Q_INVOKABLE bool speichern(const QString &json) const;
    /// Bilder zur Auswahl: Bilder-, Schreibtisch- und Download-Ordner, neueste zuerst
    Q_INVOKABLE QVariantList bilder() const;
    /// Bild einlesen → 256 px, als „data:image/jpeg;base64,…“ (wie am Mac); leer bei Fehler
    Q_INVOKABLE QString bildEinlesen(const QString &pfad) const;
    /// Bild (data-URL) als Raute anzeigen → Quelle „image://raute/<schlüssel>“
    Q_INVOKABLE QString raute(const QString &dataUrl) const;
};

/// image://raute/<schlüssel>: das Bild ausgefüllt und rautenförmig ausgeschnitten (durchsichtige Ecken)
class RautenBild : public QQuickImageProvider
{
public:
    RautenBild() : QQuickImageProvider(QQuickImageProvider::Image) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
