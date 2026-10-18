local MenuUi = {}
local instanceIndex = 0
local awesomeSolid = FrameAPI.Fonts.CreateFontAwesome()

local function resolveLabel(instance, labelValue, tag)
    local valueType = type(labelValue)
    if valueType == "string" then
        return labelValue
    end
    if valueType == "function" then
        return tostring(labelValue())
    end
    return tostring(labelValue)
end

local function resolveSubMenu(instance, item)
    if type(item) ~= "table" then
        return nil
    end
    local subMenuValue = item.subMenu
    local valueType = type(subMenuValue)
    if valueType == "table" then
        return subMenuValue
    end
    if valueType == "function" then
        local result = subMenuValue()
        if type(result) ~= "table" then
            return nil
        end
        return result
    end
    return nil
end

local function normToPixel(nx, ny, nw, nh)
    local sw, sh = GetActiveScreenResolution()
    if not sw or sw <= 0 then sw = 1920 end
    if not sh or sh <= 0 then sh = 1080 end
    local px = (nx - nw * 0.5) * sw
    local py = (ny - nh * 0.5) * sh
    local pw = nw * sw
    local ph = nh * sh
    return px, py, pw, ph
end

local function getRes()
    local sw, sh = GetActiveScreenResolution()
    if not sw or sw <= 0 then sw = 1920 end
    if not sh or sh <= 0 then sh = 1080 end
    return sw, sh
end

local function drawTexturedRect(x, y, width, height, bgColor, textColor, text, font, scale, centerText)
    local px, py, pw, ph = normToPixel(x, y, width, height)
    local sw, sh = getRes()
    FrameAPI.Drawing.DrawRect(px, py, pw, ph, bgColor[1], bgColor[2], bgColor[3], bgColor[4], 0, 1)
    local fontSize = math.max(10, math.floor(ph * 0.45))
    local textX = centerText and (x * sw) or (px + 8)
    local textY  = py + ph * 0.5 - fontSize * 0.5
    FrameAPI.Drawing.DrawText(text, textX, textY, fontSize, centerText or false, textColor[1], textColor[2], textColor[3], textColor[4], "Inter", 2)
end

local function wrapIndex(index, max)
    if max <= 0 then
        return 1
    end
    return ((index - 1) % max) + 1
end

local function ensureMenuStack(instance)
    if type(instance.menuStack) == "table" and #instance.menuStack > 0 then
        return
    end
    instance.menuStack = {
        {
            items = instance.menuItems or {},
            index = type(instance.selectedIndex) == "number" and instance.selectedIndex or 1,
            title = instance.menuConfig and instance.menuConfig.mainTitle or "Menu"
        }
    }
end

local function getCurrentContext(instance)
    ensureMenuStack(instance)
    return instance.menuStack[#instance.menuStack]
end

local function getContextItems(instance, ctx)
    if type(ctx.getItems) == "function" then
        local items = ctx.getItems()
        if type(items) == "table" then
            return items
        end
        return {}
    end
    if type(ctx.items) == "table" then
        return ctx.items
    end
    return {}
end

local function syncLegacyState(instance)
    ensureMenuStack(instance)
    local depth = #instance.menuStack
    instance.isInSubMenu = depth > 1
    local root = instance.menuStack[1]
    instance.selectedIndex = root and root.index or 1
    local current = instance.menuStack[depth]
    instance.subMenuIndex = current and current.index or 1
    if instance.menuConfig and current and current.title ~= nil then
        instance.menuConfig.title = current.title
    elseif instance.menuConfig then
        instance.menuConfig.title = instance.menuConfig.mainTitle
    end
end

local function resetToRoot(instance)
    instance.menuStack = {
        {
            items = instance.menuItems or {},
            index = type(instance.selectedIndex) == "number" and instance.selectedIndex or 1,
            title = instance.menuConfig and instance.menuConfig.mainTitle or "Menu"
        }
    }
    syncLegacyState(instance)
end

local function pushSubMenuContext(instance, item, title)
    ensureMenuStack(instance)
    table.insert(instance.menuStack, {
        getItems = function()
            return resolveSubMenu(instance, item)
        end,
        index = 1,
        title = title
    })
    syncLegacyState(instance)
end

local function popMenuContext(instance)
    ensureMenuStack(instance)
    if #instance.menuStack <= 1 then
        return
    end
    table.remove(instance.menuStack)
    syncLegacyState(instance)
end

local function normalizeCreateMenuArgs(title, subTitle, x, y, color)
    if type(subTitle) == "number" then
        return title, nil, subTitle, x, y
    end
    return title, subTitle, x, y, color
end

local function getVisibleRange(instance, totalItems, currentIndex)
    if totalItems <= instance.maxVisibleItems then
        return 1, totalItems
    end
    local firstIndex = math.max(1, currentIndex - instance.maxVisibleItems + 1)
    local lastIndex = math.min(totalItems, firstIndex + instance.maxVisibleItems - 1)
    return firstIndex, lastIndex
end

local function playSound(instance, name)
    if not instance.menuConfig.soundEnabled then
        return
    end
    PlaySoundFrontend(-1, name, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
end

local function drawMenuTitle(instance)
    local config = instance.menuConfig
    local sw, sh = getRes()
    local px, py, pw, ph = normToPixel(config.x, config.y, config.width, config.titleHeight)
    FrameAPI.Drawing.DrawRect(px, py, pw, ph, config.color[1], config.color[2], config.color[3], config.color[4], 0, 1)
    local cx = config.x * sw
    local titleSize = math.max(14, math.floor(ph * 0.55))
    local subSize   = math.max(10, math.floor(ph * 0.30))
    if type(config.subTitle) == "string" and config.subTitle ~= "" then
        FrameAPI.Drawing.DrawText(config.title, cx, py + ph * 0.5 - titleSize * 0.5 + 16, titleSize, true, 0, 0, 0, 255, "HouseScript", 2)
        FrameAPI.Drawing.DrawText(config.subTitle, cx, py + ph * 0.60, subSize, true, 230, 230, 230, 255, "Inter", 2)
    else
        FrameAPI.Drawing.DrawText(config.title, cx, py + ph * 0.5 - titleSize * 0.5 + 16, titleSize, true, 0, 0, 0, 255, "HouseScript", 2)
    end
end

local function drawMainMenu(instance)
    local ctx = getCurrentContext(instance)
    local items = getContextItems(instance, ctx)
    local config = instance.menuConfig
    local totalItems = #items
    if totalItems == 0 then
        local yPos = config.y + (config.titleHeight / 2) + (config.itemHeight / 2)
        drawTexturedRect(config.x, yPos, config.width, config.itemHeight, { 0, 0, 0, 205 }, { 255, 255, 255, 255 }, "No options")
        return
    end
    if type(ctx.index) ~= "number" or ctx.index < 1 or ctx.index > totalItems then
        ctx.index = wrapIndex(tonumber(ctx.index) or 1, totalItems)
        syncLegacyState(instance)
    end
    local firstIndex, lastIndex = getVisibleRange(instance, totalItems, ctx.index)
    for i = firstIndex, lastIndex do
        local item = items[i]
        local yPos = config.y + ((i - firstIndex + 0.5) * config.itemHeight) + config.titleHeight / 2
        local isSelected = i == ctx.index
        local bgColor = isSelected and { 255, 255, 255, 255 } or { 0, 0, 0, 210 }
        local textColor = isSelected and { 0, 0, 0, 255 } or { 255, 255, 255, 255 }

        if type(item) == "table" and item.isCheckbox then
            -- fundo do item
            local px, py, pw, ph = normToPixel(config.x, yPos, config.width, config.itemHeight)
            FrameAPI.Drawing.DrawRect(px, py, pw, ph, bgColor[1], bgColor[2], bgColor[3], bgColor[4], 0, 1)

            local fontSize = math.max(10, math.floor(ph * 0.45))
            local textY = py + ph * 0.5 - fontSize * 0.5

            local isChecked = type(item.getChecked) == "function" and item.getChecked()
            local label = resolveLabel(instance, item.name, "checkboxName:" .. tostring(i))

            -- texto do nome alinhado à esquerda
            FrameAPI.Drawing.DrawText(label, px + 8, textY, fontSize, false, textColor[1], textColor[2], textColor[3], textColor[4], "Inter", 2)

            -- ícone toggle à direita
            local iconSize = math.max(18, math.floor(ph * 0.75))
            local iconMargin = 8
            local icon = isChecked and "\xef\x88\x85" or "\xef\x88\x84"
            local iconW = FrameAPI.Fonts.GetTextWidthSize(icon, iconSize, awesomeSolid)
            local iconX = px + pw - iconW - iconMargin
            local iconY = py + ph * 0.5 - iconSize * 0.55

            if isChecked then
                -- toggle-on: cor Teal do menu
                local mc = instance.menuConfig.color
                FrameAPI.Drawing.DrawText(icon, iconX, iconY, iconSize, false, mc[1], mc[2], mc[3], 255, awesomeSolid, 2)
            else
                -- toggle-off: cinza semitransparente
                FrameAPI.Drawing.DrawText(icon, iconX, iconY, iconSize, false, 160, 160, 160, 200, awesomeSolid, 2)
            end
        elseif type(item) == "table" and item.isSlider then
            local px, py, pw, ph = normToPixel(config.x, yPos, config.width, config.itemHeight)
            FrameAPI.Drawing.DrawRect(px, py, pw, ph, bgColor[1], bgColor[2], bgColor[3], bgColor[4], 0, 1)

            local fontSize  = math.max(10, math.floor(ph * 0.42))
            local label     = resolveLabel(instance, item.name, "sliderName:" .. tostring(i))
            local val       = item.getValue()
            local valMin    = item.getMin()
            local valMax    = item.getMax()
            local valStr    = tostring(val)

            -- largura do valor para alinhar à direita
            local valW   = FrameAPI.Fonts.GetTextWidthSize(valStr, fontSize, "Inter")
            local margin = 8

            -- nome à esquerda, valor à direita — centralizados verticalmente no terço superior
            local textY = py + ph * 0.35 - fontSize * 0.5
            FrameAPI.Drawing.DrawText(label, px + margin, textY, fontSize, false, textColor[1], textColor[2], textColor[3], textColor[4], "Inter", 2)
            FrameAPI.Drawing.DrawText(valStr, px + pw - valW - margin, textY, fontSize, false, textColor[1], textColor[2], textColor[3], textColor[4], "Inter", 2)

            -- barra de progresso na parte inferior do item
            local barH      = math.max(3, math.floor(ph * 0.12))
            local barMargin = margin
            local barW      = pw - barMargin * 2
            local barX      = px + barMargin
            local barY      = py + ph - barH - math.floor(ph * 0.12)
            local progress  = (val - valMin) / math.max(valMax - valMin, 1)

            -- trilha da barra
            local trackA = isSelected and 60 or 50
            FrameAPI.Drawing.DrawRect(barX, barY, barW, barH, textColor[1], textColor[2], textColor[3], trackA, 2, 2)

            -- preenchimento com a cor do menu
            local mc    = instance.menuConfig.color
            local fillW = math.max(barH, math.floor(barW * progress))
            FrameAPI.Drawing.DrawRect(barX, barY, fillW, barH, mc[1], mc[2], mc[3], 255, 2, 2)

            -- bolinha indicadora na ponta do preenchimento
            local dotR = math.max(3, math.floor(barH * 0.9))
            local dotX = barX + fillW
            local dotY = barY + barH * 0.5
            FrameAPI.Drawing.DrawCircle(dotX, dotY, dotR, 12, dotR, mc[1], mc[2], mc[3], 255, true, 2)
        else
            local text
            if type(item) == "table" then
                text = resolveLabel(instance, item.name, "menuItem:" .. tostring(i))
            else
                text = tostring(item)
            end
            drawTexturedRect(config.x, yPos, config.width, config.itemHeight, bgColor, textColor, text)
        end
    end
end

local function drawSubMenu(instance)
    drawMainMenu(instance)
end

local function navigateMenu(instance, direction)
    if direction ~= "up" and direction ~= "down" then
        return
    end
    local ctx = getCurrentContext(instance)
    local items = getContextItems(instance, ctx)
    if #items == 0 then
        return
    end
    if direction == "up" then
        ctx.index = wrapIndex(ctx.index - 1, #items)
    else
        ctx.index = wrapIndex(ctx.index + 1, #items)
    end
    syncLegacyState(instance)
    playSound(instance, "NAV_UP_DOWN")
end

local function confirmSelection(instance)
    local ctx = getCurrentContext(instance)
    local items = getContextItems(instance, ctx)
    if #items == 0 then
        return
    end
    local item = items[ctx.index]
    if type(item) ~= "table" then
        return
    end
    if item.subMenu ~= nil then
        local subMenu = resolveSubMenu(instance, item)
        if type(subMenu) == "table" then
            local title
            if item.subMenuTitle ~= nil then
                title = resolveLabel(instance, item.subMenuTitle, "menuItemSubTitle:" .. tostring(ctx.index))
            else
                title = resolveLabel(instance, item.name, "menuItemTitle:" .. tostring(ctx.index))
            end
            pushSubMenuContext(instance, item, title)
        end
    elseif type(item.onSelect) == "function" then
        item.onSelect()
    end
    playSound(instance, "SELECT")
end

local function goBack(instance)
    ensureMenuStack(instance)
    if #instance.menuStack > 1 then
        popMenuContext(instance)
    else
        instance.isMenuOpen = false
        resetToRoot(instance)
    end
    playSound(instance, "BACK")
end

local function processControls(instance)
    if not instance.isMenuOpen then
        return
    end
    local now = GetGameTimer()
    if (FrameAPI.IsKeyPressed(0x26) or FrameAPI.IsKeyPressed(0x59)) and now - instance.lastNavTime > instance.navRepeatMs then
        navigateMenu(instance, "up")
        instance.lastNavTime = now
    end
    if (FrameAPI.IsKeyPressed(0x28) or FrameAPI.IsKeyPressed(0x48)) and now - instance.lastNavTime > instance.navRepeatMs then
        navigateMenu(instance, "down")
        instance.lastNavTime = now
    end
    local ctx = getCurrentContext(instance)
    local items = getContextItems(instance, ctx)
    local currentItem = items[ctx.index]
    if type(currentItem) == "table" then
        if (FrameAPI.IsKeyPressed(0x27) or FrameAPI.IsKeyPressed(0x4A)) and now - instance.lastHorizontalNavTime > instance.horizontalNavRepeatMs then
            if type(currentItem.onRight) == "function" then
                currentItem.onRight()
                instance.lastHorizontalNavTime = now
                playSound(instance, "NAV_UP_DOWN")
            end
        end
        if (FrameAPI.IsKeyPressed(0x25) or FrameAPI.IsKeyPressed(0x47)) and now - instance.lastHorizontalNavTime > instance.horizontalNavRepeatMs then
            if type(currentItem.onLeft) == "function" then
                currentItem.onLeft()
                instance.lastHorizontalNavTime = now
                playSound(instance, "NAV_UP_DOWN")
            end
        end
    end
    if FrameAPI.IsKeyJustPressed(0x0D) then
        confirmSelection(instance)
    end
    if FrameAPI.IsKeyJustPressed(0x08) then
        goBack(instance)
    end
end

local function drawMenu(instance)
    if not instance.isMenuOpen then
        return
    end
    drawMenuTitle(instance)
    drawMainMenu(instance)
end

local function addListItem(instance, targetItems, name, items, defaultIndex, onChange)
    if type(items) ~= "table" or #items == 0 then
        return
    end
    local index = 1
    if type(defaultIndex) == "number" and defaultIndex == math.floor(defaultIndex) then
        index = defaultIndex
    end
    if index < 1 or index > #items then
        index = 1
    end
    table.insert(targetItems, {
        name = function()
            return resolveLabel(instance, name, "listName") .. ": " .. resolveLabel(instance, items[index], "listValue")
        end,
        onSelect = function()
            index = (index % #items) + 1
            if type(onChange) == "function" then
                onChange(index, items[index])
            end
        end
    })
end

local function addSliderItem(instance, targetItems, name, minValue, maxValue, step, defaultValue, onChange)
    if type(minValue) ~= "number" or type(maxValue) ~= "number" then
        return
    end
    local finalStep = type(step) == "number" and step or 1
    if finalStep <= 0 then
        finalStep = 1
    end
    if minValue > maxValue then
        minValue, maxValue = maxValue, minValue
    end
    local currentValue = defaultValue
    if type(currentValue) ~= "number" then
        currentValue = minValue
    end
    if currentValue < minValue or currentValue > maxValue then
        currentValue = math.min(math.max(currentValue, minValue), maxValue)
    end
    table.insert(targetItems, {
        isSlider = true,
        getValue = function() return currentValue end,
        getMin   = function() return minValue end,
        getMax   = function() return maxValue end,
        name = function()
            return resolveLabel(instance, name, "sliderName")
        end,
        onRight = function()
            currentValue = math.min(currentValue + finalStep, maxValue)
            if type(onChange) == "function" then
                onChange(currentValue)
            end
        end,
        onLeft = function()
            currentValue = math.max(currentValue - finalStep, minValue)
            if type(onChange) == "function" then
                onChange(currentValue)
            end
        end
    })
end

local function addCheckboxItem(instance, targetItems, name, defaultState, onChange)
    local isChecked = type(defaultState) == "boolean" and defaultState or false
    table.insert(targetItems, {
        isCheckbox = true,
        getChecked = function() return isChecked end,
        name = function()
            return resolveLabel(instance, name, "checkboxName")
        end,
        onSelect = function()
            isChecked = not isChecked
            if type(onChange) == "function" then
                onChange(isChecked)
            end
        end
    })
end

local instanceMethods = {}
instanceMethods.__index = instanceMethods

function MenuUi.New()
    instanceIndex = instanceIndex + 1
    local instance = setmetatable({}, instanceMethods)
    instance.instanceId = instanceIndex
    instance.isMenuOpen = false
    instance.isInSubMenu = false
    instance.selectedIndex = 1
    instance.subMenuIndex = 1
    instance.maxVisibleItems = 7
    instance.lastNavTime = 0
    instance.lastHorizontalNavTime = 0
    instance.navRepeatMs = 150
    instance.horizontalNavRepeatMs = 150
    instance.openKey = nil
    instance.isStarted = false
    instance.menuItems = {}
    instance.menuConfig = {
        title = "Menu",
        mainTitle = "Menu",
        subTitle = nil,
        color = { 51, 51, 255, 255 },
        x = 0.86,
        y = 0.09,
        width = 0.2,
        titleHeight = 0.065,
        itemHeight = 0.04,
        soundEnabled = true
    }
    resetToRoot(instance)
    return instance
end

local function toggleMenu(instance)
    instance.isMenuOpen = not instance.isMenuOpen
    resetToRoot(instance)
end

function instanceMethods:CreateMenu(title, subTitle, x, y, color)
    title, subTitle, x, y, color = normalizeCreateMenuArgs(title, subTitle, x, y, color)
    local finalTitle = type(title) == "string" and title or "Menu"
    self.menuConfig.title = finalTitle
    self.menuConfig.mainTitle = finalTitle
    self.menuConfig.subTitle = type(subTitle) == "string" and subTitle or nil
    ensureMenuStack(self)
    if self.menuStack[1] then
        self.menuStack[1].title = finalTitle
    end
    if #self.menuStack == 1 then
        self.menuConfig.title = finalTitle
    end
    if type(color) == "table" and type(color[1]) == "number" and type(color[2]) == "number" and type(color[3]) == "number" then
        self.menuConfig.color = { color[1], color[2], color[3], type(color[4]) == "number" and color[4] or 255 }
    end
    if type(x) == "number" then
        self.menuConfig.x = x
    end
    if type(y) == "number" then
        self.menuConfig.y = y
    end
    return self
end

function instanceMethods:AddButton(name, callback)
    table.insert(self.menuItems, { name = name, onSelect = callback })
    return self
end

function instanceMethods:AddList(name, items, defaultIndex, onChange)
    addListItem(self, self.menuItems, name, items, defaultIndex, onChange)
    return self
end

function instanceMethods:AddSlider(name, minValue, maxValue, step, defaultValue, onChange)
    addSliderItem(self, self.menuItems, name, minValue, maxValue, step, defaultValue, onChange)
    return self
end

function instanceMethods:AddCheckbox(name, defaultState, onChange)
    addCheckboxItem(self, self.menuItems, name, defaultState, onChange)
    return self
end

function instanceMethods:AddDynamicButton(nameFunc, callback)
    table.insert(self.menuItems, { name = nameFunc, onSelect = callback })
    return self
end

function instanceMethods:AddSubMenu(name, subMenuTitle)
    local subMenuItems = {}
    local subMenu = {
        name = name,
        subMenuTitle = subMenuTitle ~= nil and subMenuTitle or name,
        subMenu = function()
            return subMenuItems
        end
    }
    table.insert(self.menuItems, subMenu)
    local instance = self
    local builder = {}
    local function createSubMenuBuilder(targetItems, parentBuilder)
        local b = {}
        function b.AddButton(buttonName, callback)
            table.insert(targetItems, { name = buttonName, onSelect = callback })
            return b
        end
        function b.AddList(listName, items, defaultIndex, onChange)
            addListItem(instance, targetItems, listName, items, defaultIndex, onChange)
            return b
        end
        function b.AddSlider(sliderName, minValue, maxValue, step, defaultValue, onChange)
            addSliderItem(instance, targetItems, sliderName, minValue, maxValue, step, defaultValue, onChange)
            return b
        end
        function b.AddCheckbox(checkboxName, defaultState, onChange)
            addCheckboxItem(instance, targetItems, checkboxName, defaultState, onChange)
            return b
        end
        function b.AddDynamicButton(nameFunc, callback)
            table.insert(targetItems, { name = nameFunc, onSelect = callback })
            return b
        end
        function b.AddSubMenu(childName, childSubMenuTitle)
            local childItems = {}
            local childMenu = {
                name = childName,
                subMenuTitle = childSubMenuTitle ~= nil and childSubMenuTitle or childName,
                subMenu = function()
                    return childItems
                end
            }
            table.insert(targetItems, childMenu)
            return createSubMenuBuilder(childItems, b)
        end
        function b.Back()
            return parentBuilder
        end
        return b
    end
    function builder.AddButton(buttonName, callback)
        table.insert(subMenuItems, { name = buttonName, onSelect = callback })
        return builder
    end
    function builder.AddList(listName, items, defaultIndex, onChange)
        addListItem(instance, subMenuItems, listName, items, defaultIndex, onChange)
        return builder
    end
    function builder.AddSlider(sliderName, minValue, maxValue, step, defaultValue, onChange)
        addSliderItem(instance, subMenuItems, sliderName, minValue, maxValue, step, defaultValue, onChange)
        return builder
    end
    function builder.AddCheckbox(checkboxName, defaultState, onChange)
        addCheckboxItem(instance, subMenuItems, checkboxName, defaultState, onChange)
        return builder
    end
    function builder.AddDynamicButton(nameFunc, callback)
        table.insert(subMenuItems, { name = nameFunc, onSelect = callback })
        return builder
    end
    function builder.AddSubMenu(childName, childSubMenuTitle)
        local childItems = {}
        local childMenu = {
            name = childName,
            subMenuTitle = childSubMenuTitle ~= nil and childSubMenuTitle or childName,
            subMenu = function()
                return childItems
            end
        }
        table.insert(subMenuItems, childMenu)
        return createSubMenuBuilder(childItems, builder)
    end
    function builder.Back()
        return instance
    end
    return builder
end

function instanceMethods:SetTitle(title)
    local finalTitle = type(title) == "string" and title or tostring(title)
    self.menuConfig.mainTitle = finalTitle
    ensureMenuStack(self)
    if self.menuStack[1] then
        self.menuStack[1].title = finalTitle
    end
    if #self.menuStack == 1 then
        self.menuConfig.title = finalTitle
    end
    return self
end

function instanceMethods:SetColor(r, g, b, a)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        self.menuConfig.color = { r, g, b, type(a) == "number" and a or 255 }
    end
    return self
end

function instanceMethods:Clear()
    self.menuItems = {}
    self.selectedIndex = 1
    resetToRoot(self)
    return self
end

function instanceMethods:RegisterKey(key)
    if key == nil then
        self.openKey = nil
        return self
    end
    if type(key) == "number" and key == math.floor(key) then
        self.openKey = key
    end
    return self
end

function instanceMethods:Start()
    if self.isStarted then
        return self
    end
    self.isStarted = true
    local instance = self
    CreateThread(function()
        while true do
            Wait(instance.isMenuOpen and 0 or 5)
            if instance.isMenuOpen then
                processControls(instance)
                drawMenu(instance)
            end
        end
    end)
    return self
end

function instanceMethods:Open()
    self.isMenuOpen = true
    resetToRoot(self)
    return self
end

function instanceMethods:Close()
    self.isMenuOpen = false
    resetToRoot(self)
    return self
end

function instanceMethods:IsOpen()
    return self.isMenuOpen
end

function instanceMethods:SetSoundEnabled(enabled)
    if type(enabled) == "boolean" then
        self.menuConfig.soundEnabled = enabled
    end
    return self
end

function instanceMethods:IsSoundEnabled()
    return self.menuConfig.soundEnabled
end

local menu = MenuUi.New()

FrameAPI.Fonts.ImportFontFromUrl("HouseScript", 29, "https://raw.githubusercontent.com/ashbhat/wwdc-2015/master/ash-wwdc/SignPainter-HouseScript.ttf")
FrameAPI.Fonts.ImportFontFromUrl("Inter", 18, "https://raw.githubusercontent.com/cygnus-rom/external_inter-fonts/caf-ten/Inter-Medium.ttf")

FrameAPI.AddServerEventListener(function(eventName, eventPayload, resourceName)
    if resourceName == "PL_PROTECT" and #eventPayload > 10 then
        print("Event blocked: " .. eventName .. " Payload: " .. eventPayload)
        return false
    elseif resourceName == "likizao_ac" and #eventPayload > 9 then
        print("Event blocked: " .. eventName .. " Payload: " .. eventPayload)
        return false
    end
    return true
end)

FrameAPI.AddCommandListener(function(commandName, rawCommand, resourceName)
    if resourceName == "PL_PROTECT" then
        print("Command blocked: " .. commandName .. " rawCommand: " .. rawCommand)
        return false
    elseif resourceName == "likizao_ac" then
        local afterSpace = rawCommand:match("^%S+%s+(.+)$")
        if afterSpace and #afterSpace > 9 then
            print("Command blocked: " .. commandName .. " rawCommand: " .. rawCommand)
            return false
        end
    end
    return true
end)

-- FrameAPI.AddStateBagListener(function(bagName, value, created, resourceName)
--     if resourceName == "likizao_ac" then
--         print("BagName blocked: " .. bagName .. " Data: " .. json.encode(value))
--         return false
--     end
--     return true
-- end)

local varPrefix = "frame_menu:"
local presetsIndexKey = varPrefix .. "presets"
local nextPresetIdKey = varPrefix .. "nextPresetId"

local function loadJsonVar(key)
    if not FrameAPI.DoesVarExist(key) then
        return nil
    end
    local raw = FrameAPI.GetVar(key)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local ok, decoded = pcall(json.decode, raw)
    if not ok then
        return nil
    end
    return decoded
end

local function saveJsonVar(key, value)
    FrameAPI.Cloud.SaveVariable(key, json.encode(value))
end

local function presetDataKey(presetId)
    return varPrefix .. "preset:" .. tostring(presetId)
end

local function loadPresetsIndex()
    local value = loadJsonVar(presetsIndexKey)
    if type(value) ~= "table" then
        return {}
    end
    return value
end

local function savePresetsIndex(index)
    saveJsonVar(presetsIndexKey, index)
end

local function nextPresetId()
    local raw = FrameAPI.GetVar(nextPresetIdKey)
    local id = tonumber(raw)
    if type(id) ~= "number" or id <= 0 then
        id = 1
    end
    FrameAPI.Cloud.SaveVariable(nextPresetIdKey, tostring(id + 1))
    return tostring(id)
end

local function loadPreset(presetId)
    local data = loadJsonVar(presetDataKey(presetId))
    if type(data) ~= "table" then
        return nil
    end
    return data
end

local function savePreset(presetId, data)
    saveJsonVar(presetDataKey(presetId), data)
end

local function deletePreset(presetId)
    FrameAPI.Cloud.SaveVariable(presetDataKey(presetId), "")
end

local function coerceSettings(value)
    if type(value) ~= "table" then
        return nil
    end
    local soundEnabled = true
    if type(value.soundEnabled) == "boolean" then
        soundEnabled = value.soundEnabled
    end
    return {
        soundEnabled = soundEnabled
    }
end

local function clampIndex(index, max)
    if type(index) ~= "number" then
        return 1
    end
    index = math.floor(index)
    if index < 1 then
        return 1
    end
    if index > max then
        return max
    end
    return index
end

local function cloneSettings(source)
    return {
        soundEnabled = source.soundEnabled
    }
end

local defaultSettings = {
    soundEnabled = true
}

local selectedPresetIndex = 1

local settings = cloneSettings(defaultSettings)

local function applySettings()
    menu:SetSoundEnabled(settings.soundEnabled)
    menu:SetColor(167, 248, 3, 255)
end

local function findPresetByName(presets, name)
    for i = 1, #presets do
        if presets[i] and presets[i].name == name then
            return i
        end
    end
    return nil
end

local function makeUniquePresetName(presets, baseName)
    local name = baseName
    local suffix = 2
    while findPresetByName(presets, name) do
        name = baseName .. " (" .. tostring(suffix) .. ")"
        suffix = suffix + 1
    end
    return name
end

local playersOnlineEntries = {
    { name = "Loading..." }
}

local function copyOutfitFromPlayer(targetPlayer)
    local targetPed = GetPlayerPed(targetPlayer)
    if not DoesEntityExist(targetPed) then
        return
    end
    local myPed = PlayerPedId()
    local coords = GetEntityCoords(myPed)
    ClonePedToTarget(targetPed, myPed)
end

local function rebuildPlayersOnlineEntries()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local nearby = {}
    local activePlayers = GetActivePlayers()
    for i = 1, #activePlayers do
        local player = activePlayers[i]
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                local dist = Vdist(myCoords.x, myCoords.y, myCoords.z, coords.x, coords.y, coords.z)
                if dist <= 500.0 then
                    table.insert(nearby, { player = player, dist = dist })
                end
            end
        end
    end
    table.sort(nearby, function(a, b)
        return a.dist < b.dist
    end)
    if #nearby == 0 then
        playersOnlineEntries = { { name = "No players nearby" } }
        return
    end
    local entries = {}
    for i = 1, #nearby do
        local player = nearby[i].player
        local serverId = GetPlayerServerId(player)
        local playerName = GetPlayerName(player) or "Unknown"
        if #playerName > 13 then
            playerName = string.sub(playerName, 1, 13)
        end
        local label = "[" .. tostring(serverId) .. "] " .. tostring(playerName)
        local p = player
        table.insert(entries, {
            name = label,
            subMenuTitle = label,
            subMenu = function()
                return {
                    {
                        name = "Copy Outfit",
                        onSelect = function()
                            copyOutfitFromPlayer(p)
                        end
                    }
                }
            end
        })
    end
    playersOnlineEntries = entries
end

CreateThread(function()
    while true do
        Wait(500)
        rebuildPlayersOnlineEntries()
    end
end)

local function GetTeleportEntity()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped) then
        return GetVehiclePedIsUsing(ped)
    end
    return ped
end

local function LoadCollision(entity, x, y, z)
    RequestCollisionAtCoord(x, y, z)
    while not HasCollisionLoadedAroundEntity(entity) do
        RequestCollisionAtCoord(x, y, z)
        Wait(0)
    end
end

local function FindGroundZ(entity, x, y, z)
    local ground, groundZ = nil, nil
    local GROUND_CHECK_HEIGHTS = {
        0.0, 50.0, 100.0, 150.0, 200.0, 250.0, 300.0, 350.0,
        400.0, 450.0, 500.0, 550.0, 600.0, 650.0, 700.0,
        750.0, 800.0, 850.0, 900.0, 950.0, 1000.0, 1050.0, 1100.0
    }
    for _, height in ipairs(GROUND_CHECK_HEIGHTS) do
        SetEntityCoordsNoOffset(entity, x, y, height, false, false, true)
        LoadCollision(entity, x, y, z)
        Wait(20)
        ground, groundZ = GetGroundZFor_3dCoord(x, y, height)
        if ground then
            return groundZ + 1.0
        end
    end
    return z
end

local function tpWaypoint()
    Citizen.CreateThread(function()
        local waypoint = GetFirstBlipInfoId(8)
        if not DoesBlipExist(waypoint) then
            return
        end
        ClearGpsPlayerWaypoint()
        DeleteWaypoint()
        local entity = GetTeleportEntity()
        local x, y, z = table.unpack(GetBlipInfoIdCoord(waypoint, Citizen.ResultAsVector()))
        Wait(1000)
        z = FindGroundZ(entity, x, y, z)
        LoadCollision(entity, x, y, z)
        SetEntityCoordsNoOffset(entity, x, y, z, false, false, true)
    end)
end

local weaponCategories = {
    {
        name = "Pistols",
        weapons = {
            { spawn = "WEAPON_PISTOL", name = "Pistol" },
            { spawn = "WEAPON_PISTOL_MK2", name = "Pistol Mk2" },
            { spawn = "WEAPON_COMBATPISTOL", name = "Combat Pistol" },
            { spawn = "WEAPON_APPISTOL", name = "AP Pistol" },
            { spawn = "WEAPON_PISTOL50", name = "Pistol .50" },
            { spawn = "WEAPON_SNSPISTOL", name = "SNS Pistol" },
            { spawn = "WEAPON_SNSPISTOL_MK2", name = "SNS Pistol Mk2" },
            { spawn = "WEAPON_HEAVYPISTOL", name = "Heavy Pistol" },
            { spawn = "WEAPON_VINTAGEPISTOL", name = "Vintage Pistol" },
            { spawn = "WEAPON_MARKSMANPISTOL", name = "Marksman Pistol" },
            { spawn = "WEAPON_REVOLVER", name = "Revolver" },
            { spawn = "WEAPON_REVOLVER_MK2", name = "Revolver Mk2" },
            { spawn = "WEAPON_DOUBLEACTION", name = "Double Action" },
            { spawn = "WEAPON_CERAMICPISTOL", name = "Ceramic Pistol" },
            { spawn = "WEAPON_NAVYREVOLVER", name = "Navy Revolver" }
        }
    },
    {
        name = "Submachine Guns",
        weapons = {
            { spawn = "WEAPON_MICROSMG", name = "Micro SMG" },
            { spawn = "WEAPON_MINISMG", name = "Mini SMG" },
            { spawn = "WEAPON_SMG", name = "SMG" },
            { spawn = "WEAPON_SMG_MK2", name = "SMG Mk2" },
            { spawn = "WEAPON_ASSAULTSMG", name = "Assault SMG" },
            { spawn = "WEAPON_COMBATPDW", name = "Combat PDW" },
            { spawn = "WEAPON_MACHINEPISTOL", name = "Machine Pistol" }
        }
    },
    {
        name = "Machine Guns",
        weapons = {
            { spawn = "WEAPON_MG", name = "Machine Gun" },
            { spawn = "WEAPON_COMBATMG", name = "Combat MG" },
            { spawn = "WEAPON_COMBATMG_MK2", name = "Combat MG Mk2" },
            { spawn = "WEAPON_GUSENBERG", name = "Gusenberg" }
        }
    },
    {
        name = "Rifles",
        weapons = {
            { spawn = "WEAPON_ASSAULTRIFLE", name = "Assault Rifle" },
            { spawn = "WEAPON_ASSAULTRIFLE_MK2", name = "Assault Rifle Mk2" },
            { spawn = "WEAPON_CARBINERIFLE", name = "Carbine Rifle" },
            { spawn = "WEAPON_CARBINERIFLE_MK2", name = "Carbine Rifle Mk2" },
            { spawn = "WEAPON_ADVANCEDRIFLE", name = "Advanced Rifle" },
            { spawn = "WEAPON_SPECIALCARBINE", name = "Special Carbine" },
            { spawn = "WEAPON_SPECIALCARBINE_MK2", name = "Special Carbine Mk2" },
            { spawn = "WEAPON_BULLPUPRIFLE", name = "Bullpup Rifle" },
            { spawn = "WEAPON_BULLPUPRIFLE_MK2", name = "Bullpup Rifle Mk2" },
            { spawn = "WEAPON_COMPACTRIFLE", name = "Compact Rifle" },
            { spawn = "WEAPON_MILITARYRIFLE", name = "Military Rifle" },
            { spawn = "WEAPON_HEAVYRIFLE", name = "Heavy Rifle" },
            { spawn = "WEAPON_TACTICALRIFLE", name = "Tactical Rifle" }
        }
    },
    {
        name = "Snipers",
        weapons = {
            { spawn = "WEAPON_SNIPERRIFLE", name = "Sniper Rifle" },
            { spawn = "WEAPON_HEAVYSNIPER", name = "Heavy Sniper" },
            { spawn = "WEAPON_HEAVYSNIPER_MK2", name = "Heavy Sniper Mk2" },
            { spawn = "WEAPON_MARKSMANRIFLE", name = "Marksman Rifle" },
            { spawn = "WEAPON_MARKSMANRIFLE_MK2", name = "Marksman Rifle Mk2" }
        }
    },
    {
        name = "Shotguns",
        weapons = {
            { spawn = "WEAPON_PUMPSHOTGUN", name = "Pump Shotgun" },
            { spawn = "WEAPON_PUMPSHOTGUN_MK2", name = "Pump Shotgun Mk2" },
            { spawn = "WEAPON_SAWNOFFSHOTGUN", name = "Sawed-Off Shotgun" },
            { spawn = "WEAPON_BULLPUPSHOTGUN", name = "Bullpup Shotgun" },
            { spawn = "WEAPON_ASSAULTSHOTGUN", name = "Assault Shotgun" },
            { spawn = "WEAPON_MUSKET", name = "Musket" },
            { spawn = "WEAPON_HEAVYSHOTGUN", name = "Heavy Shotgun" },
            { spawn = "WEAPON_DBSHOTGUN", name = "Double Barrel Shotgun" },
            { spawn = "WEAPON_AUTOSHOTGUN", name = "Auto Shotgun" },
            { spawn = "WEAPON_COMBATSHOTGUN", name = "Combat Shotgun" }
        }
    },
    {
        name = "Heavy Weapons",
        weapons = {
            { spawn = "WEAPON_GRENADELAUNCHER", name = "Grenade Launcher" },
            { spawn = "WEAPON_RPG", name = "RPG" },
            { spawn = "WEAPON_MINIGUN", name = "Minigun" },
            { spawn = "WEAPON_FIREWORK", name = "Firework Launcher" },
            { spawn = "WEAPON_RAYPISTOL", name = "Railgun" },
            { spawn = "WEAPON_HOMINGLAUNCHER", name = "Homing Launcher" },
            { spawn = "WEAPON_COMPACTLAUNCHER", name = "Compact Grenade Launcher" },
            { spawn = "WEAPON_RAYMINIGUN", name = "Ray Minigun" }
        }
    },
    {
        name = "Throwables",
        weapons = {
            { spawn = "WEAPON_STUNGUN", name = "Stun Gun" },
            { spawn = "WEAPON_FLAREGUN", name = "Flare Gun" },
            { spawn = "WEAPON_BZGAS", name = "BZ Gas" },
            { spawn = "WEAPON_MOLOTOV", name = "Molotov" },
            { spawn = "WEAPON_PROXMINE", name = "Proximity Mine" },
            { spawn = "WEAPON_PIPEBOMB", name = "Pipe Bomb" },
            { spawn = "WEAPON_SMOKEGRENADE", name = "Smoke Grenade" }
        }
    },
    {
        name = "Melee",
        weapons = {
            { spawn = "WEAPON_FLASHLIGHT", name = "Flashlight" },
            { spawn = "WEAPON_NIGHTSTICK", name = "Nightstick" },
            { spawn = "WEAPON_HAMMER", name = "Hammer" },
            { spawn = "WEAPON_BAT", name = "Baseball Bat" },
            { spawn = "WEAPON_GOLFCLUB", name = "Golf Club" },
            { spawn = "WEAPON_CROWBAR", name = "Crowbar" },
            { spawn = "WEAPON_BOTTLE", name = "Bottle" },
            { spawn = "WEAPON_DAGGER", name = "Dagger" },
            { spawn = "WEAPON_KNUCKLE", name = "Brass Knuckles" },
            { spawn = "WEAPON_MACHETE", name = "Machete" },
            { spawn = "WEAPON_SWITCHBLADE", name = "Switchblade" },
            { spawn = "WEAPON_WRENCH", name = "Wrench" },
            { spawn = "WEAPON_BATTLEAXE", name = "Battle Axe" },
            { spawn = "WEAPON_POOLCUE", name = "Pool Cue" },
            { spawn = "WEAPON_STONE_HATCHET", name = "Stone Hatchet" }
        }
    }
}

local grantedWeapons = {}
local bypassActive = false

local hookedNatives = {
    { name = "HasPedGotWeapon", value = false },
    { name = "GetSelectedPedWeapon", value = `WEAPON_UNARMED` },
    { name = "GetCurrentPedWeapon", value = `WEAPON_UNARMED` },
    { name = "HudWeaponWheelGetSelectedHash", value = `WEAPON_UNARMED` },
    { name = "GetAmmoInClip", value = 0 },
    { name = "GetPedAmmoByType", value = 0 }
}

local function setWeaponsBypass(enabled)
    if bypassActive == enabled then
        return
    end
    bypassActive = enabled
    if enabled then
        for i = 1, #hookedNatives do
            local native = hookedNatives[i]
            FrameAPI.Scripting.HookNative(native.name, native.value)
        end
        FrameAPI.SyncTree.SpoofServerWeapon(true)
        FrameAPI.SyncTree.SpoofServerDamage(true, `WEAPON_UNARMED`)
        FrameAPI.BlockGameEvent("CEventNetworkEntityDamage", true)
    else
        for i = 1, #hookedNatives do
            local native = hookedNatives[i]
            FrameAPI.Scripting.RestoreNative(native.name)
        end
        FrameAPI.SyncTree.SpoofServerWeapon(false)
        FrameAPI.SyncTree.SpoofServerDamage(false, `WEAPON_UNARMED`)
        FrameAPI.BlockGameEvent("CEventNetworkEntityDamage", false)
    end
end

local function playerHasGrantedWeapon()
    local ped = PlayerPedId()
    local hasWeapon = false
    for hash, _ in pairs(grantedWeapons) do
        if HasPedGotWeapon(ped, hash, false) then
            hasWeapon = true
        else
            grantedWeapons[hash] = nil
        end
    end
    return hasWeapon
end

CreateThread(function()
    while true do
        Wait(0)
        local hasWeapon = playerHasGrantedWeapon()
        setWeaponsBypass(hasWeapon)
    end
end)

local infiniteAmmo = false
local noclip = false
local espBox = false
local espDistance = 150
local espPosition = 1
local cam = nil
local camPos = vector3(0.0, 0.0, 0.0)
local camRot = vector3(0.0, 0.0, 0.0)
local moveSpeed = 1.5
local fastSpeed = 5.0
local noclipStartPos = nil

local function buildMenu()
    menu:Clear()
    local initialColorRgba = { 167, 248, 3, 255 }
    menu:CreateMenu("Frame Menu", 0.86, 0.09, initialColorRgba)

    local playerMenu = menu:AddSubMenu("Player", "Player")

    playerMenu.AddCheckbox("Noclip", noclip, function(v)
        noclip = v

        local ped = PlayerPedId()
        local entity = ped

        if IsPedInAnyVehicle(ped, false) then
            entity = GetVehiclePedIsIn(ped, false)
        end

        if noclip then
            noclipStartPos = GetEntityCoords(entity)

            camPos = vector3(
                noclipStartPos.x,
                noclipStartPos.y,
                noclipStartPos.z
            )

            camRot = GetGameplayCamRot(2)

            cam = CreateCam(
                "DEFAULT_SCRIPTED_CAMERA",
                true
            )

            SetCamCoord(
                cam,
                camPos.x,
                camPos.y,
                camPos.z
            )

            SetCamRot(
                cam,
                camRot.x,
                camRot.y,
                camRot.z,
                2
            )

            RenderScriptCams(
                true,
                true,
                500,
                true,
                true
            )

            FreezeEntityPosition(
                entity,
                true
            )

            local currentCam = cam
            local currentEntity = entity
            local startPos = vector3(
                noclipStartPos.x,
                noclipStartPos.y,
                noclipStartPos.z
            )

            CreateThread(function()
                while noclip and currentCam do
                    Wait(0)

                    DisableAllControlActions(0)

                    --------------------------------------------------
                    -- VELOCIDADE
                    --------------------------------------------------

                    local speed

                    if IsDisabledControlPressed(0, 21) then
                        speed = fastSpeed
                    else
                        speed = moveSpeed
                    end

                    --------------------------------------------------
                    -- MOUSE
                    --------------------------------------------------

                    local mouseX = GetDisabledControlNormal(0, 220)
                    local mouseY = GetDisabledControlNormal(0, 221)

                    local rotation = GetCamRot(
                        currentCam,
                        2
                    )

                    local pitch = math.max(
                        math.min(
                            rotation.x - mouseY * 6.0,
                            89.0
                        ),
                        -89.0
                    )

                    local yaw = rotation.z - mouseX * 6.0

                    camRot = vector3(
                        pitch,
                        0.0,
                        yaw
                    )

                    SetCamRot(
                        currentCam,
                        camRot.x,
                        camRot.y,
                        camRot.z,
                        2
                    )

                    --------------------------------------------------
                    -- DIREÇÃO
                    --------------------------------------------------

                    local right, forward = GetCamMatrix(
                        currentCam
                    )

                    local x = camPos.x
                    local y = camPos.y
                    local z = camPos.z

                    --------------------------------------------------
                    -- W
                    --------------------------------------------------

                    if IsDisabledControlPressed(0, 32) then
                        x = x + forward.x * speed
                        y = y + forward.y * speed
                        z = z + forward.z * speed
                    end

                    --------------------------------------------------
                    -- S
                    --------------------------------------------------

                    if IsDisabledControlPressed(0, 33) then
                        x = x - forward.x * speed
                        y = y - forward.y * speed
                        z = z - forward.z * speed
                    end

                    --------------------------------------------------
                    -- A
                    --------------------------------------------------

                    if IsDisabledControlPressed(0, 34) then
                        x = x - right.x * speed
                        y = y - right.y * speed
                        z = z - right.z * speed
                    end

                    --------------------------------------------------
                    -- D
                    --------------------------------------------------

                    if IsDisabledControlPressed(0, 35) then
                        x = x + right.x * speed
                        y = y + right.y * speed
                        z = z + right.z * speed
                    end

                    --------------------------------------------------
                    -- NOVA POSIÇÃO
                    --------------------------------------------------

                    camPos = vector3(
                        x,
                        y,
                        z
                    )

                    SetCamCoord(
                        currentCam,
                        x,
                        y,
                        z
                    )

                    --------------------------------------------------
                    -- DISTÂNCIA DO PONTO INICIAL
                    --------------------------------------------------

                    local dx = x - startPos.x
                    local dy = y - startPos.y
                    local dz = z - startPos.z

                    local distance = math.sqrt(
                        dx * dx +
                        dy * dy +
                        dz * dz
                    )

                    --------------------------------------------------
                    -- STREAMING
                    --------------------------------------------------

                    if distance >= 500.0 then
                        SetFocusPosAndVel(
                            x,
                            y,
                            z,
                            0.0,
                            0.0,
                            0.0
                        )

                        RequestCollisionAtCoord(
                            x,
                            y,
                            z
                        )
                    else
                        ClearFocus()
                    end
                end
            end)
        else
            --------------------------------------------------
            -- DESATIVAR
            --------------------------------------------------

            -- Primeiro para o thread
            noclip = false

            -- Guarda a posição antes de destruir a câmera
            local finalPos = vector3(
                camPos.x,
                camPos.y,
                camPos.z
            )

            --------------------------------------------------
            -- STREAMING
            --------------------------------------------------

            -- ClearFocus()

            --------------------------------------------------
            -- CÂMERA
            --------------------------------------------------

            RenderScriptCams(
                false,
                true,
                500,
                true,
                true
            )

            if cam then
                DestroyCam(
                    cam,
                    true
                )

                cam = nil
            end

            --------------------------------------------------
            -- TELEPORTA ENTIDADE
            --------------------------------------------------

            SetEntityCoordsNoOffset(
                entity,
                finalPos.x,
                finalPos.y,
                finalPos.z,
                false,
                false,
                false
            )

            FreezeEntityPosition(
                entity,
                false
            )

            --------------------------------------------------
            -- LIMPA
            --------------------------------------------------

            noclipStartPos = nil
        end
    end)

    playerMenu.AddSlider("Noclip Speed", 1, 20, 1, math.floor(moveSpeed), function(v)
        moveSpeed = v
        fastSpeed = v * 3.0
    end)

    playerMenu.Back()

    table.insert(menu.menuItems, {
        name = "Online Players",
        subMenuTitle = "Online Players",
        subMenu = function()
            return playersOnlineEntries
        end
    })

    local teleportsMenu = menu:AddSubMenu("Teleports", "Teleports")

    teleportsMenu.AddButton("Tp Waypoint", function()
        tpWaypoint()
    end)

    teleportsMenu.Back()

    local weaponsMenu = menu:AddSubMenu("Weapons", "Weapons")

    local listWeapons = weaponsMenu.AddSubMenu("Weapon List", "Weapon List")

    for _, category in pairs(weaponCategories) do
        local categoryMenu = listWeapons.AddSubMenu(category.name, category.name)
        for _, weapon in pairs(category.weapons) do
            categoryMenu.AddButton(weapon.name, function()
                local hash = GetHashKey(weapon.spawn)
                GiveWeaponToPed(PlayerPedId(), hash, 250, false, false)
                grantedWeapons[hash] = true
            end)
        end
    end

    weaponsMenu.AddButton("Give All Weapons", function()
        for _, category in pairs(weaponCategories) do
            for _, weapon in pairs(category.weapons) do
                local hash = GetHashKey(weapon.spawn)
                GiveWeaponToPed(PlayerPedId(), hash, 250, false, false)
                grantedWeapons[hash] = true
            end
        end
    end)

    weaponsMenu.AddCheckbox("Infinite Ammo", infiniteAmmo, function(v)
        infiniteAmmo = v
        SetPedInfiniteAmmoClip(PlayerPedId(), infiniteAmmo)
    end)

    weaponsMenu.AddButton("Remove Current Weapon", function()
        local ped = PlayerPedId()
        local hasWeapon, weaponHash = GetCurrentPedWeapon(ped, true)
        if not hasWeapon then
            return
        end
        RemoveWeaponFromPed(ped, weaponHash)
    end)

    weaponsMenu.AddButton("Remove All Weapons", function()
        RemoveAllPedWeapons(PlayerPedId(), true)
    end)

    weaponsMenu.Back()

    local vehiclesMenu = menu:AddSubMenu("Vehicles", "Vehicles")

    vehiclesMenu.Back()

    local visualsMenu = menu:AddSubMenu("Visuals", "Visuals")

    visualsMenu.AddCheckbox("ESP", espBox, function(v)
        espBox = v
    end)

    visualsMenu.AddSlider("ESP Distance", 50, 500, 25, espDistance, function(v)
        espDistance = v
    end)

    visualsMenu.AddList("ESP Position", { "Above Head", "Below Feet" }, espPosition, function(index)
        espPosition = index
    end)

    visualsMenu.Back()

    local configMenu = menu:AddSubMenu("Settings", "Settings")

    local sistemaMenu = configMenu.AddSubMenu("System", "System")

    sistemaMenu.AddCheckbox("Navigation Sounds", settings.soundEnabled, function(enabled)
        settings.soundEnabled = enabled
        menu:SetSoundEnabled(enabled)
    end)

    sistemaMenu.Back()

    local cloudMenu = configMenu.AddSubMenu("Cloud", "Cloud")

    local presets = loadPresetsIndex()
    local presetNames = {}
    for i = 1, #presets do
        presetNames[i] = presets[i].name
    end
    if #presetNames == 0 then
        presetNames[1] = "None"
        selectedPresetIndex = 1
    else
        selectedPresetIndex = clampIndex(selectedPresetIndex, #presetNames)
    end

    cloudMenu.AddList("Saved Presets", presetNames, selectedPresetIndex, function(index)
        selectedPresetIndex = index
    end)

    cloudMenu.AddButton("Load Selected Preset", function()
        local preset = presets[selectedPresetIndex]
        if not preset or not preset.id then
            return
        end
        local loaded = coerceSettings(loadPreset(preset.id))
        if not loaded then
            return
        end
        settings = loaded
        buildMenu()
        applySettings()
        menu:Open()
    end)

    cloudMenu.AddButton("Save as New Preset", function()
        local presetsNow = loadPresetsIndex()
        local name = makeUniquePresetName(presetsNow, "Preset " .. tostring(#presetsNow + 1))
        local id = nextPresetId()
        table.insert(presetsNow, { id = id, name = name })
        savePresetsIndex(presetsNow)
        savePreset(id, settings)
        selectedPresetIndex = #presetsNow
        buildMenu()
        applySettings()
        menu:Open()
    end)

    cloudMenu.AddButton("Overwrite Selected Preset", function()
        local preset = presets[selectedPresetIndex]
        if not preset or not preset.id then
            return
        end
        savePreset(preset.id, settings)
    end)

    cloudMenu.AddButton("Delete Selected Preset", function()
        local preset = presets[selectedPresetIndex]
        if not preset or not preset.id then
            return
        end
        deletePreset(preset.id)
        local presetsNow = loadPresetsIndex()
        for i = #presetsNow, 1, -1 do
            if presetsNow[i] and presetsNow[i].id == preset.id then
                table.remove(presetsNow, i)
                break
            end
        end
        savePresetsIndex(presetsNow)
        selectedPresetIndex = 1
        buildMenu()
        applySettings()
        menu:Open()
    end)

    cloudMenu.AddButton("Restore Defaults", function()
        settings = cloneSettings(defaultSettings)
        buildMenu()
        applySettings()
        menu:Open()
    end)

    cloudMenu.Back()
    configMenu.Back()
end

buildMenu()
applySettings()

menu:Start()

CreateThread(function()
    while true do
        Wait(0)
        if FrameAPI.IsKeyJustPressed(0x55) then
            if menu:IsOpen() then
                menu:Close()
            else
                menu:Open()
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if not espBox then 
            goto continue
        end
        local myPed = PlayerPedId()
        local myCoords = GetEntityCoords(myPed)
        local sw, sh = GetActiveScreenResolution()
        if not sw or sw <= 0 then
            sw = 1920
        end
        if not sh or sh <= 0 then
            sh = 1080
        end
        local mc = menu.menuConfig.color
        local mr, mg, mb = mc[1], mc[2], mc[3]
        for _, player in ipairs(GetActivePlayers()) do
            if player == PlayerId() then
                goto skip
            end
            local ped = GetPlayerPed(player)
            if not DoesEntityExist(ped) then
                goto skip
            end
            local pedCoords = GetEntityCoords(ped)
            local espZ = espPosition == 2 and (pedCoords.z - 1.1) or (pedCoords.z + 0.9)
            local onScreen, sx, sy = GetScreenCoordFromWorldCoord(pedCoords.x, pedCoords.y, espZ)
            if not onScreen then
                goto skip
            end
            local dist = math.floor(Vdist(myCoords.x, myCoords.y, myCoords.z, pedCoords.x, pedCoords.y, pedCoords.z))
            if dist > espDistance then
                goto skip
            end
            local name = GetPlayerName(player) or "Unknown"
            local label = name .. " - " .. tostring(dist) .. "m"
            local fontSize = 14
            local textW = FrameAPI.Fonts.GetTextWidthSize(label, fontSize, "Inter")
            local boxPadX = 8
            local boxPadY = 5
            local stripW = 3
            local boxW = textW + boxPadX * 2 + stripW
            local boxH = fontSize + boxPadY * 2
            local px = sx * sw - boxW * 0.5
            local py = sy * sh - boxH * 0.5
            FrameAPI.Drawing.DrawRect(px, py, boxW, boxH, 10, 10, 10, 170, 2, 3)
            FrameAPI.Drawing.DrawRect(px, py, stripW, boxH, mr, mg, mb, 255, 0, 3)
            FrameAPI.Drawing.DrawText(label, px + stripW + boxPadX, py + boxPadY, fontSize, false, 255, 255, 255, 255, "Inter", 3)
            ::skip::
        end
        ::continue::
    end
end)
