#include "ebene.h"
#include <QQuickWindow>
#include <QMargins>
#include <LayerShellQt/Window>

void Ebene::einrichten(QQuickWindow *fenster, int kanten, int schicht, int zone, int tastatur,
                       int abstandOben, int abstandRechts, int abstandUnten, int abstandLinks, const QString &name)
{
    if (!fenster)
        return;
    auto *lw = LayerShellQt::Window::get(fenster);
    if (!lw)
        return;
    LayerShellQt::Window::Anchors a;
    if (kanten & Oben)   a |= LayerShellQt::Window::AnchorTop;
    if (kanten & Unten)  a |= LayerShellQt::Window::AnchorBottom;
    if (kanten & Links)  a |= LayerShellQt::Window::AnchorLeft;
    if (kanten & Rechts) a |= LayerShellQt::Window::AnchorRight;
    lw->setAnchors(a);
    lw->setLayer(static_cast<LayerShellQt::Window::Layer>(qBound(0, schicht, 3)));
    lw->setExclusiveZone(zone);
    lw->setKeyboardInteractivity(static_cast<LayerShellQt::Window::KeyboardInteractivity>(qBound(0, tastatur, 2)));
    lw->setMargins(QMargins(abstandLinks, abstandOben, abstandRechts, abstandUnten));
    lw->setScope(name.isEmpty() ? QStringLiteral("auriliux") : name);
}
