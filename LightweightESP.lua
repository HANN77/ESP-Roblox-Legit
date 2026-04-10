--[[
    Lightweight ESP v2.0 — by FusedHann
    ─────────────────────────────────────
    • Works on LOW-LEVEL executors (no Drawing lib, no UNC)
    • Uses only native Roblox instances + Camera:WorldToViewportPoint
    • Object-pooled, throttled rendering for minimal perf impact
    • Features: Tracers, Health Bars, Head/Leg Highlights, Radar, Distance
    • Team exclusion, adjustable max distance
    Run in-game via any executor.
]]

local SCRIPT_VERSION = "2.8"
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
    highlight    = true,  -- full-body outline
    radar        = true,
    names        = true,
    distance     = true,
    teamCheck    = true,  -- exclude own team
    maxDistance  = 500,   -- studs
    chamsFill    = 0.5,
    chamsOutline = 0.0,
    chamsDepth   = true,  -- true = AlwaysOnTop
    chamsColor   = Color3.fromRGB(255, 60, 180),
    zoomEnabled  = true,
    zoomFOV      = 30,
    fullbright   = false,
    fbAmount     = 0.7,
    removeFog    = false,
}

local keybinds = {
    toggle = Enum.KeyCode.H,
    hide   = Enum.KeyCode.RightShift,
    zoom   = Enum.KeyCode.Z,
}
local waitingForBind = nil

-- ═══════════════════════════════════════════════════════════
-- Color Palette (Vibrant Navy & Electric Blue Theme)
-- ═══════════════════════════════════════════════════════════
local C = {
    bg           = Color3.fromRGB(15, 20, 35),    -- Deep Navy
    bgSec        = Color3.fromRGB(25, 30, 45),    -- Header & secondary
    surface      = Color3.fromRGB(35, 45, 65),    -- Distinct UI elements
    surfHover    = Color3.fromRGB(50, 65, 95),
    accent       = Color3.fromRGB(0, 170, 255),   -- Electric Blue
    accentGlow   = Color3.fromRGB(0, 200, 255),
    green        = Color3.fromRGB(50, 205, 50),   -- Vibrant Lime ON
    red          = Color3.fromRGB(220, 20, 60),   -- Vibrant Red OFF
    orange       = Color3.fromRGB(255, 160, 50),
    cyan         = Color3.fromRGB(0, 200, 255),   -- (Used for ESP Team)
    magenta      = Color3.fromRGB(255, 60, 180),  -- (Used for ESP Chams)
    yellow       = Color3.fromRGB(255, 220, 50),  -- (Used for ESP Health)
    textPri      = Color3.fromRGB(255, 255, 255),
    textMut      = Color3.fromRGB(170, 180, 200),
    divider      = Color3.fromRGB(0, 100, 200),   -- Electric Blue subtle
}

-- ═══════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════
local function tw(obj, props, dur, style, dir)
    local t = TweenService:Create(obj,
        TweenInfo.new(dur or 0.25, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
        props)
    t:Play()
    return t
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
-- Toast Notification (reusable from AutoClicker pattern)
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

-- ═══════════════════════════════════════════════════════════
-- ESP Overlay ScreenGui
-- ═══════════════════════════════════════════════════════════
local espGui = Instance.new("ScreenGui")
espGui.Name = guiId .. "_Overlay"
espGui.ResetOnSpawn = false; espGui.DisplayOrder = 0
espGui.IgnoreGuiInset = true; espGui.Enabled = true
pcall(function() if typeof(syn)=="table" and syn.protect_gui then syn.protect_gui(espGui) end end)
espGui.Parent = CoreGui

-- ═══════════════════════════════════════════════════════════
-- ESP Object Pool
-- ═══════════════════════════════════════════════════════════
local pool = {} -- array of ESP element sets

local function createEspSlot()
    local slot = {}

    -- Tracer line (thin frame)
    slot.tracer = Instance.new("Frame")
    slot.tracer.BackgroundColor3 = C.cyan; slot.tracer.BorderSizePixel = 0
    slot.tracer.AnchorPoint = Vector2.new(0, 0.5); slot.tracer.BackgroundTransparency = 0.3
    slot.tracer.Visible = false; slot.tracer.Parent = espGui

    -- Name label
    slot.nameLabel = Instance.new("TextLabel")
    slot.nameLabel.BackgroundTransparency = 1; slot.nameLabel.TextColor3 = C.textPri
    slot.nameLabel.Font = Enum.Font.GothamBold; slot.nameLabel.TextSize = 12
    slot.nameLabel.TextStrokeTransparency = 0.5; slot.nameLabel.TextStrokeColor3 = Color3.new(0,0,0)
    slot.nameLabel.Visible = false; slot.nameLabel.Parent = espGui
    slot.nameLabel.Size = UDim2.new(0,120,0,14); slot.nameLabel.TextXAlignment = Enum.TextXAlignment.Center

    -- Distance label
    slot.distLabel = Instance.new("TextLabel")
    slot.distLabel.BackgroundTransparency = 1; slot.distLabel.TextColor3 = C.textMut
    slot.distLabel.Font = Enum.Font.Gotham; slot.distLabel.TextSize = 10
    slot.distLabel.TextStrokeTransparency = 0.6; slot.distLabel.TextStrokeColor3 = Color3.new(0,0,0)
    slot.distLabel.Visible = false; slot.distLabel.Parent = espGui
    slot.distLabel.Size = UDim2.new(0,80,0,12); slot.distLabel.TextXAlignment = Enum.TextXAlignment.Center

    -- Health bar background
    slot.hpBg = Instance.new("Frame")
    slot.hpBg.Size = UDim2.new(0,40,0,4); slot.hpBg.BackgroundColor3 = Color3.fromRGB(40,40,40)
    slot.hpBg.BackgroundTransparency = 0.3; slot.hpBg.BorderSizePixel = 0
    slot.hpBg.Visible = false; slot.hpBg.Parent = espGui; corner(slot.hpBg, 2)

    -- Health bar fill
    slot.hpBar = Instance.new("Frame")
    slot.hpBar.Size = UDim2.new(1,0,1,0); slot.hpBar.BackgroundColor3 = C.green
    slot.hpBar.BorderSizePixel = 0; slot.hpBar.Parent = slot.hpBg; corner(slot.hpBar, 2)

    -- Full-body Chams (native Roblox Highlight instance)
    slot.highlight = Instance.new("Highlight")
    slot.highlight.FillColor = settings.chamsColor
    slot.highlight.FillTransparency = settings.chamsFill
    slot.highlight.OutlineColor = settings.chamsColor
    slot.highlight.OutlineTransparency = settings.chamsOutline
    slot.highlight.DepthMode = settings.chamsDepth and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    slot.highlight.Enabled = false
    slot.highlight.Parent = espGui -- Store safely in our GUI so it doesn't get destroyed on death

    -- Radar dot (lives inside radar frame, created later)
    slot.radarDot = Instance.new("Frame")
    slot.radarDot.Size = UDim2.new(0,5,0,5); slot.radarDot.BackgroundColor3 = C.red
    slot.radarDot.BorderSizePixel = 0; slot.radarDot.AnchorPoint = Vector2.new(0.5,0.5)
    slot.radarDot.Visible = false; corner(slot.radarDot, 3)

    return slot
end

-- Pre-allocate pool
for i = 1, MAX_POOL do
    pool[i] = createEspSlot()
end

local function hideSlot(slot)
    slot.tracer.Visible = false
    slot.nameLabel.Visible = false
    slot.distLabel.Visible = false
    slot.hpBg.Visible = false
    slot.highlight.Enabled = false
    slot.highlight.Adornee = nil
    slot.radarDot.Visible = false
end

-- ═══════════════════════════════════════════════════════════
-- Radar Frame
-- ═══════════════════════════════════════════════════════════
local RADAR_SIZE = 120
local radarFrame = Instance.new("Frame")
radarFrame.Name = "R"; radarFrame.Size = UDim2.new(0, RADAR_SIZE, 0, RADAR_SIZE)
radarFrame.Position = UDim2.new(0, 12, 1, -RADAR_SIZE - 12)
radarFrame.BackgroundColor3 = C.bg; radarFrame.BackgroundTransparency = 0.3
radarFrame.BorderSizePixel = 0; radarFrame.ClipsDescendants = true
radarFrame.Visible = settings.radar; radarFrame.Parent = espGui
corner(radarFrame, 8); stroke(radarFrame, C.accent, 1)

-- Crosshair lines
for _, cfg in ipairs({{UDim2.new(0.5,0,0,0), UDim2.new(0,1,1,0)}, {UDim2.new(0,0,0.5,0), UDim2.new(1,0,0,1)}}) do
    local l = Instance.new("Frame"); l.Position = cfg[1]; l.Size = cfg[2]
    l.AnchorPoint = Vector2.new(0.5, 0.5)
    l.BackgroundColor3 = C.divider; l.BackgroundTransparency = 0.6; l.BorderSizePixel = 0; l.Parent = radarFrame
end

-- Player dot (center)
local myDot = Instance.new("Frame")
myDot.Size = UDim2.new(0,6,0,6); myDot.BackgroundColor3 = C.cyan; myDot.BorderSizePixel = 0
myDot.AnchorPoint = Vector2.new(0.5,0.5); myDot.Position = UDim2.new(0.5,0,0.5,0)
myDot.Parent = radarFrame; corner(myDot, 3)

-- Parent radar dots to radarFrame
for _, slot in ipairs(pool) do
    slot.radarDot.Parent = radarFrame
end

-- ═══════════════════════════════════════════════════════════
-- ESP Render Engine (the core)
-- ═══════════════════════════════════════════════════════════
local frameSkip = 0
local THROTTLE  = 1 -- update every render frame (removes stutter)

local wasFullbright = false
local origAmbient = Color3.new(0, 0, 0)
local origColorShift_Bottom = Color3.new(0, 0, 0)
local origColorShift_Top = Color3.new(0, 0, 0)

local wasRemoveFog = false
local origFogEnd = 100000
local origFogStart = 0

local function updateESP()
    frameSkip = frameSkip + 1
    if frameSkip < THROTTLE then return end
    frameSkip = 0

    if settings.fullbright then
        if not wasFullbright then
            wasFullbright = true
            origAmbient = Lighting.Ambient
            origColorShift_Bottom = Lighting.ColorShift_Bottom
            origColorShift_Top = Lighting.ColorShift_Top
        end
        Lighting.Ambient = Color3.new(settings.fbAmount, settings.fbAmount, settings.fbAmount)
        Lighting.ColorShift_Bottom = Color3.new(settings.fbAmount, settings.fbAmount, settings.fbAmount)
        Lighting.ColorShift_Top = Color3.new(settings.fbAmount, settings.fbAmount, settings.fbAmount)
    else
        if wasFullbright then
            wasFullbright = false
            Lighting.Ambient = origAmbient
            Lighting.ColorShift_Bottom = origColorShift_Bottom
            Lighting.ColorShift_Top = origColorShift_Top
        end
    end

    if settings.removeFog then
        if not wasRemoveFog then
            wasRemoveFog = true
            origFogEnd = Lighting.FogEnd
            origFogStart = Lighting.FogStart
        end
        Lighting.FogEnd = 9e9
        Lighting.FogStart = 9e9
    else
        if wasRemoveFog then
            wasRemoveFog = false
            Lighting.FogEnd = origFogEnd
            Lighting.FogStart = origFogStart
        end
    end

    if not settings.enabled then
        for i = 1, MAX_POOL do hideSlot(pool[i]) end
        radarFrame.Visible = false
        return
    end
    radarFrame.Visible = settings.radar

    local cam = workspace.CurrentCamera
    if not cam then return end
    local vpSize = cam.ViewportSize
    local camCF  = cam.CFrame
    local myPos  = camCF.Position -- FIX: Core distance from camera, enabling ESP while droning/spectating
    local myTeam = LocalPlayer.Team

    local slotIdx = 0

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if settings.teamCheck and myTeam and plr.Team == myTeam then continue end

        local char = plr.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then continue end

        local dist = (hrp.Position - myPos).Magnitude
        if dist > settings.maxDistance then continue end

        slotIdx = slotIdx + 1
        if slotIdx > MAX_POOL then break end
        local s = pool[slotIdx]

        local rootPos, rootVis = cam:WorldToViewportPoint(hrp.Position)
        local screenX, screenY = rootPos.X, rootPos.Y

        -- Fade factor based on distance
        local fadeFactor = math.clamp(1 - (dist / settings.maxDistance), 0.15, 1)

        -- ── TRACER ──
        if settings.tracers and rootVis then
            local startPos = Vector2.new(vpSize.X / 2, vpSize.Y)
            local endPos   = Vector2.new(screenX, screenY)
            local diff     = endPos - startPos
            local length   = diff.Magnitude
            local angle    = math.deg(math.atan2(diff.Y, diff.X))
            local midPoint = startPos:Lerp(endPos, 0.5)
            
            s.tracer.Size = UDim2.new(0, length, 0, 1)
            s.tracer.Position = UDim2.new(0, midPoint.X, 0, midPoint.Y)
            s.tracer.Rotation = angle
            s.tracer.AnchorPoint = Vector2.new(0.5, 0.5)
            s.tracer.BackgroundTransparency = 1 - fadeFactor * 0.6
            s.tracer.Visible = true
        else
            s.tracer.Visible = false
        end

        -- ── NAME ──
        if settings.names and rootVis then
            s.nameLabel.Text = plr.DisplayName
            s.nameLabel.Position = UDim2.new(0, screenX - 60, 0, screenY - 28)
            s.nameLabel.TextTransparency = 1 - fadeFactor
            s.nameLabel.Visible = true
        else
            s.nameLabel.Visible = false
        end

        -- ── DISTANCE ──
        if settings.distance and rootVis then
            s.distLabel.Text = math.floor(dist) .. " stds"
            s.distLabel.Position = UDim2.new(0, screenX - 40, 0, screenY + 16)
            s.distLabel.TextTransparency = 1 - fadeFactor
            s.distLabel.Visible = true
        else
            s.distLabel.Visible = false
        end

        -- ── HEALTH BAR ──
        if settings.healthBars and rootVis then
            local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            s.hpBg.Position = UDim2.new(0, screenX - 20, 0, screenY - 16)
            s.hpBar.Size = UDim2.new(pct, 0, 1, 0)
            s.hpBar.BackgroundColor3 = healthColor(pct)
            s.hpBg.BackgroundTransparency = 1 - fadeFactor * 0.7
            s.hpBar.BackgroundTransparency = 1 - fadeFactor * 0.8
            s.hpBg.Visible = true
        else
            s.hpBg.Visible = false
        end

        -- ── CHAMS ──
        if settings.highlight then
            s.highlight.FillTransparency = settings.chamsFill
            s.highlight.OutlineTransparency = settings.chamsOutline
            s.highlight.FillColor = settings.chamsColor
            s.highlight.OutlineColor = settings.chamsColor
            s.highlight.DepthMode = settings.chamsDepth and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
            s.highlight.Adornee = char
            s.highlight.Enabled = true
        else
            s.highlight.Enabled = false
            s.highlight.Adornee = nil
        end

        -- ── RADAR DOT ──
        if settings.radar then
            local objSpace = cam.CFrame:PointToObjectSpace(hrp.Position)
            local RADAR_RANGE = 150 -- Fixed radar scale so enemies don't get squished to 1 pixel
            local radarScale = (RADAR_SIZE / 2 - 6) / RADAR_RANGE
            local dotX = math.clamp(objSpace.X * radarScale, -(RADAR_SIZE/2-4), RADAR_SIZE/2-4)
            local dotY = math.clamp(objSpace.Z * radarScale, -(RADAR_SIZE/2-4), RADAR_SIZE/2-4)
            s.radarDot.Position = UDim2.new(0.5, dotX, 0.5, dotY)
            s.radarDot.BackgroundColor3 = C.red
            s.radarDot.Visible = true
        else
            s.radarDot.Visible = false
        end
    end

    -- Hide unused slots
    for i = slotIdx + 1, MAX_POOL do
        hideSlot(pool[i])
    end
end

table.insert(connections, RunService.RenderStepped:Connect(updateESP))

-- ═══════════════════════════════════════════════════════════
-- GUI Construction (Tabs & Settings)
-- ═══════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = guiId; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.DisplayOrder = 10
pcall(function() if typeof(syn)=="table" and syn.protect_gui then syn.protect_gui(gui) end end)
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Name = "M"; main.Size = UDim2.new(0, 360, 0, 0)
main.Position = UDim2.new(0, 14, 0.5, -200)
main.BackgroundColor3 = C.bg; main.BorderSizePixel = 0; main.ClipsDescendants = true
main.Active = true; main.Parent = gui; corner(main, 6); stroke(main, C.divider, 1)

-- Shadow
local sh = Instance.new("Frame")
sh.Size = UDim2.new(1,14,1,14); sh.Position = UDim2.new(0,-7,0,-7)
sh.BackgroundColor3 = Color3.new(0,0,0); sh.BackgroundTransparency = 0.8
sh.BorderSizePixel = 0; sh.ZIndex = -1; sh.Parent = main; corner(sh, 14)

-- Top Tabs
local tBar = Instance.new("Frame")
tBar.Size = UDim2.new(1,0,0,36); tBar.BackgroundColor3 = C.bgSec
tBar.BorderSizePixel = 0; tBar.Parent = main; corner(tBar, 6)

local tbMask = Instance.new("Frame")
tbMask.Size = UDim2.new(1,0,0,10); tbMask.Position = UDim2.new(0,0,1,-10)
tbMask.BackgroundColor3 = C.bgSec; tbMask.BorderSizePixel = 0; tbMask.Parent = tBar
stroke(tBar, C.divider, 1)

local tabs = {"Home", "Visual", "Combat", "Misc", "Config"}
local tabBtns = {}
local w = 1 / #tabs

for i, tName in ipairs(tabs) do
    local b = Instance.new("TextButton", tBar)
    b.Size = UDim2.new(w, 0, 1, 0); b.Position = UDim2.new((i-1)*w, 0, 0, 0)
    b.BackgroundTransparency = 1; b.Text = tName
    b.TextColor3 = (i == 1) and C.accent or C.textMut
    b.Font = Enum.Font.GothamMedium; b.TextSize = 12
    tabBtns[tName] = b
end

-- Pages Container
local pageContainer = Instance.new("Frame", main)
pageContainer.Size = UDim2.new(1,0,1,-36); pageContainer.Position = UDim2.new(0,0,0,36)
pageContainer.BackgroundTransparency = 1

-- Home Page
local pageHome = Instance.new("Frame", pageContainer)
pageHome.Size = UDim2.new(1,0,1,0); pageHome.BackgroundTransparency = 1; pageHome.Visible = true
pad(pageHome, 16, 16, 16, 16)
local hLay = Instance.new("UIListLayout", pageHome)
hLay.SortOrder = Enum.SortOrder.LayoutOrder; hLay.Padding = UDim.new(0, 8)

local function makeText(p, txt, size, font, col, order, align)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1; l.Size = UDim2.new(1,0,0,size+4)
    l.Text = txt; l.TextColor3 = col or C.textPri; l.Font = font
    l.TextSize = size; l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.LayoutOrder = order; l.Parent = p
    if txt:find("\n") then
        l.TextYAlignment = Enum.TextYAlignment.Top
        local lines = select(2, txt:gsub('\n', '\n')) + 1
        l.Size = UDim2.new(1,0,0, lines * (size + 6))
    end
    return l
end

makeText(pageHome, "Lightweight Utilities", 20, Enum.Font.GothamBold, C.textPri, 1, Enum.TextXAlignment.Center)
makeText(pageHome, "Version " .. SCRIPT_VERSION, 10, Enum.Font.GothamMedium, C.textMut, 2, Enum.TextXAlignment.Center)

local d1 = Instance.new("Frame", pageHome); d1.Size=UDim2.new(1,0,0,1); d1.BackgroundColor3=C.divider; d1.LayoutOrder=3; d1.BorderSizePixel=0

makeText(pageHome, "Key Features:", 12, Enum.Font.GothamBold, C.accent, 4)
makeText(pageHome, "• Zero-cost GPU-rendered Chams\n• Extensive Chams configuration options\n• Fully rebindable modern minimalist UI\n• Automatic distance fade & culling\n• Safe Team filtering\n• Strict Low-level executor compatibility", 12, Enum.Font.Gotham, C.textPri, 5)

local d2 = Instance.new("Frame", pageHome); d2.Size=UDim2.new(1,0,0,1); d2.BackgroundColor3=C.divider; d2.LayoutOrder=6; d2.BorderSizePixel=0

makeText(pageHome, "Developer Hub:", 12, Enum.Font.GothamBold, C.accent, 7)
makeText(pageHome, "github.com/HANN77", 11, Enum.Font.Gotham, C.textMut, 8)

-- ESP Page (Scrollable)
local pageESP = Instance.new("ScrollingFrame", pageContainer)
pageESP.Size = UDim2.new(1,0,1,0); pageESP.BackgroundTransparency = 1; pageESP.Visible = false
pageESP.ScrollBarThickness = 2; pageESP.ScrollBarImageColor3 = C.divider
pageESP.CanvasSize = UDim2.new(0,320,0,1200)
pageESP.AutomaticCanvasSize = Enum.AutomaticSize.Y
pad(pageESP, 10, 10, 14, 14)
local eLay = Instance.new("UIListLayout", pageESP)
eLay.SortOrder = Enum.SortOrder.LayoutOrder; eLay.Padding = UDim.new(0, 6)

-- Combat Page
local pageCombat = Instance.new("ScrollingFrame", pageContainer)
pageCombat.Size = UDim2.new(1,0,1,0); pageCombat.BackgroundTransparency = 1; pageCombat.Visible = false
pageCombat.ScrollBarThickness = 2; pageCombat.ScrollBarImageColor3 = C.divider
pageCombat.CanvasSize = UDim2.new(0,320,0,1200)
pageCombat.AutomaticCanvasSize = Enum.AutomaticSize.Y
pad(pageCombat, 10, 10, 14, 14)
local cLay = Instance.new("UIListLayout", pageCombat)
cLay.SortOrder = Enum.SortOrder.LayoutOrder; cLay.Padding = UDim.new(0, 6)

-- Misc Page
local pageMisc = Instance.new("ScrollingFrame", pageContainer)
pageMisc.Size = UDim2.new(1,0,1,0); pageMisc.BackgroundTransparency = 1; pageMisc.Visible = false
pageMisc.ScrollBarThickness = 2; pageMisc.ScrollBarImageColor3 = C.divider
pageMisc.CanvasSize = UDim2.new(0,320,0,1200)
pageMisc.AutomaticCanvasSize = Enum.AutomaticSize.Y
pad(pageMisc, 10, 10, 14, 14)
local mLay = Instance.new("UIListLayout", pageMisc)
mLay.SortOrder = Enum.SortOrder.LayoutOrder; mLay.Padding = UDim.new(0, 6)

-- Config Page
local pageConfig = Instance.new("ScrollingFrame", pageContainer)
pageConfig.Size = UDim2.new(1,0,1,0); pageConfig.BackgroundTransparency = 1; pageConfig.Visible = false
pageConfig.ScrollBarThickness = 2; pageConfig.ScrollBarImageColor3 = C.divider
pageConfig.CanvasSize = UDim2.new(0,320,0,1200)
pageConfig.AutomaticCanvasSize = Enum.AutomaticSize.Y
pad(pageConfig, 10, 10, 14, 14)
local cfgLay = Instance.new("UIListLayout", pageConfig)
cfgLay.SortOrder = Enum.SortOrder.LayoutOrder; cfgLay.Padding = UDim.new(0, 10)

local uiUpdaters = {}

local function secLabel(text, order, parentPage)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,0,0,16); l.BackgroundTransparency = 1; l.Text = text
    l.TextColor3 = C.textMut; l.Font = Enum.Font.GothamMedium; l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left; l.LayoutOrder = order; l.Parent = parentPage or pageESP
end

local function makeToggle(label, settingKey, order, parentPage)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(0,310,0,26); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = parentPage or pageESP

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0,190,1,0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local toggleBg = Instance.new("Frame")
    toggleBg.Size = UDim2.new(0,34,0,16); toggleBg.Position = UDim2.new(0,276,0.5,-8)
    toggleBg.BackgroundColor3 = settings[settingKey] and C.green or C.red
    toggleBg.BorderSizePixel = 0; toggleBg.Parent = row; corner(toggleBg, 8)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1; btn.Text = ""
    btn.Parent = toggleBg

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0,12,0,12); knob.BackgroundColor3 = C.textPri; knob.BorderSizePixel = 0
    knob.Position = settings[settingKey] and UDim2.new(0,20,0.5,-6) or UDim2.new(0,2,0.5,-6)
    knob.Parent = toggleBg; corner(knob, 6)

    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(1,0,1,0); icon.Position = UDim2.new(0,0,0,-1); icon.BackgroundTransparency = 1
    icon.Font = Enum.Font.GothamBold; icon.TextSize = 10
    icon.TextColor3 = settings[settingKey] and C.green or C.red
    icon.Text = settings[settingKey] and "✓" or "✕"
    icon.Parent = knob

    local function updateVisual(on)
        tw(toggleBg, {BackgroundColor3 = on and C.green or C.red}, 0.2)
        tw(knob, {
            Position = on and UDim2.new(0,20,0.5,-6) or UDim2.new(0,2,0.5,-6)
        }, 0.2)
        tw(icon, {
            TextColor3 = on and C.green or C.red
        }, 0.2)
        icon.Text = on and "✓" or "✕"
    end
    uiUpdaters[settingKey] = updateVisual

    btn.MouseButton1Click:Connect(function()
        settings[settingKey] = not settings[settingKey]
        local on = settings[settingKey]
        updateVisual(on)
        if settingKey == "radar" then radarFrame.Visible = on end
    end)
    return row
end

local function makeSlider(label, settingKey, min, max, isFloat, order, parentPage)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(0,310,0,24); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = parentPage or pageESP

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0,130,1,0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(0,114,0,6); sliderBg.Position = UDim2.new(0,140,0.5,-3)
    sliderBg.BackgroundColor3 = C.bgSec; sliderBg.BorderSizePixel = 0; sliderBg.Parent = row; corner(sliderBg, 3)
    stroke(sliderBg, C.divider, 1)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,1,20); btn.Position = UDim2.new(0,0,0.5,-10)
    btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = sliderBg

    local val = settings[settingKey]
    local initPct = (val - min) / (max - min)

    local sliderFill = Instance.new("Frame")
    sliderFill.BackgroundColor3 = C.accent; sliderFill.BorderSizePixel = 0
    sliderFill.Size = UDim2.new(initPct, 0, 1, 0)
    sliderFill.Parent = sliderBg; corner(sliderFill, 2)

    local dragKnob = Instance.new("Frame")
    dragKnob.Size = UDim2.new(0,10,0,10); dragKnob.BackgroundColor3 = C.accent; dragKnob.BorderSizePixel = 0
    dragKnob.AnchorPoint = Vector2.new(0.5,0.5); dragKnob.Position = UDim2.new(1, 0, 0.5, 0)
    dragKnob.Parent = sliderFill; corner(dragKnob, 5)

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0,46,1,0); valLbl.Position = UDim2.new(0,264,0,0)
    valLbl.BackgroundTransparency = 1; 
    valLbl.Text = isFloat and string.format("%.2f", val) or tostring(val)
    valLbl.TextColor3 = C.textPri; valLbl.Font = Enum.Font.GothamMedium; valLbl.TextSize = 11
    valLbl.TextXAlignment = Enum.TextXAlignment.Right; valLbl.Parent = row

    local dragging = false
    btn.MouseButton1Down:Connect(function() dragging = true end)
    table.insert(connections, UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    table.insert(connections, UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local pX = inp.Position.X - sliderBg.AbsolutePosition.X
            local pct = math.clamp(pX / sliderBg.AbsoluteSize.X, 0, 1)
            local newVal = min + (max - min) * pct
            if not isFloat then newVal = math.floor(newVal) end
            settings[settingKey] = newVal
            sliderFill.Size = UDim2.new(pct, 0, 1, 0)
            valLbl.Text = isFloat and string.format("%.2f", newVal) or tostring(newVal)
        end
    end))
end

local function makeColorPicker(label, settingKey, order, parentPage)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(0,310,0,40); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = parentPage or pageESP

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0,100,0,20); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local hexBox = Instance.new("TextBox")
    hexBox.Size = UDim2.new(0,60,0,16); hexBox.Position = UDim2.new(0,100,0,2)
    hexBox.BackgroundColor3 = C.surface; hexBox.TextColor3 = C.textPri
    hexBox.Font = Enum.Font.GothamMedium; hexBox.TextSize = 10
    hexBox.Text = "#" .. settings[settingKey]:ToHex():upper()
    hexBox.Parent = row; corner(hexBox, 4); stroke(hexBox, C.divider, 1)

    local preview = Instance.new("Frame")
    preview.Size = UDim2.new(0,16,0,16); preview.Position = UDim2.new(0,168,0,2)
    preview.BackgroundColor3 = settings[settingKey]
    preview.Parent = row; corner(preview, 4); stroke(preview, C.divider, 1)

    local hueBg = Instance.new("Frame")
    hueBg.Size = UDim2.new(0,310,0,8); hueBg.Position = UDim2.new(0,0,0,26)
    hueBg.BackgroundColor3 = Color3.new(1,1,1); hueBg.BorderSizePixel = 0
    hueBg.Parent = row; corner(hueBg, 4)
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,0)), ColorSequenceKeypoint.new(1/6, Color3.fromRGB(255,255,0)),
        ColorSequenceKeypoint.new(2/6, Color3.fromRGB(0,255,0)), ColorSequenceKeypoint.new(3/6, Color3.fromRGB(0,255,255)),
        ColorSequenceKeypoint.new(4/6, Color3.fromRGB(0,0,255)), ColorSequenceKeypoint.new(5/6, Color3.fromRGB(255,0,255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255,0,0))
    })
    grad.Parent = hueBg

    local h, s, v = settings[settingKey]:ToHSV()
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0,4,0,14); knob.Position = UDim2.new(h,0,0.5,0)
    knob.AnchorPoint = Vector2.new(0.5, 0.5); knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.Parent = hueBg; corner(knob, 2); stroke(knob, Color3.new(0,0,0), 1)

    local hueBtn = Instance.new("TextButton")
    hueBtn.Size = UDim2.new(1,0,1,10); hueBtn.Position = UDim2.new(0,0,0.5,-5)
    hueBtn.BackgroundTransparency = 1; hueBtn.Text = ""; hueBtn.Parent = hueBg

    local dragging = false
    hueBtn.MouseButton1Down:Connect(function() dragging = true end)
    table.insert(connections, UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))

    local function updateColor(c)
        settings[settingKey] = c
        hexBox.Text = "#" .. c:ToHex():upper()
        preview.BackgroundColor3 = c
        if uiUpdaters[settingKey] then uiUpdaters[settingKey](c) end
    end
    
    table.insert(connections, UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local p = math.clamp((inp.Position.X - hueBg.AbsolutePosition.X) / hueBg.AbsoluteSize.X, 0, 1)
            knob.Position = UDim2.new(p, 0, 0.5, 0)
            updateColor(Color3.fromHSV(p, 1, 1))
        end
    end))

    hexBox.FocusLost:Connect(function()
        local txt = hexBox.Text:gsub("#", "")
        pcall(function()
            local c = Color3.fromHex(txt)
            updateColor(c)
            local hue = c:ToHSV()
            knob.Position = UDim2.new(hue, 0, 0.5, 0)
        end)
    end)
end

local function makeKeybindRow(label, bKey, order, parentPage)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,26); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = parentPage or pageESP
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.5,0,1,0); l.BackgroundTransparency = 1; l.Text = label
    l.TextColor3 = C.textPri; l.Font = Enum.Font.Gotham; l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = row
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.45,0,0,22); btn.Position = UDim2.new(0.55,0,0,2)
    btn.BackgroundColor3 = C.surface; btn.TextColor3 = C.textMut; btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 10; btn.Text = keyName(keybinds[bKey]); btn.AutoButtonColor = false
    btn.Parent = row; corner(btn, 4); stroke(btn, C.divider, 1)
    
    btn.MouseButton1Click:Connect(function()
        if waitingForBind then return end
        waitingForBind = bKey; btn.Text = "..."; btn.TextColor3 = C.textPri; btn.BackgroundColor3 = C.surfHover
        local bc; bc = UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType ~= Enum.UserInputType.Keyboard and not inp.UserInputType.Name:match("MouseButton") then return end
            
            if inp.KeyCode == Enum.KeyCode.Escape then
                btn.Text = keyName(keybinds[bKey]); btn.TextColor3 = C.textMut; btn.BackgroundColor3 = C.surface
                waitingForBind = nil; bc:Disconnect(); return
            end
            
            local bindVal = (inp.UserInputType == Enum.UserInputType.Keyboard) and inp.KeyCode or inp.UserInputType
            keybinds[bKey] = bindVal
            btn.Text = keyName(bindVal); btn.TextColor3 = C.textMut; btn.BackgroundColor3 = C.surface
            waitingForBind = nil; bc:Disconnect()
            notify(label.." -> "..keyName(bindVal), C.textPri, 2)
        end)
    end)
    uiUpdaters["bind_"..bKey] = function()
        btn.Text = keyName(keybinds[bKey])
    end
end

secLabel("KEYBINDS", 1)
makeKeybindRow("Toggle ESP", "toggle", 2)
makeKeybindRow("Hide Panel", "hide", 3)

secLabel("VISUALS", 10)
makeToggle("ESP Enabled", "enabled", 11)
makeToggle("Tracers", "tracers", 12)
makeToggle("Health Bars", "healthBars", 13)
makeToggle("Names", "names", 14)
makeToggle("Distance", "distance", 15)
makeToggle("Radar", "radar", 16)
makeSlider("Max Distance", "maxDistance", 50, 2000, false, 17)

secLabel("CHAMS CONFIG", 20)
makeToggle("Enable Chams", "highlight", 21)
makeToggle("Always On Top", "chamsDepth", 22)
makeSlider("Fill Transp.", "chamsFill", 0, 1, true, 23)
makeSlider("Outline Transp.", "chamsOutline", 0, 1, true, 24)
makeColorPicker("Color", "chamsColor", 25)

secLabel("FILTERS", 30)
makeToggle("Exclude Team", "teamCheck", 31)

secLabel("ZOOM MACRO", 1, pageCombat)
makeToggle("Enable Zoom", "zoomEnabled", 2, pageCombat)
makeKeybindRow("Zoom Key", "zoom", 3, pageCombat)
makeSlider("Zoom FOV", "zoomFOV", 10, 120, false, 4, pageCombat)

secLabel("ENVIRONMENT", 1, pageMisc)
makeToggle("Fullbright", "fullbright", 2, pageMisc)
makeSlider("FB Brightness", "fbAmount", 0, 1, true, 3, pageMisc)
makeToggle("Remove Fog", "removeFog", 4, pageMisc)

-- ═══════════════════════════════════════════════════════════
-- Config System logic
-- ═══════════════════════════════════════════════════════════
local function saveConfig(cfgName)
    local data = { settings = {}, keybinds = {} }
    for k,v in pairs(settings) do
        if typeof(v) == "Color3" then
            data.settings[k] = {type="Color3", hex=v:ToHex()}
        else
            data.settings[k] = v
        end
    end
    for k,v in pairs(keybinds) do
        data.keybinds[k] = {type=tostring(v.EnumType), name=v.Name}
    end
    pcall(function()
        writefile("LightweightESP/Configs/"..cfgName..".json", HttpService:JSONEncode(data))
        notify("Saved Config: " .. cfgName, C.green)
    end)
end

local function loadConfig(cfgName)
    local success, json = pcall(function() return readfile("LightweightESP/Configs/"..cfgName..".json") end)
    if not success or not json then 
        notify("Config not found!", C.red)
        return 
    end
    
    local s2, data = pcall(function() return HttpService:JSONDecode(json) end)
    if not s2 or type(data) ~= "table" then
        notify("Config Corrupted", C.red)
        return
    end
    
    if data.settings then
        for k,v in pairs(data.settings) do
            if type(v) == "table" and v.type == "Color3" then
                settings[k] = Color3.fromHex(v.hex)
            else
                settings[k] = v
            end
            if uiUpdaters[k] then uiUpdaters[k](settings[k]) end
        end
    end
    
    if data.keybinds then
        for k,v in pairs(data.keybinds) do
            if v.type == "Enum.KeyCode" and Enum.KeyCode[v.name] then
                keybinds[k] = Enum.KeyCode[v.name]
            elseif v.type == "Enum.UserInputType" and Enum.UserInputType[v.name] then
                keybinds[k] = Enum.UserInputType[v.name]
            end
            if uiUpdaters["bind_"..k] then uiUpdaters["bind_"..k]() end
        end
    end
    notify("Loaded Config: " .. cfgName, C.accent)
end

secLabel("PROFILE MANAGEMENT", 1, pageConfig)

local cfgBoxRow = Instance.new("Frame", pageConfig)
cfgBoxRow.Size = UDim2.new(1,0,0,30); cfgBoxRow.BackgroundTransparency = 1; cfgBoxRow.LayoutOrder = 2
local cfgBox = Instance.new("TextBox", cfgBoxRow)
cfgBox.Size = UDim2.new(1,0,1,0); cfgBox.BackgroundColor3 = C.surface
cfgBox.TextColor3 = C.textPri; cfgBox.Font = Enum.Font.GothamMedium
cfgBox.TextSize = 12; cfgBox.PlaceholderText = "Config Name..."
cfgBox.Text = "legit"
corner(cfgBox, 4); stroke(cfgBox, C.divider, 1)

local cfgSaveRow = Instance.new("Frame", pageConfig)
cfgSaveRow.Size = UDim2.new(1,0,0,30); cfgSaveRow.BackgroundTransparency = 1; cfgSaveRow.LayoutOrder = 3
local btnSave = Instance.new("TextButton", cfgSaveRow)
btnSave.Size = UDim2.new(1,0,1,0); btnSave.BackgroundColor3 = C.bgSec
btnSave.TextColor3 = C.green; btnSave.Font = Enum.Font.GothamBold; btnSave.TextSize = 12
btnSave.Text = "Save Config"; corner(btnSave, 4); stroke(btnSave, C.green, 1)
btnSave.MouseButton1Click:Connect(function() 
    if cfgBox.Text ~= "" then saveConfig(cfgBox.Text) end 
end)

local cfgLoadRow = Instance.new("Frame", pageConfig)
cfgLoadRow.Size = UDim2.new(1,0,0,30); cfgLoadRow.BackgroundTransparency = 1; cfgLoadRow.LayoutOrder = 4
local btnLoad = Instance.new("TextButton", cfgLoadRow)
btnLoad.Size = UDim2.new(1,0,1,0); btnLoad.BackgroundColor3 = C.bgSec
btnLoad.TextColor3 = C.textPri; btnLoad.Font = Enum.Font.GothamMedium; btnLoad.TextSize = 12
btnLoad.Text = "Load Config"; corner(btnLoad, 4); stroke(btnLoad, C.divider, 1)
btnLoad.MouseButton1Click:Connect(function() 
    if cfgBox.Text ~= "" then loadConfig(cfgBox.Text) end 
end)

if type(writefile) ~= "function" then
    secLabel("⚠️ Executor does not support saving files.", 5, pageConfig)
end

local unBtn = Instance.new("TextButton")
unBtn.Size = UDim2.new(1,0,0,28); unBtn.BackgroundColor3 = C.bgSec; unBtn.TextColor3 = C.red
unBtn.Font = Enum.Font.GothamMedium; unBtn.TextSize = 11; unBtn.Text = "Unload Utilities"
unBtn.AutoButtonColor = false; unBtn.LayoutOrder = 40; unBtn.Parent = pageESP; corner(unBtn, 4); stroke(unBtn, C.divider, 1)

main.Size = UDim2.new(0, 360, 0, 440)

-- Tab logic
for tName, btn in pairs(tabBtns) do
    btn.MouseButton1Click:Connect(function()
        for _, b in pairs(tabBtns) do b.TextColor3 = C.textMut end
        btn.TextColor3 = C.accent
        pageHome.Visible = (tName == "Home")
        pageESP.Visible = (tName == "Visual")
        pageCombat.Visible = (tName == "Combat")
        pageMisc.Visible = (tName == "Misc")
        pageConfig.Visible = (tName == "Config")
    end)
end

-- ═══════════════════════════════════════════════════════════
-- Draggable
-- ═══════════════════════════════════════════════════════════
local dragging, dragInput, dragStart, startPos = false
local function makeDrag(obj)
    table.insert(connections, obj.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = inp.Position; startPos = main.Position
            local con
            con = inp.Changed:Connect(function() 
                if inp.UserInputState == Enum.UserInputState.End then 
                    dragging = false 
                    if con then con:Disconnect() end
                end 
            end)
        end
    end))
end
makeDrag(tBar)
for _, btn in pairs(tabBtns) do makeDrag(btn) end

table.insert(connections, tBar.InputChanged:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then dragInput = inp end
end))
table.insert(connections, UserInputService.InputChanged:Connect(function(inp)
    if inp == dragInput and dragging then
        local d = inp.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end))

-- ═══════════════════════════════════════════════════════════
-- Keybind Listener
-- ═══════════════════════════════════════════════════════════
table.insert(connections, UserInputService.InputBegan:Connect(function(inp, gp)
    if waitingForBind then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard and not inp.UserInputType.Name:match("MouseButton") then return end
    if UserInputService:GetFocusedTextBox() then return end
    if inp.KeyCode == keybinds.toggle or inp.UserInputType == keybinds.toggle then
        settings.enabled = not settings.enabled
        if uiUpdaters["enabled"] then uiUpdaters["enabled"](settings.enabled) end
        notify("ESP " .. (settings.enabled and "Enabled" or "Disabled"), C.accent)
    elseif inp.KeyCode == keybinds.hide or inp.UserInputType == keybinds.hide then
        gui.Enabled = not gui.Enabled
        notify(gui.Enabled and "Panel Visible" or "Panel Hidden", C.accent, 1.5)
    elseif (inp.KeyCode == keybinds.zoom or inp.UserInputType == keybinds.zoom) and settings.zoomEnabled then
        tw(Camera, {FieldOfView = settings.zoomFOV}, 0.25)
    end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(inp, gp)
    if waitingForBind then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard and not inp.UserInputType.Name:match("MouseButton") then return end
    if UserInputService:GetFocusedTextBox() then return end
    if (inp.KeyCode == keybinds.zoom or inp.UserInputType == keybinds.zoom) and settings.zoomEnabled then
        tw(Camera, {FieldOfView = 70}, 0.3)
    end
end))

-- ═══════════════════════════════════════════════════════════
-- Unload
-- ═══════════════════════════════════════════════════════════
local function unload()
    notify("Utilities Unloaded", C.textMut, 1.5)
    task.wait(0.4); running = false
    
    if wasFullbright then
        Lighting.Ambient = origAmbient
        Lighting.ColorShift_Bottom = origColorShift_Bottom
        Lighting.ColorShift_Top = origColorShift_Top
    end
    if wasRemoveFog then
        Lighting.FogEnd = origFogEnd
        Lighting.FogStart = origFogStart
    end
    
    for _, cn in ipairs(connections) do pcall(function() cn:Disconnect() end) end
    connections = {}
    tw(main, {BackgroundTransparency = 1}, 0.3)
    for _, ch in ipairs(main:GetDescendants()) do
        pcall(function()
            if ch:IsA("GuiObject") then tw(ch, {BackgroundTransparency=1}, 0.25) end
            if ch:IsA("TextLabel") or ch:IsA("TextButton") or ch:IsA("TextBox") then tw(ch, {TextTransparency=1}, 0.25) end
        end)
    end
    task.wait(0.35)
    pcall(function() gui:Destroy() end)
    pcall(function() espGui:Destroy() end)
    task.delay(2, function() pcall(function() notifGui:Destroy() end) end)
end
unBtn.MouseButton1Click:Connect(unload)

-- ═══════════════════════════════════════════════════════════
-- Intro
-- ═══════════════════════════════════════════════════════════
do
    local tp = main.Position
    main.Position = UDim2.new(tp.X.Scale, tp.X.Offset, tp.Y.Scale, tp.Y.Offset - 20)
    main.BackgroundTransparency = 0.5
    for _, ch in ipairs(main:GetDescendants()) do if ch:IsA("GuiObject") then ch.BackgroundTransparency = 1 end end
    task.wait(0.05)
    tw(main, {Position = tp, BackgroundTransparency = 0}, 0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    for _, ch in ipairs(main:GetDescendants()) do 
        if ch:IsA("GuiObject") and ch.Name ~= "M" then 
            local def = ch.BackgroundTransparency
            ch.BackgroundTransparency = 1
            tw(ch, {BackgroundTransparency = def}, 0.6) 
            
            if ch:IsA("TextLabel") or ch:IsA("TextButton") or ch:IsA("TextBox") then
                local tDef = ch.TextTransparency
                ch.TextTransparency = 1
                tw(ch, {TextTransparency = tDef}, 0.6)
            end
        end 
    end
    task.wait(0.4)
    notify("Lightweight Utilities Loaded", C.textPri, 3)
end
