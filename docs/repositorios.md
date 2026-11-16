# Repositorios · biblioteca

Ocho repositorios, uno por pieza, igual que el grupo de VidalStore. Estos son los de **partida** de L12 (la solución de L10,
ya separado en ocho): haces Fork de los ocho y los clonas **sin el sufijo `-l12`**, uno al lado del otro, en la misma
carpeta. El `compose.yml` de esta carpeta busca a sus hermanos con `../biblioteca-<pieza>`.

| Pieza | Repositorio | Carpeta |
|---|---|---|
| frontend | https://github.com/Umbingelelo/biblioteca-web-l12 | raíz |
| gateway | https://github.com/Umbingelelo/biblioteca-gateway-l12 | raíz |
| bff | https://github.com/Umbingelelo/biblioteca-bff-l12 | raíz |
| libros | https://github.com/Umbingelelo/biblioteca-libros-l12 | raíz |
| prestamos | https://github.com/Umbingelelo/biblioteca-prestamos-l12 | raíz |
| eventos | https://github.com/Umbingelelo/biblioteca-eventos-l12 | raíz |
| admin | https://github.com/Umbingelelo/biblioteca-admin-l12 | raíz |
| plataforma | https://github.com/Umbingelelo/biblioteca-plataforma-l12 | raíz |

Cada repositorio trae su `Dockerfile` y, si lee variables, su `.env.example` con los nombres y sin los valores. Lo
único compartido es esta carpeta: `compose.yml`, `.env.example`, `docs/` y `rabbitmq/`.

Aparte de los ocho hay una herramienta, `biblioteca-simulador` (https://github.com/Umbingelelo/biblioteca-simulador):
publica en Kafka la noche de la Feria del Libro (`biblioteca.lecturas` y `biblioteca.prestamos`). No se forkea ni se
modifica: se clona al lado de los ocho, igual que ellos, y se corre con `node reproducir.mjs --velocidad 60`.
