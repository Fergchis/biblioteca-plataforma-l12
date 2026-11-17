#!/usr/bin/env bash
# 03-subir.sh · Los archivos llegan a las máquinas por S3 y los secretos por Parameter Store, porque las
# privadas no tienen SSH y el repositorio es privado.
#
#   S3               s3://biblioteca-l10-<cuenta>/deploy/ = copia de deploy/ (sin deploy/aws/secretos/)
#   Parameter Store  /biblioteca/<máquina>/env, SecureString, uno por máquina que tiene secretos:
#                    /biblioteca/mq-1/env y /biblioteca/mq-2/env   RABBITMQ_USER, RABBITMQ_PASSWORD, RABBITMQ_COOKIE
#                    /biblioteca/datos/env                         POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD
#
# Los valores reales viven en deploy/aws/secretos/<máquina>.env, que no se versiona (.gitignore) y va en
# el .zip de la entrega. Si falta alguno, este script lo crea desde su .env.example con claves aleatorias.
# Los dos nodos de RabbitMQ necesitan la misma cookie y la misma clave: mq-2.env es copia de mq-1.env.
#
# Uso, desde la raíz de biblioteca-plataforma (cada vez que cambia algo de deploy/):
#   bash deploy/aws/03-subir.sh
set -euo pipefail
source "$(dirname "$0")/comun.sh"
comprobar_cuenta
B=$(bucket)

# 1 · El bucket, una vez. Queda privado: S3 bloquea el acceso público por defecto.
if aws s3api head-bucket --bucket "$B" > /dev/null 2>&1; then
  log "bucket s3://$B ya existe"
else
  aws s3 mb "s3://$B"
  aws s3api put-bucket-tagging --bucket "$B" \
    --tagging "TagSet=[{Key=Name,Value=$B},{Key=Proyecto,Value=$PROYECTO}]"
fi

# 2 · deploy/ completo, menos los secretos (antes, sin CRLF: los .sh y los .env se usan en Linux)
sin_crlf ..
aws s3 sync .. "s3://$B/deploy/" --delete --only-show-errors --exclude "aws/secretos/*" --exclude "*.DS_Store"
log "deploy/ sincronizado en s3://$B/deploy/"
aws_ s3 ls "s3://$B/deploy/" --recursive | awk '{print "  " $3 "\t" $4}'

# 3 · Los secretos: uno por máquina, como SecureString
umask 077
clave() { openssl rand -hex "$1"; }
if [ ! -f secretos/mq-1.env ]; then
  sed -e "s/^RABBITMQ_PASSWORD=.*/RABBITMQ_PASSWORD=$(clave 12)/" \
      -e "s/^RABBITMQ_COOKIE=.*/RABBITMQ_COOKIE=$(clave 24)/" secretos/mq.env.example > secretos/mq-1.env
  log "secretos/mq-1.env creado con claves aleatorias"
fi
cmp -s secretos/mq-1.env secretos/mq-2.env 2>/dev/null || cp secretos/mq-1.env secretos/mq-2.env
if [ ! -f secretos/datos.env ]; then
  sed -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(clave 12)/" secretos/datos.env.example > secretos/datos.env
  log "secretos/datos.env creado con una clave aleatoria"
fi
# E3 · servicios, gestion y gw-aws: se arman una vez a partir de los secretos de la E2 y de Cognito
# (COGNITO_ISSUER y COGNITO_CLIENT_ID, los que imprime cognito/crear.sh). Si ya existen, no se tocan.
. secretos/mq-1.env; . secretos/datos.env
AMQP="amqp://$RABBITMQ_USER:$RABBITMQ_PASSWORD@10.0.21.11:5672"
if [ ! -f secretos/servicios.env ]; then
  : "${COGNITO_ISSUER:?falta COGNITO_ISSUER (lo imprime cognito/crear.sh)}"
  printf '%s\n' "COGNITO_ISSUER=$COGNITO_ISSUER" "RABBITMQ_URL=$AMQP" "POSTGRES_DB=$POSTGRES_DB" \
    "POSTGRES_USER=$POSTGRES_USER" "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" > secretos/servicios.env
  log "secretos/servicios.env creado"
fi
if [ ! -f secretos/gestion.env ]; then
  : "${COGNITO_CLIENT_ID:?falta COGNITO_CLIENT_ID (lo imprime cognito/crear.sh)}"
  printf '%s\n' "COGNITO_ISSUER=$COGNITO_ISSUER" "COGNITO_CLIENT_ID=$COGNITO_CLIENT_ID" "RABBIT_URL=$AMQP" \
    "RABBIT_USUARIO=$RABBITMQ_USER" "RABBIT_CLAVE=$RABBITMQ_PASSWORD" > secretos/gestion.env
  log "secretos/gestion.env creado"
fi
if [ ! -f secretos/gw-aws.env ]; then
  EIP=$(aws_ ec2 describe-addresses --filters $(filtros gw-aws) --query 'Addresses[0].PublicIp' --output text)
  # La primera vez, staging. Cuando sale el certificado de prueba se cambia aquí a producción
  # (https://acme-v02.api.letsencrypt.org/directory), se vuelve a correr este script y se despliega.
  printf '%s\n' "COGNITO_ISSUER=$COGNITO_ISSUER" "COGNITO_CLIENT_ID=$COGNITO_CLIENT_ID" \
    "SITIO=${EIP//./-}.sslip.io" "ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory" > secretos/gw-aws.env
  log "secretos/gw-aws.env creado (SITIO=${EIP//./-}.sslip.io, CA de staging)"
fi
for m in mq-1 mq-2 datos servicios gestion gw-aws; do
  aws ssm put-parameter --type SecureString --overwrite --name "/biblioteca/$m/env" \
    --value "file://secretos/$m.env" > /dev/null
  log "parámetro /biblioteca/$m/env actualizado ($(grep -c '^[A-Z]' "secretos/$m.env") variables)"
done
aws_ ssm describe-parameters --parameter-filters "Key=Name,Option=BeginsWith,Values=/biblioteca/" \
  --output table --query 'Parameters[].[Name,Type,Version,LastModifiedDate]'
