-- Recetario Forever - Core
-- Base de datos, utilidades, cálculo de colores (umbrales) y comandos.
local ADDON, ns = ...

ns.version = "1.0.0"

---------------------------------------------------------------------------
-- Constantes
---------------------------------------------------------------------------
ns.DIFF_ORDER = { "optimal", "medium", "easy", "trivial" }
ns.DIFF_INDEX = { optimal = 1, medium = 2, easy = 3, trivial = 4 }

ns.DIFF_COLOR = {
    difficult = { 1.00, 0.10, 0.10 },
    optimal   = { 1.00, 0.50, 0.25 },
    medium    = { 1.00, 1.00, 0.00 },
    easy      = { 0.25, 0.75, 0.25 },
    trivial   = { 0.50, 0.50, 0.50 },
    unknown   = { 0.85, 0.85, 0.85 },
}

ns.DIFF_NAME = {
    difficult = "Rojo (no te alcanza)",
    optimal   = "Naranja",
    medium    = "Amarillo",
    easy      = "Verde",
    trivial   = "Gris",
    unknown   = "Desconocido",
}

ns.SOURCE_ORDER = { "trainer", "vendor", "reputation", "quest", "drop", "discovery", "other", "unknown" }
ns.SOURCE_NAME = {
    trainer    = "Instructor",
    vendor     = "Vendedor",
    reputation = "Reputación",
    quest      = "Misión",
    drop       = "Botín / Drop",
    discovery  = "Descubrimiento",
    other      = "Otra",
    unknown    = "Sin datos",
}
ns.SOURCE_SHORT = {
    trainer = "Instr.", vendor = "Vend.", reputation = "Rep.", quest = "Misión",
    drop = "Drop", discovery = "Desc.", other = "Otra", unknown = "",
}

-- Palabras clave para clasificar el texto de fuente (es/en). El orden importa:
-- reputación va antes que vendedor porque las de reputación también se compran.
local SOURCE_PATTERNS = {
    { "reputation", { "reputaci", "reputation", "venerado", "exaltado", "honorable", "revered", "exalted", "honored", "facción", "faction" } },
    { "trainer",    { "instructor", "entrenador", "trainer", "maestro" } },
    { "vendor",     { "vendedor", "mercader", "vendor", "comerciante", "proveedor" } },
    { "quest",      { "misión", "mision", "quest" } },
    { "drop",       { "botín", "botin", "despojo", "drop", "caída", "cofre", "mundo" } },
    { "discovery",  { "descubr", "discovery" } },
}

-- Nombres de profesiones conocidos (es/en) para detectar las del personaje.
ns.KNOWN_PROFS = {
    ["alquimia"] = true, ["herrería"] = true, ["herreria"] = true, ["encantamiento"] = true,
    ["ingeniería"] = true, ["ingenieria"] = true, ["herboristería"] = true, ["herboristeria"] = true,
    ["botánica"] = true, ["botanica"] = true,
    ["minería"] = true, ["mineria"] = true, ["desuello"] = true, ["desollar"] = true,
    ["peletería"] = true, ["peleteria"] = true, ["sastrería"] = true, ["sastreria"] = true,
    ["cocina"] = true, ["primeros auxilios"] = true, ["pesca"] = true,
    ["joyería"] = true, ["joyeria"] = true, ["inscripción"] = true, ["inscripcion"] = true,
    ["forja"] = true, ["fundición"] = true, ["fundicion"] = true,
    ["alchemy"] = true, ["blacksmithing"] = true, ["enchanting"] = true, ["engineering"] = true,
    ["herbalism"] = true, ["mining"] = true, ["skinning"] = true, ["leatherworking"] = true,
    ["tailoring"] = true, ["cooking"] = true, ["first aid"] = true, ["fishing"] = true,
    ["jewelcrafting"] = true, ["inscription"] = true, ["smelting"] = true,
}

-- Profesiones de recolección que no tienen ventana propia de recetas
ns.GATHERING_PROFS = {
    ["herboristería"] = true, ["herboristeria"] = true, ["botánica"] = true, ["botanica"] = true,
    ["desuello"] = true, ["desollar"] = true, ["pesca"] = true,
    ["herbalism"] = true, ["skinning"] = true, ["fishing"] = true,
}

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
function ns.Print(...)
    local msg = ""
    for i = 1, select("#", ...) do msg = msg .. tostring((select(i, ...))) .. " " end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffb84dRecetario|r: " .. msg)
end

function ns.StripCodes(s)
    if not s then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|n", "\n")
    return s
end

function ns.ClassifySource(text)
    if not text or text == "" then return nil end
    local s = ns.StripCodes(text):lower()
    for _, entry in ipairs(SOURCE_PATTERNS) do
        for _, word in ipairs(entry[2]) do
            if s:find(word, 1, true) then return entry[1] end
        end
    end
    return "other"
end

function ns.Hex(rgb)
    return string.format("ff%02x%02x%02x", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255))
end

function ns.Colorize(text, diff)
    local c = ns.DIFF_COLOR[diff or "unknown"] or ns.DIFF_COLOR.unknown
    return "|c" .. ns.Hex(c) .. text .. "|r"
end

function ns.CharKey()
    local name = UnitName("player") or "?"
    local realm = (GetRealmName and GetRealmName()) or ""
    return name .. "-" .. realm
end

---------------------------------------------------------------------------
-- Base de datos (cuenta completa: los umbrales sirven para todos tus pjs)
---------------------------------------------------------------------------
function ns.InitDB()
    RecetarioForeverDB = RecetarioForeverDB or {}
    local db = RecetarioForeverDB
    db.recipes = db.recipes or {}     -- [prof][key] = recipe
    db.chars = db.chars or {}         -- [charKey] = { profs = {}, known = {} }
    db.ui = db.ui or {}
    local ui = db.ui
    if ui.status == nil then ui.status = "all" end
    ui.sources = ui.sources or {}
    for _, s in ipairs(ns.SOURCE_ORDER) do if ui.sources[s] == nil then ui.sources[s] = true end end
    ui.colors = ui.colors or {}
    for _, c in ipairs({ "difficult", "optimal", "medium", "easy", "trivial", "unknown" }) do
        if ui.colors[c] == nil then ui.colors[c] = true end
    end
    if ui.minimapAngle == nil then ui.minimapAngle = 200 end

    local key = ns.CharKey()
    db.chars[key] = db.chars[key] or {}
    local c = db.chars[key]
    c.profs = c.profs or {}
    c.known = c.known or {}
    c.class = select(2, UnitClass("player"))
    ns.db = db
    ns.char = c
    ns.charKey = key
    ns.nameIndex = nil
end

function ns.GetRecipe(prof, key)
    local p = ns.db.recipes[prof]
    return p and p[key]
end

-- Índice nombre -> lista de {prof, key} (para tooltips y búsquedas)
function ns.GetNameIndex()
    if ns.nameIndex then return ns.nameIndex end
    local idx = {}
    for prof, list in pairs(ns.db.recipes) do
        for key, r in pairs(list) do
            if r.name then
                local n = r.name:lower()
                idx[n] = idx[n] or {}
                table.insert(idx[n], { prof, key })
            end
            if r.productName and r.productName ~= r.name then
                local n = r.productName:lower()
                idx[n] = idx[n] or {}
                table.insert(idx[n], { prof, key })
            end
        end
    end
    ns.nameIndex = idx
    return idx
end

-- ¿Qué personajes conocen esta receta?
function ns.KnownBy(prof, key)
    local out = {}
    for ck, c in pairs(ns.db.chars) do
        if c.known and c.known[prof] and c.known[prof][key] then
            table.insert(out, (ck:match("^([^-]+)") or ck))
        end
    end
    table.sort(out)
    return out
end

function ns.IsKnown(prof, key, charData)
    charData = charData or ns.char
    return charData.known[prof] and charData.known[prof][key] and true or false
end

function ns.CharRank(prof, charData)
    charData = charData or ns.char
    local p = charData.profs[prof]
    return p and p.rank or nil, p and p.max or nil
end

---------------------------------------------------------------------------
-- Umbrales de color
-- Cada vez que se abre la profesión guardamos en qué nivel de habilidad
-- se vio cada color. Con eso se deducen los cortes (exactos o un rango).
---------------------------------------------------------------------------
function ns.RecordObservation(r, diff, rank)
    if not diff or not ns.DIFF_INDEX[diff] or not rank or rank <= 0 then return end
    r.obs = r.obs or {}
    local o = r.obs[diff]
    if not o then
        r.obs[diff] = { rank, rank }
    else
        if rank < o[1] then o[1] = rank end
        if rank > o[2] then o[2] = rank end
    end
end

-- Devuelve { optimal = {lo,hi}, medium = {lo,hi}, easy = {lo,hi}, trivial = {lo,hi} }
-- donde lo/hi acotan el nivel en el que EMPIEZA ese color.
function ns.Thresholds(r)
    local o = r.obs or {}
    local order = ns.DIFF_ORDER
    local res = {}
    -- Naranja empieza en el nivel requerido para aprenderla
    if r.reqSkill then
        res.optimal = { r.reqSkill, r.reqSkill }
    else
        local hi
        for j = 1, 4 do
            local x = o[order[j]]
            if x then hi = math.min(hi or 9999, x[1]) end
        end
        res.optimal = { nil, hi }
    end
    for i = 2, 4 do
        local lo, hi
        for j = 1, i - 1 do
            local x = o[order[j]]
            if x then lo = math.max(lo or 0, x[2] + 1) end
        end
        for j = i, 4 do
            local x = o[order[j]]
            if x then hi = math.min(hi or 9999, x[1]) end
        end
        -- Datos fijos (si alguna vez se cargan desde una base estática)
        if r.fixed and r.fixed[i] then lo, hi = r.fixed[i], r.fixed[i] end
        res[order[i]] = { lo, hi }
    end
    return res
end

function ns.FormatRange(lo, hi)
    if lo and hi then
        if lo >= hi then return tostring(hi) end
        return lo .. "-" .. hi
    elseif hi then
        return "<=" .. hi
    elseif lo then
        return ">=" .. lo
    end
    return "?"
end

-- Predice el color de una receta para un nivel de habilidad.
-- Devuelve diff, exacto(bool)
function ns.PredictDiff(r, rank)
    if not r or not rank then return "unknown", false end
    local order = ns.DIFF_ORDER
    local o = r.obs or {}
    -- 1) Ya se vio ese color en este nivel exacto
    for i = 1, 4 do
        local x = o[order[i]]
        if x and x[1] <= rank and rank <= x[2] then return order[i], true end
    end
    local t = ns.Thresholds(r)
    if t.optimal[1] and rank < t.optimal[1] then return "difficult", true end
    -- 2) Índice mínimo garantizado
    local lower
    if t.optimal[2] and t.optimal[2] <= rank then lower = 1 end
    for i = 2, 4 do
        local th = t[order[i]]
        if th[2] and th[2] <= rank then lower = i end
    end
    -- 3) Índice máximo posible
    local upper = 4
    for i = 4, 2, -1 do
        local th = t[order[i]]
        if th[1] and th[1] > rank then upper = i - 1 end
    end
    if lower then
        return order[lower], (lower == upper)
    end
    if next(o) == nil and not r.reqSkill then return "unknown", false end
    return order[upper], false
end

---------------------------------------------------------------------------
-- Profesiones del personaje (sin necesidad de abrir la ventana)
---------------------------------------------------------------------------
function ns.UpdateCharProfessions()
    local found = {}
    -- API moderna
    if GetProfessions and GetProfessionInfo then
        local ok, a, b, c, d, e = pcall(GetProfessions)
        if ok then
            for _, idx in ipairs({ a, b, c, d, e }) do
                if idx then
                    local ok2, name, icon, rank, maxRank = pcall(GetProfessionInfo, idx)
                    if ok2 and name then found[name] = { rank = rank, max = maxRank, icon = icon } end
                end
            end
        end
    end
    -- API clásica (panel de habilidades)
    if next(found) == nil and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank, isAbandonable = GetSkillLineInfo(i)
            if name and not isHeader and (isAbandonable or ns.KNOWN_PROFS[name:lower()] or ns.db.recipes[name]) then
                if ns.KNOWN_PROFS[name:lower()] or ns.db.recipes[name] or isAbandonable then
                    found[name] = { rank = rank, max = maxRank }
                end
            end
        end
    end
    if next(found) then
        -- Conserva datos ya escaneados, actualiza niveles
        for name, info in pairs(found) do
            local p = ns.char.profs[name] or {}
            p.rank = info.rank or p.rank
            p.max = info.max or p.max
            p.icon = info.icon or p.icon
            p.seen = true
            ns.char.profs[name] = p
        end
        -- Profesiones abandonadas
        for name, p in pairs(ns.char.profs) do
            if not found[name] and p.seen then
                -- solo la quitamos si la API las lista todas (evita falsos negativos)
                if GetProfessions then ns.char.profs[name] = nil end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Eventos generales
---------------------------------------------------------------------------
local core = CreateFrame("Frame")
ns.coreFrame = core

local function SafeRegister(frame, ev)
    pcall(frame.RegisterEvent, frame, ev)
end
ns.SafeRegister = SafeRegister

core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
SafeRegister(core, "SKILL_LINES_CHANGED")

core:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ns.InitDB()
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then ns.InitDB() end
        ns.UpdateCharProfessions()
        if ns.CreateMinimapButton then ns.CreateMinimapButton() end
        if ns.InitScanner then ns.InitScanner() end
        if ns.InitTooltip then ns.InitTooltip() end
    elseif event == "SKILL_LINES_CHANGED" then
        if ns.db then
            ns.UpdateCharProfessions()
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end
end)

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------
local function Debug()
    local version, build, date, toc = GetBuildInfo()
    ns.Print("Cliente", version, "build", build, "interfaz", toc)
    local T = C_TradeSkillUI
    ns.Print("C_TradeSkillUI:", T and "SI" or "NO",
        "| GetAllRecipeIDs:", (T and T.GetAllRecipeIDs) and "SI" or "NO",
        "| GetRecipeSourceText:", (T and T.GetRecipeSourceText) and "SI" or "NO",
        "| GetRecipeSchematic:", (T and T.GetRecipeSchematic) and "SI" or "NO")
    ns.Print("Legacy GetTradeSkillInfo:", GetTradeSkillInfo and "SI" or "NO",
        "| GetCraftInfo:", GetCraftInfo and "SI" or "NO",
        "| GetProfessions:", GetProfessions and "SI" or "NO")
    local n = 0
    for prof, list in pairs(ns.db.recipes) do
        local c = 0
        for _ in pairs(list) do c = c + 1 end
        n = n + c
        local rank = ns.CharRank(prof)
        ns.Print("  ", prof, c, "recetas", rank and ("(tu nivel " .. rank .. ")") or "")
    end
    ns.Print("Total recetas en base:", n, "| Último escaneo:", ns.lastScanInfo or "ninguno")
end

local function DumpTradeSkillAPI()
    local T = C_TradeSkillUI
    if not T then
        ns.Print("C_TradeSkillUI no existe en este cliente.")
        return
    end
    local funcs = {}
    for k, v in pairs(T) do
        if type(v) == "function" then table.insert(funcs, k) end
    end
    table.sort(funcs)
    ns.Print("Funciones en C_TradeSkillUI (" .. #funcs .. "):")
    local buf = {}
    for _, name in ipairs(funcs) do
        local low = name:lower()
        if low:find("recipe") or low:find("source") or low:find("skill") or low:find("prof") or low:find("diff") then
            table.insert(buf, name)
            if #buf >= 8 then
                ns.Print("  " .. table.concat(buf, ", "))
                buf = {}
            end
        end
    end
    if #buf > 0 then ns.Print("  " .. table.concat(buf, ", ")) end
    ns.Print("Globals extras: ForeverDB=" .. (_G.ForeverDB and "SI" or "NO")
        .. " | CraftLib=" .. (_G.CraftLib and "SI" or "NO")
        .. " | C_TooltipInfo=" .. (_G.C_TooltipInfo and "SI" or "NO"))
end

SLASH_RECETARIOFOREVER1 = "/recetas"
SLASH_RECETARIOFOREVER2 = "/rf"
SlashCmdList["RECETARIOFOREVER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "debug" then
        Debug()
    elseif msg == "api" then
        DumpTradeSkillAPI()
    elseif msg == "campos" then
        if ns.DumpSelectedFields then ns.DumpSelectedFields() end
    elseif msg == "borrar" then
        ns.Print("Para borrar TODO escribe: /recetas borrar confirmar")
    elseif msg == "borrar confirmar" then
        RecetarioForeverDB = nil
        ns.InitDB()
        ns.UpdateCharProfessions()
        if ns.RefreshUI then ns.RefreshUI() end
        ns.Print("Base de datos borrada.")
    elseif msg == "ayuda" or msg == "help" then
        ns.Print("/recetas - abrir/cerrar | /recetas debug - info del cliente | /recetas api - funciones de profesiones | /recetas campos - datos API de la receta elegida | /recetas borrar - reiniciar datos")
    else
        if ns.ToggleUI then ns.ToggleUI() end
    end
end
