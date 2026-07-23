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

local typingWPM = 250
local checkWordDelay = 0.5
local minLen = 1
local maxLen = 99
local typoChance = 0
local humaniseWPM = true

local burstCounter = 0
local burstTarget = math.random(3, 7)

local lastChunk = ""
local lastTypeTime = 0
local wasMyTurn = false
local isTyping = false

local startTime = os.time()
local totalTurns = 0

local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- === 3. RAYFIELD UI ===
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "🎨 Bro-PixelScript (Word Bomb Ultra) 🎨",
   LoadingTitle = "⚡ Bro-Pixel Loader ⚡",
   LoadingSubtitle = "by Bro-Pixel",
   Theme = "CustomTheme", 
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   ConfigurationSaving = { Enabled = false },
   KeySystem = false,
   Size = UDim2.fromOffset(360, 280),
   CustomTheme = {
        TextColor = Color3.fromRGB(255, 255, 255),
        Background = Color3.fromRGB(25, 10, 40),        
        MainColor = Color3.fromRGB(90, 30, 180),       
        AccentColor = Color3.fromRGB(0, 240, 200),       
        OutlineColor = Color3.fromRGB(140, 50, 255),    
        PlaceholderColor = Color3.fromRGB(180, 150, 220)
   }
})

local MainTab = Window:CreateTab("🪐 Main", nil)
local SettingsTab = Window:CreateTab("⚙️ Settings", nil)
local StatsTab = Window:CreateTab("📊 Stats", nil)

local statusLabel = MainTab:CreateLabel("⏳ Loading dictionary...")

-- Загрузка словаря
local function loadDictionaryAsync(url)
    task.spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then return end
        
        local total = 0
        for word in raw:gmatch("[^\r\n]+") do
            word = word:gsub("%s+", ""):lower()
            if word ~= "" then
                total = total + 1
                table.insert(globalWordsList, word)
                if total % 10000 == 0 then task.wait() end
            end
        end
        statusLabel:Set("📚 Dictionary: " .. #globalWordsList .. " words (Ready)")
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/wbdict/main/word-bomb-list.txt")

-- === ЭЛЕМЕНТЫ UI (MAIN TAB) ===
MainTab:CreateToggle({ 
    Name = "⚡ Auto Type & Search ⚡", 
    CurrentValue = false, 
    Callback = function(Value) 
        autotype = Value 
    end 
})

MainTab:CreateToggle({ 
    Name = "🚀 Instant Type (No Delay)", 
    CurrentValue = false, 
    Callback = function(Value) instanttype = Value end 
})

MainTab:CreateToggle({
    Name = "🚪 Auto Join Game 🚪",
    CurrentValue = false,
    Callback = function(Value) autojoin = Value end
})

MainTab:CreateButton({ 
    Name = "🔥 Search Word (Manual) 🔥", 
    Callback = function() copyword(true) end 
})

-- === ЭЛЕМЕНТЫ UI (SETTINGS TAB) ===
SettingsTab:CreateSlider({
   Name = "Typing WPM",
   Range = {50, 1000},
   Increment = 25,
   Suffix = " WPM",
   CurrentValue = 250,
   Callback = function(Value) typingWPM = Value end,
})

SettingsTab:CreateToggle({
   Name = "Humanise WPM (Dynamic Delays)",
   CurrentValue = true,
   Callback = function(Value) humaniseWPM = Value end,
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
   CurrentValue = 5, 
   Callback = function(Value) checkWordDelay = Value / 10 end,
})

-- === STATS TAB ===
local elapsedLabel = StatsTab:CreateLabel("Elapsed Time: 00:00:00")
local turnsLabel = StatsTab:CreateLabel("Total Turns: 0")
local promptLabel = StatsTab:CreateLabel("Current Prompt: None")
local solutionsLabel = StatsTab:CreateLabel("Solutions Found: 0")
local matchLabel = StatsTab:CreateLabel("Current Match: None")

-- === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===
local function GetLetterDelay()
    local base = 60 / (typingWPM * 5)
    if humaniseWPM then
        local roll = math.random()
        if roll < 0.15 then
            base = base * (0.35 + math.random() * 0.25)
        elseif roll < 0.80 then
            base = base * (0.80 + math.random() * 0.40)
        else
            base = base * (1.20 + math.random() * 0.60)
        end
        burstCounter = burstCounter + 1
        if burstCounter >= burstTarget then
            burstCounter = 0
            burstTarget = math.random(3, 7)
            base = base + (0.04 + math.random() * 0.08)
        end
    end
    return math.max(base, 0.005)
end

local function getChunk()
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return nil end
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end

    for _, guiName in ipairs({"GameUI", "DesktopUI", "MobileUI", "MainUI"}) do
        local gameGui = playerGui:FindFirstChild(guiName)
        if gameGui then
            for _, v in pairs(gameGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and v.Parent and (v.Parent.Name == "InfoFrame" or v.Name == "Prompt" or v.Name == "Frame") then
                    local txt = v.Text:gsub("%s+", ""):lower()
                    if #txt >= 2 and #txt <= 5 and not txt:find("turn") and not txt:find("быстро") and not txt:find("ходи") then
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
    local localPlayer = Players.LocalPlayer
    if localPlayer then
        local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            for _, v in pairs(playerGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and v.Parent.Name ~= "Rayfield" then
                    local text = v.Text:lower()
                    if string.find(text, "quick") or string.find(text, "быстро") or string.find(text, "your turn") or string.find(text, "ходи") then
                        isMyTurn = true
                        break
                    end
                end
            end
        end
    end
    return prompt, isMyTurn
end

local function SimulateKey(char)
    local keyCode = Enum.KeyCode[char:upper()]
    if char == "-" then keyCode = Enum.KeyCode.Minus end
    if char == "'" then keyCode = Enum.KeyCode.Quote end
    if char == "\n" then keyCode = Enum.KeyCode.Return end
    
    if keyCode then
        Vim:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.005)
        Vim:SendKeyEvent(false, keyCode, false, game)
    end
end

local function SimulateBackspace()
    Vim:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
    task.wait(0.005)
    Vim:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
end

-- === ПЕЧАТЬ ===
local function typeWordMobile(word, targetPrompt)
    if isTyping then return end 
    isTyping = true 
    
    if not instanttype and checkWordDelay > 0 then task.wait(checkWordDelay) end
    
    local currentPrompt, isMyTurn = getGameStatus()
    if currentPrompt ~= targetPrompt or not isMyTurn then
        isTyping = false
        return
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
    
    local finalPrompt, finalTurn = getGameStatus()
    if finalPrompt == targetPrompt and finalTurn then
        SimulateKey("\n")
        totalTurns = totalTurns + 1
        turnsLabel:Set("Total Turns: " .. totalTurns)
    end
    
    isTyping = false 
end

-- === ОСНОВНОЙ ПОИСК ===
function copyword(bruteforce)
    if isTyping then return end
    local contains, isMyTurn = getGameStatus()
    
    if not contains or contains == "" then 
        if lastChunk ~= "WAITING" then
            sessionUsedWords = {} 
            lastChunk = "WAITING" 
            wasMyTurn = false
            promptLabel:Set("Current Prompt: WAITING...")
            solutionsLabel:Set("Solutions Found: 0")
            matchLabel:Set("Current Match: Waiting for game...")
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
        local finalword = nil
        local count = 0

        for i = 1, #globalWordsList do
            local candidate = globalWordsList[i]
            if #candidate >= minLen and #candidate <= maxLen then
                if string.find(candidate, promptLower, 1, true) then
                    if not sessionUsedWords[candidate] then
                        count = count + 1
                        if not finalword then finalword = candidate end
                        if count >= 5 then break end
                    end
                end
            end
        end

        solutionsLabel:Set("Solutions Found: " .. (count >= 5 and "5+" or count))

        if finalword then
            sessionUsedWords[finalword] = true
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

-- === ФОНОВЫЙ ЦИКЛ ПОИСКА И ПЕЧАТИ ===
task.spawn(function()
    while task.wait(0.2) do
        if autotype then
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

-- === ТАЙМЕР ===
task.spawn(function()
    while task.wait(1) do
        local elapsed = os.time() - startTime
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor((elapsed % 3600) / 60)
        local seconds = elapsed % 60
        elapsedLabel:Set(string.format("Elapsed Time: %02d:%02d:%02d", hours, minutes, seconds))
    end
end)
