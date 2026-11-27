// Auriliux-Oberfläche – startet einen Teil der Oberfläche:
//   auriliux-shell goldleiste | golddock | schreibtisch   (feste Bildschirm-Ebenen)
//   auriliux-shell wabenfinder [ordner]       (normales Fenster)
//   auriliux-shell guardian [abschnitt]       (Schutz-Zentrale: uebersicht, schutz, ereignisse, herzschlag …)
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QHash>
#include <QIcon>
#include <QDir>
#include <QFileInfo>
#include <cstdio>
#include "programme.h"
#include "dateien.h"

int main(int argc, char *argv[])
{
    const QHash<QString, QString> ebenen{
        {QStringLiteral("goldleiste"), QStringLiteral("Goldleiste")},
        {QStringLiteral("golddock"), QStringLiteral("Golddock")},
        {QStringLiteral("schreibtisch"), QStringLiteral("Schreibtisch")},   // + Aufgaben-Leiste links
    };
    const QHash<QString, QString> fenster{
        {QStringLiteral("wabenfinder"), QStringLiteral("Wabenfinder")},
        {QStringLiteral("guardian"), QStringLiteral("Guardian")},
    };
    const QString teil = argc > 1 ? QString::fromLocal8Bit(argv[1]).toLower() : QStringLiteral("goldleiste");
    if (!ebenen.contains(teil) && !fenster.contains(teil)) {
        fprintf(stderr, "Unbekannter Teil: %s (bekannt: goldleiste, golddock, schreibtisch, wabenfinder, guardian)\n", qPrintable(teil));
        return 2;
    }

    // Leiste/Dock/Menüs sind feste Bildschirm-Ebenen, keine normalen Fenster
    if (ebenen.contains(teil))
        qputenv("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell");
    // Auriliux läuft nur unter Wayland (labwc) – nicht erst nach einer alten X11-Anzeige suchen
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "wayland");

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("auriliux-") + teil);
    app.setOrganizationName(QStringLiteral("Auriliux"));
    if (fenster.contains(teil)) app.setDesktopFileName(teil);     // Kennung für Leiste und Dock

    if (qEnvironmentVariableIsSet("AURILIUX_DIAGNOSE"))
        fprintf(stderr, "auriliux-shell: Plattform=%s, Bildschirme=%lld\n", qPrintable(QGuiApplication::platformName()),
                static_cast<long long>(QGuiApplication::screens().size()));

    // Symbole: Programme bringen ihre Symbole im Thema „hicolor“ mit
    if (QIcon::themeName().isEmpty()) QIcon::setThemeName(QStringLiteral("hicolor"));
    QIcon::setFallbackThemeName(QStringLiteral("Adwaita"));

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("symbol"), new SymbolBild);
    engine.addImageProvider(QStringLiteral("vorschau"), new VorschauBild);
    engine.addImageProvider(QStringLiteral("wabe"), new WabenBild);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);

    if (teil == QLatin1String("wabenfinder")) {
        QString start = argc > 2 ? QString::fromLocal8Bit(argv[2]) : QDir::homePath();
        if (start == QLatin1String("papierkorb")) start = Dateien().papierkorbOrdner();
        engine.setInitialProperties({{QStringLiteral("startPfad"), QFileInfo(start).absoluteFilePath()}});
    }
    if (teil == QLatin1String("guardian") && argc > 2)
        engine.setInitialProperties({{QStringLiteral("startAbschnitt"), QString::fromLocal8Bit(argv[2])}});
    engine.loadFromModule(QStringLiteral("Auriliux"), ebenen.value(teil, fenster.value(teil)));
    if (teil == QLatin1String("schreibtisch") && !engine.rootObjects().isEmpty()) {
        // zweite Ebene im selben Programm: senkrechte Aufgaben-Leiste mit Geräte-Kreis
        QObject *tisch = engine.rootObjects().constFirst();
        engine.loadFromModule(QStringLiteral("Auriliux"), QStringLiteral("Aufgaben"));
        if (engine.rootObjects().size() > 1) {
            QObject *aufgaben = engine.rootObjects().last();
            tisch->setProperty("aufgaben", QVariant::fromValue(aufgaben));
            aufgaben->setProperty("tisch", QVariant::fromValue(tisch));
        }
    }
    if (qEnvironmentVariableIsSet("AURILIUX_DIAGNOSE"))
        fprintf(stderr, "auriliux-shell: %lld Hauptobjekt(e) geladen\n", static_cast<long long>(engine.rootObjects().size()));
    return app.exec();
}
