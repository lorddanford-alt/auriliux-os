#!/usr/bin/env python3
"""Baut aus image/installer/auriliux.ks die config.toml für bootc-image-builder (Installer-ISO).
Aufruf: python3 werkzeuge/installer-config.py > config.toml"""
import pathlib, sys
ks = (pathlib.Path(__file__).resolve().parent.parent / "image/installer/auriliux.ks").read_text(encoding="utf-8")
if "'''" in ks:
    sys.exit("Kickstart darf keine ''' enthalten")
print("# erzeugt aus image/installer/auriliux.ks – nicht von Hand ändern")
print("[customizations.installer.kickstart]")
print("contents = '''\n" + ks + "'''")
print()
print("[customizations.installer.modules]")
print('enable = ["org.fedoraproject.Anaconda.Modules.Localization", "org.fedoraproject.Anaconda.Modules.Timezone", "org.fedoraproject.Anaconda.Modules.Users"]')
