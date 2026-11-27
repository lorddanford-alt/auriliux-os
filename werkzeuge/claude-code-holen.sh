#!/bin/bash
# Holt Claude Code (Terminal-Version von Claude, von Anthropic) für das Systemabbild – genau wie der offizielle
# Installer (claude.ai/install.sh): neueste Version aus dem Release-Verzeichnis, Prüfsumme aus dessen manifest.json.
# Ziel: $1/usr/lib/claude-code/claude (+ Versionsdatei). Bricht bei jeder Abweichung ab.
set -euo pipefail
ziel="${1:?Zielordner fehlt}"
basis="https://downloads.claude.ai/claude-code-releases"
plattform="linux-x64"
version=$(curl -fsSL --retry 3 "$basis/latest")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Unerwartete Versionsangabe: ${version:0:80}" >&2; exit 1; }
manifest=$(curl -fsSL --retry 3 "$basis/$version/manifest.json")
if [[ $manifest =~ \"$plattform\"[[:space:]]*:[[:space:]]*[{][^{}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
    summe="${BASH_REMATCH[1]}"
else
    echo "Keine Prüfsumme für $plattform im Manifest" >&2; exit 1
fi
mkdir -p "$ziel/usr/lib/claude-code"
datei="$ziel/usr/lib/claude-code/claude"
curl -fsSL --retry 3 -o "$datei" "$basis/$version/$plattform/claude"
echo "$summe  $datei" | sha256sum -c -
chmod 755 "$datei"
echo "$version" > "$ziel/usr/lib/claude-code/version"
# feste Zeitstempel: bleibt die Version gleich, ist auch die Abbild-Schicht gleich (kein erneuter Download beim Update)
find "$ziel" -exec touch -h -d @0 {} +
echo "Claude Code $version ($(du -h "$datei" | cut -f1)), Prüfsumme stimmt"
