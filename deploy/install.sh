#!/bin/bash
# Installation du serveur ToG sur un Raspberry Pi 64 bits (aarch64).
#
# À exécuter sur le Pi, depuis un clone du repo :
#   sudo bash deploy/install.sh
#
# Le script peut être relancé sans risque (idempotent) :
#  - il ne réinstalle pas Godot s'il est déjà présent ;
#  - il ne reclone pas /opt/tog s'il existe déjà.
#
# Après installation :
#  - serveur lancé par systemd :   systemctl status tog-serveur
#  - mise à jour auto toutes les 1 min depuis GitHub main, puis relance.
set -euo pipefail

GODOT_VERSION=4.7.2
REPO_URL=https://github.com/iliane442/tog.git
INSTALL_DIR=/opt/tog
GODOT_BIN=/usr/local/bin/godot
SERVEUR_USER=tog
ICI="$(cd "$(dirname "$0")" && pwd)"

[ "$(uname -m)" = "aarch64" ] || { echo "ERREUR : ce script vise un Raspberry Pi 64 bits (aarch64), pas $(uname -m)." >&2; exit 1; }
[ "$(id -u)" = 0 ] || { echo "ERREUR : lance avec sudo : sudo bash $0" >&2; exit 1; }

echo "== 1/6 Dépendances"
apt-get update -qq
apt-get install -y -qq git curl unzip ca-certificates

echo "== 2/6 Utilisateur dédié '$SERVEUR_USER'"
id "$SERVEUR_USER" &>/dev/null || useradd --system --create-home --shell /usr/sbin/nologin "$SERVEUR_USER"

echo "== 3/6 Godot ${GODOT_VERSION} headless (arm64)"
if [ ! -x "$GODOT_BIN" ]; then
    tmp="$(mktemp -d)"
    curl -fL --progress-bar -o "$tmp/godot.zip" \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.arm64.zip"
    unzip -oq "$tmp/godot.zip" -d "$tmp"
    install -m 755 "$tmp/Godot_v${GODOT_VERSION}-stable_linux.arm64" "$GODOT_BIN"
    rm -rf "$tmp"
else
    echo "   déjà présent : $GODOT_BIN"
fi
"$GODOT_BIN" --version | head -1

echo "== 4/6 Code du jeu dans $INSTALL_DIR"
if [ ! -d "$INSTALL_DIR/.git" ]; then
    # Clonage complet (pas de --depth 1) : met à jour par fetch + reset.
    git clone "$REPO_URL" "$INSTALL_DIR"
else
    echo "   clone déjà présent, synchronisation sur origin/main"
    git -C "$INSTALL_DIR" fetch origin main
    git -C "$INSTALL_DIR" reset --hard origin/main
fi
chown -R "$SERVEUR_USER:" "$INSTALL_DIR"

echo "== 5/6 Systemd : service serveur + timer de mise à jour"
install -m 644 "$ICI/tog-serveur.service" /etc/systemd/system/tog-serveur.service
install -m 644 "$ICI/tog-maj.service" /etc/systemd/system/tog-maj.service
install -m 644 "$ICI/tog-maj.timer" /etc/systemd/system/tog-maj.timer
install -m 755 "$ICI/maj-tog.sh" "$INSTALL_DIR/deploy/maj-tog.sh"
chown "$SERVEUR_USER:" "$INSTALL_DIR/deploy/maj-tog.sh"

# L'utilisateur 'tog' a le droit de relancer uniquement le service serveur.
echo "$SERVEUR_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart tog-serveur.service" > /etc/sudoers.d/tog-serveur-maj
chmod 440 /etc/sudoers.d/tog-serveur-maj
visudo -cf /etc/sudoers.d/tog-serveur-maj

systemctl daemon-reload
systemctl enable --now tog-serveur.service
systemctl enable --now tog-maj.timer

echo "== 6/6 Terminé"
echo "Serveur   : systemctl status tog-serveur   (port 7777/UDP)"
echo "MàJ auto  : systemctl list-timers tog-maj.timer"
echo "Logs      : journalctl -u tog-serveur -f"
echo "Les joueurs se connectent avec l'adresse Tailscale du Pi :"
tailscale ip -4 2>/dev/null || echo "  (tailscale ip -4 pour la connaître)"
