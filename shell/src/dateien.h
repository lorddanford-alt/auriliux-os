// Dateisystem für den Wabenfinder: Ordner lesen, anlegen, umbenennen, Papierkorb, öffnen, suchen, Vorschaubilder
#pragma once
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QQuickImageProvider>
#include <QtQml/qqmlregistration.h>

class Dateien : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString heim READ heim CONSTANT)
public:
    explicit Dateien(QObject *parent = nullptr) : QObject(parent) {}
    QString heim() const;

    /// Orte für die linke Leiste: [{id, name, path}]
    Q_INVOKABLE QVariantList orte() const;
    /// Inhalt eines Ordners: {path, name, parent, items:[…], error}
    Q_INVOKABLE QVariantMap liste(const QString &pfad) const;
    /// Aktionen – liefern "" bei Erfolg, sonst eine Fehlermeldung
    Q_INVOKABLE QString neuerOrdner(const QString &eltern, const QString &name) const;
    Q_INVOKABLE QString neueDatei(const QString &eltern, const QString &name) const;
    Q_INVOKABLE QString umbenennen(const QString &pfad, const QString &name) const;
    Q_INVOKABLE QString inPapierkorb(const QString &pfad) const;
    Q_INVOKABLE bool oeffnen(const QString &pfad) const;
    Q_INVOKABLE void pfadKopieren(const QString &pfad) const;
    Q_INVOKABLE QString papierkorbOrdner() const;
    /// Suche (im Hintergrund) – Ergebnis kommt über gefunden(anfrage, items)
    Q_INVOKABLE void suchen(const QString &wurzel, const QString &text);

signals:
    void gefunden(const QString &anfrage, const QVariantList &items);
};

/// Vorschaubilder: image://vorschau/<pfad> – Fotos verkleinert, sonst leer
class VorschauBild : public QQuickImageProvider
{
public:
    VorschauBild() : QQuickImageProvider(QQuickImageProvider::Image, QQmlImageProviderBase::ForceAsynchronousImageLoading) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
