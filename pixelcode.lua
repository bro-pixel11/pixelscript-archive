local RbxAnalytics = game:GetService("RbxAnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Vim = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local userHWID = RbxAnalytics:GetClientId()
local KEYS_URL = "https://raw.githubusercontent.com/bro-pixel11/keys.json/main/auth.json"

local userProvidedKey = getgenv().PixelKey or _G.PixelKey or PixelKey

if not userProvidedKey or userProvidedKey == "" then
    LocalPlayer:Kick("❌ Ошибка: Ключ не найден! Укажите getgenv().PixelKey = 'ВАШ_КЛЮЧ' перед loadstring.")
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
    LocalPlayer:Kick("🔒 [Bro-Pixel Auth]: " .. authMessage)
    error("[AUTH FAILED]: " .. authMessage)
    return
end

print("✅ Авторизация прошла успешно! Загрузка Bro-PixelScript...")

-- === ОСНОВНОЙ СКРИПТ ===

getgenv().deletewhendupefound = true

-- Загрузка Rayfield UI
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Создание окна
local Window = Rayfield:CreateWindow({
   Name = "🎨 Bro-PixelScript (wordbomb) 🎨",
   LoadingTitle = "⚡ Bro-Pixel Loader ⚡",
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

-- Создание вкладок
local MainTab = Window:CreateTab("🪐 Main", nil)
local SettingsTab = Window:CreateTab("⚙️ Settings", nil)

local statusLabel = MainTab:CreateLabel("⏳ Loading dictionary...")

-- Основная база слов
local globalWordsList = {} 

-- Асинхронная загрузка словаря
local function loadDictionaryAsync(url)
    task.spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then 
            statusLabel:Set("❌ Failed to load dictionary!")
            return 
        end
        
        local total = 0
        for word in raw:gmatch("[^\r\n]+") do
            word = word:gsub("%s+", ""):lower()
            if word ~= "" then
                total = total + 1
                table.insert(globalWordsList, word)
                
                if total % 10000 == 0 then
                    task.wait()
                end
            end
        end
        statusLabel:Set("📚 Dictionary: " .. total .. " words (Ready)")
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/wbdict/main/word-bomb-list.txt")

-- === STATE & SETTINGS ===
local sessionUsedWords = {} -- Хэш-таблица O(1)
local lettercap = math.huge
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
local startTime = os.time()
local totalTurns = 0

local typingWPM = 250
local speedWordDelay = 60 / (typingWPM * 5)

-- Инициализация Network
local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- UI Elements (Main)
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
    Name = "⚡ Instant Type (No Delay) ⚡", 
    CurrentValue = false, 
    Callback = function(Value) instanttype = Value end 
})

MainTab:CreateToggle({
    Name = "🚪 Auto Join Game 🚪",
    CurrentValue = false,
    Callback = function(Value)
        autojoin = Value
        if autojoin and Games then
            task.spawn(function()
                if autoJoinDelay > 0 then task.wait(autoJoinDelay) end
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
    Name = "🔥 Search Word (Manual) 🔥", 
    Callback = function() copyword(true) end 
})

-- UI Elements (Settings)
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

-- Stats Panel
local StatsSection = MainTab:CreateSection("📊 Statistics 📊")
local elapsedLabel = MainTab:CreateLabel("Elapsed Time: 00:00:00")
local turnsLabel = MainTab:CreateLabel("Total Turns: 0")
local promptLabel = MainTab:CreateLabel("Current Prompt: None")
local solutionsLabel = MainTab:CreateLabel("Solutions Found: 0")
local matchLabel = MainTab:CreateLabel("Current Match: None")
MainTab:CreateSection("------------------")

-- === КЭШИРОВАННЫЕ ХЕЛПЕРЫ ДЛЯ МАКСИМАЛЬНОГО FPS ===
local cachedPromptObject = nil

local function getChunk()
    if cachedPromptObject and cachedPromptObject.Parent and cachedPromptObject.Visible then
        local txt = cachedPromptObject.Text:gsub("%s+", ""):lower()
        if #txt >= 2 and #txt <= 5 and not txt:find("turn") and not txt:find("быстро") and not txt:find("ходи") then
            return txt
        end
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end

    for _, guiName in ipairs({"GameUI", "DesktopUI", "MobileUI", "MainUI"}) do
        local gameGui = playerGui:FindFirstChild(guiName)
        if gameGui then
            for _, v in pairs(gameGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and v.Parent and (v.Parent.Name == "InfoFrame" or v.Name == "Prompt" or v.Name == "Frame") then
                    local txt = v.Text:gsub("%s+", ""):lower()
                    if #txt >= 2 and #txt <= 5 and not txt:find("turn") and not txt:find("быстро") and not txt:find("ходи") then
                        cachedPromptObject = v
                        return txt
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
    
    local isMyTurn = false
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, v in pairs(playerGui:GetDescendants()) do
            if v:IsA("TextLabel") and v.Visible and v.Parent.Name ~= "Rayfield" then
                local text = v.Text:lower()
                if text:find("quick") or text:find("быстро") or text:find("your turn") or text:find("ходи") then
                    isMyTurn = true
                    break
                end
            end
        end
    end
    return prompt, isMyTurn
end

local function getGameTextBox()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end
    for _, v in pairs(playerGui:GetDescendants()) do
        if v:IsA("TextBox") and v.Visible and v.Parent.Name ~= "Rayfield" then return v end
    end
    return nil
end

-- === ВВОД СЛОВА ===
local function typeWordMobile(word, targetPrompt)
    if isTyping then return end 
    isTyping = true 
    
    if not instanttype and checkWordDelay > 0 then task.wait(checkWordDelay) end
    
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
        local checkPrompt, checkTurn = getGameStatus()
        if checkPrompt ~= targetPrompt or not checkTurn then break end
        
        local char = word:sub(i, i)
        local keyCode = (char == "-") and Enum.KeyCode.Minus or (char == "'") and Enum.KeyCode.Quote or Enum.KeyCode[char:upper()]
        
        if keyCode then
            local currentDelay = speedWordDelay
            
            if instanttype then
                currentDelay = 0
            elseif jitterEnabled then
                currentDelay = math.max(0.005, speedWordDelay + (math.random() * 2 - 1) * jitterIntensity)
            end
            
            if i == 1 and textBox and textBox.Text ~= "" then textBox.Text = "" end
            
            Vim:SendKeyEvent(true, keyCode, false, game)
            if currentDelay > 0 then task.wait(currentDelay / 2) end
            Vim:SendKeyEvent(false, keyCode, false, game)
            if currentDelay > 0 then task.wait(currentDelay / 2) end
        end
    end
    
    local finalPrompt, finalTurn = getGameStatus()
    if finalPrompt == targetPrompt and finalTurn then
        if not instanttype then task.wait(0.02) end
        Vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        if not instanttype then task.wait(0.01) end
        Vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        if not instanttype then task.wait(0.03) end
        totalTurns = totalTurns + 1
        turnsLabel:Set("Total Turns: " .. totalTurns)
    else
        if textBox then textBox.Text = "" end
    end
    
    isTyping = false 
end

-- === ОПТИМИЗИРОВАННАЯ ЛОГИКА ПОИСКА СЛОВА ===
function copyword(bruteforce)
    if isTyping then return end
    local contains, isMyTurn = getGameStatus()
    
    if not contains or contains == "" then 
        if lastChunk ~= "WAITING" then
            sessionUsedWords = {} -- Быстрый сброс использованных слов
            lastChunk = "WAITING" 
            wasMyTurn = false
            
            if promptLabel then promptLabel:Set("Current Prompt: WAITING...") end
            if solutionsLabel then solutionsLabel:Set("Solutions Found: 0") end
            if matchLabel then matchLabel:Set("Current Match: Waiting for game...") end
        end
        return 
    end

    local turnSwitchedToMe = (isMyTurn and not wasMyTurn)
    wasMyTurn = isMyTurn

    local currentTime = os.clock()
    if currentTime - lastTypeTime > 4 then 
        if lastChunk ~= "WAITING" then lastChunk = "" end 
    end

    if lastChunk ~= contains or bruteforce or turnSwitchedToMe then
        lastChunk = contains
        lastTypeTime = currentTime
        promptLabel:Set("Current Prompt: " .. contains:upper())

        local promptLower = contains:lower()
        local bestSpecialWord = nil
        local shortestNormalWord = nil
        local shortestNormalLen = math.huge
        local totalMatches = 0

        -- Выполняем поиск за 1 проход по словарю
        for i = 1, #globalWordsList do
            local candidate = globalWordsList[i]
            
            -- Проверка наличия слога и использования за O(1)
            if not sessionUsedWords[candidate] and #candidate <= lettercap then
                if string.find(candidate, promptLower, 1, true) then
                    totalMatches = totalMatches + 1
                    
                    -- Приоритет спецсимволам
                    if not bestSpecialWord and (string.find(candidate, "-", 1, true) or string.find(candidate, "'", 1, true)) then
                        bestSpecialWord = candidate
                    elseif #candidate < shortestNormalLen then
                        shortestNormalLen = #candidate
                        shortestNormalWord = candidate
                    end
                end
            end
        end

        solutionsLabel:Set("Solutions Found: " .. totalMatches)

        local finalword = bestSpecialWord or shortestNormalWord

        if finalword then
            sessionUsedWords[finalword] = true -- Запоминаем за O(1)
            matchLabel:Set("Current Match: " .. finalword:upper())
            
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

-- Auto Join Loop
if Games then
    local registerGame = Games:FindFirstChild("RegisterGame")
    if registerGame then
        registerGame.OnClientEvent:Connect(function(gameRoomID)
            if autojoin then 
                task.spawn(function()
                    if autoJoinDelay > 0 then task.wait(autoJoinDelay) end
                    
                    pcall(function() 
                        Games.GameEvent:FireServer(gameRoomID, "JoinGame") 
                    end)

                    task.wait(1) 
                    sessionUsedWords = {} 
                    lastChunk = "WAITING"
                    wasMyTurn = false
                end)
            end
        end)
    end
end

-- Anti-Dupe Loop
task.spawn(function()
    while task.wait(1) do
        if not autosearch then continue end
        
        local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gameGui = playerGui and (playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("DesktopUI") or playerGui:FindFirstChild("MobileUI"))
        
        if gameGui then
            for _, v in pairs(gameGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and #v.Text >= 2 then
                    local text = v.Text:gsub("%s+", "")
                    if text == text:upper() and not text:find("%d") and not text:find("TURN") and not text:find("ХОД") then
                        sessionUsedWords[text:lower()] = true
                    end
                end
            end
        end
    end
end)

-- Timer Loop
task.spawn(function()
    while task.wait(1) do
        local elapsed = os.time() - startTime
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor((elapsed % 3600) / 60)
        local seconds = elapsed % 60
        elapsedLabel:Set(string.format("Elapsed Time: %02d:%02d:%02d", hours, minutes, seconds))
    end
end)
