# Auriliux-Oberfläche: ein Programm für Goldleiste, Golddock usw. (Qt 6 / QML, Wayland-Ebenen)
cmake_minimum_required(VERSION 3.21)
project(auriliux-shell VERSION 0.1 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Gui Quick Qml WaylandClient Concurrent DBus Network Multimedia)
# Bildschirmsperre braucht die inneren Teile von Qt-Wayland (eigene Fensterart „Sperrfläche“)
find_package(Qt6 QUIET COMPONENTS WaylandClientPrivate)
find_package(PkgConfig)
if(PkgConfig_FOUND)
    pkg_get_variable(WAYLAND_PROTOKOLLE wayland-protocols pkgdatadir)
endif()
if(NOT WAYLAND_PROTOKOLLE)
    set(WAYLAND_PROTOKOLLE /usr/share/wayland-protocols)
endif()
find_package(LayerShellQt REQUIRED)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(auriliux-shell src/main.cpp)

set(AURILIUX_QML
    qml/Theme.qml qml/Goldleiste.qml qml/AuriliuxMenue.qml qml/Menuepunkt.qml qml/Segmente.qml
    qml/Trenner.qml qml/WlanSymbol.qml qml/AkkuSymbol.qml qml/Raute.qml qml/Modul.qml qml/Lupe.qml
    qml/KiStern.qml qml/AppSuche.qml qml/DockKreis.qml qml/Golddock.qml
    qml/Wabe.qml qml/WabenSymbol.qml qml/WabenHintergrund.qml qml/Wabenfinder.qml
    qml/Schreibtisch.qml qml/Aufgaben.qml
    qml/Fase.qml qml/Knopf.qml qml/Herz.qml qml/Guardian.qml qml/GuardianKarte.qml qml/Goldtor.qml qml/Anmeldebildschirm.qml qml/Sperrbildschirm.qml qml/Zentrale.qml qml/Charakter.qml qml/Tresor.qml qml/James.qml qml/JamesBlase.qml qml/PasswortBestaetigung.qml)
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
# Dateien liegen im Ordner qml/, sollen im Modul aber direkt neben qmldir liegen – sonst sehen sie
# die eigenen Typen (Theme, System, Ebene) nicht
foreach(datei IN LISTS AURILIUX_QML)
    get_filename_component(name "${datei}" NAME)
    set_source_files_properties(${datei} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()
qt_add_qml_module(auriliux-shell
    URI Auriliux
    VERSION 1.0
    SOURCES src/system.h src/system.cpp src/ebene.h src/ebene.cpp src/fenster.h src/fenster.cpp src/programme.h src/programme.cpp src/dateien.h src/dateien.cpp src/geraete.h src/geraete.cpp src/waechter.h src/waechter.cpp src/anmeldung.h src/anmeldung.cpp
            src/sperre.h src/sperre.cpp src/sperrwache.h src/sperrwache.cpp src/steuerung.h src/steuerung.cpp src/charakterspeicher.h src/charakterspeicher.cpp src/tresordienst.h src/tresordienst.cpp src/klang.h src/klang.cpp src/james.h src/james.cpp src/weckwort.h src/weckwort.cpp
    QML_FILES ${AURILIUX_QML}
)

# Wayland-Protokolle: Fensterliste („foreign toplevel“, labwc), Bildschirmsperre, Leerlauf-Meldung
qt6_generate_wayland_protocol_client_sources(auriliux-shell
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/protokolle/wlr-foreign-toplevel-management-unstable-v1.xml
          ${WAYLAND_PROTOKOLLE}/staging/ext-session-lock/ext-session-lock-v1.xml
          ${WAYLAND_PROTOKOLLE}/staging/ext-idle-notify/ext-idle-notify-v1.xml)

target_include_directories(auriliux-shell PRIVATE src)
target_compile_options(auriliux-shell PRIVATE -Wall -Wextra)
target_link_libraries(auriliux-shell PRIVATE Qt6::Gui Qt6::Quick Qt6::Qml Qt6::WaylandClient Qt6::WaylandClientPrivate
                      Qt6::Concurrent Qt6::DBus Qt6::Network Qt6::Multimedia LayerShellQt::Interface pam)

# kleines Hilfsprogramm für Passwort-Bestätigungen (Guardian, Tresor) – nur PAM, sonst nichts
add_executable(passwort-pruefen src/passwort-pruefen.c)
target_link_libraries(passwort-pruefen PRIVATE pam)

# Weckwort „James“: Spracherkennung whisper.cpp fest eingebaut (nur Prozessor, mit AVX2/FMA des i5 aus 2015).
# Ohne Quellordner wird ohne Weckwort gebaut – James hört dann nur auf Super+J.
set(AURILIUX_WHISPER "" CACHE PATH "Quellordner von whisper.cpp")
if(AURILIUX_WHISPER AND EXISTS "${AURILIUX_WHISPER}/CMakeLists.txt")
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    foreach(aus WHISPER_BUILD_TESTS WHISPER_BUILD_EXAMPLES WHISPER_BUILD_SERVER WHISPER_CURL WHISPER_SDL2 WHISPER_FFMPEG
                GGML_NATIVE GGML_OPENMP GGML_CCACHE GGML_AVX512 GGML_AVX_VNNI GGML_AMX_TILE GGML_AMX_INT8 GGML_AMX_BF16 GGML_BACKEND_DL GGML_CPU_ALL_VARIANTS)
        set(${aus} OFF CACHE BOOL "" FORCE)
    endforeach()
    foreach(an GGML_SSE42 GGML_AVX GGML_AVX2 GGML_FMA GGML_F16C GGML_BMI2)
        set(${an} ON CACHE BOOL "" FORCE)
    endforeach()
    add_subdirectory(${AURILIUX_WHISPER} whisper EXCLUDE_FROM_ALL)
    target_link_libraries(auriliux-shell PRIVATE whisper)
    target_compile_definitions(auriliux-shell PRIVATE AURILIUX_WECKWORT=1)
    message(STATUS "Weckwort: whisper.cpp aus ${AURILIUX_WHISPER}")
endif()

install(TARGETS auriliux-shell RUNTIME DESTINATION bin)
