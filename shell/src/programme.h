// Verzeichnis aller Programme (aus den .desktop-Dateien): Name, Symbol, Start – für App-Suche, Dock und Leiste.
#pragma once
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QQuickImageProvider>
#include <QtQml/qqmlregistration.h>

class Programme : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList liste READ liste NOTIFY listeGeaendert)
public:
    explicit Programme(QObject *parent = nullptr);

    QVariantList liste() const { return m_liste; }
    /// Name/Symbol/Datei zu einer app_id (Fenster-Kennung), leer wenn unbekannt
    Q_INVOKABLE QVariantMap info(const QString &appId) const;
    /// Programm über seine .desktop-Datei starten
    Q_INVOKABLE bool starten(const QString &datei) const;
    Q_INVOKABLE void neuEinlesen();

signals:
    void listeGeaendert();

private:
    QVariantList m_liste;
};

/// liefert Programmsymbole für QML: Image { source: "image://symbol/google-chrome" }
class SymbolBild : public QQuickImageProvider
{
public:
    SymbolBild() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
};
