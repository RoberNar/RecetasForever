-- Recetario Forever - Tooltips de recetas (Receta:/Patrón:/Diseño:/...)
-- Al pasar el mouse sobre una receta muestra si la conoces y quién de tus pjs la conoce.
local ADDON, ns = ...

local function FindMatches(itemName)
    if not itemName then return nil end
    local idx = ns.GetNameIndex()
    local base = itemName:match("^[^:]+:%s*(.+)$")
    local m = base and idx[base:lower()]
    if m then return m, true end
    m = idx[itemName:lower()]
    if m then return m, false end
    return nil
end

local function LearnReqSkill(tt, matches)
    if #matches ~= 1 then return end
    local prof, key = matches[1][1], matches[1][2]
    local r = ns.GetRecipe(prof, key)
    if not r or r.reqSkill then return end
    local name = tt:GetName()
    if not name then return end
    for i = 2, math.min(tt:NumLines(), 15) do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text:find(prof, 1, true) then
            local n = text:match("%((%d+)%)")
            if n then
                r.reqSkill = tonumber(n)
                return
            end
        end
    end
end

local function AddInfo(tt, itemName)
    if not ns.db or not itemName then return end
    local matches, isRecipeItem = FindMatches(itemName)
    if not matches then return end
    if isRecipeItem then LearnReqSkill(tt, matches) end
    tt:AddLine(" ")
    for _, m in ipairs(matches) do
        local prof, key = m[1], m[2]
        local r = ns.GetRecipe(prof, key)
        if r then
            local header = isRecipeItem and "Recetario" or ("Se fabrica con " .. prof)
            local by = ns.KnownBy(prof, key)
            local rank = ns.CharRank(prof)
            local line = "|cffffb84d" .. header .. ":|r "
            if ns.IsKnown(prof, key) then
                line = line .. "|cff40ff40Ya la conoces|r"
            elseif rank then
                local diff = ns.PredictDiff(r, rank)
                line = line .. "|cffff5050No la conoces|r - " .. ns.Colorize(ns.DIFF_NAME[diff], diff)
            else
                line = line .. "|cff999999No tienes " .. prof .. "|r"
            end
            tt:AddLine(line)
            if #by > 0 then tt:AddLine("  La conocen: " .. table.concat(by, ", "), 0.8, 0.8, 0.8) end
            local t = ns.Thresholds(r)
            tt:AddLine("  " .. ns.Colorize(ns.FormatRange(t.optimal[1], t.optimal[2]), "optimal") .. " / "
                .. ns.Colorize(ns.FormatRange(t.medium[1], t.medium[2]), "medium") .. " / "
                .. ns.Colorize(ns.FormatRange(t.easy[1], t.easy[2]), "easy") .. " / "
                .. ns.Colorize(ns.FormatRange(t.trivial[1], t.trivial[2]), "trivial"))
        end
    end
    tt:Show()
end

local function HandleTooltip(tt)
    if not tt or not tt.GetItem then return end
    local name, link = tt:GetItem()
    if (not name or name == "") and link and GetItemInfo then name = GetItemInfo(link) end
    AddInfo(tt, name)
end

function ns.InitTooltip()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
            if tt == GameTooltip or tt == ItemRefTooltip then pcall(HandleTooltip, tt) end
        end)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript then
                pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(HandleTooltip, self) end)
            end
        end
    end
end
