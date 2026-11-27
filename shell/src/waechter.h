// Brücke zu den Diensten Guardian (Schutz) und Herzschlag (Leistung):
//  • liest ihre Statusdateien unter /run/auriliux (und merkt Änderungen sofort)
//  • schickt Entscheidungen (Zulassen, Freigeben, Quarantäne …) über den Steuer-Socket
//  • prüft für das Guardian-Fenster, was als normaler Benutzer sichtbar ist: Übersicht, Prozesse, Autostarts, Speicher
#pragma once
#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QFileSystemWatcher;

class Waechter : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantMap status READ status NOTIFY statusGeaendert)
    Q_PROPERTY(QVariantMap herz READ herz NOTIFY herzGeaendert)
    Q_PROPERTY(bool dienstDa READ dienstDa NOTIFY statusGeaendert)
    Q_PROPERTY(bool herzDa READ herzDa NOTIFY herzGeaendert)
public:
    explicit Waechter(QObject *parent = nullptr);

    QVariantMap status() const { return m_status; }
    QVariantMap herz() const { return m_herz; }
    bool dienstDa() const { return !m_status.isEmpty(); }
    bool herzDa() const { return !m_herz.isEmpty(); }

    /// Befehl an den Guardian (im Hintergrund) – Ergebnis über antwort(kennung, {ok, text|fehler})
    Q_INVOKABLE void befehl(const QString &kennung, const QStringList &teile);
    /// "uebersicht" | "prozesse" | "autostarts" | "speicher" – Ergebnis über geladen(art, daten)
    Q_INVOKABLE void laden(const QString &art);
    /// eigene Prozesse höflich beenden (SIGTERM) – liefert die Anzahl
    Q_INVOKABLE int beenden(const QVariantList &pids);
    /// eigenen systemd-Dienst nicht mehr automatisch starten – "" bei Erfolg
    Q_INVOKABLE QString dienstAbschalten(const QString &einheit);
    /// der Goldleiste: welches Programm ist vorne (für Vorrang und Fokus-Modus des Herzschlags)
    Q_INVOKABLE void vorneMelden(const QString &kennung, bool vollbild);

signals:
    void statusGeaendert();
    void herzGeaendert();
    void antwort(const QString &kennung, const QVariantMap &daten);
    void geladen(const QString &art, const QVariant &daten);

private:
    void einlesen();
    void wachen();
    QVariantMap m_status, m_herz;
    QByteArray m_statusRoh, m_herzRoh;
    QFileSystemWatcher *m_wache = nullptr;
    QTimer m_ruhe, m_suche;
    QString m_vorne;
};
