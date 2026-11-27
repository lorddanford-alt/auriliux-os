// Auriliux-Oberfläche – startet einen Teil der Oberfläche:
//   auriliux-shell goldleiste | golddock | schreibtisch | anmeldung   (feste Bildschirm-Ebenen)
//   auriliux-shell wabenfinder [ordner]       (normales Fenster)
//   auriliux-shell guardian [abschnitt]       (Schutz-Zentrale: uebersicht, schutz, ereignisse, herzschlag …)
//   auriliux-shell zentrale [abschnitt]       (Einstellungen: bildschirm, ton, wlan, bluetooth, tastatur, energie, benutzer, updates, ueber)
//   auriliux-shell charakter [bereich]        (Charakter: Übersicht oder muskulatur, bildung, geld, beziehung)
//   auriliux-shell tresor [versionen <pfad> | rettung <zeit-ms>]   (Tresor: Schnappschüsse, Sicherung, Zurückholen – mit Drehcode)
//   auriliux-shell sperre                     (Bildschirmsperre – besser über /usr/libexec/auriliux/sperren)
//   auriliux-shell sperrwache                 (unsichtbar: sperrt bei Leerlauf, vor dem Ruhezustand, auf Befehl)
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QHash>
#include <QIcon>
#include <QDir>
#include <QFileInfo>
#include <cstdio>
#include "programme.h"
#include "dateien.h"
#include "sperrwache.h"
#include "charakterspeicher.h"
#include <QScreen>
#include <QPointer>

int main(int argc, char *argv[])
{
    const QHash<QString, QString> ebenen{
        {QStringLiteral("goldleiste"), QStringLiteral("Goldleiste")},
        {QStringLiteral("golddock"), QStringLiteral("Golddock")},
        {QStringLiteral("schreibtisch"), QStringLiteral("Schreibtisch")},   // + Aufgaben-Leiste links
        {QStringLiteral("anmeldung"), QStringLiteral("Anmeldebildschirm")},  // goldener Login (von greetd gestartet)
    };
    const QHash<QString, QString> fenster{
        {QStringLiteral("wabenfinder"), QStringLiteral("Wabenfinder")},
        {QStringLiteral("guardian"), QStringLiteral("Guardian")},
        {QStringLiteral("zentrale"), QStringLiteral("Zentrale")},
        {QStringLiteral("charakter"), QStringLiteral("Charakter")},
        {QStringLiteral("tresor"), QStringLiteral("Tresor")},
    };
    const QString teil = argc > 1 ? QString::fromLocal8Bit(argv[1]).toLower() : QStringLiteral("goldleiste");
    const bool sperre = teil == QLatin1String("sperre"), wache = teil == QLatin1String("sperrwache");
    if (!ebenen.contains(teil) && !fenster.contains(teil) && !sperre && !wache) {
        fprintf(stderr, "Unbekannter Teil: %s (bekannt: goldleiste, golddock, schreibtisch, anmeldung, wabenfinder, guardian, zentrale, charakter, tresor, sperre, sperrwache)\n", qPrintable(teil));
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

    if (wache) {
        Sperrwache w;
        return app.exec();
    }

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("symbol"), new SymbolBild);
    engine.addImageProvider(QStringLiteral("vorschau"), new VorschauBild);
    engine.addImageProvider(QStringLiteral("wabe"), new WabenBild);
    engine.addImageProvider(QStringLiteral("raute"), new RautenBild);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);

    if (sperre) {
        // je Bildschirm eine Sperrfläche; nie von selbst beenden – nur Entsperren beendet das Programm
        app.setQuitOnLastWindowClosed(false);
        auto *flaechen = new QHash<QString, QPointer<QObject>>;
        const QString haupt = QGuiApplication::primaryScreen() ? QGuiApplication::primaryScreen()->name() : QString();
        auto laden = [&engine, flaechen, haupt](QScreen *s) {
            if (!s || flaechen->value(s->name())) return;
            engine.setInitialProperties({{QStringLiteral("bildschirm"), s->name()}, {QStringLiteral("haupt"), s->name() == haupt}});
            engine.loadFromModule(QStringLiteral("Auriliux"), QStringLiteral("Sperrbildschirm"));
            if (!engine.rootObjects().isEmpty()) flaechen->insert(s->name(), engine.rootObjects().last());
        };
        for (QScreen *s : QGuiApplication::screens()) laden(s);
        QObject::connect(&app, &QGuiApplication::screenAdded, &app, laden);
        QObject::connect(&app, &QGuiApplication::screenRemoved, &app, [flaechen](QScreen *s) {
            if (QObject *f = flaechen->take(s->name())) f->deleteLater();
        });
        return app.exec();
    }
    if (teil == QLatin1String("wabenfinder")) {
        QString start = argc > 2 ? QString::fromLocal8Bit(argv[2]) : QDir::homePath();
        if (start == QLatin1String("papierkorb")) start = Dateien().papierkorbOrdner();
        engine.setInitialProperties({{QStringLiteral("startPfad"), QFileInfo(start).absoluteFilePath()}});
    }
    if (teil == QLatin1String("tresor") && argc > 3)
        engine.setInitialProperties({{QStringLiteral("startModus"), QString::fromLocal8Bit(argv[2])}, {QStringLiteral("startWert"), QString::fromLocal8Bit(argv[3])}});
    if ((teil == QLatin1String("guardian") || teil == QLatin1String("zentrale") || teil == QLatin1String("charakter")) && argc > 2)
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
