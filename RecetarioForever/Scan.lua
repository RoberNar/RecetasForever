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
    r.classicSeed = nil
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
    if ns.EnrichFromClassic then ns.EnrichFromClassic(r, prof) end

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
    -- Quita recetas clásicas sembradas que ya no existen en este servidor
    if count > 0 and ns.db.recipes[prof] then
        for k, r in pairs(ns.db.recipes[prof]) do
            if r.classicSeed then ns.db.recipes[prof][k] = nil end
        end
        ns.nameIndex = nil
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
-- Registro automático al hablar con vendedores e instructores
---------------------------------------------------------------------------
local function FormatMoney(copper)
    if not copper or copper <= 0 then return "" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if s > 0 then table.insert(parts, s .. "p") end
    if c > 0 and g == 0 then table.insert(parts, c .. "c") end
    return table.concat(parts, " ")
end

local function AppendSourceLine(r, line)
    if not line or line == "" then return end
    if not r.sourceText or r.sourceText == "" then
        r.sourceText = line
        return
    end
    if r.sourceText:find(line, 1, true) then return end
    r.sourceText = r.sourceText .. "\n" .. line
end

local function FindRecipeByItemOrName(itemID, itemName)
    local idx = ns.GetNameIndex()
    local hits = {}
    if itemID then
        for prof, list in pairs(ns.db.recipes) do
            for key, r in pairs(list) do
                if r.recipeItemID == itemID then
                    table.insert(hits, { prof, key, r })
                end
            end
        end
    end
    if #hits == 0 and itemName then
        local base = itemName:match("^[^:]+:%s*(.+)$")
        local matches = base and idx[base:lower()]
        if matches then
            for _, m in ipairs(matches) do
                local r = ns.GetRecipe(m[1], m[2])
                if r then table.insert(hits, { m[1], m[2], r }) end
            end
        end
    end
    return hits
end

local function ScanMerchant()
    if not (GetMerchantNumItems and GetMerchantItemInfo) then return end
    local npc = UnitName and UnitName("npc")
    if not npc or npc == "" then return end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local updated = 0
    for i = 1, (GetMerchantNumItems() or 0) do
        local name, _, price, _, _, _, _, extendedCost = GetMerchantItemInfo(i)
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if name or itemID then
            local hits = FindRecipeByItemOrName(itemID, name)
            for _, h in ipairs(hits) do
                local r = h[3]
                if itemID and not r.recipeItemID then r.recipeItemID = itemID end
                if r.source ~= "reputation" then
                    r.source = extendedCost and "reputation" or "vendor"
                end
                local costStr = FormatMoney(price)
                local loc = (zone ~= "" and (" (" .. zone .. ")") or "")
                local note = "Vendedor: " .. npc .. loc .. (costStr ~= "" and (" - " .. costStr) or "")
                AppendSourceLine(r, note)
                updated = updated + 1
            end
        end
    end
    if updated > 0 and ns.RefreshUI then ns.RefreshUI() end
end

local function ScanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
    local npc = UnitName and UnitName("npc")
    if not npc or npc == "" then return end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local idx = ns.GetNameIndex()
    local updated = 0
    for i = 1, (GetNumTrainerServices() or 0) do
        local name, _, category = GetTrainerServiceInfo(i)
        if name and category ~= "header" then
            local matches = idx[name:lower()]
            if matches then
                local skillLine, reqLevel
                if GetTrainerServiceSkillReq then
                    skillLine, reqLevel = try(GetTrainerServiceSkillReq, i)
                end
                local cost = GetTrainerServiceCost and try(GetTrainerServiceCost, i)
                for _, m in ipairs(matches) do
                    local prof, r = m[1], ns.GetRecipe(m[1], m[2])
                    if r and (not skillLine or ns.ResolveProfessionName(skillLine) == prof) then
                        if reqLevel and reqLevel > 0 and not r.reqSkill then r.reqSkill = reqLevel end
                        if not r.source or r.source == "unknown" or r.source == "other" then
                            r.source = "trainer"
                        end
                        local costStr = FormatMoney(cost)
                        local loc = (zone ~= "" and (" (" .. zone .. ")") or "")
                        local note = "Instructor: " .. npc .. loc .. (costStr ~= "" and (" - " .. costStr) or "")
                        AppendSourceLine(r, note)
                        updated = updated + 1
                    end
                end
            end
        end
    end
    if updated > 0 and ns.RefreshUI then ns.RefreshUI() end
end

-- Consulta opcional a Questie si está instalado en el juego
function ns.QueryQuestieForRecipe(r)
    if not (r and r.recipeItemID and _G.QuestieLoader) then return nil end
    local ok, QDB = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, "QuestieDB")
    if not (ok and type(QDB) == "table" and QDB.QueryItemSingle) then return nil end
    local lines = {}
    local okV, vendors = pcall(QDB.QueryItemSingle, r.recipeItemID, "vendors")
    if okV and type(vendors) == "table" and #vendors > 0 and QDB.QueryNPCSingle then
        local names = {}
        for k = 1, math.min(#vendors, 4) do
            local okN, npcName = pcall(QDB.QueryNPCSingle, vendors[k], "name")
            if okN and npcName then table.insert(names, npcName) end
        end
        if #names > 0 then table.insert(lines, "Vendedor (Questie): " .. table.concat(names, ", ")) end
    end
    local okD, drops = pcall(QDB.QueryItemSingle, r.recipeItemID, "npcDrops")
    if okD and type(drops) == "table" and #drops > 0 and QDB.QueryNPCSingle then
        local names = {}
        for k = 1, math.min(#drops, 3) do
            local okN, npcName = pcall(QDB.QueryNPCSingle, drops[k], "name")
            if okN and npcName then table.insert(names, npcName) end
        end
        if #names > 0 then table.insert(lines, "Botín (Questie): " .. table.concat(names, ", ")) end
    end
    if #lines > 0 then return table.concat(lines, "\n") end
    return nil
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
    if pending.merchant then
        pending.merchant = nil
        pcall(ScanMerchant)
    end
    if pending.trainer then
        pending.trainer = nil
        pcall(ScanTrainer)
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
        "TRADE_SKILL_CLOSE", "MERCHANT_SHOW", "MERCHANT_UPDATE", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
        ns.SafeRegister(f, ev)
    end
    f:SetScript("OnEvent", function(self, event)
        if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
            Queue("craft")
        elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
            Queue("merchant")
        elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
            Queue("trainer")
        elseif event == "TRADE_SKILL_CLOSE" then
            expandedOnce = false
        else
            if event == "TRADE_SKILL_SHOW" then expandedOnce = false end
            Queue("trade")
        end
    end)
end
