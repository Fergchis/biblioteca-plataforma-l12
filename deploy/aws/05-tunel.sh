#!/usr/bin/env bash
# 05-tunel.sh · Abre una herramienta de gestion en el equipo con un túnel de Session Manager
# (AWS-StartPortForwardingSession). sg-gestion no abre ningún puerto y en gestion las herramientas escuchan
# solo en 127.0.0.1: el túnel va por el agente de Session Manager, de adentro hacia afuera.
#
#   kafka-ui (por defecto)   gestion:8080 -> http://localhost:18085   (el 8085 es el del compose local)
#   admin                    gestion:3020 -> http://localhost:13020   (biblioteca-admin, con token de Cognito)
#
# Requisito: el Session Manager plugin instalado en el equipo (session-manager-plugin en el PATH).
# Uso, desde la raíz de biblioteca-plataforma, en una terminal propia (queda abierto hasta Ctrl+C):
#   bash deploy/aws/05-tunel.sh
#   bash deploy/aws/05-tunel.sh admin
set -euo pipefail
source "$(dirname "$0")/comun.sh"
case "${1:-kafka-ui}" in
  kafka-ui) REMOTO=8080; PUERTO="${PUERTO:-18085}";;
  admin)    REMOTO=3020; PUERTO="${PUERTO:-13020}";;
  *) echo "Uso: bash deploy/aws/05-tunel.sh [kafka-ui|admin]"; exit 1;;
esac
GESTION=$(id_inst gestion)
log "Túnel a ${1:-kafka-ui} de gestion ($GESTION): http://localhost:$PUERTO · Ctrl+C para cerrarlo"
aws ssm start-session --target "$GESTION" --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=$REMOTO,localPortNumber=$PUERTO"
