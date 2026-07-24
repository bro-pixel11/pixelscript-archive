-- === КЭШ СЕРВИСОВ И ИГРОКА ===
local RbxAnalytics = game:GetService("RbxAnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- === ЛОКАЛИЗАЦИЯ ЧАСТО ИСПОЛЬЗУЕМЫХ ФУНКЦИЙ ===
local string_find = string.find
local string_lower = string.lower
local string_upper = string.upper
local string_sub = string.sub
local string_gsub = string.gsub
local string_format = string.format
local table_insert = table.insert
local table_clear = table.clear
local task_wait = task.wait
local task_defer = task.defer
local math_random = math.random
local math_floor = math.floor
local os_time = os.time
local os_clock = os.clock
local pcall = pcall
local type = type
local tostring = tostring

-- === АВТОРИЗАЦИЯ ===
local userHWID = RbxAnalytics:GetClientId()
local KEYS_URL = "https://raw.githubusercontent.com/bro-pixel11/keys.json/main/auth.json"
local userProvidedKey = getgenv().PixelKey or _G.PixelKey or PixelKey

if not userProvidedKey or userProvidedKey == "" then
    LocalPlayer:Kick("Ошибка: Ключ не найден! Укажите getgenv().PixelKey = 'ВАШ_КЛЮЧ' перед loadstring.")
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
        for i = 1, #registeredHWID do
            if registeredHWID[i] == userHWID then
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
    LocalPlayer:Kick("[Bro-Pixel Auth]: " .. authMessage)
    error("[AUTH FAILED]: " .. authMessage)
    return
end

print("Авторизация прошла успешно! Загрузка Bro-PixelScript...")

-- === ОСНОВНОЙ СКРИПТ ===
getgenv().deletewhendupefound = true

-- Загрузка Rayfield UI
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "Bro-PixelScript (wordbomb)",
   LoadingTitle = "Bro-Pixel Loader",
   LoadingSubtitle = "by Bro-Pixel",
   Theme = "CustomTheme", 

   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,

   ConfigurationSaving = { Enabled = false },
   KeySystem = false,
   Size = UDim2.fromOffset(340, 260),
   
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
local statusLabel = MainTab:CreateLabel("Loading dictionary...")

-- Таблицы данных
local globalWordsList = {} 
local sessionUsedWords = {}
local specialMatches = {}
local normalMatches = {}

-- === КЭШ ИГРОВЫХ GUI ЭЛЕМЕНТОВ ===
local cachedPromptLabel = nil
local cachedTextBox = nil
local promptConnection = nil

-- === АСИНХРОННАЯ ЗАГРУЗКА И ОЧИСТКА СЛОВАРЯ ===
local function loadDictionaryAsync(url)
    task.defer(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then 
            statusLabel:Set("Failed to load dictionary!")
            return 
        end
        
        local total = 0
        for word in raw:gmatch("[^\r\n]+") do
            word = string_lower(string_gsub(word, "%s+", ""))
            if word ~= "" then
                total = total + 1
                table_insert(globalWordsList, word)
                
                if total % 5000 == 0 then
                    task_wait()
                end
            end
        end
        statusLabel:Set("Dictionary: " .. total .. " words (Ready)")
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/wbdict/main/word-bomb-list.txt")

-- === STATE & SETTINGS ===
local lettercap = 2e9
local autosearch = false
local autotype = false
local instanttype = false
local autojoin = false
local autoJoinDelay = 3 
local jitterEnabled = true 
local jitterIntensity = 0.16 
local lastChunk = ""
local lastTypeTime = 0
local wasMyTurn = false
local isTyping = false 

local checkWordDelay = 0.5 
local startTime = os_time()
local totalTurns = 0

local typingWPM = 250
local speedWordDelay = 60 / (typingWPM * 5)

-- Инициализация сетевых событий
local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- === ОБНОВЛЕНИЕ КЭША ИГРОВЫХ ЭЛЕМЕНТОВ ===
local UI_NAMES = {"GameUI", "DesktopUI", "MobileUI", "MainUI"}

local function updateGuiCache()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end

    -- Поиск и кэширование Prompt Label
    if not cachedPromptLabel or not cachedPromptLabel.Parent then
        if promptConnection then
            promptConnection:Disconnect()
            promptConnection = nil
        end
        cachedPromptLabel = nil
        for i = 1, #UI_NAMES do
            local gameGui = playerGui:FindFirstChild(UI_NAMES[i])
            if gameGui then
                local descendants = gameGui:GetDescendants()
                for j = 1, #descendants do
                    local v = descendants[j]
                    if v:IsA("TextLabel") and v.Parent then
                        local pName = v.Parent.Name
                        if pName == "InfoFrame" or v.Name == "Prompt" or v.Name == "Frame" then
                            cachedPromptLabel = v
                            break
                        end
                    end
                end
            end
            if cachedPromptLabel then break end
        end
    end

    -- Поиск и кэширование TextBox
    if not cachedTextBox or not cachedTextBox.Parent then
        cachedTextBox = nil
        for i = 1, #UI_NAMES do
            local gameGui = playerGui:FindFirstChild(UI_NAMES[i])
            if gameGui then
                local descendants = gameGui:GetDescendants()
                for j = 1, #descendants do
                    local v = descendants[j]
                    if v:IsA("TextBox") and v.Parent and v.Parent.Name ~= "Rayfield" then
                        cachedTextBox = v
                        break
                    end
                end
            end
            if cachedTextBox then break end
        end
    end

    -- Подключение события при изменении текста промпта
    if cachedPromptLabel and not promptConnection then
        promptConnection = cachedPromptLabel:GetPropertyChangedSignal("Text"):Connect(function()
            if autosearch then
                task.defer(pcall, copyword)
            end
        end)
    end
end

-- === UI ELEMENTS (MAIN TAB) ===
MainTab:CreateInput({
   Name = "Letter Cap",
   PlaceholderText = "Enter max letter count...",
   Callback = function(Text) lettercap = tonumber(Text) or 2e9 end,
})

MainTab:CreateToggle({
   Name = "Auto Search",
   CurrentValue = false,
   Callback = function(Value)
      autosearch = Value
      if autosearch then
          task.defer(pcall, copyword)
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
            task.defer(function()
                if autoJoinDelay > 0 then task_wait(autoJoinDelay) end
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
   CurrentValue = 3,
   Callback = function(Value) autoJoinDelay = Value end,
})

SettingsTab:CreateSlider({
   Name = "Check Word Delay",
   Info = "Delay before typing (0.1s to 2.0s)",
   Range = {1, 20}, 
   Increment = 1,
   Suffix = " (x0.1 sec)",
   CurrentValue = 5, 
   Callback = function(Value) checkWordDelay = Value / 10 end,
})

SettingsTab:CreateSlider({
   Name = "Typing WPM",
   Info = "Words Per Minute speed",
   Range = {100, 1000},
   Increment = 50,
   Suffix = " WPM",
   CurrentValue = 250,
   Callback = function(Value)
      typingWPM = Value
      speedWordDelay = 60 / (typingWPM * 5)
   end,
})

SettingsTab:CreateToggle({
   Name = "Human Jittering",
   CurrentValue = true,
   Info = "Slight realistic delay fluctuations",
   Callback = function(Value) jitterEnabled = Value end,
})

SettingsTab:CreateSlider({
   Name = "Jitter Delay",
   Info = "Jittering strength",
   Range = {1, 50}, 
   Increment = 1,
   Suffix = " ms", 
   CurrentValue = 16, 
   Callback = function(Value) jitterIntensity = Value / 100 end,
})

-- === STATS PANEL ===
MainTab:CreateSection("Statistics")
local elapsedLabel = MainTab:CreateLabel("Elapsed Time: 00:00:00")
local turnsLabel = MainTab:CreateLabel("Total Turns: 0")
local promptLabel = MainTab:CreateLabel("Current Prompt: None")
local solutionsLabel = MainTab:CreateLabel("Solutions Found: 0")
local matchLabel = MainTab:CreateLabel("Current Match: None")
MainTab:CreateSection("------------------")

-- === HELPERS ===
local function getChunk()
    if cachedPromptLabel and cachedPromptLabel.Parent and cachedPromptLabel.Visible then
        local txt = string_lower(string_gsub(cachedPromptLabel.Text, "%s+", ""))
        print("--------------------")
        print("PATH:", cachedPromptLabel:GetFullName())
        print("TEXT:", cachedPromptLabel.Text)
        print("--------------------")

        local chunk = txt:match("containing:([a-z]+)")
        if chunk then
            return chunk
        end

        chunk = txt:match("containing:%s*([a-z]+)")
        if chunk then
            return chunk
        end

        chunk = txt:match("\n([a-z]+)")
        if chunk then
            return chunk
        end

        return nil
    end

    updateGuiCache()

    if cachedPromptLabel and cachedPromptLabel.Parent and cachedPromptLabel.Visible then
        local txt = string_lower(string_gsub(cachedPromptLabel.Text, "%s+", ""))
        print("--------------------")
        print("PATH:", cachedPromptLabel:GetFullName())
        print("TEXT:", cachedPromptLabel.Text)
        print("--------------------")

        local chunk = txt:match("containing:([a-z]+)")
        if chunk then
            return chunk
        end

        chunk = txt:match("containing:%s*([a-z]+)")
        if chunk then
            return chunk
        end

        chunk = txt:match("\n([a-z]+)")
        if chunk then
            return chunk
        end

        return nil
    end

    return nil
end

local function getGameStatus()
    local prompt = getChunk()
    if not prompt or prompt == "" then return nil, false end
    
    local isMyTurn = false
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        local descendants = playerGui:GetDescendants()
        for i = 1, #descendants do
            local v = descendants[i]
            if v:IsA("TextLabel") and v.Visible and v.Parent and v.Parent.Name ~= "Rayfield" then
                local text = string_lower(v.Text)
                if string_find(text, "quick") or string_find(text, "быстро") or string_find(text, "your turn") or string_find(text, "ходи") then
                    isMyTurn = true
                    break
                end
            end
        end
    end
    return prompt, isMyTurn
end

local function getGameTextBox()
    if cachedTextBox and cachedTextBox.Parent and cachedTextBox.Visible then
        return cachedTextBox
    end
    updateGuiCache()
    return cachedTextBox
end

-- === TYPING LOGIC ===
local function typeWordMobile(word, targetPrompt)
    if isTyping then return end 
    isTyping = true 
    
    if not instanttype and checkWordDelay > 0 then task_wait(checkWordDelay) end
    
    local currentPrompt, isMyTurn = getGameStatus()
    if currentPrompt ~= targetPrompt or not isMyTurn then
        isTyping = false
        return
    end
    
    local textBox = getGameTextBox()
    if textBox then 
        textBox:CaptureFocus() 
        task_wait(0.01)
        textBox.Text = "" 
        task_wait(0.01)
    end
    
    local wordLen = #word
    for i = 1, wordLen do
        local checkPrompt, checkTurn = getGameStatus()
        if checkPrompt ~= targetPrompt or not checkTurn then break end
        
        local char = string_sub(word, i, i)
        local keyCode = nil
        
        if char == "-" then
            keyCode = Enum.KeyCode.Minus
        elseif char == "'" then
            keyCode = Enum.KeyCode.Quote
        else
            keyCode = Enum.KeyCode[string_upper(char)]
        end
        
        if keyCode then
            local currentDelay = speedWordDelay
            
            if instanttype then
                currentDelay = 0
            elseif jitterEnabled then
                local randomOffset = (math_random() * 2 - 1) * jitterIntensity
                currentDelay = speedWordDelay + randomOffset
                if currentDelay < 0.005 then currentDelay = 0.005 end
            end
            
            if i == 1 and textBox and textBox.Text ~= "" then textBox.Text = "" end
            
            VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
            if currentDelay > 0 then task_wait(currentDelay * 0.5) end
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
            if currentDelay > 0 then task_wait(currentDelay * 0.5) end
        end
    end
    
    local finalPrompt, finalTurn = getGameStatus()
    if finalPrompt == targetPrompt and finalTurn then
        if not instanttype then task_wait(0.02) end
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        if not instanttype then task_wait(0.01) end
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        if not instanttype then task_wait(0.03) end
        totalTurns = totalTurns + 1
        turnsLabel:Set("Total Turns: " .. totalTurns)
    else
        if textBox then textBox.Text = "" end
    end
    
    isTyping = false 
end

-- === ЛОГИКА ПОИСКА И ОЧИСТКИ (РЕЖИМ WAITING) ===
function copyword(bruteforce)
    if isTyping then return end
    local contains, isMyTurn = getGameStatus()
    
    -- WAITING: когда раунд окончен или промпт отсутствует
    if not contains or contains == "" then 
        if lastChunk ~= "WAITING" then
            table_clear(sessionUsedWords)
            print("[DEBUG] sessionUsedWords:", next(sessionUsedWords))
            
            lastChunk = "WAITING" 
            wasMyTurn = false
            
            if promptLabel then promptLabel:Set("Current Prompt: WAITING...") end
            if solutionsLabel then solutionsLabel:Set("Solutions Found: 0") end
            if matchLabel then matchLabel:Set("Current Match: Waiting for game...") end
        end
        return 
    end

    -- ИГРА: обработка промпта
    local turnSwitchedToMe = (isMyTurn and not wasMyTurn)
    wasMyTurn = isMyTurn

    local currentTime = os_clock()
    if currentTime - lastTypeTime > 4 then 
        if lastChunk ~= "WAITING" then lastChunk = "" end 
    end

    if lastChunk ~= contains or bruteforce or turnSwitchedToMe then
        lastChunk = contains
        lastTypeTime = currentTime
        promptLabel:Set("Current Prompt: " .. string_upper(contains))

        local promptLower = contains
        table_clear(specialMatches)
        table_clear(normalMatches)
        
        local dictSize = #globalWordsList
        for i = 1, dictSize do
            local candidate = globalWordsList[i]
            if string_find(candidate, promptLower, 1, true) then
                if not sessionUsedWords[candidate] and #candidate <= lettercap then
                    if string_find(candidate, "-", 1, true) or string_find(candidate, "'", 1, true) then
                        table_insert(specialMatches, candidate)
                    else
                        table_insert(normalMatches, candidate)
                    end
                end
            end
        end

        local totalMatches = #specialMatches + #normalMatches
        solutionsLabel:Set("Solutions Found: " .. totalMatches)

        local finalword = nil
        
        if #specialMatches > 0 then
            finalword = specialMatches[math_random(1, #specialMatches)]
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
            matchLabel:Set("Current Match: " .. string_upper(finalword))
            
            if autotype and isMyTurn then
                task.defer(typeWordMobile, finalword, promptLower)
                lastChunk = "" 
            end
        else
            matchLabel:Set("Current Match: Not Found")
        end
    end
end

-- === ФОНОВЫЙ ПОТОК AUTO JOIN ===
if Games then
    local registerGame = Games:FindFirstChild("RegisterGame")
    if registerGame then
        registerGame.OnClientEvent:Connect(function(gameRoomID)
            if autojoin then 
                task.defer(function()
                    if autoJoinDelay > 0 then task_wait(autoJoinDelay) end
                    
                    pcall(function() 
                        Games.GameEvent:FireServer(gameRoomID, "JoinGame") 
                    end)

                    task_wait(1) 
                    table_clear(sessionUsedWords)
                    lastChunk = "WAITING"
                    wasMyTurn = false
                end)
            end
        end)
    end
end

-- === РЕЗЕРВНЫЙ ЦИКЛ ОБНОВЛЕНИЯ UI И ПОИСКА ===
task.defer(function()
    while task_wait(0.9) do
        updateGuiCache()
        if autosearch then
            task.defer(pcall, copyword)
        end
    end
end)

-- === ANTI-DUPE ===
task.defer(function()
    while task_wait(0.8) do
        if not autosearch then continue end
        
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gameGui = playerGui and (playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("DesktopUI") or playerGui:FindFirstChild("MobileUI"))
        
        if gameGui then
            local descendants = gameGui:GetDescendants()
            for i = 1, #descendants do
                local v = descendants[i]
                if v:IsA("TextLabel") and v.Visible and #v.Text >= 2 then
                    local text = string_gsub(v.Text, "%s+", "")
                    if text == string_upper(text) and not string_find(text, "%d") and not string_find(text, "TURN") and not string_find(text, "ХОД") then
                        sessionUsedWords[string_lower(text)] = true
                    end
                end
            end
        end
    end
end)

-- === TIMER LOOP ===
task.defer(function()
    while task_wait(1) do
        local elapsed = os_time() - startTime
        local hours = math_floor(elapsed / 3600)
        local minutes = math_floor((elapsed % 3600) / 60)
        local seconds = elapsed % 60
        elapsedLabel:Set(string_format("Elapsed Time: %02d:%02d:%02d", hours, minutes, seconds))
    end
end)

-- === DEBUG PRINT CHANGED VISIBLE UI TEXTS ===
local printed = {}

task.spawn(function()
    while task.wait(0.1) do
        local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if gui then
            for _,v in ipairs(gui:GetDescendants()) do
                if (v:IsA("TextLabel") or v:IsA("TextButton") or v:IsA("TextBox")) and v.Visible then
                    local t = tostring(v.Text)

                    if t ~= "" and printed[v] ~= t then
                        printed[v] = t
                        print("PATH:", v:GetFullName())
                        print("TEXT:", t)
                        print("----------------")
                    end
                end
            end
        end
    end
end)
