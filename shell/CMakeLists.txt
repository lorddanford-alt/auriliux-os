# Auriliux-Oberfläche: ein Programm für Goldleiste, Golddock usw. (Qt 6 / QML, Wayland-Ebenen)
cmake_minimum_required(VERSION 3.21)
project(auriliux-shell VERSION 0.1 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Gui Quick Qml)
find_package(LayerShellQt REQUIRED)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(auriliux-shell src/main.cpp)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(auriliux-shell
    URI Auriliux
    VERSION 1.0
    SOURCES src/system.h src/system.cpp src/ebene.h src/ebene.cpp
    QML_FILES
        qml/Theme.qml
        qml/Goldleiste.qml
        qml/AuriliuxMenue.qml
        qml/Menuepunkt.qml
        qml/Messbalken.qml
        qml/Trenner.qml
        qml/WlanSymbol.qml
        qml/AkkuSymbol.qml
        qml/Raute.qml
)

target_include_directories(auriliux-shell PRIVATE src)
target_compile_options(auriliux-shell PRIVATE -Wall -Wextra)
target_link_libraries(auriliux-shell PRIVATE Qt6::Gui Qt6::Quick Qt6::Qml LayerShellQt::Interface)
install(TARGETS auriliux-shell RUNTIME DESTINATION bin)
