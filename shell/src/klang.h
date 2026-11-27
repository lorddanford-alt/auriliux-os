// Tresor-Geräusche, selbst erzeugt (keine fremden Tondateien): Klicken des Drehschlosses, Einrasten,
// Fehler, Ventil-Ratsche, Riegel und Tür. Beim ersten Gebrauch als kleine WAV-Dateien in
// $XDG_RUNTIME_DIR/auriliux/klang abgelegt – abgespielt werden sie in QML mit SoundEffect.
#pragma once
#include <QObject>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class Klang : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit Klang(QObject *parent = nullptr) : QObject(parent) {}
    /// "klick" | "rast" | "fehler" | "ventil" | "riegel" | "tuer" → Datei-Adresse (leer bei Fehler)
    Q_INVOKABLE QUrl datei(const QString &name) const;
};
