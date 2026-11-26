// Fensterliste des Systems (über das Wayland-Protokoll „foreign toplevel“ von labwc):
// welches Programm vorne ist, welche Fenster offen sind – und sie aktivieren, minimieren, schließen.
#pragma once
#include <QAbstractListModel>
#include <QList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class FensterManager;
class Toplevel;

class Fenster : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString aktivAppId READ aktivAppId NOTIFY aktivGeaendert)
    Q_PROPERTY(QString aktivTitel READ aktivTitel NOTIFY aktivGeaendert)
    Q_PROPERTY(bool aktivVollbild READ aktivVollbild NOTIFY aktivGeaendert)
    Q_PROPERTY(bool verbunden READ verbunden NOTIFY verbundenGeaendert)
    Q_PROPERTY(int anzahl READ rowCount NOTIFY anzahlGeaendert)
public:
    enum Rolle { AppIdRolle = Qt::UserRole + 1, TitelRolle, AktivRolle, MinimiertRolle, VollbildRolle };
    explicit Fenster(QObject *parent = nullptr);
    ~Fenster() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString aktivAppId() const;
    QString aktivTitel() const;
    bool aktivVollbild() const;
    bool verbunden() const;

    Q_INVOKABLE void aktivieren(int zeile);
    Q_INVOKABLE void minimieren(int zeile);
    Q_INVOKABLE void schliessen(int zeile);
    /// alle Fenster eines Programms (app_id) nach vorn holen bzw. das erste davon aktivieren
    Q_INVOKABLE bool programmAktivieren(const QString &appId);
    /// Home: alle Fenster minimieren (Schreibtisch zeigen); nochmal → zurückholen
    Q_INVOKABLE void alleMinimieren();
    Q_INVOKABLE void alleZurueck();
    /// aktives Fenster schließen („Sofort beenden“)
    Q_INVOKABLE void aktivesSchliessen();
    /// app_ids aller offenen Fenster (für das Dock: läuft / läuft nicht)
    Q_INVOKABLE QStringList laufendeProgramme() const;
    /// Fenster eines Programms: [{zeile, titel, minimiert, aktiv}]
    Q_INVOKABLE QVariantList fensterVon(const QString &appId) const;
    /// sind alle Fenster dieses Programms minimiert?
    Q_INVOKABLE bool alleMinimiert(const QString &appId) const;
    Q_INVOKABLE void programmMinimieren(const QString &appId);
    Q_INVOKABLE void programmSchliessen(const QString &appId);
    /// ist der Home-Modus (alles minimiert) gerade aktiv?
    Q_INVOKABLE bool homeAktiv() const { return !m_vonHomeMinimiert.isEmpty(); }

signals:
    void aktivGeaendert();
    void verbundenGeaendert();
    void anzahlGeaendert();

private:
    void neu(Toplevel *t);
    void geaendert(Toplevel *t);
    void weg(Toplevel *t);
    FensterManager *m_manager = nullptr;
    QList<Toplevel *> m_liste;
    QList<Toplevel *> m_vonHomeMinimiert;
};
