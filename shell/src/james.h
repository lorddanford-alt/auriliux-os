// James für Auriliux OS – Verbindung zum eigenen KI-Server (Gehirn, Gedächtnis, Stimme bleiben dort).
//
// Zwei Teile benutzen diese Klasse:
//   • das James-Fenster (auriliux-shell james): Chat, Aufträge, Einrichtung – nur Anfragen an den Server
//   • der James-Dienst (auriliux-shell james-dienst, unsichtbar + Sprechblase): meldet alle 30 s „Laptop an,
//     Schalter an?“, hört auf Knopfdruck zu (Super+J), spricht die Antworten, führt freigegebene
//     Claude-Code-Aufträge aus und einfache Aktionen (Webseite, Programm, Hinweis).
//
// Einstellungen: ~/.config/auriliux/james.json (Server-Adresse + App-Schlüssel, nur für dich lesbar).
// KI-Schalter: ~/.config/auriliux/ki-schalter („an“/„aus“, gemeinsam mit der Goldleiste).
// Ohne Schalter „an“ hört James nicht zu, spricht nicht und führt nichts aus.
#pragma once
#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QByteArray>
#include <QElapsedTimer>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlregistration.h>
#include <functional>
#include <memory>

class QNetworkAccessManager;
class QNetworkReply;
class QNetworkRequest;
class QLocalServer;
class QFileSystemWatcher;
class QProcess;
class QAudioSource;
class QIODevice;
class QMediaPlayer;
class QAudioOutput;
class QBuffer;
class QSoundEffect;

class JamesDienst : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool eingerichtet READ eingerichtet NOTIFY konfigGeaendert)
    Q_PROPERTY(QString server READ server NOTIFY konfigGeaendert)
    Q_PROPERTY(QString serverName READ serverName NOTIFY konfigGeaendert)
    Q_PROPERTY(bool an READ an WRITE setAn NOTIFY anGeaendert)
    Q_PROPERTY(QString name READ name NOTIFY nameGeaendert)
    Q_PROPERTY(bool verbunden READ verbunden NOTIFY verbundenGeaendert)
    Q_PROPERTY(QString verbindungsFehler READ verbindungsFehler NOTIFY verbundenGeaendert)
    Q_PROPERTY(bool dienstLaeuft READ dienstLaeuft NOTIFY dienstGeaendert)
    // Sprechblase (nur im Dienst)
    Q_PROPERTY(QString zustand READ zustand NOTIFY blaseGeaendert)       // "" | hoert | denkt | spricht | hinweis
    Q_PROPERTY(QString blasenText READ blasenText NOTIFY blaseGeaendert)
    Q_PROPERTY(qreal pegel READ pegel NOTIFY pegelGeaendert)              // Mikrofon 0..1 (für die Anzeige)
    Q_PROPERTY(QString auftragText READ auftragText NOTIFY auftragGeaendert)  // läuft gerade ein Auftrag?
    Q_PROPERTY(QString vorne READ vorne WRITE setVorne NOTIFY vorneGeaendert) // Programm vorne (für den Server)
public:
    explicit JamesDienst(QObject *parent = nullptr);
    ~JamesDienst() override;

    bool eingerichtet() const { return !m_server.isEmpty() && m_token.size() >= 32; }
    QString server() const { return m_server; }
    QString serverName() const;
    bool an() const { return m_an; }
    void setAn(bool an);
    QString name() const { return m_name; }
    bool verbunden() const { return m_verbunden; }
    QString verbindungsFehler() const { return m_verbindungsFehler; }
    bool dienstLaeuft() const { return m_dienstLaeuft; }
    QString zustand() const { return m_zustand; }
    QString blasenText() const { return m_blasenText; }
    qreal pegel() const { return m_pegel; }
    QString auftragText() const { return m_auftragText; }
    QString vorne() const { return m_vorne; }
    void setVorne(const QString &v) { if (v != m_vorne) { m_vorne = v; emit vorneGeaendert(); } }

    /// Server-Adresse und App-Schlüssel speichern (leerer Schlüssel = alten behalten). Fehlertext oder "".
    /// Danach wird die Verbindung geprüft → Signal einrichtungGeprueft.
    Q_INVOKABLE QString einrichten(const QString &adresse, const QString &schluessel);
    Q_INVOKABLE bool schluesselGespeichert() const { return m_token.size() >= 32; }
    /// Anfrage an api.php?a=<aktion>; zusatz z. B. "&vor=120". Antwort kommt als antwort(kennung, daten).
    Q_INVOKABLE void anfrage(const QString &kennung, const QString &aktion, const QVariantMap &daten = {}, const QString &zusatz = {});
    /// Chat-Nachricht schicken; die Antwort kommt Stück für Stück als live(art, daten): text | fertig | fehler
    Q_INVOKABLE void senden(const QString &text);
    Q_INVOKABLE void sendenAbbrechen();
    /// ganze Webseite (Gedächtnis, Regeln, Einstellungen …) in einem Chrome-Fenster öffnen
    Q_INVOKABLE void webseite() const;
    /// Befehl an den laufenden James-Dienst: hoeren | stopp | vorlesen <id>
    Q_INVOKABLE bool befehl(const QString &b);
    /// macht diese Instanz zum Hintergrund-Dienst (nur auriliux-shell james-dienst)
    Q_INVOKABLE void dienst();
    Q_INVOKABLE void blaseGeklickt();
    Q_INVOKABLE void blaseSchliessen();

    /// kleiner Befehlszeilen-Weg (auriliux-shell james-befehl …): schickt an den Dienst, gibt Exit-Code zurück
    static int befehlSenden(const QString &b);

signals:
    void konfigGeaendert();
    void anGeaendert();
    void nameGeaendert();
    void verbundenGeaendert();
    void dienstGeaendert();
    void blaseGeaendert();
    void pegelGeaendert();
    void auftragGeaendert();
    void vorneGeaendert();
    void antwort(const QString &kennung, const QVariantMap &daten);
    void live(const QString &art, const QVariantMap &daten);
    void einrichtungGeprueft(bool ok, const QString &text);

private slots:
    void schlafSignal(bool schlaeft);

private:
    // Grundlagen
    void konfigLaden();
    void schalterLesen();
    QNetworkRequest anfrageBauen(const QString &aktion, const QString &zusatz, int timeoutMs) const;
    void post(const QString &aktion, const QVariantMap &daten, int timeoutMs, std::function<void(const QVariantMap &, int)> fertig);
    QNetworkReply *liveStarten(const QString &text, const QString &modus,
                               std::function<void(const QVariantMap &)> zeile, std::function<void(const QString &, int)> ende);
    void verbindungMerken(bool ok, const QString &fehler);
    void dienstPruefen();

    // Dienst
    void herzschlag();
    void impuls();
    void aktionen(const QVariant &roh);
    bool programmOeffnen(const QString &name);
    void blase(const QString &zustand, const QString &text, int sekunden = 0);
    void befehlAusfuehren(const QString &b);
    bool beschaeftigt() const;

    // Ohr
    void hoerenUmschalten();
    void ohrStarten(double warteSekunden, bool gespraech);
    void ohrStoppen();
    void tonDaten();
    void tonVerarbeiten(const QByteArray &pcm16);
    void aufnahmeFertig();
    void abschreiben(const QByteArray &pcm16);
    void gehoert(QString text);
    void klang(const QString &name);

    // Mund
    void stimmeSenden(const QString &frage);
    void sprich(const QString &text);
    void teilDazu(const QString &text, int runde);
    void weiterSprechen(int runde);
    void teilGespielt();
    void antwortFertig();
    void vorlesenId(int id);
    void audioHolen(const QVariantMap &daten, std::function<void(const QByteArray &)> fertig);
    void stoppen();
    static QString vorlesbar(const QString &t);

    // Aufträge
    void auftragHolen();
    void auftragStarten(const QVariantMap &a);
    void auftragAbbrechen(const QString &grund);
    void auftragFertig(int code);
    void auftragMelden(int id, const QString &status, const QString &text);

    QNetworkAccessManager *m_netz = nullptr;
    QFileSystemWatcher *m_wache = nullptr;
    QString m_server, m_token, m_name = QStringLiteral("James");
    bool m_an = false, m_verbunden = false, m_dienstLaeuft = false, m_istDienst = false;
    QString m_verbindungsFehler;
    QPointer<QNetworkReply> m_chat;

    // Dienst-Zustand
    QString m_zustand, m_blasenText, m_auftragText, m_vorne;
    QTimer m_takt, m_blasenUhr;
    QLocalServer *m_steuerung = nullptr;
    bool m_schlaeft = false, m_darfHandeln = false, m_impulsLaeuft = false, m_mikroAn = true, m_vorlesen = true;
    int m_impulsMinuten = 60;
    double m_gespraechSekunden = 20, m_pause = 4;
    QString m_weckwort = QStringLiteral("James");
    QElapsedTimer m_seitImpuls;
    int m_beschaeftigtTakte = 0;

    // Ohr
    QAudioSource *m_quelle = nullptr;
    QIODevice *m_strom = nullptr;
    int m_quellRate = 16000, m_quellKanaele = 1, m_quellArt = 0;      // 0 Int16, 1 Float, 2 Int32, 3 UInt8
    double m_resteZeit = 0;                                              // für die Umrechnung auf 16 kHz
    QByteArray m_vorlauf, m_aufnahme;
    bool m_aufnehmen = false, m_gespraech = false;
    double m_rauschen = 0.004, m_stimme = 0;
    int m_lautFolge = 0, m_rahmenProben = 0;
    double m_rahmenSumme = 0, m_stilleSek = 0, m_aufnahmeSek = 0, m_sprachSek = 0, m_lernSumme = 0;
    int m_lernAnzahl = 0;
    qreal m_pegel = 0;
    QTimer m_ohrFrist;
    QSoundEffect *m_ton = nullptr;

    // Mund
    struct Teil { QString text; QByteArray daten; bool geladen = false; };
    QList<std::shared_ptr<Teil>> m_teile;
    int m_runde = 0, m_spielRunde = 0;
    QString m_aktuellerText;
    bool m_spielt = false, m_streamFertig = true, m_denkt = false;
    QString m_liveText, m_vorher;
    QPointer<QNetworkReply> m_live;
    QMediaPlayer *m_spieler = nullptr;
    QAudioOutput *m_ausgabe = nullptr;
    QBuffer *m_puffer = nullptr;
    QTimer m_sprechWache;

    // Aufträge
    QProcess *m_lauf = nullptr;
    int m_laufId = 0;
    QString m_laufGrund;
    QElapsedTimer m_laufUhr;
    QByteArray m_laufAus, m_laufFehler;
};
