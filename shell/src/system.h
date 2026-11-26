// Zugriff der Oberfläche auf das System: kleine Dateien lesen (/proc, /sys), Programme starten,
// Programmausgaben abfragen. Bewusst ohne Shell – Argumente werden nie als Befehlstext ausgewertet.
#pragma once
#include <QObject>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class System : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit System(QObject *parent = nullptr) : QObject(parent) {}

    /// Inhalt einer kleinen Datei (max. 64 KB), leer bei Fehler
    Q_INVOKABLE QString lies(const QString &pfad) const;
    /// Einträge eines Ordners (nur Namen)
    Q_INVOKABLE QStringList liste(const QString &ordner) const;
    /// Gibt es diese Datei/diesen Ordner?
    Q_INVOKABLE bool gibt(const QString &pfad) const;
    /// Umgebungsvariable
    Q_INVOKABLE QString umgebung(const QString &name) const;
    /// Programm starten und nicht darauf warten
    Q_INVOKABLE bool starte(const QString &programm, const QStringList &argumente = {}) const;
    /// Programm starten, Ausgabe kommt später über das Signal antwort(kennung, text)
    Q_INVOKABLE void frage(const QString &kennung, const QString &programm, const QStringList &argumente = {});

signals:
    void antwort(const QString &kennung, const QString &text, int code);
};
