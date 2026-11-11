#!/usr/bin/env bash
# Reanuda la build de LineageOS 22.2 (Android 15) donde se quedo.
#
#   bash scripts/resume-a15.sh            # continua (out/ ya tiene ~46%)
#   JOBS=8 bash scripts/resume-a15.sh
#
# No vuelve a aplicar parches (SKIP_PREP=1): el arbol ya esta preparado. Se lanza
# con setsid para que sobreviva a cortes de la sesion de VS Code / WSL.
set -euo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SRC:-$HOME/android/lineage-22}"
JOBS="${JOBS:-8}"

if [ ! -d "$SRC/.repo" ]; then
    echo "no hay arbol en $SRC" >&2
    exit 1
fi

cd "$SRC"
echo "disco:"; df -h / | tail -1
echo "out:"; du -sh "$SRC/out" 2>/dev/null || echo "  (vacio)"
echo "lanzando build en segundo plano (log: ~/build22-live.log)"

SKIP_PREP=1 JOBS="$JOBS" setsid nohup bash "$WS/scripts/build-a15.sh" \
    >"$HOME/build22.out" 2>&1 </dev/null &
sleep 5

if pgrep -f build-a15.sh >/dev/null; then
    echo "build en marcha. Sigue el log con:"
    echo "  bash $WS/scripts/watch-build.sh a15"
else
    echo "no arranco; mira $HOME/build22.out" >&2
    tail -20 "$HOME/build22.out" >&2
    exit 1
fi
