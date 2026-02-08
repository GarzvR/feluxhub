if getgenv().fishingStart then
    getgenv().fishingStart = false
    task.wait(0.5)
end

local CoreGui = game:GetService("CoreGui")
local GUI_NAMES = {
    Main = "Felux_Fishing_UI",
    Mobile = "Felux_Mobile_Button",
    Coords = "Felux_Coords_HUD",
    ToggleButton = "Felux_Toggle_Button"
}

for _, v in pairs(CoreGui:GetChildren()) do
    for _, name in pairs(GUI_NAMES) do
        if v.Name == name then v:Destroy() end
    end
end

for _, v in pairs(CoreGui:GetDescendants()) do
    if v:IsA("ScreenGui") and v.Name == "FeluxHub" then
        v:Destroy()
    end
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local SettingsState = { 
    FPSBoost = { Active = false, BackupLighting = {} }, 
    VFXRemoved = false,
    DestroyerActive = false,
    PopupDestroyed = false,
    AutoSell = {
        TimeActive = false,
        TimeInterval = 60,
        CountActive = false,
        CountThreshold = 50, 

        IsSelling = false
    },
    AutoWeather = {
        Active = false,
        Targets = {} 
    },
    PosWatcher = { Active = false, Connection = nil },
    WaterWalk = { Active = false, Part = nil, Connection = nil },
    AnimsDisabled = { Active = false, Connections = {} },
    AutoEventDisco = { Active = false },
    AutoFavorite = {
        Active = false,
        Rarities = {}
    },
    InfiniteJump = false,
    Noclip = false,
    AutoEquipRod = false,
}

local rs = game:GetService("ReplicatedStorage")
local net = rs:FindFirstChild("Packages") and rs.Packages:FindFirstChild("_Index") 
    and rs.Packages["_Index"]:FindFirstChild("sleitnick_net@0.2.0") 
    and rs.Packages["_Index"]["sleitnick_net@0.2.0"].net

if not net then warn("Net library not found, some features might break.") end

local ChargeRod    = net and net:FindFirstChild("RF/ChargeFishingRod")
local RequestGame  = net and net:FindFirstChild("RF/RequestFishingMinigameStarted")
local CompleteGame = net and net:FindFirstChild("RF/CatchFishCompleted")
local CancelInput  = net and net:FindFirstChild("RF/CancelFishingInputs")
local SellAll      = net and net:FindFirstChild("RF/SellAllItems") 
local EquipTank    = net and net:FindFirstChild("RF/EquipOxygenTank")
local UpdateRadar  = net and net:FindFirstChild("RF/UpdateFishingRadar")

task.spawn(function()
    while task.wait(1) do
        if SettingsState.AutoEquipRod then
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("Humanoid") then
                local equipped = char:FindFirstChildOfClass("Tool")

                if not (equipped and equipped.Name:lower():find("rod")) then

                    local backpack = LocalPlayer.Backpack
                    for _, tool in ipairs(backpack:GetChildren()) do
                        if tool:IsA("Tool") and tool.Name:lower():find("rod") then
                            char.Humanoid:EquipTool(tool)
                            break
                        end
                    end
                end
            end
        end
    end
end)

local function ToggleFPSBoost(state)
    if state then
        pcall(function()
            settings().Rendering.QualityLevel = 1
            game:GetService("Lighting").GlobalShadows = false
        end)
        for _, v in pairs(game:GetDescendants()) do
            if v:IsA("BasePart") then v.Material = Enum.Material.Plastic; v.CastShadow = false end
        end
    end
end

local function StartAutoSellLoop()
    task.spawn(function()
        while true do
            task.wait(1) 

            if SettingsState.AutoSell.TimeActive then

            end

            if SettingsState.AutoSell.CountActive then
                local backpack = LocalPlayer:FindFirstChild("Backpack")
                if backpack and #backpack:GetChildren() >= SettingsState.AutoSell.CountThreshold then
                    pcall(function() if SellAll then SellAll:InvokeServer() end end)
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            if SettingsState.AutoSell.TimeActive then
                task.wait(SettingsState.AutoSell.TimeInterval)
                if SettingsState.AutoSell.TimeActive then
                     pcall(function() if SellAll then SellAll:InvokeServer() end end)
                end
            else
                task.wait(1)
            end
        end
    end)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VFXFolder = ReplicatedStorage:FindFirstChild("VFX")
local DiveThrowVFX = { Active = false, Connections = {} }

local function HasDiveOrThrowAncestor(obj)
    return true 
end

local function DisableVisual(obj)
    if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
        obj.Enabled = false
    end
end

local function RestoreVisual(obj)
    if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
        obj.Enabled = true
    end
end

local function ApplyVFXHandler(handler)
    if not VFXFolder then return end
    for _, obj in ipairs(VFXFolder:GetDescendants()) do
        handler(obj)
    end
end

local function ToggleVFX(state)
    DiveThrowVFX.Active = state
    if state then
        ApplyVFXHandler(DisableVisual)
        DiveThrowVFX.Connections[#DiveThrowVFX.Connections + 1] = VFXFolder.DescendantAdded:Connect(function(child)
            task.wait()
            if DiveThrowVFX.Active then DisableVisual(child) end
        end)
    else
        ApplyVFXHandler(RestoreVisual)
        for _, conn in ipairs(DiveThrowVFX.Connections) do conn:Disconnect() end
        table.clear(DiveThrowVFX.Connections)
    end
end

local WATER_Y_LEVEL = nil
local WATER_OFFSET = 0.1 

local function DetectWaterLevel(hrp)
    return hrp.Position.Y - 2
end

local function ToggleWaterWalk(state)
    SettingsState.WaterWalk.Active = state

    if state then
        if SettingsState.WaterWalk.Part then return end
        local char = Players.LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        WATER_Y_LEVEL = DetectWaterLevel(hrp)
        local platform = Instance.new("Part")
        platform.Name = "Felux_WaterPlatform"
        platform.Size = Vector3.new(18, 1, 18)
        platform.Anchored = true
        platform.CanCollide = true
        platform.Transparency = 1
        platform.Material = Enum.Material.SmoothPlastic
        platform.Parent = Workspace
        SettingsState.WaterWalk.Part = platform

        SettingsState.WaterWalk.Connection = RunService.Heartbeat:Connect(function()
            local charNow = Players.LocalPlayer.Character
            if not charNow then return end
            local hrpNow = charNow:FindFirstChild("HumanoidRootPart")
            if not hrpNow then return end
            platform.CFrame = CFrame.new(hrpNow.Position.X, WATER_Y_LEVEL + WATER_OFFSET, hrpNow.Position.Z)
        end)
    else
        if SettingsState.WaterWalk.Connection then
            SettingsState.WaterWalk.Connection:Disconnect()
            SettingsState.WaterWalk.Connection = nil
        end
        if SettingsState.WaterWalk.Part then
            SettingsState.WaterWalk.Part:Destroy()
            SettingsState.WaterWalk.Part = nil
        end
        WATER_Y_LEVEL = nil
    end
end

game:GetService("UserInputService").JumpRequest:Connect(function()
    if SettingsState.InfiniteJump then
        LocalPlayer.Character:FindFirstChildOfClass('Humanoid'):ChangeState("Jumping")
    end
end)

RunService.Stepped:Connect(function()
    if SettingsState.Noclip then
        if LocalPlayer.Character then
            for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
                if v:IsA("BasePart") and v.CanCollide == true then
                    v.CanCollide = false
                end
            end
        end
    end
end)

local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/refs/heads/main/dist/main.lua"))()

local Window = WindUI:CreateWindow({
    Title = "Felux Hub",
    Icon = "rbxassetid://82723545384166",
    Folder = "FeluxHub",
    Size = UDim2.fromOffset(580, 460),
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 200,
    HasOutline = true,
    Author = "FeluxHub | Free",
    Badge = {
        Text = "FREE",
        TextColor = Color3.fromRGB(255, 255, 0),
    },
    ButtonStyle = "MacOS",
})

local ToggleGui = Instance.new("ScreenGui")
ToggleGui.Name = "Felux_Toggle_Button"
ToggleGui.Parent = CoreGui

local ToggleBtn = Instance.new("ImageButton")
ToggleBtn.Name = "ToggleBtn"
ToggleBtn.Parent = ToggleGui
ToggleBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.BackgroundTransparency = 1.000
ToggleBtn.Position = UDim2.new(0.12, 0, 0.095, 0)
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Image = "rbxassetid://82723545384166"
ToggleBtn.Draggable = true
ToggleBtn.Active = true
ToggleBtn.MouseButton1Click:Connect(function()
    Window:Toggle()
end)

local Tabs = {
    Info = Window:Tab({ Title = "Info", Icon = "info" }),
    Main = Window:Tab({ Title = "Main", Icon = "house" }),
    Auto = Window:Tab({ Title = "Auto", Icon = "gamepad-2" }),
    Player = Window:Tab({ Title = "Player", Icon = "user" }),
    Shop = Window:Tab({ Title = "Shop", Icon = "shopping-cart" }),
    Teleport = Window:Tab({ Title = "Teleport", Icon = "map-pin" }),
    Settings = Window:Tab({ Title = "Settings", Icon = "settings" }),
    Config = Window:Tab({ Title = "Config", Icon = "save" }),
}

local InfoSection = Tabs.Info:Section({ Title = "Community Support" })
InfoSection:Button({
    Title = "Discord",
    Description = "click to copy link",
    Callback = function()
        setclipboard("https://discord.gg/6BWXVTuM6M")
        WindUI:Notify({ Title = "Copied!", Content = "Discord link copied to clipboard.", Duration = 3 })
    end,
})

local UpdateSection = Tabs.Info:Section({ Title = "Update" })
UpdateSection:Paragraph({
    Title = "Update Log",
    Content = "Every time there is a game update or someone reports something, I will fix it as soon as possible."
})

local FishingSection = Tabs.Main:Section({ Title = "Fishing" })
local AutoRod, FishingMode, AutoFarm = false, "Legit", false
local FishingDelay = 1.0

FishingSection:Toggle({ Title = "Auto Rod", Description = "Automatically casts and reels.", Default = false, Callback = function(v) AutoRod = v end })
FishingSection:Toggle({ Title = "Auto Equip Rod", Description = "Automatically equips rod if not held.", Default = false, Callback = function(v) SettingsState.AutoEquipRod = v end }) 

FishingSection:Dropdown({ Title = "Mode", Description = "Select fishing mode.", Multi = false, AllowNone = false, Values = {"Legit", "Instant", "Perfect"}, Default = "Legit", Callback = function(v) FishingMode = v end })
FishingSection:Toggle({ Title = "Auto Farm", Description = "Enable auto farming features.", Default = false, Callback = function(v) AutoFarm = v end })
FishingSection:Input({ Title = "Fishing Delay", Description = "Delay between actions.", Default = "1.0", Placeholder = "Contoh: 1.0", Callback = function(t) FishingDelay = tonumber(t) or 1.0 end })

local RecoverySection = Tabs.Main:Section({ Title = "Recovery Fishing" })
RecoverySection:Button({ Title = "Recovery Fishing", Description = "Fix stuck fishing & reset state.", Callback = function() 
    getgenv().fishingStart = false
end })

local CrystalSection = Tabs.Auto:Section({ Title = "Crystal" })
CrystalSection:Toggle({ Title = "Auto Use Cave Crystal", Default = false, Callback = function(v) end })

local DepthsSection = Tabs.Auto:Section({ Title = "Auto Crystal Depths" })
DepthsSection:Toggle({ Title = "Auto Crystal Depths", Default = false, Callback = function(v) end })
DepthsSection:Button({ Title = "Test Equip Pickaxe", Callback = function() end })

local QuestSection = Tabs.Auto:Section({ Title = "Auto Quest" })
QuestSection:Toggle({ Title = "Auto Deep Sea Quest", Default = false, Callback = function(v) end })
QuestSection:Toggle({ Title = "Auto Element Quest", Default = false, Callback = function(v) end })
QuestSection:Toggle({ Title = "Auto Diamond Quest", Default = false, Callback = function(v) end })

local TradeSection = Tabs.Auto:Section({ Title = "Auto Trade" })
TradeSection:Paragraph({ Title = "Trade Status", Content = "Progress : Idle" })
TradeSection:Dropdown({ Title = "Select Item", Multi = false, AllowNone = true, Values = {"Item A", "Item B"}, Default = "None", Callback = function(v) end })
TradeSection:Input({ Title = "Amount to Trade", Default = "1", Placeholder = "Amount...", Callback = function(t) end })
TradeSection:Button({ Title = "Refresh Fish", Callback = function() end })
TradeSection:Button({ Title = "Refresh Stone", Callback = function() end })

local TradePlayerDropdown = TradeSection:Dropdown({ 
    Title = "Select Player", 
    Multi = false, 
    Values = {}, 

    Default = "None", 
    Callback = function(v) end 
})

TradeSection:Button({ 
    Title = "Refresh Player", 
    Callback = function() 
        local names = {}
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(names, p.Name) end
        end
        TradePlayerDropdown:SetValues(names)
    end 
})

TradeSection:Toggle({ Title = "Auto Trade", Default = false, Callback = function(v) end })
TradeSection:Toggle({ Title = "Auto Accept Trade", Default = false, Callback = function(v) end })

local SellSection = Tabs.Auto:Section({ Title = "Selling" })
SellSection:Toggle({ 
    Title = "Auto Sell (Time)", 
    Default = false, 
    Callback = function(v) 
        SettingsState.AutoSell.TimeActive = v 
    end 
})
SellSection:Input({ 
    Title = "Sell Interval", 
    Default = "60", 
    Placeholder = "Seconds", 
    Callback = function(t) 
        SettingsState.AutoSell.TimeInterval = tonumber(t) or 60 
    end 
})

SellSection:Toggle({ 
    Title = "Auto Sell (Count)", 
    Default = false, 
    Callback = function(v) 
        SettingsState.AutoSell.CountActive = v 
    end 
})
SellSection:Input({ 
    Title = "Sell Count Threshold", 
    Default = "50", 
    Placeholder = "Items count...", 
    Callback = function(t) 
        SettingsState.AutoSell.CountThreshold = tonumber(t) or 50 
    end 
})

local EnchantSection = Tabs.Auto:Section({ Title = "Enchant Features" })
EnchantSection:Paragraph({ Title = "Enchanting Features", Content = "Rod Active = Element Rod\nEnchant Now = Reeler II\nStone Left = <font color='#FFFF00'>547</font>\nStone Type = <font color='#00FF00'>Enchant Stones</font>" })
EnchantSection:Dropdown({ 
    Title = "Enchant Stone Type", 
    Multi = false, 
    Values = {"Enchant Stones", "Evolved Enchant Stone"}, 

    Default = "Enchant Stones", 
    Callback = function(v) end 
})
EnchantSection:Button({ Title = "Teleport to Altar", Callback = function() end })
EnchantSection:Button({ Title = "Teleport to Second Altar", Callback = function() end })

local BasicEnchants = {
    "Mutation Hunter I", "Mutation Hunter II", "Gold Digger I", "Cursed I", "Glistening I",
    "Leprechaun I", "Leprechaun II", "Stormhunter I", "Stargazer I", "Empowered I",
    "XPerienced I", "Prismatic I", "Reeler I", "Big Hunter I"
}
local EvolvedEnchants = {
    "SECRET Hunter", "Shark Hunter", "Prismatic I", "Cursed I", "Stargazer II",
    "Gold Digger I", "Empowered I", "Fairy Hunter I", "Stormhunter II",
    "Mutation Hunter II", "Leprechaun II", "Reeler II", "Mutation Hunter III"
}

EnchantSection:Dropdown({ Title = "Target Enchant (Basic)", Multi = true, Values = BasicEnchants, Default = {}, Callback = function(v) end })
EnchantSection:Dropdown({ Title = "Target Enchant (Evolved)", Multi = true, Values = EvolvedEnchants, Default = {}, Callback = function(v) end })
EnchantSection:Toggle({ Title = "Auto Enchant", Default = false, Callback = function(v) end })
EnchantSection:Button({ Title = "Start Double Enchant", Callback = function() end })

local PlayerSection = Tabs.Player:Section({ Title = "Local Player" })

PlayerSection:Input({
    Title = "WalkSpeed",
    Default = "16",
    Placeholder = "Contoh: 18",
    Callback = function(Text)
        local val = tonumber(Text)
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = val
        end
    end
})

PlayerSection:Input({
    Title = "JumpPower",
    Default = "50",
    Placeholder = "Contoh: 50",
    Callback = function(Text)
        local val = tonumber(Text)
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.JumpPower = val
        end
    end
})

PlayerSection:Toggle({ Title = "Infinite Jump", Default = false, Callback = function(v) SettingsState.InfiniteJump = v end })
PlayerSection:Toggle({ Title = "Noclip", Default = false, Callback = function(v) SettingsState.Noclip = v end })
PlayerSection:Toggle({ Title = "Radar", Default = false, Callback = function(v) 
    if v and UpdateRadar then UpdateRadar:InvokeServer() end
end })
PlayerSection:Toggle({ Title = "Diving Gear", Default = false, Callback = function(v) 
    if v and EquipTank then EquipTank:InvokeServer() end
end })
PlayerSection:Button({ Title = "FlyGui V3", Callback = function() 
    loadstring(game:HttpGet("https://raw.githubusercontent.com/XNEOFF/FlyGuiV3/main/FlyGuiV3.lua"))()
end })

local ShopSection = Tabs.Shop:Section({ Title = "Items" })

local RodsList = {
    "Luck Rod", "Carbon Rod", "Grass Rod", "Damascus Rod", "Ice Rod", 
    "Lucky Rod", "Midnight Rod", "Steampunk Rod", "Chrome Rod", 
    "Fluorescent Rod", "Astral Rod", "Hazmat Rod", "Ares Rod", 
    "Angler Rod", "Bamboo Rod"
}
local selectedRod = RodsList[1]

ShopSection:Dropdown({ 
    Title = "Select Rod", 
    Multi = false, 
    Values = RodsList, 
    Default = RodsList[1], 
    Callback = function(v) selectedRod = v end 
})
ShopSection:Button({ Title = "Buy Rod", Callback = function() 

    print("Buying " .. selectedRod) 
end })

local BaitsList = {
    "Topwater Bait", "Luck Bait", "Midnight Bait", "Nature Bait", 
    "Chroma Bait", "Royal Bait", "Dark Matter Bait", "Corrupt Bait", 
    "Aether Bait", "Floral Bait", "Singularity Bait"
}
local selectedBait = BaitsList[1]

ShopSection:Dropdown({ 
    Title = "Select Bait", 
    Multi = false, 
    Values = BaitsList, 
    Default = BaitsList[1], 
    Callback = function(v) selectedBait = v end 
})
ShopSection:Button({ Title = "Buy Bait", Callback = function() 

    print("Buying " .. selectedBait) 
end })

local selectedWeather = "None"
local autoBuyWeather = false
ShopSection:Dropdown({ Title = "Select Weather Events", Multi = false, AllowNone = true, Values = {"Wind", "Cloudy", "Snow", "Storm", "Radiant", "Shark Hunt"}, Default = "None", Callback = function(v) selectedWeather = v end })
ShopSection:Toggle({ Title = "Auto Buy Selected Weathers", Default = false, Callback = function(v) autoBuyWeather = v end })

local TpLocation = "Area 1"
local TeleportSection = Tabs.Teleport:Section({ Title = "Teleports" })
local TP_SPOTS = {
    ["Area 1"] = CFrame.new(100, 50, 100), 

    ["Area 2"] = CFrame.new(-100, 50, -100),
    ["Area 3"] = CFrame.new(0, 50, 0),
}

TeleportSection:Dropdown({ Title = "Select Island", Multi = false, Values = {"Area 1", "Area 2", "Area 3"}, Default = "Area 1", Callback = function(v) TpLocation = v end })
TeleportSection:Button({ Title = "Teleport to Island", Callback = function() 

    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and TP_SPOTS[TpLocation] then
        LocalPlayer.Character.HumanoidRootPart.CFrame = TP_SPOTS[TpLocation]
    end
end })

local tpPlayerName = ""
TeleportSection:Dropdown({ Title = "Select Player", Multi = false, Values = (function()
    local names = {}
    for _, p in pairs(Players:GetPlayers()) do table.insert(names, p.Name) end
    return names
end)(), Default = LocalPlayer.Name, Callback = function(v) tpPlayerName = v end })

TeleportSection:Button({ Title = "Teleport to Player", Callback = function() 
    local target = Players:FindFirstChild(tpPlayerName)
    if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        LocalPlayer.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame
    end
end })

local SettingsSection = Tabs.Settings:Section({ Title = "UI Settings" })
SettingsSection:Keybind({ Title = "Toggle UI", Default = Enum.KeyCode.RightControl, Callback = function() Window:Toggle() end })
SettingsSection:Toggle({ Title = "FPS Boost", Default = false, Callback = ToggleFPSBoost })
SettingsSection:Toggle({ Title = "Remove VFX", Default = false, Callback = function(v) ToggleVFX(v) end }) 
SettingsSection:Toggle({ Title = "Anti-AFK", Default = false, Callback = function(v) if v then StartAntiAFK() end end })
SettingsSection:Toggle({ Title = "Water Walk", Default = false, Callback = ToggleWaterWalk })

local ConfigSection = Tabs.Config:Section({ Title = "Configuration" })
local configName = "default"
local configFolder = "FeluxHub/Configs"

if not isfolder("FeluxHub") then makefolder("FeluxHub") end
if not isfolder(configFolder) then makefolder(configFolder) end

local function GetConfigFiles()
    local files = listfiles(configFolder)
    local names = {}
    for _, file in ipairs(files) do
        local name = file:match("([^/]+)%.json$")
        if name then table.insert(names, name) end
    end
    return names
end

local ConfigList = GetConfigFiles()

local ConfigDropdown = ConfigSection:Dropdown({ 
    Title = "Config List", 
    Multi = false, 
    Values = ConfigList, 
    Default = "None", 
    Callback = function(v) configName = v end 
})

ConfigSection:Input({
    Title = "Config Name",
    Default = "default",
    Placeholder = "Enter config name...",
    Callback = function(Text) configName = Text end
})

ConfigSection:Button({
    Title = "Save Config",
    Callback = function()
        local data = {
            AutoRod = AutoRod,
            FishingMode = FishingMode,
            FishingDelay = FishingDelay,
            SellInterval = SettingsState.AutoSell.TimeInterval,
            AutoSell = SettingsState.AutoSell.TimeActive,
            WalkSpeed = LocalPlayer.Character and LocalPlayer.Character.Humanoid.WalkSpeed or 16,
            JumpPower = LocalPlayer.Character and LocalPlayer.Character.Humanoid.JumpPower or 50
        }
        writefile(configFolder .. "/" .. configName .. ".json", game:GetService("HttpService"):JSONEncode(data))
        WindUI:Notify({ Title = "Config", Content = "Saved config: " .. configName, Duration = 3 })

        ConfigDropdown:SetValues(GetConfigFiles())
        ConfigDropdown:Select(configName) 
    end,
})

ConfigSection:Button({
    Title = "Load Config",
    Callback = function()
        if isfile(configFolder .. "/" .. configName .. ".json") then
            local data = game:GetService("HttpService"):JSONDecode(readfile(configFolder .. "/" .. configName .. ".json"))

            if data.FishingDelay then FishingDelay = data.FishingDelay end

            WindUI:Notify({ Title = "Config", Content = "Loaded config: " .. configName, Duration = 3 })
        else
            WindUI:Notify({ Title = "Config", Content = "Config not found!", Duration = 3 })
        end
    end,
})

ConfigSection:Button({
    Title = "Delete Config",
    Callback = function()
        if isfile(configFolder .. "/" .. configName .. ".json") then
            delfile(configFolder .. "/" .. configName .. ".json")
            WindUI:Notify({ Title = "Config", Content = "Deleted config: " .. configName, Duration = 3 })
            ConfigDropdown:SetValues(GetConfigFiles())
            ConfigDropdown:Select("None")
        end
    end,
})

task.spawn(function()
    while task.wait(0.1) do
        if AutoRod then
            local Character = LocalPlayer.Character
            if Character then
               local Tool = Character:FindFirstChildOfClass("Tool")
               if Tool and Tool.Name:lower():find("rod") then
                   task.wait(FishingDelay)
               end
            end
        end

        if autoBuyWeather and selectedWeather ~= "None" then
            print("Auto Buying Weather: " .. selectedWeather)
            task.wait(5) 

        end
    end
end)

StartAutoSellLoop()

WindUI:Notify({ Title = "Felux Hub", Content = "Script Loaded Successfully!", Duration = 5 })

