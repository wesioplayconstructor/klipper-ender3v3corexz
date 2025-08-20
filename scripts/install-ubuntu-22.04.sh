#!/usr/bin/env bash
set -euo pipefail

# Instalação via APT preferencial para garantir greenlet antes do klippy-requirements.
REQUIRED_GREENLET="1.1.2"
WHEEL_URL="${WHEEL_URL:-}"   # opcional fallback
PYTHONDIR="${HOME}/klippy-env"
SRCDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"

die(){ echo "ERROR: $*" >&2; exit 1; }
report(){ printf "\n--- %s\n" "$1"; }

# 1) Atualiza apt e tenta instalar pacote python3-greenlet
report "Tentando instalar python3-greenlet via apt (preferencial)..."
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y || true

  # Se quiser forçar uma versão específica (se disponível nos repositórios), descomente:
  # sudo apt-get install -y python3-greenlet=${REQUIRED_GREENLET} || true

  # Instala versão disponível (se houver)
  if sudo apt-get install -y python3-greenlet >/dev/null 2>&1; then
    report "Tentativa apt concluída. Verificando versão instalada..."
  else
    report "Pacote python3-greenlet não disponível / falha na instalação via apt."
  fi
else
  report "apt-get não encontrado; não é um sistema Debian/Ubuntu compatível."
fi

# 2) Verifica versão do greenlet no sistema (site-packages)
SYS_VER="$(python3 -c 'import importlib,sys
try:
  m=importlib.import_module("greenlet")
  print(m.__version__)
except Exception:
  sys.exit(1)
' 2>/dev/null || true)"

if [ -n "$SYS_VER" ]; then
  report "greenlet sistema: $SYS_VER"
else
  report "greenlet não encontrado no sistema."
fi

# 3) Se SYS_VER é a versão requerida, cria virtualenv que usa system-site-packages
if [ "$SYS_VER" = "$REQUIRED_GREENLET" ]; then
  report "Versão apt OK ($SYS_VER). Criando/updating virtualenv com acesso a site-packages do sistema..."
  if [ ! -d "$PYTHONDIR" ]; then
    python3 -m pip install --user virtualenv >/dev/null 2>&1 || true
    python3 -m virtualenv --system-site-packages -p python3 "$PYTHONDIR"
  else
    # já existe venv: garantir pip atualizado
    "$PYTHONDIR/bin/python" -m pip install --upgrade pip setuptools wheel || true
  fi

  report "Instalando requirements do klippy (usar system greenlet)..."
  if [ -f "${SRCDIR}/scripts/klippy-requirements.txt" ]; then
    "$PYTHONDIR/bin/pip" install -r "${SRCDIR}/scripts/klippy-requirements.txt"
  else
    report "klippy-requirements.txt não encontrado; pulando."
  fi

  report "Concluído (usando greenlet do apt)."
  exit 0
fi

# 4) Se chegamos aqui, apt não instalou a versão desejada -> fallback
report "apt não forneceu greenlet==${REQUIRED_GREENLET}. Tentando fallback (wheel ou compilar)."

# tentar wheel se WHEEL_URL fornecida
if [ -n "$WHEEL_URL" ]; then
  TMPW="/tmp/greenlet-$$.whl"
  if command -v curl >/dev/null 2>&1; then
    curl -L -f -o "$TMPW" "$WHEEL_URL" || rm -f "$TMPW"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$TMPW" "$WHEEL_URL" || rm -f "$TMPW"
  fi
  if [ -f "$TMPW" ]; then
    python3 -m pip install --user virtualenv >/dev/null 2>&1 || true
    python3 -m virtualenv -p python3 "$PYTHONDIR"
    "$PYTHONDIR/bin/pip" install --no-deps "$TMPW" || die "Falha ao instalar wheel"
    rm -f "$TMPW"
    report "greenlet instalado via wheel no venv."
    "$PYTHONDIR/bin/pip" install -r "${SRCDIR}/scripts/klippy-requirements.txt" || true
    exit 0
  else
    report "Wheel não disponível ou falha no download."
  fi
fi

# 5) Último recurso: compilar/instalar no venv (requer build-essentials)
report "Fallback: compilando/instalando greenlet==${REQUIRED_GREENLET} no virtualenv."
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y || true
  sudo apt-get install -y build-essential python3-dev gcc || true
fi

python3 -m pip install --user virtualenv >/dev/null 2>&1 || true
python3 -m virtualenv -p python3 "$PYTHONDIR"
"$PYTHONDIR/bin/pip" install --upgrade pip setuptools wheel || true
"$PYTHONDIR/bin/pip" install --no-binary :all: "greenlet==${REQUIRED_GREENLET}" || die "Falha ao compilar/instalar greenlet"

report "greenlet instalado no venv (compilado). Agora instalando klippy requirements..."
if [ -f "${SRCDIR}/scripts/klippy-requirements.txt" ]; then
  "$PYTHONDIR/bin/pip" install -r "${SRCDIR}/scripts/klippy-requirements.txt"
fi

report "Finalizado."
exit 0
