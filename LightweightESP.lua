--[[
    Lightweight ESP v1.0 — by FusedHann
    ─────────────────────────────────────
    • Works on LOW-LEVEL executors (no Drawing lib, no UNC)
    • Uses only native Roblox instances + Camera:WorldToViewportPoint
    • Object-pooled, throttled rendering for minimal perf impact
    • Features: Tracers, Health Bars, Head/Leg Highlights, Radar, Distance
    • Team exclusion, adjustable max distance
    Run in-game via any executor.
]]

local SCRIPT_VERSION = "1.0"
local MAX_POOL = 24 -- max simultaneous tracked players

-- ═══════════════════════════════════════════════════════════
-- Services
-- ═══════════════════════════════════════════════════════════
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService  = game:GetService("TweenService")
local CoreGui       = game:GetService("CoreGui")

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

local settings = {
    enabled     = true,
    tracers     = true,
    healthBars  = true,
    highlight   = true,  -- full-body outline
    radar       = true,
    names       = true,
    distance    = true,
    teamCheck   = true,  -- exclude own team
    maxDistance  = 500,   -- studs
}

local keybinds = {
    toggle = Enum.KeyCode.H,
    hide   = Enum.KeyCode.RightShift,
}
local waitingForBind = nil

-- ═══════════════════════════════════════════════════════════
-- Color Palette (matches AutoClicker style)
-- ═══════════════════════════════════════════════════════════
local C = {
    bg           = Color3.fromRGB(22, 22, 30),
    bgSec        = Color3.fromRGB(28, 28, 40),
    surface      = Color3.fromRGB(35, 35, 50),
    surfHover    = Color3.fromRGB(45, 45, 62),
    accent       = Color3.fromRGB(110, 90, 255),
    accentGlow   = Color3.fromRGB(140, 120, 255),
    green        = Color3.fromRGB(50, 205, 100),
    red          = Color3.fromRGB(235, 70, 80),
    orange       = Color3.fromRGB(255, 160, 50),
    cyan         = Color3.fromRGB(0, 200, 255),
    magenta      = Color3.fromRGB(255, 60, 180),
    yellow       = Color3.fromRGB(255, 220, 50),
    textPri      = Color3.fromRGB(240, 240, 250),
    textMut      = Color3.fromRGB(140, 140, 165),
    divider      = Color3.fromRGB(50, 50, 70),
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

    -- Full-body highlight (native Roblox Highlight instance)
    slot.highlight = Instance.new("Highlight")
    slot.highlight.FillColor = C.magenta
    slot.highlight.FillTransparency = 0.75
    slot.highlight.OutlineColor = C.cyan
    slot.highlight.OutlineTransparency = 0
    slot.highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    slot.highlight.Enabled = false

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
    slot.highlight.Parent = nil
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
local THROTTLE  = 2 -- update every N render frames

local function updateESP()
    frameSkip = frameSkip + 1
    if frameSkip < THROTTLE then return end
    frameSkip = 0

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
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myPos  = myRoot and myRoot.Position or Vector3.new(0,0,0)
    local myTeam = LocalPlayer.Team

    local camLook = camCF.LookVector
    local radarAngle = math.atan2(camLook.X, camLook.Z) -- for radar rotation

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
            local startX, startY = vpSize.X / 2, vpSize.Y
            local dx = screenX - startX
            local dy = screenY - startY
            local length = math.sqrt(dx*dx + dy*dy)
            local angle  = math.deg(math.atan2(dy, dx))
            s.tracer.Size = UDim2.new(0, length, 0, 1)
            s.tracer.Position = UDim2.new(0, startX, 0, startY)
            s.tracer.Rotation = angle
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

        -- ── FULL-BODY HIGHLIGHT ──
        if settings.highlight then
            s.highlight.FillTransparency = 0.65 + (1 - fadeFactor) * 0.3
            s.highlight.OutlineTransparency = (1 - fadeFactor) * 0.5
            s.highlight.Parent = char
            s.highlight.Enabled = true
        else
            s.highlight.Enabled = false
            s.highlight.Parent = nil
        end

        -- ── RADAR DOT ──
        if settings.radar then
            local offset = hrp.Position - myPos
            local rx = offset.X * math.cos(-radarAngle) - offset.Z * math.sin(-radarAngle)
            local ry = offset.X * math.sin(-radarAngle) + offset.Z * math.cos(-radarAngle)
            local radarScale = (RADAR_SIZE / 2 - 6) / settings.maxDistance
            local dotX = math.clamp(rx * radarScale, -(RADAR_SIZE/2-4), RADAR_SIZE/2-4)
            local dotY = math.clamp(-ry * radarScale, -(RADAR_SIZE/2-4), RADAR_SIZE/2-4)
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
-- GUI Construction (Settings Panel)
-- ═══════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = guiId; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.DisplayOrder = 10
pcall(function() if typeof(syn)=="table" and syn.protect_gui then syn.protect_gui(gui) end end)
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Name = "M"; main.Size = UDim2.new(0, 220, 0, 0)
main.Position = UDim2.new(0, 14, 0.5, -200)
main.BackgroundColor3 = C.bg; main.BorderSizePixel = 0; main.ClipsDescendants = true
main.Active = true; main.Parent = gui; corner(main, 12); stroke(main, C.accent, 1.5)

-- Shadow
local sh = Instance.new("Frame")
sh.Size = UDim2.new(1,8,1,8); sh.Position = UDim2.new(0,-4,0,-4)
sh.BackgroundColor3 = Color3.new(0,0,0); sh.BackgroundTransparency = 0.7
sh.BorderSizePixel = 0; sh.ZIndex = -1; sh.Parent = main; corner(sh, 14)

-- Title bar
local tBar = Instance.new("Frame")
tBar.Size = UDim2.new(1,0,0,36); tBar.BackgroundColor3 = C.bgSec
tBar.BorderSizePixel = 0; tBar.Parent = main; corner(tBar, 12)
local tbMask = Instance.new("Frame")
tbMask.Size = UDim2.new(1,0,0,14); tbMask.Position = UDim2.new(0,0,1,-14)
tbMask.BackgroundColor3 = C.bgSec; tbMask.BorderSizePixel = 0; tbMask.Parent = tBar
local aLine = Instance.new("Frame")
aLine.Size = UDim2.new(0.6,0,0,2); aLine.Position = UDim2.new(0.2,0,1,-1)
aLine.BackgroundColor3 = C.accent; aLine.BorderSizePixel = 0; aLine.Parent = tBar; corner(aLine,1)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1,-50,1,0); titleLbl.Position = UDim2.new(0,10,0,0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "👁 ESP v" .. SCRIPT_VERSION
titleLbl.TextColor3 = C.textPri; titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13; titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.Parent = tBar

local sDot = Instance.new("Frame")
sDot.Size = UDim2.new(0,8,0,8); sDot.Position = UDim2.new(1,-46,0.5,-4)
sDot.BackgroundColor3 = C.green; sDot.BorderSizePixel = 0; sDot.Parent = tBar; corner(sDot,4)

local sLbl = Instance.new("TextLabel")
sLbl.Size = UDim2.new(0,30,1,0); sLbl.Position = UDim2.new(1,-35,0,0)
sLbl.BackgroundTransparency = 1; sLbl.Text = "ON"; sLbl.TextColor3 = C.green
sLbl.Font = Enum.Font.GothamBold; sLbl.TextSize = 10; sLbl.TextXAlignment = Enum.TextXAlignment.Left
sLbl.Parent = tBar

-- Content
local content = Instance.new("Frame")
content.Size = UDim2.new(1,0,0,400); content.Position = UDim2.new(0,0,0,38)
content.BackgroundTransparency = 1; content.Parent = main; pad(content, 6, 6, 10, 10)
local lay = Instance.new("UIListLayout")
lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Padding = UDim.new(0,4); lay.Parent = content

-- Section label helper
local function secLabel(text, order)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,0,0,14); l.BackgroundTransparency = 1; l.Text = text
    l.TextColor3 = C.textMut; l.Font = Enum.Font.GothamBold; l.TextSize = 9
    l.TextXAlignment = Enum.TextXAlignment.Left; l.LayoutOrder = order; l.Parent = content
end

-- Toggle row helper
local function makeToggle(label, settingKey, order, col)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,24); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = content

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65,0,1,0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local toggleBg = Instance.new("TextButton")
    toggleBg.Size = UDim2.new(0,36,0,18); toggleBg.Position = UDim2.new(1,-36,0.5,-9)
    toggleBg.BackgroundColor3 = settings[settingKey] and (col or C.green) or C.surface
    toggleBg.BorderSizePixel = 0; toggleBg.Text = ""; toggleBg.AutoButtonColor = false
    toggleBg.Parent = row; corner(toggleBg, 9)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0,14,0,14); knob.BackgroundColor3 = C.textPri; knob.BorderSizePixel = 0
    knob.Position = settings[settingKey] and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
    knob.Parent = toggleBg; corner(knob, 7)

    toggleBg.MouseButton1Click:Connect(function()
        settings[settingKey] = not settings[settingKey]
        local on = settings[settingKey]
        tw(toggleBg, {BackgroundColor3 = on and (col or C.green) or C.surface}, 0.2)
        tw(knob, {Position = on and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)}, 0.2)

        if settingKey == "enabled" then
            sDot.BackgroundColor3 = on and C.green or C.red
            sLbl.TextColor3 = on and C.green or C.red
            sLbl.Text = on and "ON" or "OFF"
        end
        if settingKey == "radar" then radarFrame.Visible = on end

        notify(label .. ": " .. (on and "ON" or "OFF"), on and C.green or C.red, 1.5)
    end)
    return toggleBg
end

-- Build settings UI
secLabel("VISUALS", 1)
makeToggle("ESP Enabled", "enabled", 2, C.accent)
makeToggle("Tracers", "tracers", 3)
makeToggle("Health Bars", "healthBars", 4)
makeToggle("Highlight", "highlight", 5, C.magenta)
makeToggle("Names", "names", 6)
makeToggle("Distance", "distance", 7)
makeToggle("Radar", "radar", 8, C.cyan)

secLabel("FILTERS", 11)
makeToggle("Exclude Team", "teamCheck", 12, C.orange)

-- Distance slider
secLabel("MAX DISTANCE: " .. settings.maxDistance, 13)
local distRow = Instance.new("Frame")
distRow.Size = UDim2.new(1,0,0,26); distRow.BackgroundTransparency = 1; distRow.LayoutOrder = 14; distRow.Parent = content

local distMinus = Instance.new("TextButton")
distMinus.Size = UDim2.new(0,26,1,0); distMinus.BackgroundColor3 = C.surface; distMinus.TextColor3 = C.textPri
distMinus.Font = Enum.Font.GothamBold; distMinus.TextSize = 16; distMinus.Text = "−"
distMinus.AutoButtonColor = false; distMinus.Parent = distRow; corner(distMinus, 6)

local distBox = Instance.new("TextBox")
distBox.Size = UDim2.new(1,-58,1,0); distBox.Position = UDim2.new(0,30,0,0)
distBox.Text = tostring(settings.maxDistance); distBox.PlaceholderText = "studs"
distBox.BackgroundColor3 = C.surface; distBox.TextColor3 = C.textPri
distBox.Font = Enum.Font.GothamBold; distBox.TextSize = 12; distBox.Parent = distRow
corner(distBox, 6); stroke(distBox)

local distPlus = Instance.new("TextButton")
distPlus.Size = UDim2.new(0,26,1,0); distPlus.Position = UDim2.new(1,-26,0,0)
distPlus.BackgroundColor3 = C.surface; distPlus.TextColor3 = C.textPri
distPlus.Font = Enum.Font.GothamBold; distPlus.TextSize = 16; distPlus.Text = "+"
distPlus.AutoButtonColor = false; distPlus.Parent = distRow; corner(distPlus, 6)

-- Distance label reference for updating text
local distSecLabel
for _, ch in ipairs(content:GetChildren()) do
    if ch:IsA("TextLabel") and ch.Text:find("MAX DISTANCE") then distSecLabel = ch break end
end

local function setDist(v)
    v = math.clamp(math.floor(v), 50, 2000)
    settings.maxDistance = v; distBox.Text = tostring(v)
    if distSecLabel then distSecLabel.Text = "MAX DISTANCE: " .. v end
end
distMinus.MouseButton1Click:Connect(function() setDist(settings.maxDistance - 50) end)
distPlus.MouseButton1Click:Connect(function() setDist(settings.maxDistance + 50) end)
distBox.FocusLost:Connect(function()
    local v = tonumber(distBox.Text)
    if v then setDist(v) else distBox.Text = tostring(settings.maxDistance) end
end)

-- Keybinds section
secLabel("KEYBINDS", 20)

local function makeKeybindRow(label, bKey, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,24); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = content
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.5,0,1,0); l.BackgroundTransparency = 1; l.Text = label
    l.TextColor3 = C.textMut; l.Font = Enum.Font.Gotham; l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = row
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.45,0,0,20); btn.Position = UDim2.new(0.55,0,0,2)
    btn.BackgroundColor3 = C.surface; btn.TextColor3 = C.orange; btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11; btn.Text = "[ "..keyName(keybinds[bKey]).." ]"; btn.AutoButtonColor = false
    btn.Parent = row; corner(btn, 6); stroke(btn)
    btn.MouseButton1Click:Connect(function()
        if waitingForBind then return end
        waitingForBind = bKey; btn.Text = "[ ... ]"; btn.TextColor3 = C.accentGlow
        local bc; bc = UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if inp.KeyCode == Enum.KeyCode.Escape then
                btn.Text = "[ "..keyName(keybinds[bKey]).." ]"; btn.TextColor3 = C.orange
                waitingForBind = nil; bc:Disconnect(); return
            end
            keybinds[bKey] = inp.KeyCode
            btn.Text = "[ "..keyName(inp.KeyCode).." ]"; btn.TextColor3 = C.orange
            waitingForBind = nil; bc:Disconnect()
            notify(label.." → ["..keyName(inp.KeyCode).."]", C.orange, 2)
        end)
    end)
end
makeKeybindRow("Toggle ESP", "toggle", 21)
makeKeybindRow("Hide Panel", "hide", 22)

-- Divider + Unload
local div = Instance.new("Frame")
div.Size = UDim2.new(1,0,0,6); div.BackgroundTransparency = 1; div.LayoutOrder = 30; div.Parent = content
local unBtn = Instance.new("TextButton")
unBtn.Size = UDim2.new(1,0,0,28); unBtn.BackgroundColor3 = C.surface; unBtn.TextColor3 = C.red
unBtn.Font = Enum.Font.GothamBold; unBtn.TextSize = 11; unBtn.Text = "⏻  Unload ESP"
unBtn.AutoButtonColor = false; unBtn.LayoutOrder = 31; unBtn.Parent = content; corner(unBtn, 8)

-- Credit
local crd = Instance.new("TextLabel")
crd.Size = UDim2.new(1,0,0,14); crd.BackgroundTransparency = 1
crd.Text = "by FusedHann · v"..SCRIPT_VERSION
crd.TextColor3 = Color3.fromRGB(60,60,80); crd.Font = Enum.Font.Gotham; crd.TextSize = 9
crd.LayoutOrder = 32; crd.Parent = content

-- Finalize height
local totalH = 38 + 12 + lay.AbsoluteContentSize.Y + 12
totalH = math.max(totalH, 420)
main.Size = UDim2.new(0, 220, 0, totalH)

-- ═══════════════════════════════════════════════════════════
-- Draggable
-- ═══════════════════════════════════════════════════════════
local dragging, dragInput, dragStart, startPos = false
table.insert(connections, tBar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = inp.Position; startPos = main.Position
        inp.Changed:Connect(function() if inp.UserInputState == Enum.UserInputState.End then dragging = false end end)
    end
end))
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
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if UserInputService:GetFocusedTextBox() then return end
    if inp.KeyCode == keybinds.toggle then
        settings.enabled = not settings.enabled
        local on = settings.enabled
        sDot.BackgroundColor3 = on and C.green or C.red
        sLbl.TextColor3 = on and C.green or C.red; sLbl.Text = on and "ON" or "OFF"
        notify("ESP " .. (on and "Enabled ✓" or "Disabled ✗"), on and C.green or C.red)
    elseif inp.KeyCode == keybinds.hide then
        gui.Enabled = not gui.Enabled
        notify(gui.Enabled and "Panel Visible" or "Panel Hidden", C.accent, 1.5)
    end
end))

-- ═══════════════════════════════════════════════════════════
-- Unload
-- ═══════════════════════════════════════════════════════════
local function unload()
    notify("ESP Unloaded — Goodbye!", C.red, 1.5)
    task.wait(0.4); running = false
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
    main.Position = UDim2.new(tp.X.Scale, tp.X.Offset, tp.Y.Scale, tp.Y.Offset - 40)
    main.BackgroundTransparency = 0.5
    task.wait(0.05)
    tw(main, {Position = tp, BackgroundTransparency = 0}, 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    task.wait(0.4)
    notify("👁 ESP v"..SCRIPT_VERSION.." Loaded", C.accent, 3)
end
