-- Recetario Forever - Escaneo de la ventana de profesión
-- Soporta la API moderna (C_TradeSkillUI) y la clásica (GetTradeSkillInfo / GetCraftInfo).
local ADDON, ns = ...

local T -- C_TradeSkillUI (se resuelve al iniciar)

local function try(f, ...)
    if not f then return nil end
    local ok, a, b, c, d, e, g = pcall(f, ...)
    if ok then return a, b, c, d, e, g end
    return nil
end

-- Normaliza el valor de dificultad de cualquier API a optimal/medium/easy/trivial/difficult
local NUM_DIFF
local function NormDiff(d)
    if d == nil then return nil end
    if type(d) == "number" then
        if not NUM_DIFF then
            NUM_DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
            local E = Enum and Enum.TradeskillRelativeDifficulty
            if E then
                NUM_DIFF = {}
                if E.Optimal then NUM_DIFF[E.Optimal] = "optimal" end
                if E.Medium then NUM_DIFF[E.Medium] = "medium" end
                if E.Easy then NUM_DIFF[E.Easy] = "easy" end
                if E.Trivial then NUM_DIFF[E.Trivial] = "trivial" end
            end
        end
        return NUM_DIFF[d]
    end
    d = tostring(d):lower()
    if d == "optimal" or d == "orange" then return "optimal" end
    if d == "medium" or d == "yellow" then return "medium" end
    if d == "easy" or d == "green" then return "easy" end
    if d == "trivial" or d == "gray" or d == "grey" then return "trivial" end
    if d == "difficult" or d == "red" then return "difficult" end
    return nil
end
ns.NormDiff = NormDiff

local function ParseReqSkill(text)
    if not text then return nil end
    local s = ns.StripCodes(text)
    local low = s:lower()
    if low:find("requiere", 1, true) or low:find("requires", 1, true) then
        local n = s:match("%((%d+)%)")
        return n and tonumber(n) or nil
    end
    return nil
end

---------------------------------------------------------------------------
-- Guardado común
---------------------------------------------------------------------------
local function Store(prof, key, data, rank)
    local db = ns.db
    db.recipes[prof] = db.recipes[prof] or {}
    local r = db.recipes[prof][key]
    if not r then
        r = { obs = {} }
        db.recipes[prof][key] = r
        ns.nameIndex = nil
    end
    if data.name and r.name ~= data.name then r.name = data.name; ns.nameIndex = nil end
    r.icon = data.icon or r.icon
    r.link = data.link or r.link
    r.spellLink = data.spellLink or r.spellLink
    r.productID = data.productID or r.productID
    r.productName = data.productName or r.productName
    r.recipeID = data.recipeID or r.recipeID
    r.category = data.category or r.category
    if data.reagents and #data.reagents > 0 then r.reagents = data.reagents end
    if data.sourceText and data.sourceText ~= "" then
        r.sourceText = data.sourceText
        r.source = ns.ClassifySource(data.sourceText)
        local req = ParseReqSkill(data.sourceText)
        if req then r.reqSkill = req end
    end
    if data.reqSkill then r.reqSkill = data.reqSkill end
    if data.maxTrivial and data.maxTrivial > 0 then
        r.fixed = r.fixed or {}
        r.fixed[4] = data.maxTrivial
    end
    if data.description and data.description ~= "" then r.description = data.description end
    if data.apiFields then r.apiFields = data.apiFields end
    if data.diff then ns.RecordObservation(r, data.diff, rank) end

    local known = ns.char.known
    known[prof] = known[prof] or {}
    if data.learned then
        known[prof][key] = true
    elseif data.learned == false then
        known[prof][key] = nil
    end
    return r
end

local function SetProfLevel(prof, rank, maxRank, icon)
    local p = ns.char.profs[prof] or {}
    if rank then p.rank = rank end
    if maxRank then p.max = maxRank end
    if icon then p.icon = icon end
    p.scanned = time()
    ns.char.profs[prof] = p
end

---------------------------------------------------------------------------
-- API moderna
---------------------------------------------------------------------------
local function ModernProfLine()
    local name, rank, maxRank
    local base = T.GetBaseProfessionInfo and try(T.GetBaseProfessionInfo)
    local child = T.GetChildProfessionInfo and try(T.GetChildProfessionInfo)
    if type(base) == "table" and base.professionName and base.professionName ~= "" then
        name = base.professionName
        rank, maxRank = base.skillLevel, base.maxSkillLevel
    end
    if type(child) == "table" and child.professionName and child.professionName ~= "" then
        name = name or child.professionName
        if child.skillLevel and child.skillLevel > 0 then
            rank, maxRank = child.skillLevel, child.maxSkillLevel
        end
    end
    if not name and T.GetTradeSkillLine then
        local _, n, r, m = try(T.GetTradeSkillLine)
        name, rank, maxRank = n, r, m
    end
    return name, rank, maxRank
end

local function ModernReagents(id)
    local out = {}
    if T.GetRecipeSchematic then
        local sch = try(T.GetRecipeSchematic, id, false)
        if type(sch) == "table" and sch.reagentSlotSchematics then
            for _, slot in ipairs(sch.reagentSlotSchematics) do
                local r = slot.reagents and slot.reagents[1]
                if r and r.itemID and slot.required ~= false then
                    table.insert(out, { itemID = r.itemID, count = slot.quantityRequired or 1 })
                end
            end
            return out, sch.outputItemID
        end
    end
    if T.GetRecipeNumReagents then
        local n = try(T.GetRecipeNumReagents, id) or 0
        for i = 1, n do
            local name, tex, count = try(T.GetRecipeReagentInfo, id, i)
            local link = T.GetRecipeReagentItemLink and try(T.GetRecipeReagentItemLink, id, i)
            local itemID = link and tonumber(link:match("item:(%d+)"))
            table.insert(out, { name = name, icon = tex, count = count or 1, itemID = itemID })
        end
    end
    return out
end

local function CollectApiFields(info)
    local f = {}
    for k, v in pairs(info) do
        local t = type(v)
        if t == "number" or t == "boolean" or t == "string" then f[k] = v end
    end
    return f
end

local function ScanModern()
    if not (T and T.GetAllRecipeIDs) then return false end
    if T.IsTradeSkillLinked and try(T.IsTradeSkillLinked) then return true end
    if T.IsTradeSkillGuild and try(T.IsTradeSkillGuild) then return true end
    if T.IsNPCCrafting and try(T.IsNPCCrafting) then return true end
    local prof, rank, maxRank = ModernProfLine()
    if not prof then return false end
    local ids = try(T.GetAllRecipeIDs)
    if type(ids) ~= "table" or #ids == 0 then return false end
    SetProfLevel(prof, rank, maxRank)

    local count, learnedCount = 0, 0
    for _, id in ipairs(ids) do
        local info = try(T.GetRecipeInfo, id)
        if type(info) == "table" and info.name and not info.isDummyRecipe then
            local data = {
                name = info.name,
                icon = info.icon,
                recipeID = id,
                learned = info.learned and true or false,
                diff = NormDiff(info.relativeDifficulty or info.difficulty),
                category = info.categoryID,
            }
            data.link = T.GetRecipeItemLink and try(T.GetRecipeItemLink, id)
            data.spellLink = T.GetRecipeLink and try(T.GetRecipeLink, id)
            local reagents, outputID = ModernReagents(id)
            data.reagents = reagents
            data.productID = outputID or (data.link and tonumber(data.link:match("item:(%d+)")))
            if T.GetRecipeSourceText then
                data.sourceText = try(T.GetRecipeSourceText, id)
            end
            if T.GetRecipeDescription then
                data.description = try(T.GetRecipeDescription, id)
            end
            data.apiFields = CollectApiFields(info)
            -- Si la API expone umbrales directamente, los usamos
            if info.minSkillLevel and info.minSkillLevel > 0 then data.reqSkill = info.minSkillLevel end
            if info.maxTrivialLevel and info.maxTrivialLevel > 0 then data.maxTrivial = info.maxTrivialLevel end
            -- En recetas no aprendidas, solo registramos dificultad si no es un 0 por defecto sin requisito verificado
            if not data.learned then
                if data.diff == "optimal" and not (data.reqSkill and rank and rank >= data.reqSkill) then
                    data.diff = nil
                end
            end
            Store(prof, id, data, rank)
            count = count + 1
            if data.learned then learnedCount = learnedCount + 1 end
        end
    end
    ns.lastScanInfo = string.format("%s (moderno): %d recetas, %d conocidas, nivel %s", prof, count, learnedCount, tostring(rank))
    return true
end

---------------------------------------------------------------------------
-- API clásica (TradeSkill)
---------------------------------------------------------------------------
local expandedOnce = false

local function ScanLegacyTrade()
    if not (GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillLine) then return false end
    local prof, rank, maxRank = GetTradeSkillLine()
    if not prof or prof == "UNKNOWN" or prof == "" then return false end
    if IsTradeSkillLinked and try(IsTradeSkillLinked) then return true end
    if not expandedOnce and ExpandTradeSkillSubClass then
        expandedOnce = true
        try(ExpandTradeSkillSubClass, 0) -- abre todas las categorías
    end
    SetProfLevel(prof, rank, maxRank)
    local n = GetNumTradeSkills() or 0
    local count = 0
    for i = 1, n do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
            local data = { name = name, learned = true, diff = NormDiff(kind) }
            data.icon = GetTradeSkillIcon and try(GetTradeSkillIcon, i)
            data.link = GetTradeSkillItemLink and try(GetTradeSkillItemLink, i)
            data.spellLink = GetTradeSkillRecipeLink and try(GetTradeSkillRecipeLink, i)
            data.productID = data.link and tonumber(data.link:match("item:(%d+)"))
            local reagents = {}
            local nr = (GetTradeSkillNumReagents and try(GetTradeSkillNumReagents, i)) or 0
            for j = 1, nr do
                local rn, rt, rc = try(GetTradeSkillReagentInfo, i, j)
                local rl = GetTradeSkillReagentItemLink and try(GetTradeSkillReagentItemLink, i, j)
                table.insert(reagents, { name = rn, icon = rt, count = rc or 1, itemID = rl and tonumber(rl:match("item:(%d+)")) })
            end
            data.reagents = reagents
            Store(prof, name, data, rank)
            count = count + 1
        end
    end
    ns.lastScanInfo = string.format("%s (clásico): %d recetas conocidas, nivel %s", prof, count, tostring(rank))
    return count > 0
end

local function ScanLegacyCraft()
    if not (GetNumCrafts and GetCraftInfo) then return false end
    local prof, rank, maxRank
    if GetCraftDisplaySkillLine then prof, rank, maxRank = GetCraftDisplaySkillLine() end
    if not prof and GetCraftSkillLine then prof, rank, maxRank = GetCraftSkillLine(1) end
    if not prof or prof == "UNKNOWN" or prof == "" then return false end
    SetProfLevel(prof, rank, maxRank)
    local count = 0
    for i = 1, (GetNumCrafts() or 0) do
        local name, _, kind = GetCraftInfo(i)
        if name and kind ~= "header" then
            local data = { name = name, learned = true, diff = NormDiff(kind) }
            data.icon = GetCraftIcon and try(GetCraftIcon, i)
            data.link = GetCraftItemLink and try(GetCraftItemLink, i)
            data.spellLink = GetCraftRecipeLink and try(GetCraftRecipeLink, i)
            local reagents = {}
            local nr = (GetCraftNumReagents and try(GetCraftNumReagents, i)) or 0
            for j = 1, nr do
                local rn, rt, rc = try(GetCraftReagentInfo, i, j)
                local rl = GetCraftReagentItemLink and try(GetCraftReagentItemLink, i, j)
                table.insert(reagents, { name = rn, icon = rt, count = rc or 1, itemID = rl and tonumber(rl:match("item:(%d+)")) })
            end
            data.reagents = reagents
            Store(prof, name, data, rank)
            count = count + 1
        end
    end
    ns.lastScanInfo = string.format("%s (clásico/craft): %d recetas conocidas, nivel %s", prof, count, tostring(rank))
    return count > 0
end

---------------------------------------------------------------------------
-- Disparadores (con pequeño retardo para no escanear 20 veces seguidas)
---------------------------------------------------------------------------
local pending = {}
local scanFrame = CreateFrame("Frame")
local elapsed = 0
scanFrame:Hide()
scanFrame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < 0.4 then return end
    self:Hide()
    local did = false
    if pending.trade then
        pending.trade = nil
        local ok, res = pcall(ScanModern)
        if not (ok and res) then
            local ok2, res2 = pcall(ScanLegacyTrade)
            did = ok2 and res2
        else
            did = true
        end
    end
    if pending.craft then
        pending.craft = nil
        local ok, res = pcall(ScanLegacyCraft)
        did = did or (ok and res)
    end
    if did then
        ns.UpdateCharProfessions()
        if ns.RefreshUI then ns.RefreshUI() end
    end
end)

local function Queue(kind)
    pending[kind] = true
    elapsed = 0
    scanFrame:Show()
end
ns.QueueScan = Queue

function ns.InitScanner()
    T = C_TradeSkillUI
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE",
        "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED", "CRAFT_SHOW", "CRAFT_UPDATE",
        "TRADE_SKILL_CLOSE" }) do
        ns.SafeRegister(f, ev)
    end
    f:SetScript("OnEvent", function(self, event)
        if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
            Queue("craft")
        elseif event == "TRADE_SKILL_CLOSE" then
            expandedOnce = false
        else
            if event == "TRADE_SKILL_SHOW" then expandedOnce = false end
            Queue("trade")
        end
    end)
end
