// Bildschirmsperre über das Wayland-Protokoll „ext-session-lock“: Der Fenster-Manager (labwc) selbst hält den
// Bildschirm gesperrt. Stürzt die Sperre ab, bleibt er trotzdem gesperrt – entsperrt wird nur nach richtigem
// Passwort (geprüft über PAM, Dienst „auriliux-sperre“).
// Ende des Programms: 0 = entsperrt · 3 = war schon gesperrt / verweigert · 4 = Sperren nicht möglich
#pragma once
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QtQml/qqmlregistration.h>

class SperrVerwalter;
class SperrObjekt;
class SperrIntegration;

class Sperre : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString anzeige READ anzeige CONSTANT)
    Q_PROPERTY(QString seit READ seit CONSTANT)
    Q_PROPERTY(bool gesperrt READ gesperrt NOTIFY gesperrtGeaendert)
    Q_PROPERTY(bool beschaeftigt READ beschaeftigt NOTIFY beschaeftigtGeaendert)
    Q_PROPERTY(QString aktiv READ aktiv NOTIFY aktivGeaendert)
public:
    explicit Sperre(QObject *parent = nullptr);
    ~Sperre() override;
    QString anzeige() const { return m_anzeige; }
    QString seit() const { return m_seit; }
    bool gesperrt() const { return m_gesperrt; }
    bool beschaeftigt() const { return m_beschaeftigt; }
    QString aktiv() const { return m_aktiv; }

    /// macht das Fenster zur Sperrfläche auf dem Bildschirm mit diesem Namen (vor dem Anzeigen aufrufen)
    Q_INVOKABLE bool einrichten(QQuickWindow *fenster, const QString &bildschirm);
    /// prüft das Passwort → erfolg() oder fehler(text)
    Q_INVOKABLE void entsperren(const QString &passwort);
    /// nach erfolg(): Sperre wirklich aufheben und beenden (nur nach richtigem Passwort möglich)
    Q_INVOKABLE void aufheben();
    /// "aus" | "neustart" | "ruhe"
    Q_INVOKABLE void energie(const QString &was);
    Q_INVOKABLE bool grossschreibung() const;

    // vom Protokoll
    void istGesperrt();
    void istBeendet();

signals:
    void erfolg();
    void fehler(const QString &text);
    void gesperrtGeaendert();
    void beschaeftigtGeaendert();
    void aktivGeaendert();   // Bildschirm, auf dem gerade getippt wird

private:
    QString m_benutzer, m_anzeige, m_seit;
    bool m_gesperrt = false, m_beschaeftigt = false, m_passwortRichtig = false, m_aufgehoben = false;
    QString m_aktiv;
    int m_fehlversuche = 0;
    SperrVerwalter *m_verwalter = nullptr;
    SperrObjekt *m_sperre = nullptr;
    SperrIntegration *m_integration = nullptr;
};
