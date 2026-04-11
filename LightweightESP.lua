--[[
    Lightweight ESP v3.1 — by FusedHann
    ─────────────────────────────────────
    • Premium-grade ESP with Legit Aim Assist
    • Distance-based sorting (Bypasses 31-Highlight limit)
    • HSV Color Customization System
    • Visibility Raycasting & Wall Detection (workspace:Raycast)
    • 2D Bounding Boxes (Standard/Corner)
    • Smooth Aim Assist with Head/Body Targeting
    • Object-pooled, throttled rendering for maximum FPS
    • JSON Config Save/Load System
    ─────────────────────────────────────
    Changelog v3.1:
    [FIX] Replaced deprecated Ray.new/FindPartOnRayWithIgnoreList → workspace:Raycast
    [FIX] Highlight adornee caching (prevents redundant writes/micro-stutters)
    [FIX] Health bar fade consistency (unified fade rate)
    [FIX] Drag no longer sticks when mouse leaves window
    [NEW] Config tab: Save/Load settings as JSON profiles
]]

local SCRIPT_VERSION = "3.1"
local MAX_POOL = 24 -- max simultaneous tracked players

-- ═══════════════════════════════════════════════════════════
-- Services
-- ═══════════════════════════════════════════════════════════
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService  = game:GetService("TweenService")
local CoreGui       = game:GetService("CoreGui")
local HttpService   = game:GetService("HttpService")
local Lighting      = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════
-- Cleanup previous instance
-- ═══════════════════════════════════════════════════════════
local guiId = "ESP_LW_" .. tostring(math.random(1000,9999))
for _, c in ipairs(CoreGui:GetChildren()) do
    if c.Name:sub(1,6) == "ESP_LW" then pcall(function() c:Destroy() end) end
end

-- ═══════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════
local running    = true
local connections = {}

pcall(function()
    if not isfolder("LightweightESP") then makefolder("LightweightESP") end
    if not isfolder("LightweightESP/Configs") then makefolder("LightweightESP/Configs") end
end)

local settings = {
    enabled      = true,
    tracers      = true,
    healthBars   = true,
    boxes        = false,
    boxType      = "Standard", -- Standard, Corner
    highlight    = true,  -- full-body outline
    radar        = true,
    names        = true,
    distance     = true,
    visibleOnly  = false,
    teamCheck    = true,  -- exclude own team
    teamColor    = false, -- use team color instead of chamsColor
    maxDistance  = 500,   -- studs
    chamsFill    = 0.5,
    chamsOutline = 0.0,
    chamsDepth   = true,  -- true = AlwaysOnTop
    chamsColor   = Color3.fromRGB(0, 170, 255),
    zoomEnabled  = true,
    zoomFOV      = 30,
    fullbright   = false,
    fbAmount     = 0.7,
    removeFog    = false,
    aimEnabled   = false,
    aimTarget    = "Head", -- Head, Body
    aimFOV       = 100,
    aimSmooth    = 5,
}

local keybinds = {
    toggle = Enum.KeyCode.H,
    hide   = Enum.KeyCode.RightShift,
    zoom   = Enum.KeyCode.Z,
    aim    = Enum.UserInputType.MouseButton2,
}
local waitingForBind = nil

-- ═══════════════════════════════════════════════════════════
-- Color Palette (Vibrant Navy & Electric Blue Theme)
-- ═══════════════════════════════════════════════════════════
local C = {
    bg           = Color3.fromRGB(15, 20, 35),
    bgSec        = Color3.fromRGB(25, 30, 45),
    surface      = Color3.fromRGB(35, 45, 65),
    surfHover    = Color3.fromRGB(50, 65, 95),
    accent       = Color3.fromRGB(0, 170, 255),
    accentGlow   = Color3.fromRGB(0, 200, 255),
    green        = Color3.fromRGB(50, 205, 50),
    red          = Color3.fromRGB(220, 20, 60),
    orange       = Color3.fromRGB(255, 160, 50),
    cyan         = Color3.fromRGB(0, 200, 255),
    magenta      = Color3.fromRGB(255, 60, 180),
    yellow       = Color3.fromRGB(255, 220, 50),
    textPri      = Color3.fromRGB(255, 255, 255),
    textMut      = Color3.fromRGB(170, 180, 200),
    divider      = Color3.fromRGB(0, 100, 200),
}

-- ═══════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════
local function tw(obj, props, dur, style, dir)
    local t = TweenService:Create(obj, TweenInfo.new(dur or 0.25, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
    t:Play(); return t
end

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p; return c
end

local function stroke(p, col, th)
    local s = Instance.new("UIStroke"); s.Color = col or C.divider; s.Thickness = th or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p; return s
end

local function pad(p, t, b, l, r)
    local u = Instance.new("UIPadding")
    u.PaddingTop = UDim.new(0,t or 0); u.PaddingBottom = UDim.new(0,b or 0)
    u.PaddingLeft = UDim.new(0,l or 0); u.PaddingRight = UDim.new(0,r or 0)
    u.Parent = p; return u
end

local function keyName(kc)
    local friendly = {
        LeftShift="L-Shift",RightShift="R-Shift",LeftControl="L-Ctrl",
        RightControl="R-Ctrl",LeftAlt="L-Alt",RightAlt="R-Alt",
        MouseButton1="MB1",MouseButton2="MB2",MouseButton3="MB3",
    }
    return friendly[kc.Name] or kc.Name
end

local function lerpColor(a, b, t)
    return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t)
end

local function healthColor(pct)
    if pct > 0.5 then return lerpColor(C.yellow, C.green, (pct-0.5)*2) end
    return lerpColor(C.red, C.yellow, pct*2)
end

-- ═══════════════════════════════════════════════════════════
-- Notifications & Overlays
-- ═══════════════════════════════════════════════════════════
local notifGui = Instance.new("ScreenGui")
notifGui.Name = guiId .. "_N"
notifGui.ResetOnSpawn = false; notifGui.DisplayOrder = 999
notifGui.IgnoreGuiInset = true; notifGui.Enabled = true
pcall(function() if typeof(syn)=="table" and syn.protect_gui then syn.protect_gui(notifGui) end end)
notifGui.Parent = CoreGui

local toast = Instance.new("Frame")
toast.Size = UDim2.new(0,200,0,26); toast.Position = UDim2.new(1,-210,0,12)
toast.BackgroundColor3 = C.bg; toast.BackgroundTransparency = 1; toast.BorderSizePixel = 0
toast.Visible = false; toast.Parent = notifGui; corner(toast,6); stroke(toast)

local tDot = Instance.new("Frame")
tDot.Size = UDim2.new(0,6,0,6); tDot.Position = UDim2.new(0,8,0.5,-3)
tDot.BackgroundColor3 = C.accent; tDot.BorderSizePixel = 0; tDot.Parent = toast; corner(tDot,3)

local tLbl = Instance.new("TextLabel")
tLbl.Size = UDim2.new(1,-24,1,0); tLbl.Position = UDim2.new(0,20,0,0)
tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = C.textPri
tLbl.Font = Enum.Font.Gotham; tLbl.TextSize = 11; tLbl.TextXAlignment = Enum.TextXAlignment.Left
tLbl.TextTruncate = Enum.TextTruncate.AtEnd; tLbl.Parent = toast

local nVer = 0
local function notify(msg, col, dur)
    if not running then return end
    col = col or C.accent; dur = dur or 2
    nVer = nVer + 1; local myV = nVer
    tLbl.Text = msg; tDot.BackgroundColor3 = col; toast.Visible = true
    toast.Position = UDim2.new(1,20,0,12)
    toast.BackgroundTransparency = 0.5; tLbl.TextTransparency = 0.5; tDot.BackgroundTransparency = 0.5
    tw(toast, {Position=UDim2.new(1,-210,0,12), BackgroundTransparency=0.05}, 0.25)
    tw(tLbl, {TextTransparency=0}, 0.2); tw(tDot, {BackgroundTransparency=0}, 0.2)
    task.spawn(function()
        task.wait(dur)
        if myV ~= nVer then return end
        pcall(function()
            tw(toast, {Position=UDim2.new(1,20,0,12), BackgroundTransparency=1}, 0.25)
            tw(tLbl, {TextTransparency=1}, 0.2); tw(tDot, {BackgroundTransparency=1}, 0.2)
            task.wait(0.3)
            if myV == nVer then toast.Visible = false end
        end)
    end)
end

local espGui = Instance.new("ScreenGui")
espGui.Name = guiId .. "_Overlay"; espGui.ResetOnSpawn = false; espGui.IgnoreGuiInset = true; espGui.Enabled = true
pcall(function() if typeof(syn)=="table" and syn.protect_gui then syn.protect_gui(espGui) end end)
espGui.Parent = CoreGui

local aimCircle = Instance.new("Frame")
aimCircle.Name = "AimCircle"; aimCircle.BackgroundColor3 = Color3.new(1,1,1); aimCircle.BackgroundTransparency = 1
aimCircle.BorderSizePixel = 0; aimCircle.AnchorPoint = Vector2.new(0.5,0.5); aimCircle.Visible = false
aimCircle.Parent = espGui
stroke(aimCircle, Color3.new(1,1,1), 1)
local fovCorner = Instance.new("UICorner"); fovCorner.CornerRadius = UDim.new(1,0); fovCorner.Parent = aimCircle

-- ═══════════════════════════════════════════════════════════
-- ESP Object Pool
-- ═══════════════════════════════════════════════════════════
local pool = {}
local function createEspSlot()
    local slot = {}
    slot.tracer = Instance.new("Frame")
    slot.tracer.BorderSizePixel = 0; slot.tracer.AnchorPoint = Vector2.new(0.5, 0.5)
    slot.tracer.Visible = false; slot.tracer.Parent = espGui

    slot.box = Instance.new("Frame")
    slot.box.BackgroundColor3 = Color3.new(1,1,1)
    slot.box.BackgroundTransparency = 1; slot.box.BorderSizePixel = 0
    slot.box.Visible = false; slot.box.Parent = espGui
    
    local bl, br, bt, bb = Instance.new("Frame", slot.box), Instance.new("Frame", slot.box), Instance.new("Frame", slot.box), Instance.new("Frame", slot.box)
    bl.Size=UDim2.new(0,1,1,0); br.Size=UDim2.new(0,1,1,0); br.Position=UDim2.new(1,-1,0,0)
    bt.Size=UDim2.new(1,0,0,1); bb.Size=UDim2.new(1,0,0,1); bb.Position=UDim2.new(0,0,1,-1)
    slot.boxSides = {bl, br, bt, bb}
    for _, s in ipairs(slot.boxSides) do s.BackgroundColor3 = Color3.new(1,1,1); s.BorderSizePixel = 0; stroke(s, Color3.new(0,0,0), 0.5) end

    slot.nameLabel = Instance.new("TextLabel")
    slot.nameLabel.Size = UDim2.new(0,120,0,16); slot.nameLabel.BackgroundTransparency = 1
    slot.nameLabel.Font = Enum.Font.GothamBold; slot.nameLabel.TextSize = 12
    slot.nameLabel.TextColor3 = Color3.new(1,1,1); slot.nameLabel.TextStrokeTransparency = 0.5
    slot.nameLabel.Visible = false; slot.nameLabel.Parent = espGui

    slot.distLabel = Instance.new("TextLabel")
    slot.distLabel.Size = UDim2.new(0,80,0,14); slot.distLabel.BackgroundTransparency = 1
    slot.distLabel.Font = Enum.Font.GothamMedium; slot.distLabel.TextSize = 10
    slot.distLabel.TextColor3 = Color3.new(1,1,1); slot.distLabel.TextStrokeTransparency = 0.5
    slot.distLabel.Visible = false; slot.distLabel.Parent = espGui

    slot.hpBg = Instance.new("Frame")
    slot.hpBg.Size = UDim2.new(0,40,0,4); slot.hpBg.BackgroundColor3 = Color3.new(0,0,0)
    slot.hpBg.BackgroundTransparency = 0.5; slot.hpBg.BorderSizePixel = 0
    slot.hpBg.Visible = false; slot.hpBg.Parent = espGui; corner(slot.hpBg, 2)
    
    slot.hpBar = Instance.new("Frame")
    slot.hpBar.Size = UDim2.new(1,0,1,0); slot.hpBar.BackgroundColor3 = C.green
    slot.hpBar.BorderSizePixel = 0; slot.hpBar.Parent = slot.hpBg; corner(slot.hpBar, 2)

    slot.highlight = Instance.new("Highlight")
    slot.highlight.FillColor = C.magenta; slot.highlight.OutlineColor = Color3.new(1,1,1)
    slot.highlight.Enabled = false; slot.highlight.Parent = espGui

    slot.radarDot = Instance.new("Frame")
    slot.radarDot.Size = UDim2.new(0,5,0,5); slot.radarDot.BackgroundColor3 = C.red
    slot.radarDot.BorderSizePixel = 0; slot.radarDot.AnchorPoint = Vector2.new(0.5,0.5)
    slot.radarDot.Visible = false; corner(slot.radarDot, 3); slot.radarDot.Parent = nil -- To be parented later

    return slot
end

for i = 1, MAX_POOL do pool[i] = createEspSlot() end

local function hideSlot(slot)
    slot.tracer.Visible = false
    slot.nameLabel.Visible = false; slot.distLabel.Visible = false
    slot.hpBg.Visible = false; slot.box.Visible = false
    slot.highlight.Enabled = false; slot.highlight.Adornee = nil
    slot.radarDot.Visible = false
end

-- ═══════════════════════════════════════════════════════════
-- Radar Frame
-- ═══════════════════════════════════════════════════════════
local RADAR_SIZE = 120
local radarFrame = Instance.new("Frame", espGui)
radarFrame.Name = "R"; radarFrame.Size = UDim2.new(0, RADAR_SIZE, 0, RADAR_SIZE)
radarFrame.Position = UDim2.new(0, 12, 1, -RADAR_SIZE - 12)
radarFrame.BackgroundColor3 = C.bg; radarFrame.BackgroundTransparency = 0.3
radarFrame.BorderSizePixel = 0; radarFrame.ClipsDescendants = true; radarFrame.Visible = settings.radar
corner(radarFrame, 8); stroke(radarFrame, C.accent, 1)

for _, cfg in ipairs({{UDim2.new(0.5,0,0,0), UDim2.new(0,1,1,0)}, {UDim2.new(0,0,0.5,0), UDim2.new(1,0,0,1)}}) do
    local l = Instance.new("Frame", radarFrame); l.Position = cfg[1]; l.Size = cfg[2]
    l.AnchorPoint = Vector2.new(0.5, 0.5); l.BackgroundColor3 = C.divider; l.BackgroundTransparency = 0.6; l.BorderSizePixel = 0
end

local myDot = Instance.new("Frame", radarFrame)
myDot.Size = UDim2.new(0,6,0,6); myDot.BackgroundColor3 = C.cyan; myDot.BorderSizePixel = 0
myDot.AnchorPoint = Vector2.new(0.5,0.5); myDot.Position = UDim2.new(0.5,0,0.5,0); corner(myDot, 3)

for _, slot in ipairs(pool) do slot.radarDot.Parent = radarFrame end

-- ═══════════════════════════════════════════════════════════
-- Core Render Engine
-- ═══════════════════════════════════════════════════════════
local wasFullbright, wasRemoveFog = false, false
local origAmb, origCSB, origCST, origFogE, origFogS
local frameSkip, THROTTLE = 0, 1

-- [FIX v3.1.2] Robust isVisible — filters nil values to avoid RaycastParams crash during respawn
local function isVisible(p, ignoreList)
    local camPos = Camera.CFrame.Position
    local dir = p - camPos
    local ok, result = pcall(function()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local safe = {}
        for _, v in ipairs(ignoreList or {}) do
            if v then table.insert(safe, v) end
        end
        params.FilterDescendantsInstances = safe
        return workspace:Raycast(camPos, dir, params)
    end)
    return (not ok) or result == nil
end

local function updateESP()
    frameSkip = frameSkip + 1
    if frameSkip < THROTTLE then return end
    frameSkip = 0

    if settings.fullbright then
        if not wasFullbright then wasFullbright = true; origAmb, origCSB, origCST = Lighting.Ambient, Lighting.ColorShift_Bottom, Lighting.ColorShift_Top end
        Lighting.Ambient = Color3.new(settings.fbAmount, settings.fbAmount, settings.fbAmount)
        Lighting.ColorShift_Bottom = Lighting.Ambient; Lighting.ColorShift_Top = Lighting.Ambient
    elseif wasFullbright then
        wasFullbright = false; Lighting.Ambient, Lighting.ColorShift_Bottom, Lighting.ColorShift_Top = origAmb, origCSB, origCST
    end

    if settings.removeFog then
        if not wasRemoveFog then wasRemoveFog = true; origFogE, origFogS = Lighting.FogEnd, Lighting.FogStart end
        Lighting.FogEnd, Lighting.FogStart = 9e9, 9e9
    elseif wasRemoveFog then
        wasRemoveFog = false; Lighting.FogEnd, Lighting.FogStart = origFogE, origFogS
    end

    if not settings.enabled then
        for i = 1, MAX_POOL do hideSlot(pool[i]) end
        radarFrame.Visible, aimCircle.Visible = false, false; return
    end
    radarFrame.Visible = settings.radar

    local cam = workspace.CurrentCamera
    if not cam then return end
    local vpSize, camCF, myPos, myTeam = cam.ViewportSize, cam.CFrame, cam.CFrame.Position, LocalPlayer.Team

    aimCircle.Visible = settings.aimEnabled
    if settings.aimEnabled then
        local mPos = UserInputService:GetMouseLocation()
        aimCircle.Position = UDim2.new(0, mPos.X, 0, mPos.Y)
        aimCircle.Size = UDim2.new(0, settings.aimFOV * 2, 0, settings.aimFOV * 2)
    end

    local targets = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer or (settings.teamCheck and myTeam and plr.Team == myTeam) then continue end
        local char = plr.Character
        local hrp, hum = char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 then
            local dist = (hrp.Position - myPos).Magnitude
            if dist <= settings.maxDistance then table.insert(targets, {p=plr, c=char, h=hrp, hum=hum, d=dist}) end
        end
    end
    table.sort(targets, function(a,b) return a.d < b.d end)

    local slotIdx = 0
    for i = 1, #targets do
        slotIdx = slotIdx + 1; if slotIdx > MAX_POOL then break end
        local data = targets[i]
        local plr, char, hrp, hum, dist = data.p, data.c, data.h, data.hum, data.d
        local s = pool[slotIdx]

        local rootPos, rootVis = cam:WorldToViewportPoint(hrp.Position)
        local visible = rootVis and isVisible(hrp.Position, {char, LocalPlayer.Character, Camera})
        if settings.visibleOnly and not visible then slotIdx = slotIdx - 1; continue end

        local fade = math.clamp(1 - (dist / settings.maxDistance), 0.15, 1)
        local mainColor = settings.teamColor and plr.TeamColor.Color or settings.chamsColor
        if not visible then mainColor = mainColor:Lerp(Color3.new(0.3,0.3,0.3), 0.4) end

        if settings.tracers and rootVis then
            local start, dest = Vector2.new(vpSize.X/2, vpSize.Y), Vector2.new(rootPos.X, rootPos.Y)
            local diff = dest - start; s.tracer.Size = UDim2.new(0, diff.Magnitude, 0, 1)
            s.tracer.Position = UDim2.new(0, (start.X+dest.X)/2, 0, (start.Y+dest.Y)/2)
            s.tracer.Rotation = math.deg(math.atan2(diff.Y, diff.X)); s.tracer.BackgroundColor3 = mainColor
            s.tracer.BackgroundTransparency = 1 - fade * 0.6; s.tracer.Visible = true
        else s.tracer.Visible = false end

        if settings.boxes and rootVis then
            local head = char:FindFirstChild("Head")
            if head then
                local hPos = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local lPos = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3.5, 0))
                local h = math.abs(hPos.Y - lPos.Y); local w = h * 0.6
                s.box.Size = UDim2.new(0, w, 0, h); s.box.Position = UDim2.new(0, rootPos.X - w/2, 0, rootPos.Y - h/2)
                for i, side in ipairs(s.boxSides) do
                    side.BackgroundColor3 = mainColor; side.BackgroundTransparency = 1 - fade
                    if settings.boxType == "Corner" then side.Size = (i <= 2) and UDim2.new(0, 1, 0.2, 0) or UDim2.new(0.2, 0, 0, 1)
                    else side.Size = (i <= 2) and UDim2.new(0, 1, 1, 0) or UDim2.new(1, 0, 0, 1) end
                end
                s.box.Visible = true
            end
        else s.box.Visible = false end

        if settings.names and rootVis then
            s.nameLabel.Text = plr.DisplayName; s.nameLabel.Position = UDim2.new(0, rootPos.X-60, 0, rootPos.Y-28)
            s.nameLabel.TextColor3 = mainColor; s.nameLabel.TextTransparency = 1-fade; s.nameLabel.Visible = true
        else s.nameLabel.Visible = false end

        if settings.distance and rootVis then
            s.distLabel.Text = math.floor(dist).." stds"; s.distLabel.Position = UDim2.new(0, rootPos.X-40, 0, rootPos.Y+16)
            s.distLabel.TextTransparency = 1-fade; s.distLabel.Visible = true
        else s.distLabel.Visible = false end

        if settings.healthBars and rootVis then
            local pct = math.clamp(hum.Health/hum.MaxHealth, 0, 1)
            s.hpBg.Position = UDim2.new(0, rootPos.X-20, 0, rootPos.Y-16); s.hpBar.Size = UDim2.new(pct,0,1,0)
            -- [FIX v3.1] Unified fade rate for bg and bar (was 0.7 vs 0.8, now consistent)
            s.hpBar.BackgroundColor3 = healthColor(pct)
            s.hpBg.BackgroundTransparency = 1 - fade * 0.75
            s.hpBar.BackgroundTransparency = 1 - fade * 0.75
            s.hpBg.Visible = true
        else s.hpBg.Visible = false end

        if settings.highlight and slotIdx <= 30 then
            s.highlight.FillTransparency, s.highlight.OutlineTransparency = settings.chamsFill, settings.chamsOutline
            s.highlight.FillColor, s.highlight.OutlineColor = mainColor, mainColor
            s.highlight.DepthMode = settings.chamsDepth and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
            -- [FIX v3.1] Cache adornee to avoid redundant assignments causing micro-stutters
            if s.highlight.Adornee ~= char then s.highlight.Adornee = char end
            s.highlight.Enabled = true
        else
            if s.highlight.Enabled then s.highlight.Enabled = false end
        end

        if settings.radar then
            local obj = camCF:PointToObjectSpace(hrp.Position)
            local scale = (RADAR_SIZE/2 - 6) / 150
            local dx, dy = math.clamp(obj.X * scale, -56, 56), math.clamp(obj.Z * scale, -56, 56)
            s.radarDot.Position = UDim2.new(0.5, dx, 0.5, dy); s.radarDot.BackgroundColor3 = mainColor; s.radarDot.Visible = true
        else s.radarDot.Visible = false end
    end
    for i = slotIdx + 1, MAX_POOL do hideSlot(pool[i]) end
end
table.insert(connections, RunService.RenderStepped:Connect(updateESP))

-- ═══════════════════════════════════════════════════════════
-- GUI Construction
-- ═══════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui", CoreGui); gui.Name = guiId
local main = Instance.new("Frame", gui); main.Size = UDim2.new(0, 360, 0, 440)
main.Position = UDim2.new(0, 14, 0.5, -220); main.BackgroundColor3 = C.bg; main.BorderSizePixel = 0
corner(main, 6); stroke(main, C.divider, 1)

local tBar = Instance.new("Frame", main); tBar.Size = UDim2.new(1,0,0,36); tBar.BackgroundColor3 = C.bgSec
corner(tBar, 6); stroke(tBar, C.divider, 1)
-- Mask frame covers the bottom rounded corners of tBar so it blends flush into the page area below
local mask = Instance.new("Frame", tBar); mask.Name = "M"; mask.Size = UDim2.new(1,0,0,10)
mask.Position = UDim2.new(0,0,1,-10); mask.BackgroundColor3 = C.bgSec; mask.BorderSizePixel = 0

local tabs, tabBtns = {"Home", "Visual", "Combat", "Misc", "Config"}, {}
for i, name in ipairs(tabs) do
    local b = Instance.new("TextButton", tBar); b.Size = UDim2.new(1/#tabs,0,1,0); b.Position = UDim2.new((i-1)/#tabs,0,0,0)
    b.BackgroundTransparency = 1; b.Text = name; b.TextColor3 = (i==1 and C.accent or C.textMut)
    b.Font = Enum.Font.GothamMedium; b.TextSize = 12; tabBtns[name] = b
end

local pageContainer = Instance.new("Frame", main); pageContainer.Size = UDim2.new(1,0,1,-36); pageContainer.Position = UDim2.new(0,0,0,36); pageContainer.BackgroundTransparency = 1
local pages = {}
for _, name in ipairs(tabs) do
    local p = Instance.new("ScrollingFrame", pageContainer); p.Size = UDim2.new(1,0,1,0); p.Visible = (name=="Home")
    p.BackgroundTransparency = 1; p.ScrollBarThickness = 2; p.AutomaticCanvasSize = Enum.AutomaticSize.Y; pad(p, 10,10,14,14)
    local l = Instance.new("UIListLayout", p); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0, 6)
    pages[name] = p
end

local uiUpdaters = {}
local function makeToggle(label, key, order, parent, cb)
    local row = Instance.new("Frame", parent or pages.Visual); row.LayoutOrder = order; row.Size = UDim2.new(1,0,0,26); row.BackgroundTransparency = 1
    local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0,190,1,0); lbl.Text = label; lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.BackgroundTransparency = 1
    local tBg = Instance.new("Frame", row); tBg.Size = UDim2.new(0,34,0,16); tBg.Position = UDim2.new(1,-40,0.5,-8); tBg.BackgroundColor3 = (settings[key] and C.green or C.red); corner(tBg, 8)
    local knob = Instance.new("Frame", tBg); knob.Size = UDim2.new(0,12,0,12); knob.Position = settings[key] and UDim2.new(0,20,0.5,-6) or UDim2.new(0,2,0.5,-6); knob.BackgroundColor3 = C.textPri; corner(knob, 6)
    local btn = Instance.new("TextButton", tBg); btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1; btn.Text = ""
    btn.MouseButton1Click:Connect(function()
        settings[key] = not settings[key]; if cb then cb(settings[key]) end
        tw(tBg, {BackgroundColor3 = settings[key] and C.green or C.red}, 0.2)
        tw(knob, {Position = settings[key] and UDim2.new(0,20,0.5,-6) or UDim2.new(0,2,0.5,-6)}, 0.2)
    end)
    uiUpdaters[key] = function(v) tw(tBg, {BackgroundColor3 = v and C.green or C.red}, 0.2); tw(knob, {Position = v and UDim2.new(0,20,0.5,-6) or UDim2.new(0,2,0.5,-6)}, 0.2) end
end

local function makeSlider(label, key, min, max, float, order, parent)
    local row = Instance.new("Frame", parent or pages.Visual); row.Size = UDim2.new(1,0,0,26); row.BackgroundTransparency = 1; row.LayoutOrder = order
    local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0,130,1,0); lbl.Text = label; lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.BackgroundTransparency = 1
    local sBg = Instance.new("Frame", row); sBg.Size = UDim2.new(0,110,0,6); sBg.Position = UDim2.new(0,140,0.5,-3); sBg.BackgroundColor3 = C.bgSec; corner(sBg, 3); stroke(sBg, C.divider, 1)
    local sFill = Instance.new("Frame", sBg); sFill.Size = UDim2.new((settings[key]-min)/(max-min),0,1,0); sFill.BackgroundColor3 = C.accent; corner(sFill, 2)
    local vLbl = Instance.new("TextLabel", row); vLbl.Size = UDim2.new(0,40,1,0); vLbl.Position = UDim2.new(1,-40,0,0); vLbl.Text = string.format(float and "%.2f" or "%d", settings[key]); vLbl.TextColor3 = C.textMut; vLbl.Font = Enum.Font.Gotham; vLbl.TextSize = 11; vLbl.BackgroundTransparency = 1
    local btn = Instance.new("TextButton", sBg); btn.Size = UDim2.new(1,0,1,10); btn.BackgroundTransparency = 1; btn.Text = ""; local drag = false
    btn.MouseButton1Down:Connect(function() drag = true end)
    table.insert(connections, UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end end))
    table.insert(connections, UserInputService.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local p = math.clamp((i.Position.X - sBg.AbsolutePosition.X)/sBg.AbsoluteSize.X, 0, 1)
            local v = min + (max-min)*p; settings[key] = float and v or math.floor(v)
            sFill.Size = UDim2.new(p,0,1,0); vLbl.Text = string.format(float and "%.2f" or "%d", settings[key])
        end
    end))
end

local function makeColorPicker(label, key, order, parent)
    local row = Instance.new("Frame", parent or pages.Visual); row.Size = UDim2.new(1,0,0,80); row.BackgroundColor3 = C.bgSec; row.LayoutOrder = order; corner(row, 6); stroke(row, C.divider, 1)
    local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0,100,0,24); lbl.Position = UDim2.new(0,8,0,4); lbl.Text = label; lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.BackgroundTransparency = 1
    local pre = Instance.new("Frame", row); pre.Size = UDim2.new(0,24,0,24); pre.Position = UDim2.new(1,-32,0,4); pre.BackgroundColor3 = settings[key]; corner(pre, 4); stroke(pre, Color3.new(1,1,1), 1)
    local h, s, v = settings[key]:ToHSV()
    local function mkSli(l, off, val, cb)
        local sR = Instance.new("Frame", row); sR.Size = UDim2.new(1,-16,0,14); sR.Position = UDim2.new(0,8,0,off); sR.BackgroundTransparency = 1
        local sL = Instance.new("TextLabel", sR); sL.Size = UDim2.new(0,12,1,0); sL.Text = l; sL.TextColor3 = C.textMut; sL.Font = Enum.Font.Gotham; sL.TextSize = 10; sL.BackgroundTransparency = 1
        local sB = Instance.new("Frame", sR); sB.Size = UDim2.new(1,-20,0,4); sB.Position = UDim2.new(0,16,0.5,-2); sB.BackgroundColor3 = C.surface; corner(sB, 2)
        local sF = Instance.new("Frame", sB); sF.Size = UDim2.new(val,0,1,0); sF.BackgroundColor3 = C.accent; corner(sF, 2)
        local b = Instance.new("TextButton", sB); b.Size = UDim2.new(1,0,1,10); b.BackgroundTransparency = 1; b.Text = ""; local d = false
        b.MouseButton1Down:Connect(function() d = true end)
        table.insert(connections, UserInputService.InputChanged:Connect(function(i)
            if d and i.UserInputType == Enum.UserInputType.MouseMovement then
                local p = math.clamp((i.Position.X - sB.AbsolutePosition.X)/sB.AbsoluteSize.X,0,1); sF.Size = UDim2.new(p,0,1,0); cb(p)
                local nc = Color3.fromHSV(h,s,v); settings[key] = nc; pre.BackgroundColor3 = nc
            end
        end))
        table.insert(connections, UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then d = false end end))
    end
    mkSli("H", 30, h, function(nv) h = nv end); mkSli("S", 46, s, function(nv) s = nv end); mkSli("V", 62, v, function(nv) v = nv end)
end

local function makeKeybind(label, bKey, order, parent)
    local row = Instance.new("Frame", parent or pages.Visual); row.Size = UDim2.new(1,0,0,26); row.BackgroundTransparency = 1; row.LayoutOrder = order
    local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.5,0,1,0); lbl.Text = label; lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.BackgroundTransparency = 1
    local btn = Instance.new("TextButton", row); btn.Size = UDim2.new(0.45,0,0,22); btn.Position = UDim2.new(0.55,0,0,2); btn.BackgroundColor3 = C.surface; btn.TextColor3 = C.textMut; btn.Font = Enum.Font.GothamMedium; btn.TextSize = 10; btn.Text = keyName(keybinds[bKey]); btn.AutoButtonColor = false; corner(btn, 4); stroke(btn, C.divider, 1)
    btn.MouseButton1Click:Connect(function()
        if waitingForBind then return end; waitingForBind = bKey; btn.Text = "..."; local bc; bc = UserInputService.InputBegan:Connect(function(i)
            if i.UserInputType ~= Enum.UserInputType.Focus and i.KeyCode ~= Enum.KeyCode.Unknown then
                keybinds[bKey] = (i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode or i.UserInputType)
                btn.Text = keyName(keybinds[bKey]); waitingForBind = nil; bc:Disconnect()
            end
        end)
    end)
end

-- Construction
local hp = pages.Home
local function makeText(p, t, s, f, c, o)
    local l = Instance.new("TextLabel", p)
    l.Size = UDim2.new(1,0,0,s+8); l.Text = t; l.TextColor3 = c; l.Font = f; l.TextSize = s
    l.BackgroundTransparency = 1; l.LayoutOrder = o
end
makeText(hp, "Lightweight ESP v3.0", 20, Enum.Font.GothamBold, C.accent, 1)
makeText(hp, "Premium Edition — by FusedHann", 12, Enum.Font.GothamMedium, C.textMut, 2)
makeText(hp, "• Distance-based Sorting\n• HSV Color Palette\n• Smooth Legit Aim Assist\n• Visibility Checks", 12, Enum.Font.Gotham, C.textPri, 4)

makeToggle("ESP Enabled", "enabled", 1); makeToggle("Tracers", "tracers", 2); makeToggle("Health Bars", "healthBars", 3); makeToggle("Box ESP", "boxes", 4)
makeToggle("Corner Box", "boxType", 5, pages.Visual, function(on) settings.boxType = on and "Corner" or "Standard" end)
makeToggle("Always On Top", "chamsDepth", 6); makeToggle("Radar", "radar", 7); makeToggle("Team Colors", "teamColor", 8); makeToggle("Visible Only", "visibleOnly", 9)
makeSlider("Max Distance", "maxDistance", 50, 2000, false, 10); makeColorPicker("Global Color", "chamsColor", 11)

makeToggle("Enable Aim", "aimEnabled", 1, pages.Combat); makeKeybind("Aim Key", "aim", 2, pages.Combat); makeToggle("Target Head", "aimTarget", 3, pages.Combat, function(on) settings.aimTarget = on and "Head" or "Body" end)
makeSlider("Aim FOV", "aimFOV", 10, 600, false, 4, pages.Combat); makeSlider("Smoothing", "aimSmooth", 1, 25, false, 5, pages.Combat)

makeToggle("Fullbright", "fullbright", 1, pages.Misc); makeSlider("FB Amount", "fbAmount", 0, 1, true, 2, pages.Misc); makeToggle("Remove Fog", "removeFog", 3, pages.Misc)

-- Unload
local unBtn = Instance.new("TextButton", pages.Misc); unBtn.Size = UDim2.new(1,0,0,30); unBtn.BackgroundColor3 = C.bgSec; unBtn.TextColor3 = C.red; unBtn.Text = "Unload Script"; corner(unBtn, 4); stroke(unBtn, C.red, 1)

-- ═══════════════════════════════════════════════════════════
-- Config Tab — [NEW v3.1] JSON Save/Load System
-- ═══════════════════════════════════════════════════════════
local CONFIG_KEY = "default"
local SETTING_KEYS = {"enabled","tracers","healthBars","boxes","boxType","highlight","radar","names","distance","visibleOnly","teamCheck","teamColor","maxDistance","chamsFill","chamsOutline","chamsDepth","zoomEnabled","zoomFOV","fullbright","fbAmount","removeFog","aimEnabled","aimTarget","aimFOV","aimSmooth"}

local function serializeColor(c) return {r=math.floor(c.R*255), g=math.floor(c.G*255), b=math.floor(c.B*255)} end
local function deserializeColor(t) return Color3.fromRGB(t.r, t.g, t.b) end

local function saveConfig(name)
    pcall(function()
        local data = {}
        for _, k in ipairs(SETTING_KEYS) do data[k] = settings[k] end
        data.chamsColor = serializeColor(settings.chamsColor)
        local json = HttpService:JSONEncode(data)
        writefile("LightweightESP/Configs/" .. name .. ".json", json)
        notify("Config saved: " .. name, C.green, 2)
    end)
end

local function loadConfig(name)
    pcall(function()
        local path = "LightweightESP/Configs/" .. name .. ".json"
        if not isfile(path) then notify("No config: " .. name, C.orange, 2); return end
        local data = HttpService:JSONDecode(readfile(path))
        for _, k in ipairs(SETTING_KEYS) do
            if data[k] ~= nil then settings[k] = data[k] end
        end
        if data.chamsColor then settings.chamsColor = deserializeColor(data.chamsColor) end
        -- Update all toggle UI elements to reflect loaded values
        for k, fn in pairs(uiUpdaters) do fn(settings[k]) end
        notify("Config loaded: " .. name, C.accent, 2)
    end)
end

-- Auto-load default config on script start
pcall(function()
    if isfile("LightweightESP/Configs/default.json") then
        loadConfig("default")
    end
end)

-- Config Tab UI
local function makeConfigLabel(txt, order)
    local l = Instance.new("TextLabel", pages.Config); l.Size = UDim2.new(1,0,0,20); l.LayoutOrder = order
    l.Text = txt; l.TextColor3 = C.textMut; l.Font = Enum.Font.Gotham; l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left; l.BackgroundTransparency = 1
end

local function makeConfigBtn(txt, col, order, cb)
    local b = Instance.new("TextButton", pages.Config); b.Size = UDim2.new(1,0,0,28); b.LayoutOrder = order
    b.BackgroundColor3 = C.bgSec; b.TextColor3 = col; b.Text = txt; b.Font = Enum.Font.GothamMedium
    b.TextSize = 12; b.AutoButtonColor = false; corner(b, 4); stroke(b, col, 1)
    b.MouseButton1Click:Connect(cb)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = C.surface end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = C.bgSec end)
    return b
end

-- Profile name input box
local nameRow = Instance.new("Frame", pages.Config); nameRow.Size = UDim2.new(1,0,0,28); nameRow.BackgroundTransparency = 1; nameRow.LayoutOrder = 1
local nameLbl = Instance.new("TextLabel", nameRow); nameLbl.Size = UDim2.new(0,80,1,0); nameLbl.Text = "Profile:"; nameLbl.TextColor3 = C.textPri; nameLbl.Font = Enum.Font.Gotham; nameLbl.TextSize = 12; nameLbl.TextXAlignment = Enum.TextXAlignment.Left; nameLbl.BackgroundTransparency = 1
local nameBox = Instance.new("TextBox", nameRow); nameBox.Size = UDim2.new(1,-85,0,22); nameBox.Position = UDim2.new(0,82,0,3); nameBox.Text = "default"; nameBox.Font = Enum.Font.GothamMedium; nameBox.TextSize = 12; nameBox.TextColor3 = C.textPri; nameBox.BackgroundColor3 = C.surface; nameBox.ClearTextOnFocus = false; corner(nameBox, 4); stroke(nameBox, C.divider, 1); pad(nameBox, 2, 2, 6, 6)
nameLbl.BackgroundTransparency = 1; nameBox.BackgroundTransparency = 0

makeConfigBtn("💾  Save Config", C.accent, 2, function() saveConfig(nameBox.Text ~= "" and nameBox.Text or "default") end)
makeConfigBtn("📂  Load Config", C.green, 3, function() loadConfig(nameBox.Text ~= "" and nameBox.Text or "default") end)
makeConfigLabel("» Auto-saves on load. Default profile auto-loads on inject.", 4)

-- Tab logic
for name, btn in pairs(tabBtns) do
    btn.MouseButton1Click:Connect(function()
        for n, p in pairs(pages) do p.Visible = (n==name) end
        for n, b in pairs(tabBtns) do b.TextColor3 = (n==name and C.accent or C.textMut) end
    end)
end

-- Draggable — [FIX v3.1] dragging flag is always cleared on MouseButton1 release anywhere
local dragging, dStart, sPos
tBar.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging, dStart, sPos = true, i.Position, main.Position end end)
UserInputService.InputChanged:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseMovement and dragging then
        local d = i.Position - dStart
        main.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- Aim Logic Thread
local isAiming = false
UserInputService.InputBegan:Connect(function(i) if i.UserInputType == keybinds.aim or i.KeyCode == keybinds.aim then isAiming = true end end)
UserInputService.InputEnded:Connect(function(i) if i.UserInputType == keybinds.aim or i.KeyCode == keybinds.aim then isAiming = false end end)

local mousemoverel = (typeof(mousemoverel) == "function" and mousemoverel) or (Input and Input.move_mouse_relative)
RunService.RenderStepped:Connect(function()
    if settings.aimEnabled and isAiming and mousemoverel then
        local best, minDist = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == LocalPlayer or (settings.teamCheck and plr.Team == LocalPlayer.Team) then continue end
            local char = plr.Character; local part = char and char:FindFirstChild(settings.aimTarget == "Head" and "Head" or "HumanoidRootPart")
            if part and char.Humanoid.Health > 0 then
                local sPos, vis = Camera:WorldToViewportPoint(part.Position)
                if vis then
                    local mag = (Vector2.new(sPos.X, sPos.Y) - UserInputService:GetMouseLocation()).Magnitude
                    if mag < settings.aimFOV and mag < minDist and isVisible(part.Position, {char, LocalPlayer.Character, Camera}) then
                        minDist, best = mag, sPos
                    end
                end
            end
        end
        if best then
            local mPos = UserInputService:GetMouseLocation()
            mousemoverel((best.X - mPos.X)/settings.aimSmooth, (best.Y - mPos.Y)/settings.aimSmooth)
        end
    end
end)

unBtn.MouseButton1Click:Connect(function()
    running = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    -- [FIX v3.1] Also destroy notifGui on unload for fully clean teardown
    pcall(function() gui:Destroy() end)
    pcall(function() espGui:Destroy() end)
    pcall(function() notifGui:Destroy() end)
end)

notify("Lightweight Utilities Loaded (v3.1)", C.accent, 3)
