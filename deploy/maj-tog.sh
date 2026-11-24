#!/bin/bash
# Met à jour le serveur ToG depuis la branche main de GitHub,
# puis relance le serveur si un nouveau commit est arrivé.
# Lancé chaque minute par tog-maj.timer (utilisateur 'tog').
set -euo pipefail

REPO=/opt/tog
SERVICE=tog-serveur.service

cd "$REPO"

avant="$(git rev-parse main)"
git fetch --quiet origin main
apres="$(git rev-parse origin/main)"

if [ "$avant" = "$apres" ]; then
    exit 0
fi

# mmo.db (comptes joueurs) n'est pas suivi par git : reset --hard le préserve.
git reset --hard "$apres"

# Relance immédiate du serveur (déconnecte les joueurs en ligne).
sudo /usr/bin/systemctl restart "$SERVICE"
echo "ToG mis à jour : $avant -> $apres, serveur relancé."
