-- === ЛОКАЛИЗАЦИЯ ЧАСТО ИСПОЛЬЗУЕМЫХ ФУНКЦИЙ И БИБЛИОТЕК ===
local string_find = string.find
local string_lower = string.lower
local string_sub = string.sub
local string_gsub = string.gsub
local string_upper = string.upper
local math_random = math.random
local math_floor = math.floor
local math_huge = math.huge
local table_clear = table.clear
local task_spawn = task.spawn
local task_wait = task.wait
local os_time = os.time
local os_clock = os.clock
local pcall = pcall
local type = type
local typeof = typeof
local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs
local getgc = getgc
local debug_getinfo = debug.getinfo
local debug_getupvalues = debug.getupvalues

local RbxAnalytics = game:GetService("RbxAnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Vim = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local userHWID = RbxAnalytics:GetClientId()
local KEYS_URL = "https://raw.githubusercontent.com/bro-pixel11/keys.json/main/auth.json"

local userProvidedKey = getgenv().PixelKey or _G.PixelKey or PixelKey

if not userProvidedKey or userProvidedKey == "" then
    Players.LocalPlayer:Kick("❌ Ошибка: Ключ не найден! Укажите getgenv().PixelKey = 'ВАШ_КЛЮЧ' перед loadstring.")
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
    Players.LocalPlayer:Kick("🔒 [Bro-Pixel Auth]: " .. authMessage)
    error("[AUTH FAILED]: " .. authMessage)
    return
end

print("✅ Авторизация прошла успешно! Загрузка Bro-PixelScript...")

-- === ОСНОВНОЙ СКРИПТ ===

getgenv().deletewhendupefound = true

-- Предварительное объявление UI элементов статистики
local elapsedLabel, turnsLabel, promptLabel, solutionsLabel, matchLabel

-- Загрузка Rayfield UI
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Создание окна
local Window = Rayfield:CreateWindow({
    Name = "Bro-PixelScript (wordbomb)",
    LoadingTitle = "Bro-Pixel Loader",
    LoadingSubtitle = "by Bro-Pixel",
    Theme = "CustomTheme", 

    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,

    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
    Size = UDim2.fromOffset(340, 280),
   
    CustomTheme = {
        TextColor = Color3.fromRGB(255, 255, 255),
        Background = Color3.fromRGB(25, 10, 40),        
        MainColor = Color3.fromRGB(90, 30, 180),       
        AccentColor = Color3.fromRGB(0, 240, 200),       
        OutlineColor = Color3.fromRGB(140, 50, 255),    
        PlaceholderColor = Color3.fromRGB(180, 150, 220)
    }
})

-- Создание вкладок
local MainTab = Window:CreateTab("Main", nil)
local SettingsTab = Window:CreateTab("Settings", nil)

local statusLabel = MainTab:CreateLabel("Loading and indexing dictionary...")

-- Основная база слов
local globalWordsList = {} 

-- === АСИНХРОННАЯ ЗАГРУЗКА СЛОВАРЯ ===
local function loadDictionaryAsync(url)
    task.spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then 
            statusLabel:Set("Failed to load dictionary!")
            return 
        end
        
        local total = 0
        for word in raw:gmatch("[^\r\n]+") do
            word = word:gsub("%s+", ""):lower()
            if word ~= "" then
                total = total + 1
                table.insert(globalWordsList, word)
                
                if total % 5000 == 0 then
                    task.wait()
                end
            end
        end
        statusLabel:Set("Dictionary: " .. total .. " words (Ready)")
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/fullwords/main/full_dict.txt")

-- === STATE & SETTINGS ===
local sessionUsedWords = {}
local lettercap = math.huge
local autosearch = false
local autotype = false
local instanttype = false
local autojoin = false
local autoJoinDelay = 2 
local jitterEnabled = false 
local jitterIntensity = 0.05 
local rngVariationPercent = 0 

local lastChunk = "WAITING"
local lastTypeTime = 0
local wasMyTurn = false
local isTyping = false 
local typingSessionId = 0

local checkWordDelay = 1.0 
local startTime = os.time()
local totalTurns = 0

local typingWPM = 500
local speedWordDelay = 60 / (typingWPM * 5)

local function applyRngVariation(baseValue)
    if rngVariationPercent <= 0 then return baseValue end
    local factor = 1 + ((math.random() * 2 - 1) * (rngVariationPercent / 100))
    local result = baseValue * factor
    return result < 0 and 0 or result
end

-- === ИНИЦИАЛИЗАЦИЯ СЕТЕВЫХ СОБЫТИЙ ДЛЯ AUTO JOIN ===
local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- === HELPERS & CORE LOGIC ===

local cachedUpdateFunc = nil

-- Проверка жизнеспособности таблицы upvalues и принадлежащих ей объектов в Дереве игры (game)
local function isUpvalueAlive(upvalueTable)
    if type(upvalueTable) ~= "table" then return false end
    
    local hasInstance = false
    local isAlive = false

    for _, val in pairs(upvalueTable) do
        if typeof(val) == "Instance" then
            hasInstance = true
            if val:IsDescendantOf(game) then
                isAlive = true
                break
            end
        elseif type(val) == "table" then
            for _, subVal in pairs(val) do
                if typeof(subVal) == "Instance" then
                    hasInstance = true
                    if subVal:IsDescendantOf(game) then
                        isAlive = true
                        break
                    end
                end
            end
        end
    end

    if hasInstance then
        return isAlive
    end
    
    return true
end

local function getChunk()
    -- 1. Проверка сохраненного кэша с подтверждением валидности UI
    if cachedUpdateFunc then
        local isValid = false
        local currentPrompt = nil

        local ok = pcall(function()
            local upvalues = debug.getupvalues(cachedUpdateFunc)
            if upvalues then
                for _, up in pairs(upvalues) do
                    if type(up) == "table" and up.Prompt ~= nil then 
                        if isUpvalueAlive(up) then
                            local strPrompt = tostring(up.Prompt):lower():gsub("%s+", "")
                            if strPrompt ~= "" and strPrompt ~= "nil" then
                                currentPrompt = strPrompt
                                isValid = true
                            end
                        end
                        break
                    end
                end
            end
        end)

        if ok and isValid and currentPrompt then 
            return currentPrompt 
        else
            cachedUpdateFunc = nil
        end
    end

    -- 2. Сканирование getgc() с конца массива (поиск самых свежих функций)
    local gcObjects = getgc(true)
    for i = #gcObjects, 1, -1 do
        local v = gcObjects[i]
        if type(v) == "function" then
            local info = debug.getinfo(v)
            if info and info.name == "updateInfoFrame" then
                local upvalues = debug.getupvalues(v)
                if upvalues then
                    for _, up in pairs(upvalues) do
                        if type(up) == "table" and up.Prompt ~= nil then 
                            if isUpvalueAlive(up) then
                                local strPrompt = tostring(up.Prompt):lower():gsub("%s+", "")
                                if strPrompt ~= "" and strPrompt ~= "nil" then
                                    cachedUpdateFunc = v
                                    return strPrompt
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function getGameStatus()
    local prompt = getChunk()
    if not prompt or prompt == "" then return nil, false end
    
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return nil, false end
    
    local isMyTurn = false
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, v in pairs(playerGui:GetDescendants()) do
            if v:IsA("TextLabel") and v.Visible and v.Parent and v.Parent.Name ~= "Rayfield" then
                local text = v.Text:lower()
                if string.find(text, "quick") or string.find(text, "быстро") or string.find(text, "your turn") or string.find(text, "ходи") then
                    isMyTurn = true
                    break
                end
            end
        end
    end
    return prompt, isMyTurn
end

local function getGameTextBox()
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return nil end
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end
    for _, v in pairs(playerGui:GetDescendants()) do
        if v:IsA("TextBox") and v.Visible and v.Parent and v.Parent.Name ~= "Rayfield" then return v end
    end
    return nil
end

-- === TYPING LOGIC (ЗАЩИТА ОТ ГОНОК И ПАРАЛЛЕЛЬНЫХ ПОТОКОВ) ===
local function typeWordMobile(word, targetPrompt)
    if isTyping then return end 
    isTyping = true 
    
    typingSessionId = typingSessionId + 1
    local currentSession = typingSessionId

    if not instanttype and checkWordDelay > 0 then 
        local finalDelay = applyRngVariation(checkWordDelay)
        task.wait(finalDelay) 
    end
    
    if currentSession ~= typingSessionId then
        isTyping = false
        return
    end

    local currentPrompt, isMyTurn = getGameStatus()
    if currentPrompt ~= targetPrompt or not isMyTurn then
        isTyping = false
        return
    end
    
    local textBox = getGameTextBox()
    if textBox then 
        textBox:CaptureFocus() 
        task.wait(0.01)
        textBox.Text = "" 
        task.wait(0.01)
    end
    
    for i = 1, #word do
        if currentSession ~= typingSessionId then break end
        
        local checkPrompt, checkTurn = getGameStatus()
        if checkPrompt ~= targetPrompt or not checkTurn then break end
        
        local char = string.sub(word, i, i)
        local keyCode = nil
        
        if char == "-" then
            keyCode = Enum.KeyCode.Minus
        elseif char == "'" then
            keyCode = Enum.KeyCode.Quote
        else
            keyCode = Enum.KeyCode[char:upper()]
        end
        
        if keyCode then
            local currentDelay = speedWordDelay
            
            if instanttype then
                currentDelay = 0
            else
                currentDelay = applyRngVariation(speedWordDelay)
                
                if jitterEnabled then
                    local currentJitter = applyRngVariation(jitterIntensity)
                    local randomOffset = (math.random() * 2 - 1) * currentJitter
                    currentDelay = currentDelay + randomOffset
                end
                
                if currentDelay < 0.005 then currentDelay = 0.005 end
            end
            
            if i == 1 and textBox and textBox.Text ~= "" then textBox.Text = "" end
            
            Vim:SendKeyEvent(true, keyCode, false, game)
            if currentDelay > 0 then task.wait(currentDelay / 2) end
            Vim:SendKeyEvent(false, keyCode, false, game)
            if currentDelay > 0 then task.wait(currentDelay / 2) end
        end
    end
    
    if currentSession == typingSessionId then
        local finalPrompt, finalTurn = getGameStatus()
        if finalPrompt == targetPrompt and finalTurn then
            if not instanttype then task.wait(0.02) end
            Vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
            if not instanttype then task.wait(0.01) end
            Vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
            if not instanttype then task.wait(0.03) end
            totalTurns = totalTurns + 1
            if turnsLabel then turnsLabel:Set("Total Turns: " .. totalTurns) end
        else
            if textBox then textBox.Text = "" end
        end
    end
    
    if currentSession == typingSessionId then
        isTyping = false 
    end
end

-- === ЛОГИКА ПОИСКА СЛОВ И СБРОСА ===
local function copyword(bruteforce)
    if isTyping then return end
    local contains, isMyTurn = getGameStatus()
    
    if not contains or contains == "" then 
        if lastChunk ~= "WAITING" then
            sessionUsedWords = {} 
            lastChunk = "WAITING" 
            wasMyTurn = false
            cachedUpdateFunc = nil
            
            if promptLabel then promptLabel:Set("Current Prompt: Waiting...") end
            if solutionsLabel then solutionsLabel:Set("Solutions Found: 0") end
            if matchLabel then matchLabel:Set("Current Match: Waiting for game...") end
        end
        return 
    end

    wasMyTurn = isMyTurn
    local currentTime = os.clock()

    if currentTime - lastTypeTime > 5 and lastChunk == contains then
        sessionUsedWords = {}
        cachedUpdateFunc = nil
    end

    if lastChunk ~= contains or bruteforce then
        lastChunk = contains
        lastTypeTime = currentTime
        if promptLabel then promptLabel:Set("Current Prompt: " .. contains:upper()) end

        local promptLower = contains:lower()
        local specialMatches = {}
        local normalMatches = {}
        
        for i = 1, #globalWordsList do
            local candidate = globalWordsList[i]
            if #candidate <= lettercap and not sessionUsedWords[candidate] then
                if string.find(candidate, promptLower, 1, true) then
                    if string.find(candidate, "-", 1, true) or string.find(candidate, "'", 1, true) then
                        table.insert(specialMatches, candidate)
                    else
                        table.insert(normalMatches, candidate)
                    end
                end
            end
        end

        if solutionsLabel then solutionsLabel:Set("Solutions Found: " .. (#specialMatches + #normalMatches)) end

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
            if matchLabel then matchLabel:Set("Current Match: " .. finalword:upper()) end
            
            if autotype and isMyTurn and not isTyping then
                task.spawn(function()
                    typeWordMobile(finalword, promptLower)
                end)
                lastChunk = "" 
            end
        else
            if matchLabel then matchLabel:Set("Current Match: Not Found") end
        end
    end
end

-- === UI ELEMENTS (MAIN TAB) ===
MainTab:CreateInput({
   Name = "Letter Cap",
   PlaceholderText = "Enter max letter count...",
   Callback = function(Text) lettercap = tonumber(Text) or math.huge end,
})

MainTab:CreateToggle({
   Name = "Auto Search",
   CurrentValue = false,
   Callback = function(Value)
      autosearch = Value
      if autosearch then
          task.spawn(function()
              while autosearch do 
                  task.wait(0.15)
                  pcall(copyword) 
              end
          end)
      end
   end,
})

MainTab:CreateToggle({ 
    Name = "Auto Type (Mobile)", 
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
    Callback = function(Value)
        autojoin = Value
        if autojoin and Games then
            task.spawn(function()
                if autoJoinDelay > 0 then task.wait(autoJoinDelay) end
                typingSessionId = typingSessionId + 1
                sessionUsedWords = {} 
                lastChunk = "WAITING"
                wasMyTurn = false
                isTyping = false
                cachedUpdateFunc = nil
                pcall(function()
                    for i = -1, -20, -1 do 
                        Games.GameEvent:FireServer(i, "JoinGame") 
                    end
                end)
            end)
        end
    end
})

MainTab:CreateButton({ 
    Name = "Search Word (Manual)", 
    Callback = function() copyword(true) end 
})

-- === UI ELEMENTS (SETTINGS TAB) ===
SettingsTab:CreateSlider({
   Name = "Auto Join Delay",
   Info = "Delay before auto joining game (1s to 5s)",
   Range = {1, 5},
   Increment = 1,
   Suffix = " sec",
   CurrentValue = 2,
   Callback = function(Value) autoJoinDelay = Value end,
})

SettingsTab:CreateSlider({
   Name = "Check Word Delay",
   Info = "Delay before typing (0.1s to 2.0s)",
   Range = {1, 20}, 
   Increment = 1,
   Suffix = " (x0.1 sec)",
   CurrentValue = 10, 
   Callback = function(Value) checkWordDelay = Value / 10 end,
})

SettingsTab:CreateSlider({
   Name = "Typing WPM",
   Info = "Words Per Minute speed",
   Range = {100, 1000},
   Increment = 50,
   Suffix = " WPM",
   CurrentValue = 500,
   Callback = function(Value)
      typingWPM = Value
      speedWordDelay = 60 / (typingWPM * 5)
   end,
})

SettingsTab:CreateSlider({
   Name = "RNG Variation",
   Info = "Random speed & delay variation (+-0% to +-100%)",
   Range = {0, 100},
   Increment = 5,
   Suffix = "%",
   CurrentValue = 0,
   Callback = function(Value)
      rngVariationPercent = Value
   end,
})

SettingsTab:CreateToggle({
   Name = "Human Jittering",
   CurrentValue = false,
   Info = "Slight realistic delay fluctuations",
   Callback = function(Value) jitterEnabled = Value end,
})

SettingsTab:CreateSlider({
   Name = "Jitter Delay",
   Info = "Jittering strength",
   Range = {1, 20}, 
   Increment = 1,
   Suffix = " ms", 
   CurrentValue = 5, 
   Callback = function(Value) jitterIntensity = Value / 100 end,
})

-- === STATS PANEL ===
MainTab:CreateSection("Statistics")
elapsedLabel = MainTab:CreateLabel("Elapsed Time: 00:00:00")
turnsLabel = MainTab:CreateLabel("Total Turns: 0")
promptLabel = MainTab:CreateLabel("Current Prompt: None")
solutionsLabel = MainTab:CreateLabel("Solutions Found: 0")
matchLabel = MainTab:CreateLabel("Current Match: None")
MainTab:CreateSection("------------------")

-- === ФОНОВЫЙ ПОТОК AUTO JOIN ===
if Games then
    local registerGame = Games:FindFirstChild("RegisterGame")
    if registerGame then
        registerGame.OnClientEvent:Connect(function(gameRoomID)
            if autojoin then 
                task.spawn(function()
                    if autoJoinDelay > 0 then task.wait(autoJoinDelay) end
                    
                    typingSessionId = typingSessionId + 1 
                    sessionUsedWords = {} 
                    lastChunk = "WAITING"
                    wasMyTurn = false
                    isTyping = false
                    cachedUpdateFunc = nil 
                    
                    pcall(function() 
                        Games.GameEvent:FireServer(gameRoomID, "JoinGame") 
                    end)

                    task.wait(1)
                    
                    if promptLabel then promptLabel:Set("Current Prompt: Waiting...") end
                    if matchLabel then matchLabel:Set("Current Match: Waiting...") end
                end)
            end
        end)
    end
end

-- === ANTI-DUPE ===
task.spawn(function()
    while task.wait(0.8) do
        if not autosearch then continue end
        
        local localPlayer = Players.LocalPlayer
        local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then continue end

        local targetGui = playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("DesktopUI") or playerGui:FindFirstChild("MobileUI")
        
        if targetGui then
            for _, child in ipairs(targetGui:GetChildren()) do
                if child:IsA("Frame") or child:IsA("ScrollingFrame") then
                    for _, v in ipairs(child:GetChildren()) do
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
        end
    end
end)

-- === TIMER LOOP ===
task.spawn(function()
    while task.wait(1) do
        local elapsed = os.time() - startTime
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor((elapsed % 3600) / 60)
        local seconds = elapsed % 60
        if elapsedLabel then
            elapsedLabel:Set(string.format("Elapsed Time: %02d:%02d:%02d", hours, minutes, seconds))
        end
    end
end)
