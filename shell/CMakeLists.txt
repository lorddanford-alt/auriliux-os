# Auriliux-Oberfläche: ein Programm für Goldleiste, Golddock usw. (Qt 6 / QML, Wayland-Ebenen)
cmake_minimum_required(VERSION 3.21)
project(auriliux-shell VERSION 0.1 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Gui Quick Qml WaylandClient)
find_package(LayerShellQt REQUIRED)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(auriliux-shell src/main.cpp)

set(AURILIUX_QML
    qml/Theme.qml qml/Goldleiste.qml qml/AuriliuxMenue.qml qml/Menuepunkt.qml qml/Segmente.qml
    qml/Trenner.qml qml/WlanSymbol.qml qml/AkkuSymbol.qml qml/Raute.qml qml/Modul.qml qml/Lupe.qml
    qml/KiStern.qml qml/AppSuche.qml qml/DockKreis.qml qml/Golddock.qml)
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
    SOURCES src/system.h src/system.cpp src/ebene.h src/ebene.cpp src/fenster.h src/fenster.cpp src/programme.h src/programme.cpp
    QML_FILES ${AURILIUX_QML}
)

# Fensterliste über das Wayland-Protokoll „foreign toplevel“ (labwc)
qt6_generate_wayland_protocol_client_sources(auriliux-shell
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/protokolle/wlr-foreign-toplevel-management-unstable-v1.xml)

target_include_directories(auriliux-shell PRIVATE src)
target_compile_options(auriliux-shell PRIVATE -Wall -Wextra)
target_link_libraries(auriliux-shell PRIVATE Qt6::Gui Qt6::Quick Qt6::Qml Qt6::WaylandClient LayerShellQt::Interface)
install(TARGETS auriliux-shell RUNTIME DESTINATION bin)
