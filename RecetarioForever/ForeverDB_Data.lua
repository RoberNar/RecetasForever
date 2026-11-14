-- Recetario Forever - Base de datos estÃ¡tica de ForeverDB.net
-- Este archivo se rellena ejecutando una sola vez `tools/sync_foreverdb.py`
-- (o colocando aquÃ­ tus recetas exportadas) y se carga por cuenta al pulsar
-- el botÃ³n "Cargar ForeverDB" dentro del addon.
local ADDON, ns = ...

ns.ExternalDB = {
    meta = {
        source = "ForeverDB.net",
        updatedAt = nil, -- ej. "2026-11-14"
        version = 1,
    },
    -- Cada entrada puede usar:
    -- {
    --   prof = "Cocina",
    --   id = 12345,              -- recipeID / spellID (opcional si pones name)
    --   name = "Ala crocante de murciÃ©lago",
    --   reqSkill = 1,            -- nivel en que se aprende (naranja)
    --   thresholds = { 1, 45, 70, 95 }, -- { naranja, amarillo, verde, gris }
    --   source = "vendor",       -- trainer|vendor|reputation|quest|drop|discovery|other
    --   sourceText = "Vendedor: ...",
    --   productID = 12224,
    --   reagents = { { itemID = 12223, count = 1 } },
    -- }
    recipes = {},
}
