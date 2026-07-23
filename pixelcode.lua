-- Bro-PixelScript (Word Bomb Ultra) - интеграция jitter + автотипинга
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
-- Удалять слово из глобального списка при использовании (если true)
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

-- Jitter settings (взято из присланного скрипта)
local jitterEnabled = true
local jitterIntensity = 0.16 -- в секундах (0.16 ~ 160ms max offset)
local typingWPM = 250
local checkWordDelay = 0.2
local minLen = 1
local maxLen = 99
local typoChance = 0
-- удалил humaniseWPM переменную — теперь используется jitterEnabled

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

-- Загрузка словаря
local function loadDictionaryAsync(url)
    task.spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then
            pcall(function() statusLabel:Set("Dictionary: error loading (" .. tostring(raw) .. ")") end)
            return
        end

        local total = 0
        for word in raw:gmatch("[^\r\n]+") do
            local w = word:gsub("%s+", ""):lower()
            if w ~= "" then
                total = total + 1
                table.insert(globalWordsList, w)
                if total % 5000 == 0 then task.wait() end
            end
        end

        pcall(function() statusLabel:Set("Dictionary: " .. #globalWordsList .. " words (Ready)") end)
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/wbdict/main/word-bomb-list.txt")

-- === UI ВКЛАДКИ ===
MainTab:CreateToggle({ 
    Name = "Auto Type & Search", 
    CurrentValue = false, 
    Callback = function(Value) autotype = Value end 
})

MainTab:CreateToggle({ 
    Name = "Instant Type (No Delay)", 
    CurrentValue = false, 
    Callback = function(Value) instanttype = Value end 
})

MainTab:CreateToggle({
    Name = "Auto Join Game",
    CurrentValue = false,
    Callback = function(Value) autojoin = Value end
})

MainTab:CreateButton({ 
    Name = "Search Word (Manual)", 
    Callback = function() copyword(true) end 
})

SettingsTab:CreateSlider({
   Name = "Typing WPM",
   Range = {50, 1000},
   Increment = 25,
   Suffix = " WPM",
   CurrentValue = 250,
   Callback = function(Value) typingWPM = Value end,
})

SettingsTab:CreateToggle({
   Name = "Jitter Typing",
   CurrentValue = true,
   Callback = function(Value) jitterEnabled = Value end,
})

SettingsTab:CreateSlider({
   Name = "Jitter Delay",
   Info = "Jittering strength (ms)",
   Range = {1, 50}, 
   Increment = 1,
   Suffix = " ms", 
   CurrentValue = 16, 
   Callback = function(Value) jitterIntensity = Value / 100 end,
})

SettingsTab:CreateSlider({
   Name = "Typo Chance (Опечатки)",
   Info = "Шанс сделать случайную ошибку и исправить её",
   Range = {0, 20},
   Increment = 1,
   Suffix = "%",
   CurrentValue = 0,
   Callback = function(Value) typoChance = Value / 100 end,
})

SettingsTab:CreateSlider({
   Name = "Min Word Length",
   Range = {1, 15},
   Increment = 1,
   Suffix = " letters",
   CurrentValue = 1,
   Callback = function(Value) minLen = Value end,
})

SettingsTab:CreateSlider({
   Name = "Max Word Length",
   Range = {3, 30},
   Increment = 1,
   Suffix = " letters",
   CurrentValue = 30,
   Callback = function(Value) maxLen = Value end,
})

SettingsTab:CreateSlider({
   Name = "Check Word Delay",
   Range = {1, 20}, 
   Increment = 1,
   Suffix = " (x0.1 sec)",
   CurrentValue = 2, 
   Callback = function(Value) checkWordDelay = Value / 10 end,
})

local elapsedLabel = StatsTab:CreateLabel("Elapsed Time: 00:00:00")
local turnsLabel = StatsTab:CreateLabel("Total Turns: 0")
local promptLabel = StatsTab:CreateLabel("Current Prompt: None")
local solutionsLabel = StatsTab:CreateLabel("Solutions Found: 0")
local matchLabel = StatsTab:CreateLabel("Current Match: None")

-- === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===
local function GetLetterDelay()
    -- базовая задержка равна одному символу при typingWPM
    local base = 60 / (typingWPM * 5)
    if jitterEnabled then
        local offset = (math.random() * 2 - 1) * jitterIntensity
        base = base + offset
    else
        -- небольшая вариация, чтобы избежать робота-равномерности
        base = base * (0.95 + math.random() * 0.1)
    end

    -- burst behavior retained (soft)
    burstCounter = burstCounter + 1
    if burstCounter >= burstTarget then
        burstCounter = 0
        burstTarget = math.random(3, 7)
        base = base + (0.02 + math.random() * 0.06)
    end

    return math.max(base, 0.005)
end

-- Удалить слово из глобального списка (если включено)
local function removeFromGlobalWords(word)
    if not getgenv().deletewhendupefound then return end
    for i = 1, #globalWordsList do
        if globalWordsList[i] == word then
            table.remove(globalWordsList, i)
            return
        end
    end
end

-- ===== ЗАМЕНА: улучшённый getGameStatus с валидацией видимости prompt в UI =====
local cachedInfoUpvalues = nil

local function promptVisibleInGUI(prompt)
    if not prompt or prompt == "" then return false end
    local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return false end

    local needle = tostring(prompt):gsub("%s+", ""):lower()
    for _, v in pairs(playerGui:GetDescendants()) do
        if v:IsA("TextLabel") and v.Visible and v.Text and v.Text ~= "" then
            local txt = v.Text:gsub("%s+", ""):lower()
            if txt:find(needle, 1, true) then
                return true
            end
        end
    end
    return false
end

local function findUpdateInfoUpvaluesOnce()
    if cachedInfoUpvalues then return cachedInfoUpvalues end
    pcall(function()
        for _, v in pairs(getgc()) do
            if type(v) == "function" then
                local ok, info = pcall(debug.getinfo, v)
                if ok and info and info.name == "updateInfoFrame" then
                    local ok2, up = pcall(debug.getupvalues, v)
                    if ok2 and type(up) == "table" then
                        cachedInfoUpvalues = up
                        return
                    end
                end
            end
        end
    end)
    return cachedInfoUpvalues
end

local function isWaitingLikeText(t)
    if not t or t == "" then return false end
    local s = tostring(t):lower()
    -- ключевые слова для окончания раунда / ожидания (англ + рус)
    local bad = {"waiting", "wait", "press", "game over", "round over", "end", "finished", "finish", "подождите", "ожидайте", "конец", "конецраунда", "игра закончена", "дождитесь", "заверш"}
    for _, kw in ipairs(bad) do
        if s:find(kw, 1, true) then return true end
    end
    return false
end

local function getGameStatus()
    local prompt = nil
    local isMyTurn = false

    -- 1) Попытка через кэш upvalues (быстро)
    local upvalues = findUpdateInfoUpvaluesOnce()
    if upvalues then
        pcall(function()
            for _, vv in pairs(upvalues) do
                if type(vv) == "table" then
                    if vv.Prompt ~= nil and tostring(vv.Prompt) ~= "" then
                        prompt = tostring(vv.Prompt):gsub("%s+", ""):lower()
                    end
                    if vv.PlayerID ~= nil and vv.PlayerID == Players.LocalPlayer.UserId then
                        isMyTurn = true
                    end
                end
            end
        end)
    end

    -- 2) Фолбэк через PlayerGui, если не найден или пуст
    if (not prompt or prompt == "") then
        pcall(function()
            local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                local promptLbl = playerGui:FindFirstChild("PromptLabel", true)
                if promptLbl and promptLbl.Text ~= "" then
                    prompt = promptLbl.Text:gsub("%s+", ""):lower()
                else
                    -- более общий поиск через текстовые метки (если конкретный PromptLabel отсутствует)
                    for _, v in pairs(playerGui:GetDescendants()) do
                        if v:IsA("TextLabel") and v.Visible and v.Text and #v.Text > 0 then
                            local txt = v.Text:gsub("%s+", ""):lower()
                            -- heurистика: короткий текст 2..6 символов скорее всего промпт
                            if #txt >= 2 and #txt <= 6 and not txt:find("turn") and not txt:find("ход") then
                                prompt = txt
                                break
                            end
                        end
                    end
                end
            end
        end)
    end

    -- 3) Проверка: действительно ли найденный prompt видим в GUI; если нет — считаем его отсутствующим
    if prompt and prompt ~= "" then
        if not promptVisibleInGUI(prompt) then
            -- если текст похож на "waiting"/"press"/"game over" и не видим — тоже считаем отсутствующим
            if isWaitingLikeText(prompt) then
                prompt = nil
            else
                -- часто upvalues могут хранить устаревший prompt; если он не виден в GUI — сбрасываем
                prompt = nil
            end
        end
    end

    -- 4) Проверка флага хода через UI как дополнительный источник (fallback)
    if not isMyTurn then
        pcall(function()
            local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                for _, v in pairs(playerGui:GetDescendants()) do
                    if v:IsA("TextLabel") and v.Visible and v.Text then
                        local txt = v.Text:lower()
                        if txt:find("quick") or txt:find("your turn") or txt:find("ходи") or txt:find("быстро") then
                            isMyTurn = true
                            break
                        end
                    end
                end
            end
        end)
    end

    return prompt, isMyTurn
end

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

-- === НАДЁЖНАЯ ЭМИТАЦИЯ КЛАВИШ ===
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

-- === ПЕЧАТЬ (интегрированный jitter + автотипинг) ===
local function typeWordMobile(word, targetPrompt)
    if isTyping then return end
    isTyping = true

    pcall(function()
        if not instanttype and checkWordDelay > 0 then task.wait(checkWordDelay) end

        local currentPrompt, isMyTurn = getGameStatus()
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
            local checkPrompt, checkTurn = getGameStatus()
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

-- === ОСНОВНОЙ ПОИСК (использует стратегию special/normal matches из присланного скрипта) ===
function copyword(bruteforce)
    if isTyping then return end
    local contains, isMyTurn = getGameStatus()

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
        promptLabel:Set("Current Prompt: " .. contains:upper())

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
        solutionsLabel:Set("Solutions Found: " .. (totalSolutions >= 5 and "5+" or tostring(totalSolutions)))

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
            matchLabel:Set("Current Match: " .. finalword:upper())

            if getgenv().deletewhendupefound then
                removeFromGlobalWords(finalword)
            end

            if autotype and isMyTurn then
                task.spawn(function()
                    typeWordMobile(finalword, promptLower)
                end)
                lastChunk = ""
            end
        else
            matchLabel:Set("Current Match: Not Found")
        end
    end
end

-- === ФОНОВЫЙ ЦИКЛ ПОИСКА И ПЕЧАТИ ===
task.spawn(function()
    while task.wait(0.15) do
        if autotype or autojoin then
            pcall(function()
                copyword(false)
            end)
        end
    end
end)

-- === АВТО-ПРИСОЕДИНЕНИЕ (AUTO JOIN) ===
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

-- === ANTI-DUPE (background collection) ===
task.spawn(function()
    while task.wait(0.8) do
        -- здесь можно отметить видимые заголовки как использованные
        local localPlayer = Players.LocalPlayer
        local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
        local gameGui = playerGui and (playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("DesktopUI") or playerGui:FindFirstChild("MobileUI"))
        
        if gameGui then
            for _, v in pairs(gameGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and #v.Text >= 2 then
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
end)

-- === ТАЙМЕР ===
task.spawn(function()
    while task.wait(1) do
        local elapsed = os.time() - startTime
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor((elapsed % 3600) / 60)
        local seconds = elapsed % 60
        pcall(function() elapsedLabel:Set(string.format("Elapsed Time: %02d:%02d:%02d", hours, minutes, seconds)) end)
    end
end)
