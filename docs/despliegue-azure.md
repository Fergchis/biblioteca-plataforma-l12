# Despliegue en Azure · EP3 E2

Red y máquinas de Azure de la biblioteca, creadas en Azure for Students el 9 de noviembre de 2026, grupo
`biblioteca-l10`, región `northcentralus`. El diseño está en `docs/red.md`. En la E2 las dos máquinas quedan
**creadas y desasignadas**; Caddy, HTTPS y los servicios se despliegan en la E3.

## Cómo se crea

En Git Bash, con `az login` hecho y la suscripción «Azure for Students» activa:

```bash
bash deploy/azure/red.sh        # grupo, VNet, subredes, NSG, tabla de rutas, IP pública con etiqueta DNS
bash deploy/azure/maquinas.sh   # gw-azure y bff, llave SSH, apagado automático, ~/.ssh/biblioteca-azure.config
bash deploy/azure/apagar.sh     # desasigna las dos VM
bash deploy/azure/encender.sh   # las vuelve a encender (primero gw-azure, que es el NAT de bff)
```

| Archivo | Qué hace |
|---|---|
| `deploy/azure/comun.sh` | Variables: `G=biblioteca-l10`, `L=northcentralus`, `ETIQUETA=biblioteca-l10`, `CLAVE=~/.ssh/biblioteca-azure` |
| `deploy/azure/red.sh` | Red completa. Se puede volver a correr: si cambia tu IP, actualiza la regla de SSH |
| `deploy/azure/maquinas.sh` | Las dos VM; si ya existen, no las vuelve a crear. `CORREO=<correo>` opcional para el aviso del apagado |
| `deploy/azure/cloud-init-gw-azure.yaml` | Docker, `ip_forward`, MASQUERADE de 10.1.2.0/24, reglas en `DOCKER-USER`, todo persistente |
| `deploy/azure/cloud-init-bff.yaml` | Docker (baja por el NAT de `gw-azure`) |

Los dos `cloud-init` son ASCII puro: con una tilde, cloud-init descarta el archivo entero sin avisar.

## La red

```text
$ az network vnet show -g biblioteca-l10 -n vnet-biblioteca --query "{nombre:name,region:location,rango:addressSpace.addressPrefixes[0]}" -o table
Nombre           Region          Rango
---------------  --------------  -----------
vnet-biblioteca  northcentralus  10.1.0.0/16

$ az network vnet subnet list -g biblioteca-l10 --vnet-name vnet-biblioteca --query "[].{nombre:name,rango:addressPrefix,nsg:networkSecurityGroup.id,rutas:routeTable.id,salidaPorDefecto:defaultOutboundAccess}" -o table
Nombre    Rango        Nsg           SalidaPorDefecto    Rutas
--------  -----------  ------------  ------------------  ----------
publica   10.1.1.0/24  nsg-gw-azure  False
privada   10.1.2.0/24  nsg-bff       False               rt-privada
```

(Los ID de `nsg` y `rutas` se recortaron al nombre del recurso.)

```text
$ az network route-table route list -g biblioteca-l10 --route-table-name rt-privada -o table
AddressPrefix    HasBgpOverride    Name    NextHopIpAddress    NextHopType       ProvisioningState    ResourceGroup
---------------  ----------------  ------  ------------------  ----------------  -------------------  ---------------
0.0.0.0/0        False             salida  10.1.1.4            VirtualAppliance  Succeeded            biblioteca-l10

$ az network public-ip show -g biblioteca-l10 -n pip-gw-azure --query "{ip:ipAddress,asignacion:publicIPAllocationMethod,fqdn:dnsSettings.fqdn}" -o table
Ip              Asignacion    Fqdn
--------------  ------------  ------------------------------------------------
40.116.108.230  Static        biblioteca-l10.northcentralus.cloudapp.azure.com

$ az network nic list -g biblioteca-l10 --query "[].{nic:name,ip:ipConfigurations[0].privateIPAddress,forwarding:enableIPForwarding}" -o table
Nic           Ip        Forwarding
------------  --------  ------------
nic-bff       10.1.2.4  False
nic-gw-azure  10.1.1.4  True
```

## Los NSG

```text
$ az network nsg rule list -g biblioteca-l10 --nsg-name nsg-gw-azure --query "[].{regla:name,prioridad:priority,acceso:access,protocolo:protocol,origen:join(',',[sourceAddressPrefix||'',join(',',sourceAddressPrefixes)]),puertos:join(',',[destinationPortRange||'',join(',',destinationPortRanges)])}" -o table
Regla           Prioridad    Acceso    Protocolo    Origen              Puertos
--------------  -----------  --------  -----------  ------------------  ---------
web             100          Allow     Tcp          Internet,           ,80,443
ssh-integrante  110          Allow     Tcp          181.42.184.193/32,  22,
desde-privada   120          Allow     *            10.1.2.0/24,        *,

$ az network nsg rule list -g biblioteca-l10 --nsg-name nsg-bff --query "(la misma consulta)" -o table
Regla       Prioridad    Acceso    Protocolo    Origen        Puertos
----------  -----------  --------  -----------  ------------  ---------
desde-vnet  100          Allow     *            10.1.0.0/16,  *,
deny-resto  4000         Deny      *            *,            *,
```

Las comas sobrantes vienen de la consulta, que junta el campo simple y la lista. El SSH solo se permite desde la IP
de quien aloja Azure; cada integrante que necesite entrar agrega su `/32` volviendo a correr `red.sh` desde su
equipo con otra regla, o en el portal.

## Prueba del NAT, antes de apagar

```text
$ ssh -F ~/.ssh/biblioteca-azure.config gw-azure 'hostname; ip -4 addr show eth0|grep inet; docker --version; cat /proc/sys/net/ipv4/ip_forward; sudo iptables -t nat -S POSTROUTING|grep MASQ'
gw-azure
    inet 10.1.1.4/24 metric 100 brd 10.1.1.255 scope global eth0
Docker version 29.1.3, build 29.1.3-0ubuntu3~24.04.2
1
-A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
-A POSTROUTING -s 10.1.2.0/24 -o eth0 -j MASQUERADE

$ ssh -F ~/.ssh/biblioteca-azure.config bff 'hostname; ip -4 addr show eth0|grep inet; cloud-init status --wait; docker --version; echo -n "salida: "; curl -s ifconfig.me; echo; ip route|head -2'
Warning: Permanently added '10.1.2.4' (ED25519) to the list of known hosts.
bff
    inet 10.1.2.4/24 metric 100 brd 10.1.2.255 scope global eth0
status: done
Docker version 29.1.3, build 29.1.3-0ubuntu3~24.04.2
salida: 40.116.108.230
default via 10.1.2.1 dev eth0 proto dhcp src 10.1.2.4 metric 100
10.1.2.0/24 dev eth0 proto kernel scope link src 10.1.2.4 metric 100
```

`bff` no tiene IP pública y sale a internet con `40.116.108.230`, la IP pública de `gw-azure`: el NAT funciona. Se
entra a `bff` saltando por `gw-azure` (`ProxyJump` en `~/.ssh/biblioteca-azure.config`). Docker quedó instalado en las
dos; el de `bff` se bajó por el NAT.

## Las máquinas, al final de la E2

```text
$ az vm list -g biblioteca-l10 -d --query "[].{vm:name,tam:hardwareProfile.vmSize,estado:powerState,privada:privateIps,publica:publicIps}" -o table   (encendidas)
Vm        Tam                Estado      Privada    Publica
--------  -----------------  ----------  ---------  --------------
bff       Standard_B2als_v2  VM running  10.1.2.4
gw-azure  Standard_B2ats_v2  VM running  10.1.1.4   40.116.108.230

$ bash deploy/azure/apagar.sh
Vm        Estado
--------  --------------
bff       VM deallocated
gw-azure  VM deallocated
```

Desasignadas no cobran cómputo; siguen cobrando los discos (30 GB StandardSSD cada uno) y la IP pública estática,
que se conserva: `40.116.108.230` es la que va en la regla 443 de `sg-gw` en AWS. Las dos tienen apagado
automático a las 03:00 UTC (`shutdown-computevm-gw-azure` y `shutdown-computevm-bff`).

Uso de vCPU de la región con las dos creadas: 4 de 6 (`az vm list-usage -l northcentralus`, «Total Regional vCPUs»).
