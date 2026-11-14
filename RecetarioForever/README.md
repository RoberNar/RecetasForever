# Recetario Forever

Addon para **WoW Forever** (cliente 1.60.x, interfaz 16001).

## Instalación
1. Copia la carpeta `RecetarioForever` a la carpeta de addons del cliente Forever, por ejemplo:
   `...\World of Warcraft\_forever_\Interface\AddOns\RecetarioForever`
   (el nombre de la subcarpeta `_forever_` puede variar: es la carpeta donde está el .exe del Forever).
2. En la pantalla de personajes -> AddOns, activa **Recetario Forever**. Si sale "desactualizado", marca "Cargar addons desactualizados".

## Uso
- `/recetas` o `/rf`, el botón del minimapa, o el botón **Recetario** en la ventana de profesión.
- **Abre cada profesión una vez** (libro de hechizos o tecla K): así el addon lee todas sus recetas.
- Filtros: Todas / Conocidas / No conocidas · Fuente (Instructor, Vendedor, Reputación, Misión, Botín...) · Color a tu nivel actual.
- "Solo comprables" = recetas de vendedor y de reputación.
- El buscador también busca en el texto de la fuente (zona, nombre del NPC, facción).
- Pasa el mouse por una receta (Receta:/Patrón:/Diseño:) para ver si ya la conoces y quién de tus pjs la tiene.

## Cómo calcula los colores
El juego no siempre informa directamente en qué nivel una receta pasa a amarillo/verde/gris.
El addon guarda en qué nivel viste cada color cada vez que abres la profesión (con cualquier pj de la cuenta)
y deduce los cortes. Al principio verás rangos (`120-135`); se vuelven exactos a medida que subes.

## Comandos
- `/recetas debug` – muestra versión del cliente y qué funciones del juego existen.
- `/recetas api` – lista las funciones disponibles en `C_TradeSkillUI` y si hay bases externas cargadas.
- `/recetas campos` – muestra los datos crudos de la receta elegida.
- `/recetas importar` – carga los datos de `ForeverDB_Data.lua` en la base de tu cuenta (igual que el botón **Cargar ForeverDB**).
- `/recetas borrar` – reinicia la base de datos.

## Créditos
<a href="https://foreverdb.net">Data from ForeverDB.net</a>

