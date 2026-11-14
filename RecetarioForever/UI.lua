-- Recetario Forever - Interfaz
local ADDON, ns = ...

local ALL = "__ALL__"
local W, H = 980, 560
local ROW_H, ROWS = 18, 20
local LIST_X, LIST_W = 190, 400
local DETAIL_X = 620

local F                 -- ventana principal
local rows = {}
local profButtons = {}
local statusButtons = {}
local sourceChecks, colorChecks = {}, {}
local slider, infoText, emptyText
local detail = {}

local state = {
    prof = nil,         -- profesión elegida o ALL
    offset = 0,
    list = {},
    selected = nil,     -- { prof, key }
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function ItemName(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(itemID)
        if n then return n end
    end
    local n = GetItemInfo and GetItemInfo(itemID)
    if not n and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return n
end

local function ItemIcon(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemIconByID then
        local i = C_Item.GetItemIconByID(itemID)
        if i then return i end
    end
    if GetItemIcon then return GetItemIcon(itemID) end
end

local function Est(range)
    if not range then return nil end
    local lo, hi = range[1], range[2]
    if lo and hi then return math.floor((lo + hi) / 2) end
    return lo or hi
end

local function SortSkill(r)
    local t = ns.Thresholds(r)
    return r.reqSkill or t.optimal[2] or t.medium[1] or 9999
end

local function MakeFont(parent, template, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    if size then
        local font, _, flags = fs:GetFont()
        if font then fs:SetFont(font, size, flags) end
    end
    return fs
end

local function SetBackdropSafe(frame, bg, edge, edgeSize, inset)
    local solid = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetPoint("TOPLEFT", inset, -inset)
    solid:SetPoint("BOTTOMRIGHT", -inset, inset)
    solid:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = bg, edgeFile = edge, tile = true, tileSize = 32, edgeSize = edgeSize,
            insets = { left = inset, right = inset, top = inset, bottom = inset },
        })
        if frame.SetBackdropColor then frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95) end
    end
end

---------------------------------------------------------------------------
-- Construcción de la lista filtrada
---------------------------------------------------------------------------
local function ProfessionList()
    local seen, mine, others = {}, {}, {}
    for name in pairs(ns.char.profs) do
        seen[name] = true
        table.insert(mine, name)
    end
    for name in pairs(ns.db.recipes) do
        if not seen[name] then table.insert(others, name) end
    end
    table.sort(mine)
    table.sort(others)
    return mine, others
end

local function BuildList()
    local db, ui = ns.db, ns.db.ui
    local profs = {}
    if state.prof == ALL then
        for p in pairs(db.recipes) do table.insert(profs, p) end
    elseif state.prof then
        profs = { state.prof }
    end
    local q = (F.search:GetText() or ""):lower()
    local list, total = {}, 0
    for _, prof in ipairs(profs) do
        local rank = ns.CharRank(prof)
        for key, r in pairs(db.recipes[prof] or {}) do
            total = total + 1
            local known = ns.IsKnown(prof, key)
            local pass = true
            if ui.status == "known" and not known then pass = false end
            if ui.status == "unknown" and known then pass = false end
            local src = r.source or "unknown"
            if pass and not ui.sources[src] then pass = false end
            local diff, exact = "unknown", false
            if rank then diff, exact = ns.PredictDiff(r, rank) end
            if pass and not ui.colors[diff] then pass = false end
            if pass and q ~= "" then
                local hay = (r.name or ""):lower()
                if not hay:find(q, 1, true) then
                    local st = r.sourceText and ns.StripCodes(r.sourceText):lower() or ""
                    if not st:find(q, 1, true) then pass = false end
                end
            end
            if pass then
                table.insert(list, {
                    prof = prof, key = key, r = r, known = known,
                    diff = diff, exact = exact, sort = SortSkill(r),
                })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.sort ~= b.sort then return a.sort < b.sort end
        return (a.r.name or "") < (b.r.name or "")
    end)
    state.list = list
    return list, total
end

---------------------------------------------------------------------------
-- Detalle
---------------------------------------------------------------------------
local function UpdateBar(r, rank)
    local bar = detail.bar
    local t = ns.Thresholds(r)
    local s1 = t.optimal[1] or t.optimal[2]
    local s2, s3, s4 = Est(t.medium), Est(t.easy), Est(t.trivial)
    if not (s2 and s3 and s4) then
        bar:Hide()
        return
    end
    s1 = s1 or math.max(1, s2 - 10)
    local maxScale = math.max(s4 + 25, rank or 0)
    local minScale = math.max(0, s1 - 10)
    local width = bar:GetWidth()
    local function X(v) return (v - minScale) / (maxScale - minScale) * width end
    local starts = { s1, s2, s3, s4, maxScale }
    for i = 1, 4 do
        local seg = bar.segs[i]
        local x1, x2 = X(starts[i]), X(math.max(starts[i], starts[i + 1]))
        seg:ClearAllPoints()
        seg:SetPoint("TOPLEFT", bar, "TOPLEFT", x1, 0)
        seg:SetWidth(math.max(1, x2 - x1))
        seg:SetHeight(bar:GetHeight())
        local c = ns.DIFF_COLOR[ns.DIFF_ORDER[i]]
        seg:SetColorTexture(c[1], c[2], c[3], 1)
        bar.labels[i]:ClearAllPoints()
        bar.labels[i]:SetPoint("TOP", bar, "TOPLEFT", x1, -14)
        bar.labels[i]:SetText(starts[i])
    end
    if rank and rank >= minScale and rank <= maxScale then
        bar.marker:ClearAllPoints()
        bar.marker:SetPoint("CENTER", bar, "LEFT", X(rank), 0)
        bar.marker:Show()
        bar.markerText:SetText("tú: " .. rank)
    else
        bar.marker:Hide()
        bar.markerText:SetText("")
    end
    bar:Show()
end

local function UpdateDetail()
    local sel = state.selected
    local r = sel and ns.GetRecipe(sel[1], sel[2])
    if not r then
        detail.frame:Hide()
        return
    end
    detail.frame:Show()
    local prof, key = sel[1], sel[2]
    local rank, maxRank = ns.CharRank(prof)
    local diff, exact = "unknown", false
    if rank then diff, exact = ns.PredictDiff(r, rank) end

    detail.icon:SetTexture(r.icon or ItemIcon(r.productID) or "Interface\\Icons\\INV_Misc_QuestionMark")
    detail.name:SetText(ns.Colorize(r.name or "?", diff))

    local L = {}
    local function add(s) table.insert(L, s or "") end
    add("|cffffd200Profesión:|r " .. prof)
    local known = ns.IsKnown(prof, key)
    add("|cffffd200Estado:|r " .. (known and "|cff40ff40Conocida|r" or "|cffff5050No conocida|r"))
    local by = ns.KnownBy(prof, key)
    if #by > 0 then add("|cffffd200La conocen:|r " .. table.concat(by, ", ")) end
    if rank then
        add(string.format("|cffffd200Tu nivel:|r %d/%d  ->  %s%s", rank, maxRank or 0,
            ns.Colorize(ns.DIFF_NAME[diff], diff), exact and "" or " |cff999999(estimado)|r"))
    else
        add("|cff999999Este personaje no tiene esta profesión.|r")
    end
    add()
    add("|cffffd200Nivel en que cambia de color:|r")
    local t = ns.Thresholds(r)
    add("  " .. ns.Colorize("Naranja " .. ns.FormatRange(t.optimal[1], t.optimal[2]), "optimal")
        .. "   " .. ns.Colorize("Amarillo " .. ns.FormatRange(t.medium[1], t.medium[2]), "medium"))
    add("  " .. ns.Colorize("Verde " .. ns.FormatRange(t.easy[1], t.easy[2]), "easy")
        .. "   " .. ns.Colorize("Gris " .. ns.FormatRange(t.trivial[1], t.trivial[2]), "trivial"))
    local complete = true
    for _, d in ipairs({ "medium", "easy", "trivial" }) do
        if not (t[d][1] and t[d][2] and t[d][1] >= t[d][2]) then complete = false end
    end
    if not complete then
        add("|cff999999(\"5-9\" = cambia entre esos niveles. Se afina solo cada vez que abres la profesión con más nivel, con cualquier pj.)|r")
    end
    local splitAt = #L
    add("|cffffd200Cómo se consigue:|r " .. (ns.SOURCE_NAME[r.source or "unknown"] or "?"))
    if r.sourceText and r.sourceText ~= "" then
        add(r.sourceText:gsub("|n", "\n"))
    elseif known then
        add("|cff999999La API no da la fuente de recetas ya aprendidas. Si otro pj tuyo la ve sin aprender, se completa.|r")
    else
        add("|cff999999Sin datos de fuente.|r")
    end
    if r.description and r.description ~= "" then
        add("|cffcccccc" .. ns.StripCodes(r.description) .. "|r")
    end
    if r.reagents and #r.reagents > 0 then
        add()
        add("|cffffd200Reactivos:|r")
        for _, rg in ipairs(r.reagents) do
            local name = rg.name or ItemName(rg.itemID) or ("objeto " .. tostring(rg.itemID))
            local have = rg.itemID and GetItemCount and GetItemCount(rg.itemID, true) or nil
            add(string.format("  %dx %s%s", rg.count or 1, name, have and ("  |cff999999(tienes " .. have .. ")|r") or ""))
        end
    end
    -- Parte superior / barra / parte inferior
    local top, bottom = {}, {}
    for i = 1, splitAt do table.insert(top, L[i]) end
    for i = splitAt + 1, #L do table.insert(bottom, L[i]) end
    detail.text:SetText(table.concat(top, "\n"))
    detail.text2:SetText(table.concat(bottom, "\n"))
    UpdateBar(r, rank)
    detail.text2:ClearAllPoints()
    detail.text2:SetPoint("TOPLEFT", detail.text, "BOTTOMLEFT", 0, detail.bar:IsShown() and -46 or -10)

    detail.linkBtn:SetEnabled((r.link or r.spellLink) and true or false)
end

---------------------------------------------------------------------------
-- Render de filas
---------------------------------------------------------------------------
local function RenderRows()
    local list = state.list
    local maxOffset = math.max(0, #list - ROWS)
    if state.offset > maxOffset then state.offset = maxOffset end
    for i = 1, ROWS do
        local row = rows[i]
        local e = list[i + state.offset]
        if e then
            row.entry = e
            row.icon:SetTexture(e.r.icon or ItemIcon(e.r.productID) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local name = e.r.name or "?"
            if state.prof == ALL then name = name .. " |cff777777(" .. e.prof .. ")|r" end
            row.name:SetText(ns.Colorize(name, e.diff) .. ((not e.exact and e.diff ~= "unknown") and " |cff777777~|r" or ""))
            row.src:SetText(ns.SOURCE_SHORT[e.r.source or "unknown"] or "")
            local t = ns.Thresholds(e.r)
            row.lvl:SetText(e.r.reqSkill and tostring(e.r.reqSkill) or (t.optimal[2] and ("<=" .. t.optimal[2]) or ""))
            row.check:SetShown(e.known)
            local sel = state.selected
            row.sel:SetShown(sel and sel[1] == e.prof and sel[2] == e.key or false)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    slider:SetMinMaxValues(0, maxOffset)
    slider:SetShown(maxOffset > 0)
    if math.floor(slider:GetValue() + 0.5) ~= state.offset then slider:SetValue(state.offset) end
end

local function RefreshProfButtons()
    local mine, others = ProfessionList()
    local entries = {}
    for _, p in ipairs(mine) do table.insert(entries, { prof = p, mine = true }) end
    for _, p in ipairs(others) do table.insert(entries, { prof = p }) end
    table.insert(entries, { prof = ALL })
    if not state.prof then state.prof = mine[1] or others[1] or ALL end
    for i, btn in ipairs(profButtons) do
        local e = entries[i]
        if e then
            btn.prof = e.prof
            if e.prof == ALL then
                btn.text:SetText("|cff80c0ffBuscar en todas|r")
            else
                local rank, maxRank = ns.CharRank(e.prof)
                local n = 0
                for _ in pairs(ns.db.recipes[e.prof] or {}) do n = n + 1 end
                if e.mine then
                    btn.text:SetText(string.format("%s |cffaaaaaa%s/%s|r", e.prof, tostring(rank or "?"), tostring(maxRank or "?")))
                else
                    btn.text:SetText("|cff999999" .. e.prof .. " (otros pjs)|r")
                end
                if n == 0 and not (ns.GATHERING_PROFS and ns.GATHERING_PROFS[e.prof:lower()]) then
                    btn.text:SetText(btn.text:GetText() .. " |cffff6060*|r")
                end
            end
            btn.sel:SetShown(state.prof == e.prof)
            btn:Show()
        else
            btn:Hide()
        end
    end
end

function ns.RefreshUI()
    if not F or not F:IsShown() then return end
    RefreshProfButtons()
    local ui = ns.db.ui
    for k, b in pairs(statusButtons) do
        if ui.status == k then b:LockHighlight() else b:UnlockHighlight() end
    end
    for k, cb in pairs(sourceChecks) do cb:SetChecked(ui.sources[k]) end
    for k, cb in pairs(colorChecks) do cb:SetChecked(ui.colors[k]) end
    local list, total = BuildList()
    RenderRows()
    infoText:SetText(string.format("Mostrando %d de %d recetas", #list, total))
    if total == 0 and state.prof ~= ALL then
        if ns.GATHERING_PROFS and state.prof and ns.GATHERING_PROFS[state.prof:lower()] then
            emptyText:SetText("Esta es una profesión de recolección y no tiene ventana propia de recetas.")
        else
            emptyText:SetText("No hay recetas guardadas de esta profesión.\n\nAbre la ventana de la profesión en el juego\n(libro de hechizos o tecla K) una vez y se cargan solas.\n\nLas de otras profesiones aparecen cuando\nlas abres con otro personaje tuyo.")
        end
        emptyText:Show()
    elseif #list == 0 then
        emptyText:SetText("Ninguna receta cumple los filtros.")
        emptyText:Show()
    else
        emptyText:Hide()
    end
    UpdateDetail()
end

---------------------------------------------------------------------------
-- Creación de la ventana
---------------------------------------------------------------------------
local function CreateCheck(parent, label, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local fs = MakeFont(cb, "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 0, 1)
    fs:SetText(label)
    cb:SetScript("OnClick", onClick)
    return cb
end

local function CreateUI()
    F = CreateFrame("Frame", "RecetarioForeverFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    F:SetSize(W, H)
    F:SetPoint("CENTER")
    F:SetFrameStrata("HIGH")
    F:SetMovable(true)
    F:EnableMouse(true)
    F:SetClampedToScreen(true)
    F:RegisterForDrag("LeftButton")
    F:SetScript("OnDragStart", F.StartMoving)
    F:SetScript("OnDragStop", F.StopMovingOrSizing)
    SetBackdropSafe(F, "Interface\\DialogFrame\\UI-DialogBox-Background", "Interface\\DialogFrame\\UI-DialogBox-Border", 32, 11)
    table.insert(UISpecialFrames, "RecetarioForeverFrame")
    F:Hide()

    local title = MakeFont(F, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetText("Recetario Forever")

    local close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Profesiones (izquierda)
    local ph = MakeFont(F, "GameFontNormal")
    ph:SetPoint("TOPLEFT", 20, -48)
    ph:SetText("Profesiones")
    for i = 1, 16 do
        local b = CreateFrame("Button", nil, F)
        b:SetSize(160, 22)
        b:SetPoint("TOPLEFT", 16, -66 - (i - 1) * 24)
        b.text = MakeFont(b, "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWidth(154)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.8, 0.2, 0.25)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
        b:SetScript("OnClick", function(self)
            state.prof = self.prof
            state.offset = 0
            ns.RefreshUI()
        end)
        profButtons[i] = b
    end

    -- Buscador
    local sl = MakeFont(F, "GameFontNormalSmall")
    sl:SetPoint("TOPLEFT", LIST_X, -46)
    sl:SetText("Buscar (nombre, zona, vendedor...):")
    local search = CreateFrame("EditBox", "RecetarioForeverSearchBox", F, "InputBoxTemplate")
    search:SetSize(220, 20)
    search:SetPoint("TOPLEFT", LIST_X + 6, -60)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() state.offset = 0; ns.RefreshUI() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    F.search = search

    -- Estado
    local statusDefs = { { "all", "Todas" }, { "known", "Conocidas" }, { "unknown", "No conocidas" } }
    for i, d in ipairs(statusDefs) do
        local b = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
        b:SetSize(100, 22)
        b:SetPoint("TOPLEFT", LIST_X + 240 + (i - 1) * 104, -58)
        b:SetText(d[2])
        b:SetScript("OnClick", function()
            ns.db.ui.status = d[1]
            state.offset = 0
            ns.RefreshUI()
        end)
        statusButtons[d[1]] = b
    end

    -- Filtro por fuente
    local fl = MakeFont(F, "GameFontNormalSmall")
    fl:SetPoint("TOPLEFT", LIST_X, -88)
    fl:SetText("Fuente:")
    local srcLabel = { trainer = "Instr.", vendor = "Vend.", reputation = "Reput.", quest = "Misión",
        drop = "Botín", discovery = "Descub.", other = "Otra", unknown = "Sin datos" }
    for i, s in ipairs(ns.SOURCE_ORDER) do
        sourceChecks[s] = CreateCheck(F, srcLabel[s], LIST_X + 46 + (i - 1) * 90, -82, function(self)
            ns.db.ui.sources[s] = self:GetChecked() and true or false
            state.offset = 0
            ns.RefreshUI()
        end)
    end
    -- Botón "solo comprables"
    local onlyVendor = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    onlyVendor:SetSize(115, 20)
    onlyVendor:SetPoint("TOPRIGHT", F, "TOPRIGHT", -38, -14)
    onlyVendor:SetText("Solo comprables")
    onlyVendor:SetScript("OnClick", function()
        for _, s in ipairs(ns.SOURCE_ORDER) do ns.db.ui.sources[s] = (s == "vendor" or s == "reputation") end
        state.offset = 0
        ns.RefreshUI()
    end)
    local allSrc = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    allSrc:SetSize(115, 20)
    allSrc:SetPoint("RIGHT", onlyVendor, "LEFT", -6, 0)
    allSrc:SetText("Todas las fuentes")
    allSrc:SetScript("OnClick", function()
        for _, s in ipairs(ns.SOURCE_ORDER) do ns.db.ui.sources[s] = true end
        for k in pairs(ns.db.ui.colors) do ns.db.ui.colors[k] = true end
        state.offset = 0
        ns.RefreshUI()
    end)

    -- Filtro por color (a TU nivel actual)
    local cl = MakeFont(F, "GameFontNormalSmall")
    cl:SetPoint("TOPLEFT", LIST_X, -112)
    cl:SetText("Color:")
    local colorDefs = { "optimal", "medium", "easy", "trivial", "difficult", "unknown" }
    local colorLabel = { optimal = "Naranja", medium = "Amarillo", easy = "Verde", trivial = "Gris", difficult = "Rojo (bajo)", unknown = "Sin datos" }
    for i, c in ipairs(colorDefs) do
        colorChecks[c] = CreateCheck(F, ns.Colorize(colorLabel[c], c), LIST_X + 46 + (i - 1) * 105, -106, function(self)
            ns.db.ui.colors[c] = self:GetChecked() and true or false
            state.offset = 0
            ns.RefreshUI()
        end)
    end

    -- Encabezados
    local hy = -136
    local h1 = MakeFont(F, "GameFontNormalSmall"); h1:SetPoint("TOPLEFT", LIST_X + 24, hy); h1:SetText("Receta (color a tu nivel)")
    local h2 = MakeFont(F, "GameFontNormalSmall"); h2:SetPoint("TOPLEFT", LIST_X + 270, hy); h2:SetText("Nivel")
    local h3 = MakeFont(F, "GameFontNormalSmall"); h3:SetPoint("TOPLEFT", LIST_X + 318, hy); h3:SetText("Fuente")

    -- Filas
    local listFrame = CreateFrame("Frame", nil, F)
    listFrame:SetPoint("TOPLEFT", LIST_X, hy - 16)
    listFrame:SetSize(LIST_W, ROW_H * ROWS)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, state.offset - delta * 3)
        RenderRows()
    end)
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, listFrame)
        row:SetSize(LIST_W, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.04)
        end
        row.sel = row:CreateTexture(nil, "BORDER")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.8, 0.2, 0.22)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
        row.check = row:CreateTexture(nil, "OVERLAY")
        row.check:SetSize(14, 14)
        row.check:SetPoint("LEFT", 2, 0)
        row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 20, 0)
        row.name = MakeFont(row, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 40, 0)
        row.name:SetWidth(230)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.lvl = MakeFont(row, "GameFontHighlightSmall")
        row.lvl:SetPoint("LEFT", 272, 0)
        row.src = MakeFont(row, "GameFontHighlightSmall")
        row.src:SetPoint("LEFT", 320, 0)
        row:SetScript("OnClick", function(self)
            if not self.entry then return end
            if IsShiftKeyDown() and (self.entry.r.link or self.entry.r.spellLink) and ChatEdit_InsertLink then
                ChatEdit_InsertLink(self.entry.r.link or self.entry.r.spellLink)
                return
            end
            state.selected = { self.entry.prof, self.entry.key }
            RenderRows()
            UpdateDetail()
        end)
        row:SetScript("OnEnter", function(self)
            local link = self.entry and (self.entry.r.link or self.entry.r.spellLink)
            if link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end

    slider = CreateFrame("Slider", nil, F)
    slider:SetOrientation("VERTICAL")
    slider:SetSize(14, ROW_H * ROWS)
    slider:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 2, 0)
    local sbg = slider:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(0, 0, 0, 0.4)
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:SetScript("OnValueChanged", function(_, v)
        local o = math.floor(v + 0.5)
        if o ~= state.offset then
            state.offset = o
            RenderRows()
        end
    end)

    emptyText = MakeFont(F, "GameFontNormal")
    emptyText:SetPoint("TOP", listFrame, "TOP", 0, -60)
    emptyText:SetWidth(LIST_W - 20)

    infoText = MakeFont(F, "GameFontDisableSmall")
    infoText:SetPoint("BOTTOMLEFT", LIST_X, 18)

    local hint = MakeFont(F, "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 18)
    hint:SetWidth(165)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cffff6060*|r = abre esa profesión\nuna vez para cargarla.\n~ = color estimado.\nShift+clic = link al chat.")

    -- Panel de detalle
    local d = CreateFrame("Frame", nil, F, BackdropTemplateMixin and "BackdropTemplate" or nil)
    d:SetPoint("TOPLEFT", DETAIL_X, -132)
    d:SetPoint("BOTTOMRIGHT", -18, 16)
    SetBackdropSafe(d, "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border", 14, 3)
    if d.SetBackdropColor then d:SetBackdropColor(0, 0, 0, 0.6) end
    detail.frame = d
    detail.icon = d:CreateTexture(nil, "ARTWORK")
    detail.icon:SetSize(32, 32)
    detail.icon:SetPoint("TOPLEFT", 10, -10)
    detail.name = MakeFont(d, "GameFontNormalLarge")
    detail.name:SetPoint("LEFT", detail.icon, "RIGHT", 8, 0)
    detail.name:SetWidth(250)
    detail.name:SetJustifyH("LEFT")
    detail.text = MakeFont(d, "GameFontHighlightSmall")
    detail.text:SetPoint("TOPLEFT", 12, -50)
    detail.text:SetWidth(280)
    detail.text:SetJustifyH("LEFT")
    detail.text:SetJustifyV("TOP")
    detail.text:SetSpacing(2)
    detail.text2 = MakeFont(d, "GameFontHighlightSmall")
    detail.text2:SetPoint("TOPLEFT", detail.text, "BOTTOMLEFT", 0, -10)
    detail.text2:SetWidth(280)
    detail.text2:SetJustifyH("LEFT")
    detail.text2:SetJustifyV("TOP")
    detail.text2:SetSpacing(2)

    local bar = CreateFrame("Frame", nil, d)
    bar:SetSize(270, 10)
    bar.segs, bar.labels = {}, {}
    for i = 1, 4 do
        bar.segs[i] = bar:CreateTexture(nil, "ARTWORK")
        bar.labels[i] = MakeFont(bar, "GameFontHighlightSmall", 9)
    end
    bar.marker = bar:CreateTexture(nil, "OVERLAY")
    bar.marker:SetSize(2, 16)
    bar.marker:SetColorTexture(1, 1, 1, 1)
    bar.markerText = MakeFont(bar, "GameFontHighlightSmall", 9)
    bar.markerText:SetPoint("BOTTOM", bar.marker, "TOP", 0, 0)
    bar:SetPoint("TOPLEFT", detail.text, "BOTTOMLEFT", 4, -24)
    bar:Hide()
    detail.bar = bar

    local linkBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    linkBtn:SetSize(120, 20)
    linkBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    linkBtn:SetText("Link al chat")
    linkBtn:SetScript("OnClick", function()
        local sel = state.selected
        local r = sel and ns.GetRecipe(sel[1], sel[2])
        local link = r and (r.link or r.spellLink)
        if link and ChatEdit_InsertLink then
            if not ChatEdit_InsertLink(link) and ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
        end
    end)
    detail.linkBtn = linkBtn
    d:Hide()

    F:SetScript("OnShow", function()
        ns.UpdateCharProfessions()
        ns.RefreshUI()
    end)

    -- Refresca nombres de reactivos cuando llegan del servidor
    local itemPending = false
    local itemTimer = CreateFrame("Frame", nil, F)
    itemTimer:Hide()
    itemTimer:SetScript("OnUpdate", function(self)
        self:Hide()
        itemPending = false
        if F:IsShown() then UpdateDetail() end
    end)
    ns.SafeRegister(F, "GET_ITEM_INFO_RECEIVED")
    F:SetScript("OnEvent", function(_, event, _, success)
        if event == "GET_ITEM_INFO_RECEIVED" and success and F:IsShown() and not itemPending then
            itemPending = true
            itemTimer:Show()
        end
    end)
end

function ns.ToggleUI()
    if not F then CreateUI() end
    if F:IsShown() then F:Hide() else F:Show() end
end

function ns.DumpSelectedFields()
    local sel = state.selected
    local r = sel and ns.GetRecipe(sel[1], sel[2])
    if not r then ns.Print("Elige una receta en la ventana primero.") return end
    ns.Print("Campos de", r.name, "(id " .. tostring(r.recipeID or sel[2]) .. ")")
    if r.apiFields then
        local keys = {}
        for k in pairs(r.apiFields) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do ns.Print("  ", k, "=", tostring(r.apiFields[k])) end
    else
        ns.Print("  (sin campos: cliente con API clásica)")
    end
    if C_TradeSkillUI and r.recipeID then
        local T = C_TradeSkillUI
        local src = T.GetRecipeSourceText and select(2, pcall(T.GetRecipeSourceText, r.recipeID))
        local desc = T.GetRecipeDescription and select(2, pcall(T.GetRecipeDescription, r.recipeID))
        ns.Print("  GetRecipeSourceText:", tostring(src))
        ns.Print("  GetRecipeDescription:", tostring(desc))
    end
    for d, o in pairs(r.obs or {}) do ns.Print("  visto", d, "entre", o[1], "y", o[2]) end
end

---------------------------------------------------------------------------
-- Botón del minimapa
---------------------------------------------------------------------------
function ns.CreateMinimapButton()
    if ns.minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "RecetarioForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function Place()
        local a = math.rad(ns.db.ui.minimapAngle or 200)
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
    end
    Place()
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.ui.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            Place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function() ns.ToggleUI() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Recetario Forever")
        GameTooltip:AddLine("Clic: abrir / cerrar", 1, 1, 1)
        GameTooltip:AddLine("Arrastrar: mover", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if ns.db.ui.hideMinimap then b:Hide() end
    ns.minimapButton = b
end

---------------------------------------------------------------------------
-- Botón dentro de la ventana de profesión
---------------------------------------------------------------------------
local attachFrame = CreateFrame("Frame")
ns.SafeRegister(attachFrame, "TRADE_SKILL_SHOW")
ns.SafeRegister(attachFrame, "CRAFT_SHOW")
attachFrame:SetScript("OnEvent", function()
    for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
        local pf = _G[name]
        if pf and not pf.recetarioBtn then
            local b = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
            b:SetSize(90, 20)
            b:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -60, -2)
            b:SetText("Recetario")
            b:SetFrameStrata("HIGH")
            b:SetScript("OnClick", function() ns.ToggleUI() end)
            pf.recetarioBtn = b
        end
    end
end)
