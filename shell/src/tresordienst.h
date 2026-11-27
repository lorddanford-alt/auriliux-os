// Verbindung zum Tresor-Dienst (root): Status aus /run/auriliux/tresor/status.json, Befehle über den Socket.
// Der Dienst nimmt Befehle nur von /usr/bin/auriliux-shell an; alte Stände gibt es nur mit gültiger Karte (Drehcode).
#pragma once
#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QFileSystemWatcher;

class TresorDienst : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantMap status READ status NOTIFY statusGeaendert)
    Q_PROPERTY(bool da READ da NOTIFY statusGeaendert)
public:
    explicit TresorDienst(QObject *parent = nullptr);
    QVariantMap status() const { return m_status; }
    bool da() const { return !m_status.isEmpty(); }

    /// Befehl an den Dienst; Antwort kommt über antwort(kennung, daten)
    Q_INVOKABLE void befehl(const QString &kennung, const QStringList &teile);
    /// Pfad im Wabenfinder zeigen (Ordner der zurückgeholten Datei)
    Q_INVOKABLE void zeigen(const QString &pfad);

signals:
    void statusGeaendert();
    void antwort(const QString &kennung, const QVariantMap &daten);

private:
    void lesen();
    QVariantMap m_status;
    QFileSystemWatcher *m_wache = nullptr;
    QTimer m_ruhe;
};
