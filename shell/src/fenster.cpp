#include "fenster.h"
#include <QGuiApplication>
#include <QtGui/qguiapplication_platform.h>
#include <QtWaylandClient/qwaylandclientextension.h>
#include "qwayland-wlr-foreign-toplevel-management-unstable-v1.h"

// ── ein einzelnes Fenster ──────────────────────────────────────────────────
class Toplevel : public QObject, public QtWayland::zwlr_foreign_toplevel_handle_v1
{
    Q_OBJECT
public:
    explicit Toplevel(::zwlr_foreign_toplevel_handle_v1 *h) : QtWayland::zwlr_foreign_toplevel_handle_v1(h) {}
    ~Toplevel() override { if (object()) destroy(); }

    QString titel, appId;
    bool aktiv = false, minimiert = false, maximiert = false, vollbild = false;

signals:
    void fertig();
    void zu();

protected:
    void zwlr_foreign_toplevel_handle_v1_title(const QString &t) override { m_titel = t; }
    void zwlr_foreign_toplevel_handle_v1_app_id(const QString &a) override { m_appId = a; }
    void zwlr_foreign_toplevel_handle_v1_state(wl_array *zustand) override
    {
        m_aktiv = m_minimiert = m_maximiert = m_vollbild = false;
        const auto *w = static_cast<const uint32_t *>(zustand->data);
        const size_t n = zustand->size / sizeof(uint32_t);
        for (size_t i = 0; i < n; ++i) {
            switch (w[i]) {
            case state_maximized:  m_maximiert = true; break;
            case state_minimized:  m_minimiert = true; break;
            case state_activated:  m_aktiv = true; break;
            case state_fullscreen: m_vollbild = true; break;
            default: break;
            }
        }
        m_zustandNeu = true;
    }
    void zwlr_foreign_toplevel_handle_v1_done() override
    {
        if (!m_titel.isNull()) titel = m_titel;
        if (!m_appId.isNull()) appId = m_appId;
        if (m_zustandNeu) { aktiv = m_aktiv; minimiert = m_minimiert; maximiert = m_maximiert; vollbild = m_vollbild; }
        m_titel = QString(); m_appId = QString(); m_zustandNeu = false;
        emit fertig();
    }
    void zwlr_foreign_toplevel_handle_v1_closed() override { emit zu(); }

private:
    QString m_titel, m_appId;
    bool m_aktiv = false, m_minimiert = false, m_maximiert = false, m_vollbild = false, m_zustandNeu = false;
};

// ── Verbindung zum Fenster-Manager ───────────────────────────────────────────
class FensterManager : public QWaylandClientExtensionTemplate<FensterManager>, public QtWayland::zwlr_foreign_toplevel_manager_v1
{
    Q_OBJECT
public:
    FensterManager() : QWaylandClientExtensionTemplate<FensterManager>(3) { initialize(); }
signals:
    void neuesFenster(::zwlr_foreign_toplevel_handle_v1 *h);
protected:
    void zwlr_foreign_toplevel_manager_v1_toplevel(::zwlr_foreign_toplevel_handle_v1 *h) override { emit neuesFenster(h); }
    void zwlr_foreign_toplevel_manager_v1_finished() override {}
};

static wl_seat *sitz()
{
    if (auto *wa = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>())
        return wa->seat();
    return nullptr;
}

Fenster::Fenster(QObject *parent) : QAbstractListModel(parent)
{
    m_manager = new FensterManager();
    connect(m_manager, &FensterManager::activeChanged, this, &Fenster::verbundenGeaendert);
    connect(m_manager, &FensterManager::neuesFenster, this, [this](::zwlr_foreign_toplevel_handle_v1 *h) { neu(new Toplevel(h)); });
}

Fenster::~Fenster()
{
    qDeleteAll(m_liste);
    delete m_manager;
}

void Fenster::neu(Toplevel *t)
{
    t->setParent(this);
    connect(t, &Toplevel::fertig, this, [this, t] { geaendert(t); });
    connect(t, &Toplevel::zu, this, [this, t] { weg(t); });
    beginInsertRows({}, m_liste.size(), m_liste.size());
    m_liste.append(t);
    endInsertRows();
    emit anzahlGeaendert();
}

void Fenster::geaendert(Toplevel *t)
{
    const int i = m_liste.indexOf(t);
    if (i >= 0) emit dataChanged(index(i), index(i));
    emit aktivGeaendert();
}

void Fenster::weg(Toplevel *t)
{
    const int i = m_liste.indexOf(t);
    if (i < 0) return;
    beginRemoveRows({}, i, i);
    m_liste.removeAt(i);
    endRemoveRows();
    m_vonHomeMinimiert.removeAll(t);
    t->deleteLater();
    emit anzahlGeaendert();
    emit aktivGeaendert();
}

int Fenster::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : m_liste.size(); }

QVariant Fenster::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_liste.size()) return {};
    const Toplevel *t = m_liste.at(index.row());
    switch (role) {
    case AppIdRolle: return t->appId;
    case TitelRolle: return t->titel;
    case AktivRolle: return t->aktiv;
    case MinimiertRolle: return t->minimiert;
    case VollbildRolle: return t->vollbild;
    default: return {};
    }
}

QHash<int, QByteArray> Fenster::roleNames() const
{
    return {{AppIdRolle, "appId"}, {TitelRolle, "titel"}, {AktivRolle, "aktiv"}, {MinimiertRolle, "minimiert"}, {VollbildRolle, "vollbild"}};
}

QString Fenster::aktivAppId() const { for (auto *t : m_liste) if (t->aktiv) return t->appId; return {}; }
QString Fenster::aktivTitel() const { for (auto *t : m_liste) if (t->aktiv) return t->titel; return {}; }
bool Fenster::aktivVollbild() const { for (auto *t : m_liste) if (t->aktiv) return t->vollbild; return false; }
bool Fenster::verbunden() const { return m_manager && m_manager->isActive(); }

void Fenster::aktivieren(int zeile)
{
    if (zeile < 0 || zeile >= m_liste.size()) return;
    auto *t = m_liste.at(zeile);
    if (t->minimiert) t->unset_minimized();
    if (auto *s = sitz()) t->activate(s);
}
void Fenster::minimieren(int zeile) { if (zeile >= 0 && zeile < m_liste.size()) m_liste.at(zeile)->set_minimized(); }
void Fenster::schliessen(int zeile) { if (zeile >= 0 && zeile < m_liste.size()) m_liste.at(zeile)->close(); }

bool Fenster::programmAktivieren(const QString &appId)
{
    bool gefunden = false;
    for (int i = 0; i < m_liste.size(); ++i) {
        if (m_liste.at(i)->appId.compare(appId, Qt::CaseInsensitive) == 0) { aktivieren(i); gefunden = true; }
    }
    return gefunden;
}

void Fenster::alleMinimieren()
{
    m_vonHomeMinimiert.clear();
    for (auto *t : std::as_const(m_liste)) {
        if (!t->minimiert) { t->set_minimized(); m_vonHomeMinimiert.append(t); }
    }
}

void Fenster::alleZurueck()
{
    auto *s = sitz();
    for (auto *t : std::as_const(m_vonHomeMinimiert)) { t->unset_minimized(); if (s) t->activate(s); }
    m_vonHomeMinimiert.clear();
}

void Fenster::aktivesSchliessen() { for (auto *t : std::as_const(m_liste)) if (t->aktiv) { t->close(); return; } }

QStringList Fenster::laufendeProgramme() const
{
    QStringList l;
    for (auto *t : m_liste) if (!l.contains(t->appId)) l << t->appId;
    return l;
}

#include "fenster.moc"
