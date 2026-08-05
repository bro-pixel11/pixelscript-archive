-- === LOCALIZATION OF FREQUENTLY USED FUNCTIONS AND LIBRARIES ===
local string_find   = string.find
local string_lower  = string.lower
local string_sub    = string.sub
local string_gsub   = string.gsub
local string_upper  = string.upper
local math_random   = math.random
local math_floor    = math.floor
local math_huge     = math.huge
local table_clear   = table.clear
local table_insert  = table.insert
local task_spawn    = task.spawn
local task_wait     = task.wait
local os_time       = os.time
local os_clock      = os.clock
local pcall         = pcall
local xpcall        = xpcall
local type          = type
local typeof        = typeof
local tostring      = tostring
local tonumber      = tonumber
local ipairs        = ipairs
local pairs         = pairs
local getgc         = getgc
local debug_getinfo = debug.getinfo
local debug_getupvalues = debug.getupvalues

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Vim = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- === NEW RENDER HWID & KEY AUTHENTICATION ===
local API_URL = "https://roblox-key-api-zxnv.onrender.com/verify"
local userProvidedKey = getgenv().PixelKey or _G.PixelKey or PixelKey

if not userProvidedKey or userProvidedKey == "" then
    if LocalPlayer then LocalPlayer:Kick("❌ [Bro-Pixel Auth]: Key not found! Set getgenv().PixelKey = 'YOUR_KEY' before execution.") end
    return
end

local function checkKey(userKey)
    local rawHwid = gethwid and gethwid() or (game:GetService("RbxAnalyticsService"):GetClientId())
    local requestUrl = string.format("%s?key=%s&hwid=%s", API_URL, tostring(userKey), tostring(rawHwid))
    
    local success, response = pcall(function()
        return game:HttpGet(requestUrl)
    end)
    
    if success and response then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(response)
        end)
        
        if ok and type(data) == "table" then
            if data.status == "success" then
                return true, data.message or "Access Granted!"
            else
                return false, data.message or "Access Denied!"
            end
        else
            return false, "Invalid response structure from server!"
        end
    else
        return false, "Failed to connect to the authentication server!"
    end
end

local isAuthenticated, authMessage = checkKey(userProvidedKey)

if not isAuthenticated then
    if LocalPlayer then LocalPlayer:Kick("🔒 [Bro-Pixel Auth]: " .. tostring(authMessage)) end
    error("[AUTH FAILED]: " .. tostring(authMessage))
    return
end

print("✅ [Bro-Pixel Auth]: Authorization successful: " .. tostring(authMessage))

-- === MAIN SCRIPT & UI SETUP ===
getgenv().deletewhendupefound = true

local elapsedLabel, turnsLabel, promptLabel, solutionsLabel, matchLabel, fusionLabel

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

local MainTab = Window:CreateTab("Main", nil)
local DictionaryTab = Window:CreateTab("Dictionary", nil)
local SettingsTab = Window:CreateTab("Settings", nil)

local statusLabel = MainTab:CreateLabel("Loading and indexing dictionary...")

-- === ACTIVITY TRACKING ===
local lastActivity = os_clock()

local function updateActivity()
    lastActivity = os_clock()
end

-- === DICTIONARY INDEXING & MEMORY BUFFERS ===
local globalWordsList = {} 
local PromptIndex = {}

local validCandidatesBuffer = {}
local specialMatchesBuffer = {}
local normalMatchesBuffer = {}

local function loadDictionaryAsync(url)
    task_spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then 
            statusLabel:Set("Failed to load dictionary!")
            print("❌ [DEBUG]: Failed to download dictionary!")
            return 
        end
        
        local total = 0
        local seenSubstrings = {}

        for word in raw:gmatch("[^\r\n]+") do
            word = word:gsub("%s+", ""):lower()
            local wordLen = #word
            if wordLen >= 2 then
                total = total + 1
                table_insert(globalWordsList, word)
                
                table_clear(seenSubstrings)

                for len = 2, 3 do
                    for i = 1, wordLen - len + 1 do
                        local sub = string_sub(word, i, i + len - 1)
                        if not seenSubstrings[sub] then
                            seenSubstrings[sub] = true
                            local list = PromptIndex[sub]
                            if not list then
                                list = {}
                                PromptIndex[sub] = list
                            end
                            table_insert(list, word)
                        end
                    end
                end
                
                if total % 4000 == 0 then
                    statusLabel:Set("Indexing: " .. total .. " words...")
                    task_wait()
                end
            end
        end
        statusLabel:Set("Dictionary: " .. total .. " words (Indexed & Ready)")
        print("✅ [DEBUG]: Dictionary indexed with " .. total .. " words.")
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/wbdict/main/word-bomb-list.txt")

-- === STATE & SETTINGS ===
local sessionUsedWords = {}
local lettercap = math_huge
local autosearch = false
local autotype = false
local instanttype = false
local autojoin = false
local autoJoinDelay = 2 
local jitterEnabled = false 
local jitterIntensity = 0.05 
local rngVariationPercent = 0 

-- Fuse Delay Settings
local useFuseProgress = true
local fusePercent = 0.50          
local currentFusionStats = "0.00s / 0.00s"

-- Human Typos Settings
local typosEnabled = false
local typoChancePercent = 3

local wordPriorityMode = "Hyphenated / Short"

local lastHandledPrompt = ""
local lastFuseStart = 0
local wasMyTurn = false
local isTyping = false 
local isSubmitting = false 
local typingSessionId = 0

local checkWordDelay = 1.0 
local startTime = os_time()
local totalTurns = 0

local typingWPM = 500
local speedWordDelay = 60 / (typingWPM * 5)

local alphabet = "abcdefghijklmnopqrstuvwxyz"

local function applyRngVariation(baseValue)
    if rngVariationPercent <= 0 then return baseValue end
    local factor = 1 + ((math_random() * 2 - 1) * (rngVariationPercent / 100))
    local result = baseValue * factor
    return result < 0 and 0 or result
end

-- === NETWORK EVENTS INITIALIZATION (SINGLETON LISTENERS) ===
local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

local Network = ReplicatedStorage:FindFirstChild("Network")
if Network then
    local gameEvent = Network:FindFirstChild("GameEvent", true)
    if gameEvent then
        local currentTypingBuffer = ""
        local systemStrings = {
            ["typingevent"] = true,
            ["changepossessor"] = true,
            ["english"] = true,
        }

        gameEvent.OnClientEvent:Connect(function(...)
            local args = {...}
            local isTypingEvent = false
            
            for i = 1, #args do
                local arg = args[i]
                if type(arg) == "string" then
                    local lowerArg = arg:lower()
                    if lowerArg == "typingevent" then
                        isTypingEvent = true
                    end
                end
            end

            if isTypingEvent then
                for i = 1, #args do
                    local arg = args[i]
                    if type(arg) == "string" then
                        local lowerArg = arg:lower()
                        if not systemStrings[lowerArg] and not lowerArg:find("abcdefg") then
                            currentTypingBuffer = lowerArg
                        end
                    end
                end
            else
                for i = 1, #args do
                    if type(args[i]) == "string" and args[i]:lower() == "changepossessor" then
                        if #currentTypingBuffer > 1 then
                            sessionUsedWords[currentTypingBuffer] = true
                            currentTypingBuffer = ""
                        end
                        break
                    end
                end
            end
        end)
    end
end

-- === DYNAMIC GC FUNCTION SEARCH WITH BLACKLIST & DOM PRIORITY ===
local activeUpdateFn = nil
local deadFunctions = {}

local function isValidStructure(fn)
    if type(fn) ~= "function" then return false end
    
    local isTargetName = false
    pcall(function()
        if debug_getinfo(fn).name == "updateInfoFrame" then
            isTargetName = true
        end
    end)
    if not isTargetName then return false end
    
    local hasPrompt = false
    local hasPlayerID = false
    
    pcall(function()
        for _, vv in pairs(debug_getupvalues(fn)) do
            if type(vv) == "table" then
                if vv.Prompt ~= nil then hasPrompt = true end
                if vv.PlayerID ~= nil then hasPlayerID = true end
            end
        end
    end)
    
    return hasPrompt and hasPlayerID
end

local function isFnAlive(fn)
    if not fn or deadFunctions[fn] or not isValidStructure(fn) then return false end
    local alive = false
    pcall(function()
        for _, vv in pairs(debug_getupvalues(fn)) do
            if type(vv) == "table" and vv.Prompt ~= nil then
                if type(vv.Prompt) == "string" then
                    alive = true
                end
            end
        end
    end)
    return alive
end

local function getActiveUpdateInfoFrame()
    if activeUpdateFn and isFnAlive(activeUpdateFn) then
        return activeUpdateFn
    end

    activeUpdateFn = nil
    for _, v in pairs(getgc()) do
        if type(v) == "function" and not deadFunctions[v] and isValidStructure(v) and isFnAlive(v) then
            local isWaiting = false
            pcall(function()
                for _, vv in pairs(debug_getupvalues(v)) do
                    if type(vv) == "table" and vv.Prompt ~= nil then
                        if type(vv.Prompt) == "string" and vv.Prompt:lower():find("waiting") then
                            isWaiting = true
                        end
                    end
                end
            end)

            if not isWaiting then
                activeUpdateFn = v
                print("🔍 [DEBUG - GC]: Found VALID active updateInfoFrame function!")
                return v
            end
        end
    end
    
    return nil
end

local function getInfoTable()
    local fn = getActiveUpdateInfoFrame()
    if fn then
        local s, r = pcall(function()
            for _, vv in pairs(debug_getupvalues(fn)) do
                if type(vv) == "table" and vv.FuseStart ~= nil then 
                    return vv 
                end
            end
        end)
        if s and type(r) == "table" then return r end
    end
    return nil
end

-- === DOM-FIRST GETTERS (V2 PATTERN) WITH FALLBACK ===
local function GetTurn()
    -- 1. Fast DOM Access (Из V2)
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        local gameUI = playerGui:FindFirstChild("GameUI")
        if gameUI then
            local infoFrame = gameUI:FindFirstChild("InfoFrame", true)
            if infoFrame and infoFrame:FindFirstChild("PlayerID") then
                return infoFrame.PlayerID.Value
            end
        end
    end

    -- 2. Fallback to GC
    local fn = getActiveUpdateInfoFrame()
    if fn then
        local s, r = pcall(function()
            for _, vv in pairs(debug_getupvalues(fn)) do
                if type(vv) == "table" and vv.PlayerID ~= nil then 
                    return vv.PlayerID 
                end
            end
        end)
        if s and r ~= nil then return r end
    end
    return nil
end

local function GetLetters()
    -- 1. Fast DOM Access (Из V2)
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, guiName in ipairs({"GameUI", "DesktopUI", "MobileUI", "PlayerGui"}) do
            local target = playerGui:FindFirstChild(guiName) or playerGui
            local promptLbl = target:FindFirstChild("PromptLabel", true) or target:FindFirstChild("Prompt", true)
            if promptLbl and promptLbl:IsA("TextLabel") and promptLbl.Visible and promptLbl.Text ~= "" then
                local txt = promptLbl.Text
                if not txt:lower():find("waiting") then
                    return txt
                end
            end
        end
    end

    -- 2. Fallback to GC
    local fn = getActiveUpdateInfoFrame()
    if fn then
        local s, r = pcall(function()
            for _, vv in pairs(debug_getupvalues(fn)) do
                if type(vv) == "table" and vv.Prompt ~= nil then 
                    return vv.Prompt 
                end
            end
        end)
        if s and type(r) == "string" and r ~= "" and not r:lower():find("waiting") then 
            return r 
        end
    end

    return nil
end

local function getGameStatus()
    local rawPrompt = GetLetters()
    if not rawPrompt or type(rawPrompt) ~= "string" then return nil, false end

    local prompt = rawPrompt:lower():gsub("%s+", "")
    if prompt == "" or prompt == "waiting" or prompt == "waiting..." then return nil, false end

    if not LocalPlayer then return nil, false end

    local currentTurnId = GetTurn()
    local isMyTurn = (currentTurnId == LocalPlayer.UserId)

    if currentTurnId == nil then
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            for _, v in pairs(playerGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and v.Parent and v.Parent.Name ~= "Rayfield" then
                    local text = v.Text:lower()
                    if string_find(text, "quick") or string_find(text, "быстро") or string_find(text, "your turn") or string_find(text, "ходи") then
                        isMyTurn = true
                        break
                    end
                end
            end
        end
    end

    return prompt, isMyTurn
end

local function getGameTextBox()
    if not LocalPlayer then return nil end
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end
    for _, v in pairs(playerGui:GetDescendants()) do
        if v:IsA("TextBox") and v.Visible and v.Parent and v.Parent.Name ~= "Rayfield" then return v end
    end
    return nil
end

-- === FUSE DELAY LOGIC ===
local function waitFuseProgress(targetSession)
    if not useFuseProgress then return end

    local tbl = getInfoTable()
    if not tbl or not tbl.FuseStart or tbl.FuseStart <= 1000 or not tbl.FuseRate or tbl.FuseRate == 0 then
        if checkWordDelay > 0 and not instanttype then
            task_wait(applyRngVariation(checkWordDelay))
        end
        return
    end

    local fuseStart = tbl.FuseStart
    local fuseRate = tbl.FuseRate
    local totalFuseTime = math.abs(1 / fuseRate)
    local targetWaitSeconds = math.max(0, (totalFuseTime * fusePercent) - 0.05)

    local localStart = os_clock()

    while typingSessionId == targetSession do
        local tblCurrent = getInfoTable()
        if not tblCurrent or tblCurrent.FuseStart ~= fuseStart then break end

        local elapsed = os_clock() - localStart
        currentFusionStats = string.format("%.2fs / %.2fs", math.min(elapsed, totalFuseTime), totalFuseTime)
        if fusionLabel then 
            fusionLabel:Set("Fusion Progress: " .. currentFusionStats) 
        end

        if elapsed >= targetWaitSeconds then break end
        task_wait(0.01)
    end
end

-- === FULL ROUND STATE RESET ===
local function resetRoundState()
    print("🔄 [DEBUG - Game Reset]: Resetting Round State...")
    
    if activeUpdateFn then
        deadFunctions[activeUpdateFn] = true
    end
    
    activeUpdateFn = nil 
    typingSessionId = typingSessionId + 1 
    sessionUsedWords = {} 
    lastHandledPrompt = ""
    lastFuseStart = 0
    wasMyTurn = false
    isTyping = false
    isSubmitting = false
    updateActivity()

    if promptLabel then promptLabel:Set("Current Prompt: Waiting...") end
    if solutionsLabel then solutionsLabel:Set("Solutions Found: 0") end
    if matchLabel then matchLabel:Set("Current Match: Waiting...") end
    if fusionLabel then fusionLabel:Set("Fusion Progress: 0.00s / 0.00s") end
end

-- === TYPING LOGIC (WITH GUARANTEED STATE CLEANUP) ===
local function typeWordMobile(word, targetPrompt)
    if isTyping then return end 
    isTyping = true 
    
    typingSessionId = typingSessionId + 1
    local currentSession = typingSessionId

    print("⌨️ [DEBUG - Type]: Starting typing process for word: " .. tostring(word))

    local success, err = pcall(function()
        if not instanttype then 
            if useFuseProgress then
                waitFuseProgress(currentSession)
            elseif checkWordDelay > 0 then 
                local finalDelay = applyRngVariation(checkWordDelay)
                task_wait(finalDelay) 
            end
        end
        
        if currentSession ~= typingSessionId then
            print("⚠️ [DEBUG - Type]: Session changed mid-delay, canceling type.")
            return
        end

        local focusedBox = UserInputService:GetFocusedTextBox()
        if focusedBox and focusedBox ~= getGameTextBox() then
            print("💬 [DEBUG - Chat Protect]: Player is using Chat! Aborting auto-type.")
            return
        end

        local currentPrompt, isMyTurn = getGameStatus()
        if currentPrompt ~= targetPrompt or not isMyTurn then
            print("⚠️ [DEBUG - Type]: Status changed before typing!")
            return
        end
        
        local textBox = getGameTextBox()
        if textBox then 
            textBox:CaptureFocus() 
            task_wait(0.01)
            textBox.Text = "" 
            task_wait(0.01)
        end
        
        local interrupted = false

        for i = 1, #word do
            if currentSession ~= typingSessionId then 
                interrupted = true
                break 
            end
            
            local activeBox = UserInputService:GetFocusedTextBox()
            if activeBox and activeBox ~= textBox then
                print("💬 [DEBUG - Chat Protect]: Player focused chat during typing! Stopping.")
                interrupted = true
                break
            end

            local checkPrompt, checkTurn = getGameStatus()
            if checkPrompt ~= targetPrompt or not checkTurn then 
                print("⚠️ [DEBUG - Type]: Turn lost during typing string.")
                interrupted = true
                break 
            end
            
            local char = string_sub(word, i, i)

            if typosEnabled and not instanttype and math_random(1, 100) <= typoChancePercent then
                local wrongCharIndex = math_random(1, #alphabet)
                local wrongChar = string_sub(alphabet, wrongCharIndex, wrongCharIndex)
                
                if wrongChar ~= char then
                    local wrongKeyCode = Enum.KeyCode[wrongChar:upper()]
                    if wrongKeyCode then
                        Vim:SendKeyEvent(true, wrongKeyCode, false, game)
                        task_wait(0.01)
                        Vim:SendKeyEvent(false, wrongKeyCode, false, game)
                        task_wait(math_random(200, 400) / 1000)
                        
                        Vim:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
                        task_wait(0.01)
                        Vim:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
                        task_wait(math_random(100, 250) / 1000)
                    end
                end
            end

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
                        local randomOffset = (math_random() * 2 - 1) * currentJitter
                        currentDelay = currentDelay + randomOffset
                    end
                    if currentDelay < 0.005 then currentDelay = 0.005 end
                end
                
                if i == 1 and textBox and textBox.Text ~= "" then textBox.Text = "" end
                
                Vim:SendKeyEvent(true, keyCode, false, game)
                if currentDelay > 0 then task_wait(currentDelay / 2) end
                Vim:SendKeyEvent(false, keyCode, false, game)
                if currentDelay > 0 then task_wait(currentDelay / 2) end
            end
        end
        
        if not interrupted and currentSession == typingSessionId then
            local finalPrompt, finalTurn = getGameStatus()
            if finalPrompt == targetPrompt and finalTurn then
                isSubmitting = true 

                if not instanttype then task_wait(0.02) end
                Vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
                if not instanttype then task_wait(0.01) end
                Vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                if not instanttype then task_wait(0.03) end
                
                totalTurns = totalTurns + 1
                if turnsLabel then turnsLabel:Set("Total Turns: " .. totalTurns) end
                updateActivity()
                print("✅ [DEBUG - Type]: Word successfully submitted: " .. tostring(word))
            else
                if textBox then textBox.Text = "" end
            end
        end
    end)

    if not success then
        warn("⚠️ [TYPE ERROR]: Exception during typing execution: " .. tostring(err))
    end

    if currentSession == typingSessionId then
        isTyping = false
        isSubmitting = false
    end
end

-- === WORD SEARCH LOGIC (REUSED BUFFERS & CHAT SAFEGUARD) ===
local function copyword(bruteforce)
    local contains, isMyTurn = getGameStatus()
    local tbl = getInfoTable()
    local currentFuseStart = tbl and tbl.FuseStart or 0
    
    if not contains or contains == "" or not isMyTurn then 
        lastHandledPrompt = ""
        isSubmitting = false
        return 
    end

    if contains ~= lastHandledPrompt or (lastFuseStart > 0 and currentFuseStart ~= lastFuseStart) then
        isSubmitting = false
    end

    if isTyping and contains ~= lastHandledPrompt then
        print("🔄 [DEBUG - Search]: Prompt changed mid-type! Stopping typing session.")
        isTyping = false
        isSubmitting = false
    end

    if isTyping or isSubmitting then return end

    local focusedBox = UserInputService:GetFocusedTextBox()
    if focusedBox and focusedBox ~= getGameTextBox() then return end

    wasMyTurn = true

    if contains ~= lastHandledPrompt or (lastFuseStart > 0 and currentFuseStart ~= lastFuseStart) or bruteforce then
        lastHandledPrompt = contains
        lastFuseStart = currentFuseStart
        updateActivity()
        print("🎯 [DEBUG - Search]: New turn detected! Prompt: " .. tostring(contains))
        
        if promptLabel then promptLabel:Set("Current Prompt: " .. contains:upper()) end

        local promptLower = contains:lower()
        
        table_clear(validCandidatesBuffer)
        table_clear(specialMatchesBuffer)
        table_clear(normalMatchesBuffer)
        
        local candidates = PromptIndex[promptLower]
        if candidates then
            for i = 1, #candidates do
                local candidate = candidates[i]
                if #candidate <= lettercap and not sessionUsedWords[candidate] then
                    table_insert(validCandidatesBuffer, candidate)
                    if string_find(candidate, "-", 1, true) or string_find(candidate, "'", 1, true) then
                        table_insert(specialMatchesBuffer, candidate)
                    else
                        table_insert(normalMatchesBuffer, candidate)
                    end
                end
            end
        end

        if solutionsLabel then solutionsLabel:Set("Solutions Found: " .. #validCandidatesBuffer) end

        local finalword = nil

        if #validCandidatesBuffer > 0 then
            local currentMode = wordPriorityMode
            if type(currentMode) == "table" then
                currentMode = currentMode[1] or "Hyphenated / Short"
            end

            if currentMode == "Hyphenated / Short" or currentMode == "Hyphenated/short" then
                if #specialMatchesBuffer > 0 then
                    finalword = specialMatchesBuffer[math_random(1, #specialMatchesBuffer)]
                elseif #normalMatchesBuffer > 0 then
                    local shortest = normalMatchesBuffer[1]
                    for i = 2, #normalMatchesBuffer do
                        if #normalMatchesBuffer[i] < #shortest then shortest = normalMatchesBuffer[i] end
                    end
                    finalword = shortest
                else
                    local shortest = validCandidatesBuffer[1]
                    for i = 2, #validCandidatesBuffer do
                        if #validCandidatesBuffer[i] < #shortest then shortest = validCandidatesBuffer[i] end
                    end
                    finalword = shortest
                end

            elseif currentMode == "Shortest" then
                local shortest = validCandidatesBuffer[1]
                for i = 2, #validCandidatesBuffer do
                    if #validCandidatesBuffer[i] < #shortest then shortest = validCandidatesBuffer[i] end
                end
                finalword = shortest

            elseif currentMode == "Longest" then
                local longest = validCandidatesBuffer[1]
                for i = 2, #validCandidatesBuffer do
                    if #validCandidatesBuffer[i] > #longest then longest = validCandidatesBuffer[i] end
                end
                finalword = longest

            elseif currentMode == "Random" then
                finalword = validCandidatesBuffer[math_random(1, #validCandidatesBuffer)]
            else
                finalword = validCandidatesBuffer[math_random(1, #validCandidatesBuffer)]
            end
        end

        if finalword then
            sessionUsedWords[finalword] = true
            updateActivity()
            if matchLabel then matchLabel:Set("Current Match: " .. finalword:upper()) end
            print("💡 [DEBUG - Search]: Picked word: " .. tostring(finalword))
            
            if autotype and isMyTurn then
                task_spawn(function()
                    typeWordMobile(finalword, promptLower)
                end)
            end
        else
            if matchLabel then matchLabel:Set("Current Match: Not Found") end
            print("❌ [DEBUG - Search]: No available words found for prompt: " .. tostring(contains))
            lastHandledPrompt = ""
        end
    end
end

-- === SINGLETON AUTO SEARCH LOOP CONTROL ===
local isAutoSearchLoopRunning = false

local function ensureAutoSearchLoop()
    if isAutoSearchLoopRunning then return end
    isAutoSearchLoopRunning = true

    task_spawn(function()
        print("▶️ [AUTO SEARCH]: Single persistent loop started.")
        local waitingCounter = 0

        while autosearch do
            xpcall(function()
                task_wait(0.15)
                
                local currentPrompt = GetLetters()
                if currentPrompt == nil or currentPrompt:lower():find("waiting") then
                    waitingCounter = waitingCounter + 1
                    if waitingCounter >= 6 then
                        activeUpdateFn = nil 
                        waitingCounter = 0
                    end
                else
                    waitingCounter = 0
                end

                copyword()
            end, function(err)
                warn("[AUTO SEARCH LOOP CRASH]: " .. tostring(err))
            end)
        end

        isAutoSearchLoopRunning = false
        print("⏹️ [AUTO SEARCH]: Loop safely terminated.")
    end)
end

-- === UI ELEMENTS (MAIN TAB) ===
MainTab:CreateInput({
   Name = "Letter Cap",
   PlaceholderText = "Enter max letter count...",
   Callback = function(Text) lettercap = tonumber(Text) or math_huge end,
})

MainTab:CreateToggle({
   Name = "Auto Search",
   CurrentValue = false,
   Callback = function(Value)
      autosearch = Value
      if autosearch then
          ensureAutoSearchLoop()
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
            task_spawn(function()
                if autoJoinDelay > 0 then task_wait(autoJoinDelay) end
                resetRoundState()
                pcall(function()
                    print("🚪 [DEBUG - AutoJoin]: Attempting to join game...")
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

-- === UI ELEMENTS (DICTIONARY TAB) ===
DictionaryTab:CreateDropdown({
   Name = "Word Priority",
   Options = {"Hyphenated / Short", "Shortest", "Longest", "Random"},
   CurrentOption = {"Hyphenated / Short"},
   MultipleOptions = false,
   Callback = function(Option)
      if type(Option) == "table" then
          wordPriorityMode = Option[1]
      else
          wordPriorityMode = Option
      end
   end,
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

SettingsTab:CreateToggle({
   Name = "Dynamic Fuse Delay",
   CurrentValue = true,
   Info = "Waits for turn timer % before typing",
   Callback = function(Value) useFuseProgress = Value end,
})

SettingsTab:CreateSlider({
   Name = "Fuse Delay Target %",
   Info = "Target % of fuse time to wait (1% to 95%)",
   Range = {1, 95},
   Increment = 1,
   Suffix = "%",
   CurrentValue = 50,
   Callback = function(Value) fusePercent = Value / 100 end,
})

SettingsTab:CreateSlider({
   Name = "Check Word Delay (Fallback)",
   Info = "Static delay if fuse not active (0.1s to 2.0s)",
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

SettingsTab:CreateToggle({
   Name = "Human Typos",
   CurrentValue = false,
   Info = "Simulates natural human typing mistakes",
   Callback = function(Value) typosEnabled = Value end,
})

SettingsTab:CreateSlider({
   Name = "Typo Chance",
   Info = "Chance of making a typo per character (1% to 20%)",
   Range = {1, 20},
   Increment = 1,
   Suffix = "%",
   CurrentValue = 3,
   Callback = function(Value) typoChancePercent = Value end,
})

-- === STATS PANEL ===
MainTab:CreateSection("Statistics")
elapsedLabel = MainTab:CreateLabel("Elapsed Time: 00:00:00")
turnsLabel = MainTab:CreateLabel("Total Turns: 0")
promptLabel = MainTab:CreateLabel("Current Prompt: None")
solutionsLabel = MainTab:CreateLabel("Solutions Found: 0")
matchLabel = MainTab:CreateLabel("Current Match: None")
fusionLabel = MainTab:CreateLabel("Fusion Progress: 0.00s / 0.00s")
MainTab:CreateSection("------------------")

-- === BACKGROUND AUTO JOIN THREAD (SINGLETON LISTENER) ===
if Games then
    local registerGame = Games:FindFirstChild("RegisterGame")
    if registerGame then
        registerGame.OnClientEvent:Connect(function(gameRoomID)
            print("📩 [DEBUG - Network]: RegisterGame Event Fired for RoomID: " .. tostring(gameRoomID))
            resetRoundState()
            
            task.delay(1, function()
                activeUpdateFn = nil
            end)

            if autojoin then 
                task_spawn(function()
                    if autoJoinDelay > 0 then task_wait(autoJoinDelay) end
                    pcall(function() 
                        Games.GameEvent:FireServer(gameRoomID, "JoinGame") 
                    end)
                end)
            end
        end)
    end
end

-- === TIMER LOOP (SINGLETON THREAD) ===
task_spawn(function()
    while true do
        xpcall(function()
            while task_wait(1) do
                local elapsed = os_time() - startTime
                local hours = math_floor(elapsed / 3600)
                local minutes = math_floor((elapsed % 3600) / 60)
                local seconds = elapsed % 60
                if elapsedLabel then
                    elapsedLabel:Set(string.format("Elapsed Time: %02d:%02d:%02d", hours, minutes, seconds))
                end
            end
        end, function(err)
            warn("[CRASH] Timer Loop errored: " .. tostring(err))
        end)
        task_wait(1)
    end
end)
