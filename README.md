# RecetasForever

Addon para **WoW Forever** (cliente 1.60.x, interfaz `16001`).

La carpeta del addon se encuentra en [`RecetarioForever/`](RecetarioForever/). Consulta [RecetarioForever/README.md](RecetarioForever/README.md) para ver las instrucciones de instalación y uso.

## Sincronización con ForeverDB.net (1 sola carga por cuenta)
WoW no permite hacer peticiones HTTP desde dentro del juego. Para no repetir consultas a la API:
1. Copia [`tools/foreverdb_config.example.json`](tools/foreverdb_config.example.json) a `tools/foreverdb_config.json` (ignorado por Git) y coloca ahí tu token de ForeverDB.
2. Ejecuta una vez: `python tools/sync_foreverdb.py` (usa caché en `tools/cache/` para no volver a pedir lo ya descargado).
3. Dentro del juego, abre `/recetas` y pulsa **Cargar ForeverDB** (o `/recetas importar`): los datos se guardan en `RecetarioForeverDB` para toda tu cuenta.

## Créditos
- <a href="https://foreverdb.net">Data from ForeverDB.net</a>
- Datos base de recetas clásicas derivados de [LibCrafts-1.0](https://github.com/refaim/LibCrafts-1.0) (MIT License, Copyright (c) 2024 Roman Kharitonov).

