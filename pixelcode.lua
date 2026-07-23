-- Bro-PixelScript (Word Bomb Ultra) - optimized prompt search integrated
local RbxAnalytics = game:GetService("RbxAnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Vim = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- === 1. HWID / КЛЮЧЕВАЯ АВТОРИЗАЦИЯ ===
local userHWID = RbxAnalytics:GetClientId()
local KEYS_URL = "https://raw.githubusercontent.com/bro-pixel11/keys.json/main/auth.json"

local userProvidedKey = getgenv().PixelKey or _G.PixelKey or PixelKey

if not userProvidedKey or userProvidedKey == "" then
    Players.LocalPlayer:Kick("Ошибка: Ключ не найден! Укажите getgenv().PixelKey = 'ВАШ_КЛЮЧ' перед loadstring.")
    return
end

local function authenticate()
    local success, response = pcall(function()
        return game:HttpGet(KEYS_URL)
    end)

    if not success or not response then
        return false, "Ошибка подключения к серверу авторизации!"
    end

    local ok, keysData = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if not ok or type(keysData) ~= "table" then
        return false, "Ошибка чтения базы ключей!"
    end

    local registeredHWID = keysData[userProvidedKey]

    if not registeredHWID then
        return false, "Неверный ключ доступа!"
    end

    if type(registeredHWID) == "table" then
        for _, allowedHWID in ipairs(registeredHWID) do
            if allowedHWID == userHWID then
                return true, "Успешно!"
            end
        end
        return false, "Ваш HWID не найден в списке разрешённых!\nВаш HWID: " .. tostring(userHWID)
    end

    if registeredHWID == userHWID then
        return true, "Успешно!"
    end

    if registeredHWID == "UNASSIGNED" then
        return false, "Ключ не активирован. Ваш HWID:\n" .. tostring(userHWID)
    end

    return false, "Ключ привязан к другому HWID!\nВаш текущий HWID: " .. tostring(userHWID)
end

local isAuthenticated, authMessage = authenticate()

if not isAuthenticated then
    Players.LocalPlayer:Kick("[Bro-Pixel Auth]: " .. authMessage)
    error("[AUTH FAILED]: " .. authMessage)
    return
end

print("Авторизация прошла успешно! Загрузка Bro-PixelScript...")

-- === 2. НАСТРОЙКИ И ПЕРЕМЕННЫЕ ===
getgenv().deletewhendupefound = true

local globalWordsList = {
    "pseudopseudohypoparathyroidism", "floccinaucinihilipilification",
    "antidisestablishmentarianism", "supercalifragilisticexpialidocious",
    "hexakosioihexekontahexaphobia", "dichlorodiphenyltrichloroethane",
    "electroencephalographically", "xenotransplantations",
    "counterdemonstrations", "characteristically", "unconstitutionality"
}

local TypoNeighbours = {
    a="s", b="v", c="v", d="f", e="w", f="d", g="h", h="j",
    i="o", j="h", k="l", l="k", m="n", n="m", o="i", p="o",
    q="w", r="t", s="a", t="r", u="y", v="c", w="e", x="z",
    y="u", z="x"
}

local sessionUsedWords = {}
local autotype = false
local instanttype = false
local autojoin = false
local autoJoinDelay = 3

-- Jitter / typing
local jitterEnabled = true
local jitterIntensity = 0.16
local typingWPM = 250
local checkWordDelay = 0.2
local minLen = 1
local maxLen = 99
local typoChance = 0

local burstCounter = 0
local burstTarget = math.random(3, 7)

local lastChunk = ""
local wasMyTurn = false
local isTyping = false

local startTime = os.time()
local totalTurns = 0

local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- === 3. RAYFIELD UI ===
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "Bro-PixelScript (Word Bomb Ultra)",
   LoadingTitle = "Bro-Pixel Loader",
   LoadingSubtitle = "by Bro-Pixel",
   Theme = "CustomTheme",
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   ConfigurationSaving = { Enabled = false },
   KeySystem = false,
   Size = UDim2.fromOffset(360, 300),
   CustomTheme = {
        TextColor = Color3.fromRGB(255, 255, 255),
        Background = Color3.fromRGB(25, 10, 40),
        MainColor = Color3.fromRGB(90, 30, 180),
        AccentColor = Color3.fromRGB(0, 240, 200),
        OutlineColor = Color3.fromRGB(140, 50, 255),
        PlaceholderColor = Color3.fromRGB(180, 150, 220)
   }
})

local MainTab = Window:CreateTab("Main", nil)
local SettingsTab = Window:CreateTab("Settings", nil)
local StatsTab = Window:CreateTab("Stats", nil)

local statusLabel = MainTab:CreateLabel("Loading dictionary...")

-- Загрузка словаря (безопасно, с yields)
local function loadDictionaryAsync(url)
    task.spawn(function()
        local ok, raw = pcall(game.HttpGet, game, url)
        if not ok or not raw then
            pcall(function() statusLabel:Set("Dictionary: error loading") end)
            return
        end
        local total = 0
        for w in raw:gmatch("[^\r\n]+") do
            local s = w:gsub("%s+", ""):lower()
            if s ~= "" then
                total = total + 1
                table.insert(globalWordsList, s)
                if (total % 5000) == 0 then task.wait() end
            end
        end
        pcall(function() statusLabel:Set("Dictionary: " .. #globalWordsList .. " words (Ready)") end)
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/wbdict/main/word-bomb-list.txt")

-- === UI Элементы ===
MainTab:CreateToggle({ Name = "Auto Type & Search", CurrentValue = false, Callback = function(v) autotype = v end })
MainTab:CreateToggle({ Name = "Instant Type (No Delay)", CurrentValue = false, Callback = function(v) instanttype = v end })
MainTab:CreateToggle({ Name = "Auto Join Game", CurrentValue = false, Callback = function(v) autojoin = v end })
MainTab:CreateButton({ Name = "Search Word (Manual)", Callback = function() copyword(true) end })

SettingsTab:CreateSlider({
   Name = "Typing WPM", Range = {50, 1000}, Increment = 25, Suffix = " WPM", CurrentValue = 250,
   Callback = function(Value) typingWPM = Value end,
})
SettingsTab:CreateToggle({ Name = "Jitter Typing", CurrentValue = true, Callback = function(v) jitterEnabled = v end })
SettingsTab:CreateSlider({
   Name = "Jitter Delay", Range = {1,50}, Increment = 1, Suffix = " ms", CurrentValue = 16,
   Callback = function(Value) jitterIntensity = Value / 100 end,
})
SettingsTab:CreateSlider({
   Name = "Typo Chance (Опечатки)", Range = {0,20}, Increment = 1, Suffix = "%", CurrentValue = 0,
   Callback = function(Value) typoChance = Value / 100 end,
})
SettingsTab:CreateSlider({ Name = "Min Word Length", Range = {1,15}, Increment = 1, CurrentValue = 1, Callback = function(v) minLen = v end })
SettingsTab:CreateSlider({ Name = "Max Word Length", Range = {3,30}, Increment = 1, CurrentValue = 30, Callback = function(v) maxLen = v end })
SettingsTab:CreateSlider({ Name = "Check Word Delay", Range = {1,20}, Increment = 1, CurrentValue = 2, Callback = function(v) checkWordDelay = v/10 end })

local elapsedLabel = StatsTab:CreateLabel("Elapsed Time: 00:00:00")
local turnsLabel = StatsTab:CreateLabel("Total Turns: 0")
local promptLabel = StatsTab:CreateLabel("Current Prompt: None")
local solutionsLabel = StatsTab:CreateLabel("Solutions Found: 0")
local matchLabel = StatsTab:CreateLabel("Current Match: None")

-- === HELPERS (typing/jitter/etc) ===
local function GetLetterDelay()
    local base = 60 / (typingWPM * 5)
    if jitterEnabled then
        local offset = (math.random() * 2 - 1) * jitterIntensity
        base = base + offset
    else
        base = base * (0.95 + math.random() * 0.1)
    end

    burstCounter = burstCounter + 1
    if burstCounter >= burstTarget then
        burstCounter = 0
        burstTarget = math.random(3, 7)
        base = base + (0.02 + math.random() * 0.06)
    end
    return math.max(base, 0.005)
end

local function removeFromGlobalWords(word)
    if not getgenv().deletewhendupefound then return end
    for i = 1, #globalWordsList do
        if globalWordsList[i] == word then
            table.remove(globalWordsList, i)
            return
        end
    end
end

-- === ОПТИМИЗИРОВАННАЯ ЛОГИКА ПОИСКА ПРОМПТА (GUI-FIRST, минимальные сканы) ===
-- Конфигурация
local PROMPT_MIN_LEN = 2                -- разрешаем 2-символьные промпты
local PROMPT_STABLE_THRESHOLD = 2       -- сколько одинаковых тиков, чтобы подтвердить промпт
local PROMPT_MISSING_THRESHOLD = 2      -- сколько пропаданий, чтобы считать промпт ушедшим
local GUI_CONTAINER_NAMES = { "GameUI", "DesktopUI", "MobileUI", "MainUI" } -- ограничиваем поиск
local PROMPT_LABEL_NAMES = { "PromptLabel", "Prompt", "InfoFrame" } -- имена, где чаще всего промпт
local GC_FALLBACK_INTERVAL = 5          -- seconds between expensive getgc scans (rare)

-- внутренние состояния для debounce и оптимизации
local lastSeenPrompt = nil
local promptStableCount = 0
local missingPromptCount = 0
local lastGCTime = 0

-- локализованные быстрые ссылки (для производительности)
local Players_local = Players
local tostring_local = tostring
local string_gsub = string.gsub
local string_lower = string.lower
local string_find = string.find

-- проверяем, что GUI-элемент находится под игровым контейнером (быстрая проверка)
local function isUnderAllowedContainer(obj)
    if not obj or not obj.Parent then return false end
    -- поднимаемся вверх не более 6 уровней, чтобы избежать долгих циклов
    local cur = obj
    for i = 1, 6 do
        if not cur then break end
        local name = tostring(cur.Name)
        name = string_lower(name)
        for _, allowed in ipairs(GUI_CONTAINER_NAMES) do
            if name == string_lower(allowed) then
                return true
            end
        end
        cur = cur.Parent
    end
    return false
end

-- Быстрый GUI-first поиск промпта; выходит при первом найденном релевантном значении
local function findPromptInPlayerGui(playerGui)
    if not playerGui then return nil end

    -- 1) Сначала попытка FindFirstChild для известных меток (рекурсивно) — очень быстро
    for _, containerName in ipairs(GUI_CONTAINER_NAMES) do
        local container = playerGui:FindFirstChild(containerName)
        if container then
            for _, plName in ipairs(PROMPT_LABEL_NAMES) do
                local lbl = container:FindFirstChild(plName, true)
                if lbl and lbl:IsA("TextLabel") and lbl.Visible and lbl.Text and #lbl.Text > 0 and isUnderAllowedContainer(lbl) then
                    local txt = string_gsub(tostring_local(lbl.Text), "%s+", "")
                    txt = string_lower(txt)
                    if #txt >= PROMPT_MIN_LEN then
                        return txt
                    end
                end
            end
        end
    end

    -- 2) Если контейнеры существуют, делаем короткий рекурсивный проход но с ранним выходом.
    --    Ищем только в найденных контейнерах, если они есть.
    for _, containerName in ipairs(GUI_CONTAINER_NAMES) do
        local container = playerGui:FindFirstChild(containerName)
        if container then
            -- проход по GetDescendants ограниченный: быстро проверяем и выходим при первом совпадении
            local desc = container:GetDescendants()
            for i = 1, #desc do
                local v = desc[i]
                if v and v:IsA and v:IsA("TextLabel") and v.Visible and v.Text and #v.Text >= PROMPT_MIN_LEN then
                    local txt = string_gsub(tostring_local(v.Text), "%s+", "")
                    txt = string_lower(txt)
                    -- фильтруем метки хода/служебные слова
                    if not (string_find(txt, "turn") or string_find(txt, "ход") or string_find(txt, "быстро")) then
                        return txt
                    end
                end
            end
        end
    end

    return nil
end

-- Редкий, дорогой fallback через getgc — используется только не чаще чем GC_FALLBACK_INTERVAL секунд
local function getPromptFromGC()
    local now = os.clock()
    if now - lastGCTime < GC_FALLBACK_INTERVAL then return nil end
    lastGCTime = now

    -- безопасно pcall весь блок
    local ok, res = pcall(function()
        for _, v in pairs(getgc(true)) do
            if type(v) == "function" then
                local info = debug.getinfo(v)
                if info and info.name == "updateInfoFrame" then
                    local ups = debug.getupvalues(v)
                    if type(ups) == "table" then
                        for _, up in pairs(ups) do
                            if type(up) == "table" and up.Prompt and tostring_local(up.Prompt) ~= "" then
                                local cand = string_lower(string_gsub(tostring_local(up.Prompt), "%s+", ""))
                                if #cand >= PROMPT_MIN_LEN then
                                    return cand
                                end
                            end
                        end
                    end
                end
            end
        end
        return nil
    end)
    if ok then return res end
    return nil
end

-- Основная оптимизированная функция, возвращает prompt (или nil) и isMyTurn (bool)
local function getGameStatusOptimized()
    -- быстрое локальное получение playerGui
    local player = Players_local.LocalPlayer
    if not player then return nil, false end
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil, false end

    -- GUI-first поиск (быстро и доминирует)
    local found = findPromptInPlayerGui(playerGui)

    -- Если нет GUI-результата, можно (редко) попробовать GC fallback — но только если нужно
    if (not found or found == "") then
        -- не используем GC часто; это дорогая операция
        found = getPromptFromGC()
        -- но подтверждать через GUI строго: если GC нашёл, но GUI не подтверждает, игнорируем GC
        if found then
            -- quick check: is any visible TextLabel contains this cand? (cheap)
            local needle = found
            local seen = false
            for _, containerName in ipairs(GUI_CONTAINER_NAMES) do
                local container = playerGui:FindFirstChild(containerName)
                if container then
                    local desc = container:GetDescendants()
                    for i = 1, #desc do
                        local v = desc[i]
                        if v and v:IsA and v:IsA("TextLabel") and v.Visible and v.Text then
                            local txt = string_lower(string_gsub(tostring_local(v.Text), "%s+", ""))
                            if txt:find(needle, 1, true) then
                                seen = true
                                break
                            end
                        end
                    end
                    if seen then break end
                end
            end
            if not seen then
                -- ignore GC result to avoid stale prompts
                found = nil
            end
        end
    end

    -- Определение isMyTurn — минимальный короткий поиск по UI
    local isMyTurn = false
    -- ищем ключевые слова "quick", "your turn", "быстро", "ходи" в ограниченных контейнерах
    for _, containerName in ipairs(GUI_CONTAINER_NAMES) do
        local container = playerGui:FindFirstChild(containerName)
        if container then
            local desc = container:GetDescendants()
            for i = 1, #desc do
                local v = desc[i]
                if v and v:IsA and v:IsA("TextLabel") and v.Visible and v.Text then
                    local txt = string_lower(v.Text)
                    if string_find(txt, "quick") or string_find(txt, "your turn") or string_find(txt, "быстро") or string_find(txt, "ходи") then
                        isMyTurn = true
                        break
                    end
                end
            end
        end
        if isMyTurn then break end
    end

    -- Debounce / stability: обновляем lastSeenPrompt / stable counters
    if found and found ~= "" then
        if lastSeenPrompt == found then
            promptStableCount = promptStableCount + 1
        else
            lastSeenPrompt = found
            promptStableCount = 1
        end
        missingPromptCount = 0
    else
        missingPromptCount = missingPromptCount + 1
        promptStableCount = 0
        if missingPromptCount >= PROMPT_MISSING_THRESHOLD then
            lastSeenPrompt = nil
        end
    end

    if lastSeenPrompt and promptStableCount >= PROMPT_STABLE_THRESHOLD then
        return lastSeenPrompt, isMyTurn
    end

    return nil, isMyTurn
end

-- === Key emulation ===
local keyMap = {
    [" "] = Enum.KeyCode.Space,
    ["-"] = Enum.KeyCode.Minus,
    ["'"] = Enum.KeyCode.Quote,
    ["."] = Enum.KeyCode.Period,
    [","] = Enum.KeyCode.Comma,
    ["/"] = Enum.KeyCode.Slash,
    [";"] = Enum.KeyCode.Semicolon,
    ["0"] = Enum.KeyCode.Zero, ["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two,
    ["3"] = Enum.KeyCode.Three, ["4"] = Enum.KeyCode.Four, ["5"] = Enum.KeyCode.Five,
    ["6"] = Enum.KeyCode.Six, ["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight,
    ["9"] = Enum.KeyCode.Nine
}

local function SimulateKey(char)
    if not char or #char == 0 then return end
    local upper = char:upper()
    local keyCode = keyMap[char] or keyMap[upper]
    if not keyCode then
        if upper:match("^[A-Z]$") then
            keyCode = Enum.KeyCode[upper]
        end
    end
    if keyCode then
        pcall(function()
            Vim:SendKeyEvent(true, keyCode, false, game)
            task.wait(0.002)
            Vim:SendKeyEvent(false, keyCode, false, game)
        end)
    end
end

local function SimulateBackspace()
    pcall(function()
        Vim:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
        task.wait(0.002)
        Vim:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
    end)
end

local function PressEnter()
    pcall(function()
        Vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.01)
        Vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    end)
end

-- === Typing function (uses optimized getGameStatus) ===
local function getGameTextBox()
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return nil end
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end
    for _, v in pairs(playerGui:GetDescendants()) do
        if v:IsA("TextBox") and v.Visible and v.Parent.Name ~= "Rayfield" then return v end
    end
    return nil
end

local function typeWordMobile(word, targetPrompt)
    if isTyping then return end
    isTyping = true

    pcall(function()
        if not instanttype and checkWordDelay > 0 then task.wait(checkWordDelay) end

        local currentPrompt, isMyTurn = getGameStatusOptimized()
        if currentPrompt ~= targetPrompt or not isMyTurn then
            isTyping = false
            return
        end

        local textBox = getGameTextBox()
        if textBox then
            pcall(function() textBox:CaptureFocus() end)
            task.wait(0.01)
            pcall(function() textBox.Text = "" end)
            task.wait(0.01)
        end

        for i = 1, #word do
            local checkPrompt, checkTurn = getGameStatusOptimized()
            if checkPrompt ~= targetPrompt or not checkTurn then break end

            local char = string.sub(word, i, i)

            if not instanttype and typoChance > 0 and math.random() < typoChance then
                local lower = string.lower(char)
                local typoKey = TypoNeighbours[lower] or lower
                SimulateKey(typoKey)
                task.wait(GetLetterDelay())
                SimulateBackspace()
                task.wait(0.02)
                SimulateKey(char)
            else
                SimulateKey(char)
            end

            if not instanttype then
                task.wait(GetLetterDelay())
            end
        end

        task.wait(0.02)
        PressEnter()
        totalTurns = totalTurns + 1
        pcall(function() turnsLabel:Set("Total Turns: " .. totalTurns) end)
    end)

    isTyping = false
end

-- === Main search logic (unchanged strategy) ===
function copyword(bruteforce)
    if isTyping then return end
    local contains, isMyTurn = getGameStatusOptimized()

    if not contains or contains == "" then
        if lastChunk ~= "WAITING" then
            sessionUsedWords = {}
            lastChunk = "WAITING"
            wasMyTurn = false
            pcall(function()
                promptLabel:Set("Current Prompt: WAITING...")
                solutionsLabel:Set("Solutions Found: 0")
                matchLabel:Set("Current Match: Waiting for game...")
            end)
        end
        return
    end

    local turnSwitchedToMe = (isMyTurn and not wasMyTurn)
    wasMyTurn = isMyTurn

    if lastChunk ~= contains or bruteforce or turnSwitchedToMe then
        lastChunk = contains
        pcall(function() promptLabel:Set("Current Prompt: " .. contains:upper()) end)

        local promptLower = contains:lower()
        local specialMatches = {}
        local normalMatches = {}

        for i = 1, #globalWordsList do
            local candidate = globalWordsList[i]
            if #candidate >= minLen and #candidate <= maxLen then
                if string.find(candidate, promptLower, 1, true) then
                    if not sessionUsedWords[candidate] then
                        if candidate:find("-", 1, true) or candidate:find("'", 1, true) then
                            table.insert(specialMatches, candidate)
                        else
                            table.insert(normalMatches, candidate)
                        end
                    end
                end
            end
        end

        local totalSolutions = #specialMatches + #normalMatches
        pcall(function() solutionsLabel:Set("Solutions Found: " .. (totalSolutions >= 5 and "5+" or tostring(totalSolutions))) end)

        local finalword = nil

        if #specialMatches > 0 then
            finalword = specialMatches[math.random(1, #specialMatches)]
        elseif #normalMatches > 0 then
            local shortestNormal = normalMatches[1]
            for i = 2, #normalMatches do
                if #normalMatches[i] < #shortestNormal then
                    shortestNormal = normalMatches[i]
                end
            end
            finalword = shortestNormal
        end

        if finalword then
            sessionUsedWords[finalword] = true
            pcall(function() matchLabel:Set("Current Match: " .. finalword:upper()) end)

            if getgenv().deletewhendupefound then removeFromGlobalWords(finalword) end

            if autotype and isMyTurn then
                task.spawn(function()
                    typeWordMobile(finalword, promptLower)
                end)
                lastChunk = ""
            end
        else
            pcall(function() matchLabel:Set("Current Match: Not Found") end)
        end
    end
end

-- === Background search loop (lightweight) ===
task.spawn(function()
    while task.wait(0.15) do
        if autotype or autojoin then
            pcall(copyword, false)
        end
    end
end)

-- === Auto join handler ===
if Games then
    local registerGame = Games:FindFirstChild("RegisterGame")
    if registerGame then
        registerGame.OnClientEvent:Connect(function(gameRoomID)
            if autojoin then
                task.spawn(function()
                    if autoJoinDelay > 0 then task.wait(autoJoinDelay) end
                    pcall(function() Games.GameEvent:FireServer(gameRoomID, "JoinGame") end)
                    task.wait(1)
                    sessionUsedWords = {}
                    lastChunk = "WAITING"
                    wasMyTurn = false
                end)
            end
        end)
    end
end

-- === Anti-dupe collector (lightweight) ===
task.spawn(function()
    while task.wait(0.8) do
        if not autotype then continue end
        local localPlayer = Players.LocalPlayer
        local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then continue end
        for _, c in ipairs(GUI_CONTAINER_NAMES) do
            local gameGui = playerGui:FindFirstChild(c)
            if gameGui then
                local desc = gameGui:GetDescendants()
                for i = 1, #desc do
                    local v = desc[i]
                    if v and v:IsA and v:IsA("TextLabel") and v.Visible and #v.Text >= 2 then
                        local text = v.Text:gsub("%s+", "")
                        if text == text:upper() and not text:find("%d") and not text:find("TURN") and not text:find("ХОД") then
                            local lowerWord = text:lower()
                            if not sessionUsedWords[lowerWord] then
                                sessionUsedWords[lowerWord] = true
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- === Timer ===
task.spawn(function()
    while task.wait(1) do
        local elapsed = os.time() - startTime
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor((elapsed % 3600) / 60)
        local seconds = elapsed % 60
        pcall(function() elapsedLabel:Set(string.format("Elapsed Time: %02d:%02d:%02d", hours, minutes, seconds)) end)
    end
end)
