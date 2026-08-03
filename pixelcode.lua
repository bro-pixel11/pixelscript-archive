-- === LOCALIZATION OF FREQUENTLY USED FUNCTIONS AND LIBRARIES ===
local string_find = string.find
local string_lower = string.lower
local string_sub = string.sub
local string_gsub = string.gsub
local string_upper = string.upper
local math_random = math.random
local math_floor = math.floor
local math_huge = math.huge
local table_clear = table.clear
local table_insert = table.insert
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

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Vim = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- === EXPLOIT SPECIFIC FUNCTIONS ===
local is_window_active = isrbxactive or iswindowactive or function() return true end

-- === NEW RENDER HWID & KEY AUTHENTICATION ===
local API_URL = "https://roblox-key-api-zxnv.onrender.com/verify"
local userProvidedKey = getgenv().PixelKey or _G.PixelKey or PixelKey

if not userProvidedKey or userProvidedKey == "" then
    Players.LocalPlayer:Kick("❌ [Bro-Pixel Auth]: Key not found! Set getgenv().PixelKey = 'YOUR_KEY' before execution.")
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
            if type(response) == "string" and (string_find(response, "<html") or string_find(response, "<head")) then
                return false, "Сервер авторизации запускается. Пожалуйста, подождите 30-50 секунд и перезапустите скрипт."
            end
            return false, "Invalid response structure from server!"
        end
    else
        return false, "Failed to connect to the authentication server!"
    end
end

local isAuthenticated, authMessage = checkKey(userProvidedKey)

if not isAuthenticated then
    Players.LocalPlayer:Kick("🔒 [Bro-Pixel Auth]: " .. tostring(authMessage))
    error("[AUTH FAILED]: " .. tostring(authMessage))
    return
end

print("✅ [Bro-Pixel Auth]: Authorization successful: " .. tostring(authMessage))

-- === MAIN SCRIPT ===

local elapsedLabel, turnsLabel, promptLabel, solutionsLabel, matchLabel, fusionLabel

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Bro-Pixel Hub",
    LoadingTitle = "Premium Word Bomb Script",
    LoadingSubtitle = "by Bro-Pixel",
    Theme = "CustomTheme", 

    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,

    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
    Size = UDim2.fromOffset(340, 280),
   
    CustomTheme = {
        TextColor = Color3.fromRGB(255, 255, 255),
        Background = Color3.fromRGB(11, 14, 20),        
        MainColor = Color3.fromRGB(26, 31, 43),      
        AccentColor = Color3.fromRGB(139, 92, 255),      
        OutlineColor = Color3.fromRGB(0, 217, 255),    
        PlaceholderColor = Color3.fromRGB(139, 92, 255)
    }
})

local MainTab = Window:CreateTab("Main", nil)
local DictionaryTab = Window:CreateTab("Dictionary", nil)
local SettingsTab = Window:CreateTab("Settings", nil)

local statusLabel = MainTab:CreateLabel("Loading and indexing dictionary...")

-- === SAFE UTILITIES & ERROR HANDLING ===
local function safeExecute(componentName, callback, ...)
    local success, result = pcall(callback, ...)
    if not success then
        warn(string.format("[%s Error]: %s", tostring(componentName), tostring(result)))
    end
    return success, result
end

-- === DICTIONARY STORAGE & INDEXING ===
local Words = {}
local PromptIndex = {}

local function loadDictionaryAsync(url, statusCallback)
    task_spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then 
            if statusCallback then statusCallback:Set("Failed to load dictionary!") end
            warn("[Dictionary Error]: Failed to download dictionary file.")
            return 
        end
        
        table_clear(Words)
        table_clear(PromptIndex)
        
        local wordSet = {}
        local rawWords = {}
        
        for word in raw:gmatch("[^\r\n]+") do
            word = word:gsub("%s+", ""):lower()
            if #word >= 2 and not wordSet[word] then
                wordSet[word] = true
                table_insert(rawWords, word)
            end
        end
        
        wordSet = nil
        local totalWords = #rawWords
        local seenSubstrings = {}

        for i = 1, totalWords do
            local word = rawWords[i]
            Words[i] = word
            
            table_clear(seenSubstrings)
            local wordLen = #word
            
            for len = 2, 3 do
                for pos = 1, wordLen - len + 1 do
                    local sub = string_sub(word, pos, pos + len - 1)
                    if not seenSubstrings[sub] then
                        seenSubstrings[sub] = true
                        local list = PromptIndex[sub]
                        if not list then
                            list = {}
                            PromptIndex[sub] = list
                        end
                        table_insert(list, i)
                    end
                end
            end
            
            if i % 500 == 0 then
                if statusCallback then
                    statusCallback:Set("Indexing: " .. i .. " / " .. totalWords .. " words...")
                end
                task_wait()
            end
        end
        
        if statusCallback then
            statusCallback:Set("Dictionary: " .. totalWords .. " words (Indexed & Ready)")
        end
        print("✅ [Dictionary]: Indexed " .. totalWords .. " unique words.")
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/wbdict/main/word-bomb-list.txt", statusLabel)

-- === WORD STATE MANAGEMENT ===
local PendingWords = {}
local UsedWords = {}

local function markWordPending(word)
    if word then PendingWords[word] = true end
end

local function confirmWordUsed(word)
    if word then
        PendingWords[word] = nil
        UsedWords[word] = true
    end
end

local function clearPendingWord(word)
    if word then PendingWords[word] = nil end
end

local function resetWordStates()
    table_clear(PendingWords)
    table_clear(UsedWords)
end

-- === OPERATION GENERATION & CANCELLATION ===
local operationGeneration = 0

local function cancelCurrentOperation()
    operationGeneration += 1
    return operationGeneration
end

local function isOperationValid(localToken)
    return localToken == operationGeneration
end

-- === TIMING AND VARIATION HELPERS ===
local function applyRandomVariation(baseValue, variationPercent)
    if not variationPercent or variationPercent <= 0 then return baseValue end
    local factor = 1 + ((math_random() * 2 - 1) * (variationPercent / 100))
    local result = baseValue * factor
    return math.max(0.005, result)
end

local function getCharacterDelay(speedWordDelaySeconds, jitterEnabled, jitterSeconds, variationPercent)
    local currentDelay = applyRandomVariation(speedWordDelaySeconds, variationPercent)
    
    if jitterEnabled and jitterSeconds > 0 then
        local jitterOffset = (math_random() * 2 - 1) * applyRandomVariation(jitterSeconds, variationPercent)
        currentDelay += jitterOffset
    end
    
    return math.max(0.005, currentDelay)
end

local function formatElapsedTime(totalSeconds)
    local hours = math_floor(totalSeconds / 3600)
    local minutes = math_floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

-- === RARE SCORE CALCULATOR & CANDIDATE SELECTION ===
local LETTER_WEIGHTS = {
    q=8, x=8, z=8, j=8,
    k=4, v=4, w=4, y=3, f=3, p=3, b=3, g=3, m=3, c=3, d=3,
    e=1, t=1, a=1, o=1, i=1, n=1, s=1, r=1, h=2, l=1, u=2
}

local function getRareScore(word)
    local score = 0
    local len = #word
    for i = 1, len do
        local char = string_sub(word, i, i)
        score += (LETTER_WEIGHTS[char] or 1)
    end
    if len > 7 then
        score += ((len - 7) * 3)
    end
    return score
end

local function chooseCandidate(candidates, mode, lettercap)
    if not candidates or #candidates == 0 then
        return nil, 0
    end

    local validCount = 0
    local chosenWord = nil
    local bestScore = -math_huge
    local targetLength = (mode == "Shortest") and math_huge or -math_huge
    local hasSpecialChoice = false

    for i = 1, #candidates do
        local wordId = candidates[i]
        local word = Words[wordId]
        
        if word and #word <= lettercap and not UsedWords[word] and not PendingWords[word] then
            validCount += 1
            local wordLen = #word
            
            if mode == "Rare Words" then
                local score = getRareScore(word)
                if score > bestScore then
                    bestScore = score
                    chosenWord = word
                end
                
            elseif mode == "Hyphenated / Short" or mode == "Hyphenated/short" then
                local isSpecial = string_find(word, "-", 1, true) or string_find(word, "'", 1, true)
                if isSpecial then
                    if not hasSpecialChoice then
                        hasSpecialChoice = true
                        chosenWord = word
                        targetLength = wordLen
                    elseif wordLen < targetLength then
                        targetLength = wordLen
                        chosenWord = word
                    end
                elseif not hasSpecialChoice then
                    if wordLen < targetLength then
                        targetLength = wordLen
                        chosenWord = word
                    end
                end
                
            elseif mode == "Shortest" then
                if wordLen < targetLength then
                    targetLength = wordLen
                    chosenWord = word
                end
                
            elseif mode == "Longest" then
                if wordLen > targetLength then
                    targetLength = wordLen
                    chosenWord = word
                end
                
            elseif mode == "Random" then
                -- Reservoir Sampling (k = 1)
                if math_random(1, validCount) == 1 then
                    chosenWord = word
                end
            end
        end
    end

    return chosenWord, validCount
end

-- === STATE & SETTINGS ===
local lettercap = math_huge
local autosearch = false
local autotype = false
local instanttype = false
local autojoin = false
local autoJoinDelay = 2 
local jitterEnabled = false 
local jitterSeconds = 0.005 
local rngVariationPercent = 0 

-- Fuse Delay Settings
local useFuseProgress = true
local fusePercent = 0.50          
local currentFusionStats = "0.00s / 0.00s"

local wordPriorityMode = "Hyphenated / Short"

local lastHandledPrompt = ""
local lastFuseStart = 0
local wasMyTurn = false
local isSubmitting = false 

local fallbackDelaySeconds = 1.0 
local startTime = os_time()
local totalTurns = 0

local typingWPM = 500
local speedWordDelaySeconds = 60 / (typingWPM * 5)

-- === NETWORK EVENTS INITIALIZATION ===
local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- === INTERCEPT NETWORK EVENTS ===
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
                if type(arg) == "string" and arg:lower() == "typingevent" then
                    isTypingEvent = true
                    break
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
                            confirmWordUsed(currentTypingBuffer)
                            currentTypingBuffer = ""
                        end
                        break
                    end
                end
            end
        end)
    end
end

-- === DYNAMIC GC FUNCTION SEARCH (FAST, SAFE & SELF-RESETTING) ===
local activeUpdateFn = nil

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
    if not fn or not isValidStructure(fn) then return false end
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
        local isStuck = false
        pcall(function()
            for _, vv in pairs(debug_getupvalues(activeUpdateFn)) do
                if type(vv) == "table" and vv.Prompt ~= nil then
                    if type(vv.Prompt) == "string" and vv.Prompt:lower():find("waiting") then
                        isStuck = true
                    end
                end
            end
        end)
        
        if not isStuck then
            return activeUpdateFn
        end
    end

    activeUpdateFn = nil
    local foundFns = {}
    
    for _, v in pairs(getgc()) do
        if isValidStructure(v) and isFnAlive(v) then
            table_insert(foundFns, v)
        end
    end
    
    for i = #foundFns, 1, -1 do
        local fn = foundFns[i]
        local promptText = ""
        pcall(function()
            for _, vv in pairs(debug_getupvalues(fn)) do
                if type(vv) == "table" and vv.Prompt ~= nil then 
                    promptText = tostring(vv.Prompt):lower()
                end
            end
        end)
        
        if not string_find(promptText, "waiting") then
            activeUpdateFn = fn
            print("🔍 [DEBUG - GC]: Switched to NEW frame function.")
            return fn
        end
    end
    
    if #foundFns > 0 then
        activeUpdateFn = foundFns[#foundFns]
        return activeUpdateFn
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

-- === FUSE DELAY LOGIC ===
local function waitFuseProgress(localToken)
    if not useFuseProgress then return end

    local tbl = getInfoTable()
    
    if not tbl or not tbl.FuseStart or tbl.FuseStart <= 1000 or not tbl.FuseRate or tbl.FuseRate == 0 then
        if fallbackDelaySeconds > 0 and not instanttype then
            task_wait(applyRandomVariation(fallbackDelaySeconds, rngVariationPercent))
        end
        return
    end

    local fuseStart = tbl.FuseStart
    local fuseRate = tbl.FuseRate
    
    local fuseDurationSeconds = math.abs(1 / fuseRate)
    local targetWaitSeconds = math.max(0, (fuseDurationSeconds * fusePercent) - 0.05)

    local localStart = os_clock()

    while isOperationValid(localToken) do
        local tblCurrent = getInfoTable()
        if not tblCurrent or tblCurrent.FuseStart ~= fuseStart then break end

        local elapsed = os_clock() - localStart

        currentFusionStats = string.format("%.2fs / %.2fs", math.min(elapsed, fuseDurationSeconds), fuseDurationSeconds)
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
    activeUpdateFn = nil 
    cancelCurrentOperation()
    resetWordStates()
    
    lastHandledPrompt = ""
    lastFuseStart = 0
    wasMyTurn = false
    isSubmitting = false

    if promptLabel then promptLabel:Set("Current Prompt: Waiting...") end
    if solutionsLabel then solutionsLabel:Set("Solutions Found: 0") end
    if matchLabel then matchLabel:Set("Current Match: Waiting...") end
    if fusionLabel then fusionLabel:Set("Fusion Progress: 0.00s / 0.00s") end
end

-- === CORE DATA GETTERS ===
local function GetLetters()
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

    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, guiName in ipairs({"GameUI", "DesktopUI", "MobileUI", "PlayerGui"}) do
            local target = playerGui:FindFirstChild(guiName) or playerGui
            local promptLbl = target:FindFirstChild("PromptLabel", true) or target:FindFirstChild("Prompt", true)
            if promptLbl and promptLbl:IsA("TextLabel") and promptLbl.Visible and promptLbl.Text ~= "" then
                return promptLbl.Text
            end
        end
    end

    return nil
end

local function GetTurn()
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

local function getGameStatus()
    local rawPrompt = GetLetters()
    if not rawPrompt or type(rawPrompt) ~= "string" then return nil, false end

    local prompt = rawPrompt:lower():gsub("%s+", "")
    if prompt == "" or prompt == "waiting" or prompt == "waiting..." then return nil, false end

    local localPlayer = Players.LocalPlayer
    if not localPlayer then return nil, false end

    local currentTurnId = GetTurn()
    local isMyTurn = (currentTurnId == localPlayer.UserId)

    if currentTurnId == nil then
        local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
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
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return nil end
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end
    for _, v in pairs(playerGui:GetDescendants()) do
        if v:IsA("TextBox") and v.Visible and v.Parent and v.Parent.Name ~= "Rayfield" then return v end
    end
    return nil
end

-- === TYPING LOGIC (WITH CANCELLATION TOKEN & CHAT PROTECTION) ===
local function typeWordMobile(word, targetPrompt)
    local token = cancelCurrentOperation()
    markWordPending(word)

    print("⌨️ [Type Process]: Starting typing for word: " .. tostring(word))

    if not instanttype then 
        if useFuseProgress then
            waitFuseProgress(token)
        elseif fallbackDelaySeconds > 0 then 
            local finalDelay = applyRandomVariation(fallbackDelaySeconds, rngVariationPercent)
            task_wait(finalDelay) 
        end
    end
    
    if not isOperationValid(token) then
        print("⚠️ [Type Process]: Cancelled due to token generation mismatch.")
        clearPendingWord(word)
        return
    end

    if not is_window_active() then
        print("⚠️ [Focus]: Window lost focus! Cancelling typing.")
        clearPendingWord(word)
        return
    end

    local focusedBox = UserInputService:GetFocusedTextBox()
    if focusedBox and focusedBox ~= getGameTextBox() then
        print("💬 [Chat Protect]: Chat box in use! Cancelling auto-type.")
        clearPendingWord(word)
        return
    end

    local currentPrompt, isMyTurn = getGameStatus()
    if currentPrompt ~= targetPrompt or not isMyTurn then
        print("⚠️ [Type Process]: Turn or prompt changed before typing started.")
        clearPendingWord(word)
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
        if not isOperationValid(token) or not is_window_active() then 
            interrupted = true
            break 
        end

        local activeBox = UserInputService:GetFocusedTextBox()
        if activeBox and activeBox ~= textBox then
            interrupted = true
            break
        end

        local checkPrompt, checkTurn = getGameStatus()
        if checkPrompt ~= targetPrompt or not checkTurn then 
            interrupted = true
            break 
        end
        
        local char = string_sub(word, i, i)
        local keyCode = (char == "-") and Enum.KeyCode.Minus 
            or (char == "'") and Enum.KeyCode.Quote 
            or Enum.KeyCode[char:upper()]
        
        if keyCode then
            local currentDelay = 0
            if not instanttype then
                currentDelay = getCharacterDelay(
                    speedWordDelaySeconds, 
                    jitterEnabled, 
                    jitterSeconds, 
                    rngVariationPercent
                )
            end
            
            if i == 1 and textBox and textBox.Text ~= "" then textBox.Text = "" end
            
            Vim:SendKeyEvent(true, keyCode, false, game)
            if currentDelay > 0 then task_wait(currentDelay / 2) end
            Vim:SendKeyEvent(false, keyCode, false, game)
            if currentDelay > 0 then task_wait(currentDelay / 2) end
        end
    end
    
    if not interrupted and isOperationValid(token) then
        local finalPrompt, finalTurn = getGameStatus()
        if finalPrompt == targetPrompt and finalTurn then
            isSubmitting = true 

            if not instanttype then task_wait(0.02) end
            Vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
            if not instanttype then task_wait(0.01) end
            Vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
            if not instanttype then task_wait(0.03) end
            
            totalTurns += 1
            if turnsLabel then turnsLabel:Set("Total Turns: " .. totalTurns) end
            print("✅ [Type Process]: Submitted word: " .. tostring(word))
        else
            if textBox then textBox.Text = "" end
            clearPendingWord(word)
            isSubmitting = false
        end
    else
        clearPendingWord(word)
        isSubmitting = false
    end
end

-- === WORD SEARCH LOGIC WITH PRIORITY & CHAT SAFEGUARD ===
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

    local focusedBox = UserInputService:GetFocusedTextBox()
    if isSubmitting or (focusedBox and focusedBox ~= getGameTextBox()) then 
        return 
    end

    wasMyTurn = true

    if contains ~= lastHandledPrompt or (lastFuseStart > 0 and currentFuseStart ~= lastFuseStart) or bruteforce then
        lastHandledPrompt = contains
        lastFuseStart = currentFuseStart
        print("🎯 [Search]: New turn detected! Prompt: " .. tostring(contains))
        
        if promptLabel then promptLabel:Set("Current Prompt: " .. contains:upper()) end

        local promptLower = contains:lower()
        local candidates = PromptIndex[promptLower]
        
        local currentMode = wordPriorityMode
        if type(currentMode) == "table" then
            currentMode = currentMode[1] or "Hyphenated / Short"
        end

        local finalword, validCount = chooseCandidate(candidates, currentMode, lettercap)

        if solutionsLabel then solutionsLabel:Set("Solutions Found: " .. validCount) end

        if finalword then
            if matchLabel then matchLabel:Set("Current Match: " .. finalword:upper()) end
            print("💡 [Search]: Picked word: " .. tostring(finalword) .. " (Mode: " .. tostring(currentMode) .. ")")
            
            if autotype and isMyTurn then
                task_spawn(function()
                    typeWordMobile(finalword, promptLower)
                end)
            end
        else
            if matchLabel then matchLabel:Set("Current Match: Not Found") end
            print("❌ [Search]: No available words found for prompt: " .. tostring(contains))
            lastHandledPrompt = ""
        end
    end
end

-- === UI ELEMENTS (MAIN TAB) ===
MainTab:CreateInput({
   Name = "Letter Cap",
   PlaceholderText = "Enter max letter count...",
   Callback = function(Text) lettercap = tonumber(Text) or math_huge end,
})

local searchWorkerRunning = false

MainTab:CreateToggle({
   Name = "Auto Search",
   CurrentValue = false,
   Callback = function(Value)
      autosearch = Value
      if autosearch and not searchWorkerRunning then
          searchWorkerRunning = true
          print("▶️ [Auto Search]: Worker Started")
          
          task_spawn(function()
              local waitingCounter = 0
              while autosearch do 
                  task_wait(0.15)
                  
                  local currentPrompt = GetLetters()
                  if currentPrompt == nil or currentPrompt:lower():find("waiting") then
                      waitingCounter += 1
                      if waitingCounter >= 6 then
                          activeUpdateFn = nil 
                          waitingCounter = 0
                      end
                  else
                      waitingCounter = 0
                  end

                  safeExecute("AutoSearch", copyword)
              end
              searchWorkerRunning = false
              print("⏹️ [Auto Search]: Worker Stopped")
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

local autoJoinWorkerRunning = false

MainTab:CreateToggle({
    Name = "Auto Join Game",
    CurrentValue = false,
    Callback = function(Value)
        autojoin = Value
        if autojoin and Games and not autoJoinWorkerRunning then
            autoJoinWorkerRunning = true
            task_spawn(function()
                if autoJoinDelay > 0 then task_wait(autoJoinDelay) end
                resetRoundState()
                safeExecute("AutoJoin", function()
                    print("🚪 [AutoJoin]: Attempting to join game...")
                    for i = -1, -20, -1 do 
                        Games.GameEvent:FireServer(i, "JoinGame") 
                    end
                end)
                autoJoinWorkerRunning = false
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
   Options = {"Rare Words", "Hyphenated / Short", "Shortest", "Longest", "Random"},
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
   Callback = function(Value) fallbackDelaySeconds = Value / 10 end,
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
      speedWordDelaySeconds = 60 / (typingWPM * 5)
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
   Callback = function(Value) jitterSeconds = Value / 1000 end,
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

-- === BACKGROUND AUTO JOIN THREAD ===
if Games then
    local registerGame = Games:FindFirstChild("RegisterGame")
    if registerGame then
        registerGame.OnClientEvent:Connect(function(gameRoomID)
            print("📩 [Network]: RegisterGame Event Fired for RoomID: " .. tostring(gameRoomID))
            resetRoundState()
            
            task.delay(1, function()
                activeUpdateFn = nil
            end)

            if autojoin and not autoJoinWorkerRunning then 
                autoJoinWorkerRunning = true
                task_spawn(function()
                    if autoJoinDelay > 0 then task_wait(autoJoinDelay) end
                    safeExecute("RegisterGameJoin", function()
                        Games.GameEvent:FireServer(gameRoomID, "JoinGame") 
                    end)
                    autoJoinWorkerRunning = false
                end)
            end
        end)
    end
end

-- === TIMER LOOP ===
task_spawn(function()
    while task_wait(1) do
        local elapsed = os_time() - startTime
        if elapsedLabel then
            elapsedLabel:Set("Elapsed Time: " .. formatElapsedTime(elapsed))
        end
    end
end)
