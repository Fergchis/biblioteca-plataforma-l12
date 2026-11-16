# Despliegue en AWS y Azure · biblioteca · E2

La red de `docs/red.md` y la capa de datos levantadas en el Learner Lab (cuenta `139658837350`, `us-east-1`)
el lunes 9 de noviembre de 2026, con los scripts de `deploy/aws/`. En la E2 corren `nat`, `mq-1` a `mq-3`,
`datos` y `gestion`; `gw-aws` y `servicios` se crean en la E3.

## Cómo se levantó

Desde la raíz de `biblioteca-plataforma`, en Git Bash, con las credenciales de «AWS Details» en
`~/.aws/credentials`. Cada script se puede volver a correr: lo que ya existe se reutiliza.

```bash
bash deploy/aws/01-red.sh               # VPC, Internet Gateway, 4 subredes, 2 tablas de rutas, 6 grupos de reglas
bash deploy/aws/02-maquinas.sh          # nat (y la ruta privada hacia ella), mq-1, mq-2, mq-3, datos, gestion
bash deploy/aws/03-subir.sh             # deploy/ a S3 y los .env de deploy/aws/secretos/ a Parameter Store
bash deploy/aws/04-levantar.sh          # Kafka, topics, RabbitMQ, políticas, Postgres, Kafka UI y el simulador
bash deploy/aws/05-tunel.sh             # Kafka UI en http://localhost:18085
bash deploy/aws/06-evidencia.sh         # las salidas de este documento
```

| Qué | Dónde |
|---|---|
| Archivos | `s3://biblioteca-l10-139658837350/deploy/` → `/opt/biblioteca/deploy/` en cada máquina |
| Secretos | Parameter Store, SecureString: `/biblioteca/mq-1/env`, `/biblioteca/mq-2/env`, `/biblioteca/datos/env` → `/opt/biblioteca/secretos/` |
| Kafka | `deploy/aws/mq/kafka/compose.yml` con `mq-1.env`, `mq-2.env`, `mq-3.env`; topics con `topics.sh` desde `mq-1` |
| RabbitMQ | `deploy/aws/mq/rabbit/compose.yml` con `mq-1.env` y `mq-2.env`; `rabbitmq.conf` y `erlang.cookie` los escribe `secretos.sh` |
| Postgres | `deploy/aws/datos/compose.yml`, Postgres 18 |
| Kafka UI y simulador | `deploy/aws/gestion/compose.yml`; el simulador, de `github.com/Umbingelelo/biblioteca-simulador` en un contenedor `node:24-slim` |

## 1 · Las máquinas y sus IP

Las de `docs/red.md`. Las privadas no tienen IP pública; `nat` sí, porque es la salida a internet de las demás.

```text
$ aws ec2 describe-instances --output table --query \
    "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],PrivateIpAddress,PublicIpAddress]"
---------------------------------------------
|             DescribeInstances             |
+---------+--------------+------------------+
|  gestion|  10.0.11.20  |  None            |
|  datos  |  10.0.21.30  |  None            |
|  mq-1   |  10.0.21.11  |  None            |
|  mq-2   |  10.0.22.12  |  None            |
|  mq-3   |  10.0.21.13  |  None            |
|  nat    |  10.0.1.10   |  100.61.167.115  |
+---------+--------------+------------------+
```

## 2 · Nadie abre el 22

```text
$ aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=22 \
    --query "SecurityGroups[].GroupName"
[]
```

Se entra a todas las máquinas por Session Manager.

## 3 · El quórum de KRaft: tres votantes

En `mq-1`, por Session Manager. `K="sudo docker exec biblioteca-mq-broker-1 /opt/kafka/bin"`.

```text
$ $K/kafka-metadata-quorum.sh --bootstrap-server 10.0.21.11:9092 describe --status
ClusterId:              QmlibGlvdGVjYS1LYWZrYQ
LeaderId:               1
LeaderEpoch:            1
HighWatermark:          1085
MaxFollowerLag:         0
MaxFollowerLagTimeMs:   0
CurrentVoters:          [{"id": 1, "endpoints": ["CONTROLLER://10.0.21.11:9093"]}, {"id": 2, "endpoints": ["CONTROLLER://10.0.22.12:9093"]}, {"id": 3, "endpoints": ["CONTROLLER://10.0.21.13:9093"]}]
CurrentObservers:       [{"id": 6, "directoryId": "Q_-RjK_3F_cF2kSJ5nhnoA"}, {"id": 5, "directoryId": "U5VilkNxhSwOGujzwZd67A"}, {"id": 4, "directoryId": "ErwI6wTWi9kscVUHfLvv1A"}]
```

Los votantes 1, 2 y 3 son los controllers de `mq-1`, `mq-2` y `mq-3`; los observadores 4, 5 y 6, los brokers.

## 4 · `biblioteca.prestamos`: tres particiones con ISR de tres

```text
$ $K/kafka-topics.sh --bootstrap-server 10.0.21.11:9092 --describe --topic biblioteca.prestamos
Topic: biblioteca.prestamos	TopicId: v4eelkRYT66Q0LrmCn6upA	PartitionCount: 3	ReplicationFactor: 3	Configs: min.insync.replicas=2,cleanup.policy=delete,retention.ms=604800000
	Topic: biblioteca.prestamos	Partition: 0	Leader: 6	Replicas: 6,4,5	Isr: 6,4,5	Elr: 	LastKnownElr: 
	Topic: biblioteca.prestamos	Partition: 1	Leader: 4	Replicas: 4,5,6	Isr: 4,5,6	Elr: 	LastKnownElr: 
	Topic: biblioteca.prestamos	Partition: 2	Leader: 5	Replicas: 5,6,4	Isr: 5,6,4	Elr: 	LastKnownElr: 
```

Cada partición tiene su líder en un broker distinto. Los otros cuatro topics (`biblioteca.lecturas`, los dos
`.dlt` y `biblioteca.catalogo`, compactado) también quedaron con 3 particiones y ISR de 3 (salida de `topics.sh`
en `deploy/aws/` y Kafka UI).

## 5 · Los mensajes de la noche, por partición

El simulador publicó desde `gestion` las 2.984 lecturas y los 404 préstamos en 63 segundos (`--velocidad 60`),
todos confirmados con `acks=all`.

```text
$ $K/kafka-get-offsets.sh --bootstrap-server 10.0.21.11:9092 --topic biblioteca.lecturas
biblioteca.lecturas:0:492
biblioteca.lecturas:1:2279
biblioteca.lecturas:2:213
$ $K/kafka-get-offsets.sh --bootstrap-server 10.0.21.11:9092 --topic biblioteca.prestamos
biblioteca.prestamos:0:136
biblioteca.prestamos:1:145
biblioteca.prestamos:2:123
```

Son las mismas cifras que en local y que `dataset/resumen.json` del simulador: 492 · 2.279 · 213 y
136 · 145 · 123. La partición 1 de lecturas es la caliente (el libro 18). Kafka UI, por el túnel en
`http://localhost:18085`, muestra el clúster `biblioteca-aws` con 3 brokers (4, 5 y 6 en 10.0.21.11, 10.0.22.12
y 10.0.21.13), 5 topics, 15 particiones en línea y ninguna sub-replicada.

## RabbitMQ · dos nodos en clúster

En `mq-1`: `sudo docker exec biblioteca-rabbit-rabbit-1 rabbitmqctl cluster_status` (recortado a los nodos).

```text
Disk Nodes
rabbit@mq-1
rabbit@mq-2
Running Nodes
rabbit@mq-1
rabbit@mq-2
Versions
rabbit@mq-1: RabbitMQ 4.3.7 on Erlang 27.3.4.19
rabbit@mq-2: RabbitMQ 4.3.7 on Erlang 27.3.4.19
Alarms
(none)
Network Partitions
(none)
```

Las políticas de `docs/politicas.md` se cargaron en `mq-1` con `rabbitmqctl import_definitions`.

## Postgres · arriba en `datos`

```text
$ sudo docker ps --filter name=biblioteca-datos --format "{{.Names}}  {{.Image}}  {{.Status}}"
biblioteca-datos-postgres-1  postgres:18  Up 7 minutes (healthy)
$ sudo docker exec biblioteca-datos-postgres-1 sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "select version()"'
PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
```

Los grupos de reglas se comprobaron desde adentro: `gestion` llega a Postgres (5432), a RabbitMQ (5672) y a
Kafka (9092); `mq-3` llega a Kafka pero no a Postgres ni a RabbitMQ, porque `sg-mq` no está en esas reglas.

## Memoria medida

`free -m` y `docker stats --no-stream` con todo arriba y la noche ya publicada:

| Máquina | Usado | Lo que corre |
|---|---|---|
| `mq-1` | 1.041 de 1.909 MB | broker 409 MiB, controller 236, `rabbit@mq-1` 110 |
| `mq-2` | 1.006 de 1.909 MB | broker 389 MiB, controller 205, `rabbit@mq-2` 112 |
| `mq-3` | 909 de 1.909 MB | broker 441 MiB, controller 205 |
| `datos` | 314 de 1.909 MB | Postgres 39 MiB |
| `gestion` | 657 de 3.835 MB | Kafka UI 326 MiB |

## 6 · Azure: `bff` sale a internet con la IP de `gw-azure`

En `bff`, entrando por `gw-azure` con ProxyJump (`ssh -F ~/.ssh/biblioteca-azure.config bff`), antes de apagar:

```text
$ curl -s ifconfig.me
40.116.108.230
```

`bff` no tiene IP pública: sale con `40.116.108.230`, la IP estática de `gw-azure` (`pip-gw-azure`,
`biblioteca-l10.northcentralus.cloudapp.azure.com`). El detalle completo de la prueba está en `docs/despliegue-azure.md`.

## 7 · Azure: la ruta de la subred privada apunta a `gw-azure`

```text
$ az network route-table route list -g biblioteca-l10 --route-table-name rt-privada -o table
AddressPrefix    HasBgpOverride    Name    NextHopIpAddress    NextHopType       ProvisioningState    ResourceGroup
---------------  ----------------  ------  ------------------  ----------------  -------------------  ---------------
0.0.0.0/0        False             salida  10.1.1.4            VirtualAppliance  Succeeded            biblioteca-l10
```

## 8 · Azure: las dos máquinas, desasignadas al entregar

```text
$ az vm list -d -g biblioteca-l10 --query "[].[name,privateIps,powerState]" -o table
Column1    Column2    Column3
---------  ---------  --------------
bff        10.1.2.4   VM deallocated
gw-azure   10.1.1.4   VM deallocated
```
