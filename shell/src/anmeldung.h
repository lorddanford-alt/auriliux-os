// Anmeldung über greetd: spricht dessen Protokoll (JSON über den Socket $GREETD_SOCK),
// prüft Benutzer + Passwort über PAM (macht greetd) und startet danach die Auriliux-Sitzung (labwc).
// Ohne greetd (Vorschau) gilt das Passwort „auriliux“.
#pragma once
#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class Anmeldung : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList benutzer READ benutzer CONSTANT)
    Q_PROPERTY(QString letzter READ letzter CONSTANT)
    Q_PROPERTY(bool beschaeftigt READ beschaeftigt NOTIFY beschaeftigtGeaendert)
public:
    explicit Anmeldung(QObject *parent = nullptr);
    QVariantList benutzer() const { return m_benutzer; }
    QString letzter() const { return m_letzter; }
    bool beschaeftigt() const { return m_beschaeftigt; }

    /// prüft das Passwort; bei Erfolg ist die Sitzung bestellt → erfolg(), sonst fehler(text)
    Q_INVOKABLE void anmelden(const QString &benutzer, const QString &passwort);
    /// "aus" | "neustart" | "ruhe"
    Q_INVOKABLE void energie(const QString &was);
    /// ist die Feststelltaste an?
    Q_INVOKABLE bool grossschreibung() const;

signals:
    void erfolg();
    void fehler(const QString &text);
    void beschaeftigtGeaendert();

private:
    QVariantList m_benutzer;
    QString m_letzter;
    bool m_beschaeftigt = false;
};
