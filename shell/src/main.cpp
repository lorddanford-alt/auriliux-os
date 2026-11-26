// Auriliux-Oberfläche – startet einen Teil der Oberfläche: „auriliux-shell goldleiste“
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QHash>
#include <QIcon>
#include "programme.h"
#include <cstdio>

int main(int argc, char *argv[])
{
    // Alle Fenster dieses Programms sind feste Bildschirm-Ebenen (Leiste, Dock, Menüs), keine normalen Fenster
    qputenv("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell");
    // Auriliux läuft nur unter Wayland (labwc) – nicht erst nach einer alten X11-Anzeige suchen
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "wayland");
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("auriliux-shell"));
    app.setOrganizationName(QStringLiteral("Auriliux"));

    const QHash<QString, QString> teile{
        {QStringLiteral("goldleiste"), QStringLiteral("Goldleiste")},
        {QStringLiteral("golddock"), QStringLiteral("Golddock")},
    };
    const QString teil = argc > 1 ? QString::fromLocal8Bit(argv[1]).toLower() : QStringLiteral("goldleiste");
    if (!teile.contains(teil)) {
        qCritical("Unbekannter Teil: %s (bekannt: goldleiste, golddock)", qPrintable(teil));
        return 2;
    }

    if (qEnvironmentVariableIsSet("AURILIUX_DIAGNOSE"))
        fprintf(stderr, "auriliux-shell: Plattform=%s, Bildschirme=%lld\n", qPrintable(QGuiApplication::platformName()),
                static_cast<long long>(QGuiApplication::screens().size()));

    // Symbole: Programme bringen ihre Symbole im Thema „hicolor“ mit
    if (QIcon::themeName().isEmpty()) QIcon::setThemeName(QStringLiteral("hicolor"));

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("symbol"), new SymbolBild);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("Auriliux"), teile.value(teil));
    if (qEnvironmentVariableIsSet("AURILIUX_DIAGNOSE"))
        fprintf(stderr, "auriliux-shell: %lld Hauptobjekt(e) geladen\n", static_cast<long long>(engine.rootObjects().size()));
    return app.exec();
}
