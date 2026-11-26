// Auriliux-Oberfläche – startet einen Teil der Oberfläche: „auriliux-shell goldleiste“
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QHash>

int main(int argc, char *argv[])
{
    // Alle Fenster dieses Programms sind feste Bildschirm-Ebenen (Leiste, Dock, Menüs), keine normalen Fenster
    qputenv("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell");
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("auriliux-shell"));
    app.setOrganizationName(QStringLiteral("Auriliux"));

    const QHash<QString, QString> teile{
        {QStringLiteral("goldleiste"), QStringLiteral("Goldleiste")},
    };
    const QString teil = argc > 1 ? QString::fromLocal8Bit(argv[1]).toLower() : QStringLiteral("goldleiste");
    if (!teile.contains(teil)) {
        qCritical("Unbekannter Teil: %s (bekannt: goldleiste)", qPrintable(teil));
        return 2;
    }

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("Auriliux"), teile.value(teil));
    return app.exec();
}
