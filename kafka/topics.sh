#!/bin/sh
# Crea los topics de la biblioteca (L9 y L10, calco del punto 7 de la Guia de la EP3). Se puede correr las veces
# que haga falta: --if-not-exists no toca un topic que ya existe. Cada parametro esta justificado en docs/topics.md.
# Uso, desde la carpeta del compose.yml (macOS, Linux o Git Bash en Windows):
#   sh kafka/topics.sh
# En la nube, en mq-1, desde la carpeta de mq-compose.yml (el servicio se llama broker):
#   sudo SERVICIO=broker BOOTSTRAP=10.0.21.11:9092 sh topics.sh

set -eu

# Git Bash convierte /opt/... en una ruta de Windows antes de pasarla a docker. Esto lo evita.
export MSYS_NO_PATHCONV=1

SERVICIO="${SERVICIO:-broker-1}"
BOOTSTRAP="${BOOTSTRAP:-broker-1:19092}"
SIETE_DIAS=604800000
UN_DIA=86400000

# crear <topic> <politica> [retencion en ms]. Con compact no hay retencion: se guarda el ultimo valor de cada key.
crear() {
  topic=$1
  politica=$2
  retencion=${3:-}
  docker compose exec -T "$SERVICIO" /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists \
    --topic "$topic" \
    --partitions 3 \
    --replication-factor 3 \
    --config min.insync.replicas=2 \
    --config cleanup.policy="$politica" \
    ${retencion:+--config retention.ms="$retencion"}
}

crear biblioteca.prestamos delete "$SIETE_DIAS"
crear biblioteca.lecturas delete "$UN_DIA"
# L10, grupos de 3: el ultimo estado de cada libro (key libroId), compactado.
crear biblioteca.catalogo compact

# E3, paso 1: un .dlt por cada topic que lee biblioteca-eventos. Ahi publica la aplicacion cada evento que un
# grupo no puede procesar (header x-motivo). 3 particiones, igual que el original: con la misma key y el mismo
# particionador, el desviado cae en la misma particion que el original. 3 replicas y min.insync.replicas=2: un
# evento desviado es un evento que nadie mas tiene, no puede vivir en una sola copia. 7 dias y delete: el plazo
# para revisarlo y reprocesarlo; son pocos mensajes, el plazo largo no cuesta. El del catalogo tambien es delete:
# guarda cada error, no el ultimo de cada libro.
crear biblioteca.prestamos.dlt delete "$SIETE_DIAS"
crear biblioteca.lecturas.dlt delete "$SIETE_DIAS"
crear biblioteca.catalogo.dlt delete "$SIETE_DIAS"

docker compose exec -T "$SERVICIO" /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "$BOOTSTRAP" --describe --topics-with-overrides --exclude-internal
