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

local SCRIPT_VERSION = "2.0"
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
    bg           = Color3.fromRGB(18, 18, 18),    -- Dark minimalist window
    bgSec        = Color3.fromRGB(24, 24, 24),    -- Header & secondary
    surface      = Color3.fromRGB(32, 32, 32),    -- UI elements
    surfHover    = Color3.fromRGB(42, 42, 42),
    accent       = Color3.fromRGB(240, 240, 240), -- Sleek white/gray accent
    accentGlow   = Color3.fromRGB(255, 255, 255),
    green        = Color3.fromRGB(50, 205, 100),  -- (Used for ESP Health)
    red          = Color3.fromRGB(235, 70, 80),   -- (Used for ESP Radar/Health)
    orange       = Color3.fromRGB(255, 160, 50),
    cyan         = Color3.fromRGB(0, 200, 255),   -- (Used for ESP Team)
    magenta      = Color3.fromRGB(255, 60, 180),  -- (Used for ESP Chams)
    yellow       = Color3.fromRGB(255, 220, 50),  -- (Used for ESP Health)
    textPri      = Color3.fromRGB(245, 245, 245),
    textMut      = Color3.fromRGB(150, 150, 150),
    divider      = Color3.fromRGB(40, 40, 40),
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
    local myPos  = camCF.Position -- FIX: Core distance from camera, enabling ESP while droning/spectating
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
            local startPos = Vector2.new(vpSize.X / 2, vpSize.Y / 2)
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

local tabHome = Instance.new("TextButton", tBar)
tabHome.Size = UDim2.new(0.5,0,1,0); tabHome.Position = UDim2.new(0,0,0,0)
tabHome.BackgroundTransparency = 1; tabHome.Text = "Home"
tabHome.TextColor3 = C.accent; tabHome.Font = Enum.Font.GothamMedium; tabHome.TextSize = 12

local tabESP = Instance.new("TextButton", tBar)
tabESP.Size = UDim2.new(0.5,0,1,0); tabESP.Position = UDim2.new(0.5,0,0,0)
tabESP.BackgroundTransparency = 1; tabESP.Text = "ESP Visuals"
tabESP.TextColor3 = C.textMut; tabESP.Font = Enum.Font.GothamMedium; tabESP.TextSize = 12

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
pageESP.CanvasSize = UDim2.new(0,320,0,760)
pad(pageESP, 10, 10, 14, 14)
local eLay = Instance.new("UIListLayout", pageESP)
eLay.SortOrder = Enum.SortOrder.LayoutOrder; eLay.Padding = UDim.new(0, 6)

local uiUpdaters = {}

local function secLabel(text, order)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,0,0,16); l.BackgroundTransparency = 1; l.Text = text
    l.TextColor3 = C.textMut; l.Font = Enum.Font.GothamMedium; l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left; l.LayoutOrder = order; l.Parent = pageESP
end

local function makeToggle(label, settingKey, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,26); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = pageESP

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65,0,1,0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local toggleBg = Instance.new("TextButton")
    toggleBg.Size = UDim2.new(0,34,0,16); toggleBg.Position = UDim2.new(1,-34,0.5,-8)
    toggleBg.BackgroundColor3 = settings[settingKey] and C.green or C.surface
    toggleBg.BorderSizePixel = 0; toggleBg.Text = ""; toggleBg.AutoButtonColor = false
    toggleBg.Parent = row; corner(toggleBg, 8)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0,12,0,12); knob.BackgroundColor3 = settings[settingKey] and C.bg or C.red; knob.BorderSizePixel = 0
    knob.Position = settings[settingKey] and UDim2.new(1,-14,0.5,-6) or UDim2.new(0,2,0.5,-6)
    knob.Parent = toggleBg; corner(knob, 6)

    local function updateVisual(on)
        tw(toggleBg, {BackgroundColor3 = on and C.green or C.surface}, 0.2)
        tw(knob, {
            Position = on and UDim2.new(1,-14,0.5,-6) or UDim2.new(0,2,0.5,-6),
            BackgroundColor3 = on and C.bg or C.red
        }, 0.2)
    end
    uiUpdaters[settingKey] = updateVisual

    toggleBg.MouseButton1Click:Connect(function()
        settings[settingKey] = not settings[settingKey]
        local on = settings[settingKey]
        updateVisual(on)
        if settingKey == "radar" then radarFrame.Visible = on end
    end)
    return row
end

local function makeSlider(label, settingKey, min, max, isFloat, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,24); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = pageESP

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.4,0,1,0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local sliderBg = Instance.new("TextButton")
    sliderBg.Size = UDim2.new(0.4,0,0,4); sliderBg.Position = UDim2.new(0.45,0,0.5,-2)
    sliderBg.BackgroundColor3 = C.surface; sliderBg.BorderSizePixel = 0; sliderBg.Text = ""
    sliderBg.AutoButtonColor = false; sliderBg.Parent = row; corner(sliderBg, 2)

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
    valLbl.Size = UDim2.new(0.15,0,1,0); valLbl.Position = UDim2.new(0.85,0,0,0)
    valLbl.BackgroundTransparency = 1; 
    valLbl.Text = isFloat and string.format("%.2f", val) or tostring(val)
    valLbl.TextColor3 = C.textPri; valLbl.Font = Enum.Font.GothamMedium; valLbl.TextSize = 11
    valLbl.TextXAlignment = Enum.TextXAlignment.Right; valLbl.Parent = row

    local dragging = false
    sliderBg.MouseButton1Down:Connect(function() dragging = true end)
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

local function makeColorPicker(label, settingKey, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,26); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = pageESP

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.3,0,1,0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = C.textPri; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local hexBox = Instance.new("TextBox")
    hexBox.Size = UDim2.new(0,60,0,20); hexBox.Position = UDim2.new(0.3,0,0.5,-10)
    hexBox.BackgroundColor3 = C.surface; hexBox.TextColor3 = C.textPri
    hexBox.Font = Enum.Font.GothamMedium; hexBox.TextSize = 10
    hexBox.Text = "#" .. settings[settingKey]:ToHex():upper()
    hexBox.Parent = row; corner(hexBox, 4); stroke(hexBox, C.divider, 1)

    local presetCont = Instance.new("Frame")
    presetCont.Size = UDim2.new(0.5, 0, 1, 0); presetCont.Position = UDim2.new(0.5, 0, 0, 0)
    presetCont.BackgroundTransparency = 1; presetCont.Parent = row
    local pl = Instance.new("UIListLayout"); pl.FillDirection = Enum.FillDirection.Horizontal
    pl.VerticalAlignment = Enum.VerticalAlignment.Center; pl.Padding = UDim.new(0,6)
    pl.HorizontalAlignment = Enum.HorizontalAlignment.Right; pl.Parent = presetCont
    
    local presetColors = { C.red, C.green, C.cyan, C.magenta, C.yellow, C.accentGlow }
    for _, col in ipairs(presetColors) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0,18,0,18); btn.BackgroundColor3 = col
        btn.BorderSizePixel = 0; btn.Text = ""; btn.Parent = presetCont; corner(btn, 9)
        btn.MouseButton1Click:Connect(function()
            settings[settingKey] = col
            hexBox.Text = "#" .. col:ToHex():upper()
        end)
    end

    hexBox.FocusLost:Connect(function()
        local txt = hexBox.Text:gsub("#", "")
        pcall(function()
            local c = Color3.fromHex(txt)
            settings[settingKey] = c
            hexBox.Text = "#" .. c:ToHex():upper()
        end)
    end)
end

secLabel("VISUALS", 1)
makeToggle("ESP Enabled", "enabled", 2)
makeToggle("Tracers", "tracers", 3)
makeToggle("Health Bars", "healthBars", 4)
makeToggle("Names", "names", 5)
makeToggle("Distance", "distance", 6)
makeToggle("Radar", "radar", 7)
makeSlider("Max Distance", "maxDistance", 50, 2000, false, 8)

secLabel("CHAMS CONFIG", 10)
makeToggle("Enable Chams", "highlight", 11)
makeToggle("Always On Top", "chamsDepth", 12)
makeSlider("Fill Transp.", "chamsFill", 0, 1, true, 13)
makeSlider("Outline Transp.", "chamsOutline", 0, 1, true, 14)
makeColorPicker("Color", "chamsColor", 15)

secLabel("FILTERS", 20)
makeToggle("Exclude Team", "teamCheck", 21)

secLabel("KEYBINDS", 30)
local function makeKeybindRow(label, bKey, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,26); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = pageESP
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
            if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if inp.KeyCode == Enum.KeyCode.Escape then
                btn.Text = keyName(keybinds[bKey]); btn.TextColor3 = C.textMut; btn.BackgroundColor3 = C.surface
                waitingForBind = nil; bc:Disconnect(); return
            end
            keybinds[bKey] = inp.KeyCode
            btn.Text = keyName(inp.KeyCode); btn.TextColor3 = C.textMut; btn.BackgroundColor3 = C.surface
            waitingForBind = nil; bc:Disconnect()
            notify(label.." -> "..keyName(inp.KeyCode), C.textPri, 2)
        end)
    end)
end
makeKeybindRow("Toggle ESP", "toggle", 31)
makeKeybindRow("Hide Panel", "hide", 32)

local unBtn = Instance.new("TextButton")
unBtn.Size = UDim2.new(1,0,0,28); unBtn.BackgroundColor3 = C.bgSec; unBtn.TextColor3 = C.red
unBtn.Font = Enum.Font.GothamMedium; unBtn.TextSize = 11; unBtn.Text = "Unload Utilities"
unBtn.AutoButtonColor = false; unBtn.LayoutOrder = 40; unBtn.Parent = pageESP; corner(unBtn, 4); stroke(unBtn, C.divider, 1)

main.Size = UDim2.new(0, 360, 0, 440)

-- Tab logic
tabHome.MouseButton1Click:Connect(function()
    tabHome.TextColor3 = C.accent; tabESP.TextColor3 = C.textMut
    pageHome.Visible = true; pageESP.Visible = false
end)
tabESP.MouseButton1Click:Connect(function()
    tabESP.TextColor3 = C.accent; tabHome.TextColor3 = C.textMut
    pageESP.Visible = true; pageHome.Visible = false
end)

-- ═══════════════════════════════════════════════════════════
-- Draggable
-- ═══════════════════════════════════════════════════════════
local dragging, dragInput, dragStart, startPos = false
local function makeDrag(obj)
    table.insert(connections, obj.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = inp.Position; startPos = main.Position
            inp.Changed:Connect(function() if inp.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end))
end
makeDrag(tBar); makeDrag(tabHome); makeDrag(tabESP)

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
        if uiUpdaters["enabled"] then uiUpdaters["enabled"](settings.enabled) end
        notify("ESP " .. (settings.enabled and "Enabled" or "Disabled"), C.accent)
    elseif inp.KeyCode == keybinds.hide then
        gui.Enabled = not gui.Enabled
        notify(gui.Enabled and "Panel Visible" or "Panel Hidden", C.accent, 1.5)
    end
end))

-- ═══════════════════════════════════════════════════════════
-- Unload
-- ═══════════════════════════════════════════════════════════
local function unload()
    notify("Utilities Unloaded", C.textMut, 1.5)
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
        end 
    end
    task.wait(0.4)
    notify("Lightweight Utilities Loaded", C.textPri, 3)
end
