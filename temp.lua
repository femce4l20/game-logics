local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

local animator = nil
local originalHipHeight = nil

player.CharacterAdded:Connect(function(c)
	character = c
	animator = nil
	originalHipHeight = nil
end)

-- CONFIG
local CONFIG_URL = "https://raw.githubusercontent.com/femce4l20/new/refs/heads/main/tabs.lua"

-- Force GitHub-only mode:
-- When true, the script will skip local file reads/writes entirely and only use the GitHub URL.
local FORCE_GITHUB_ONLY = false

-- Local file settings
local LOCAL_FOLDER = "e"
local LOCAL_FILE = LOCAL_FOLDER .. "/tabs.lua"

local fallbackConfig = {
	{ name = "Emotes", animations = {
		{ id = "rbxassetid://124575754112740", name = "shiii ts broke frfr", start = nil, finish = nil, hipHeight = -5, speed = 1 },
	}},
	{ name = "Test", animations = {
		{ id = "90651744667158", name = "pingpong test", start = 0, finish = 5, pingpong = true, speed = 1.5 },
	}},
}

local function normalizeAnimationId(raw)
	if not raw then return nil end
	raw = tostring(raw):gsub("^%s*(.-)%s*$", "%1")
	local digits = raw:match("(%d+)")
	if digits then
		return "rbxassetid://" .. digits
	end
	if raw:match("^rbxassetid://") then return raw end
	return nil
end

-- Synapse file helpers
local localCacheSupported = nil

local function ensureLocalFolder()
	if makefolder then
		pcall(function()
			if not isfolder or not isfolder(LOCAL_FOLDER) then
				if makefolder then makefolder(LOCAL_FOLDER) end
			end
		end)
	end
end

local function probeLocalCacheSupport()
	if FORCE_GITHUB_ONLY then
		localCacheSupported = false
		return false
	end

	if localCacheSupported ~= nil then
		return localCacheSupported
	end

	if not (writefile and readfile) then
		localCacheSupported = false
		return false
	end

	ensureLocalFolder()

	local probeFile = LOCAL_FOLDER .. "/.__cache_probe.tmp"
	local ok = pcall(function()
		writefile(probeFile, "probe")
		local _ = readfile(probeFile)
		if delfile then
			pcall(function()
				delfile(probeFile)
			end)
		end
	end)

	localCacheSupported = ok
	return localCacheSupported
end

local function localFileExists()
	if not probeLocalCacheSupport() then
		return false
	end
	if isfile then
		local ok, res = pcall(function() return isfile(LOCAL_FILE) end)
		return ok and res
	end
	return false
end

local function readLocalFile()
	if not probeLocalCacheSupport() then
		return nil
	end
	if readfile and localFileExists() then
		local ok, content = pcall(function() return readfile(LOCAL_FILE) end)
		if ok then return content end
	end
	return nil
end

local function writeLocalFile(content)
	if not probeLocalCacheSupport() then
		return false
	end
	if writefile then
		local ok = pcall(function()
			ensureLocalFolder()
			writefile(LOCAL_FILE, content)
		end)
		if not ok then
			localCacheSupported = false
			return false
		end
		return true
	end
	localCacheSupported = false
	return false
end

local function deleteLocalFile()
	if not probeLocalCacheSupport() then
		return false
	end
	if delfile and localFileExists() then
		pcall(function() delfile(LOCAL_FILE) end)
	end
	return true
end

local function applyDefaultAnimationFields(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	for _, tab in ipairs(tbl) do
		for _, anim in ipairs(tab.animations or {}) do
			if anim.speed == nil then
				anim.speed = 1
			end
		end
	end
	return tbl
end

local function serializeConfig(tbl)
	local lines = {}
	table.insert(lines, "return {")
	for _, tab in ipairs(tbl) do
		local tabName = tab.name or ""
		table.insert(lines, ("  { name = %q, animations = {"):format(tabName))
		for _, anim in ipairs(tab.animations or {}) do
			local pieces = {}
			if anim.id ~= nil then table.insert(pieces, ("id = %q"):format(anim.id)) end
			if anim.name ~= nil then table.insert(pieces, ("name = %q"):format(anim.name)) end
			if anim.start ~= nil then table.insert(pieces, ("start = %s"):format(tostring(anim.start))) end
			if anim.finish ~= nil then table.insert(pieces, ("finish = %s"):format(tostring(anim.finish))) end
			if anim.hipHeight ~= nil then table.insert(pieces, ("hipHeight = %s"):format(tostring(anim.hipHeight))) end
			if anim.pingpong ~= nil then table.insert(pieces, ("pingpong = %s"):format(tostring(anim.pingpong))) end
			if anim.speed ~= nil and anim.speed ~= 1 then
				table.insert(pieces, ("speed = %s"):format(tostring(anim.speed)))
			end
			table.insert(lines, "    { " .. table.concat(pieces, ", ") .. " },")
		end
		table.insert(lines, "  } },")
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

local function loadRemoteOrLocalConfig()
	local useLocalCache = probeLocalCacheSupport()

	if useLocalCache then
		local localContent = readLocalFile()
		if localContent then
			local ok, f = pcall(function() return loadstring(localContent) end)
			if ok and type(f) == "function" then
				local success, result = pcall(function() return f() end)
				if success and type(result) == "table" then
					return applyDefaultAnimationFields(result)
				end
			end
		end
	end

	local ok, result = pcall(function()
		local code = game:HttpGet(CONFIG_URL)
		local f = loadstring(code)
		assert(type(f) == "function", "Code did not return function")
		return f()
	end)

	if ok and type(result) == "table" then
		result = applyDefaultAnimationFields(result)
		if useLocalCache then
			writeLocalFile(serializeConfig(result))
		end
		return result
	else
		if useLocalCache then
			writeLocalFile(serializeConfig(fallbackConfig))
		end
		return applyDefaultAnimationFields(fallbackConfig)
	end
end

local tabConfig = loadRemoteOrLocalConfig()

local function findTabIndexByName(name)
	for i, t in ipairs(tabConfig) do
		if t.name == name then return i end
	end
	return nil
end

local function ensureTabExists(name)
	local idx = findTabIndexByName(name)
	if idx then return idx end
	local newTab = { name = name, animations = {} }
	table.insert(tabConfig, newTab)
	writeLocalFile(serializeConfig(tabConfig))
	return #tabConfig
end

-- ===== UI THEME =====
local Theme = {
	BG = Color3.fromRGB(13, 13, 16),
	Panel = Color3.fromRGB(21, 21, 26),
	Panel2 = Color3.fromRGB(28, 28, 34),
	Surface = Color3.fromRGB(35, 35, 42),
	Surface2 = Color3.fromRGB(42, 42, 50),
	Stroke = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(244, 244, 246),
	Muted = Color3.fromRGB(180, 180, 188),
	Accent = Color3.fromRGB(255, 186, 202), -- light pink
	AccentHover = Color3.fromRGB(255, 205, 216),
	AccentDeep = Color3.fromRGB(245, 145, 170),
	AccentSoft = Color3.fromRGB(255, 222, 230),
	Danger = Color3.fromRGB(165, 78, 94),
	DangerHover = Color3.fromRGB(184, 94, 111),
	Success = Color3.fromRGB(92, 145, 114),
	SuccessHover = Color3.fromRGB(110, 167, 130),
}

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Stroke
	stroke.Transparency = transparency or 0.84
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

local function addPadding(parent, left, right, top, bottom)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, left or 0)
	pad.PaddingRight = UDim.new(0, right or 0)
	pad.PaddingTop = UDim.new(0, top or 0)
	pad.PaddingBottom = UDim.new(0, bottom or 0)
	pad.Parent = parent
	return pad
end

local function tween(obj, info, props)
	return TweenService:Create(obj, info or TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
end

local function softPanel(frame, radius)
	frame.BackgroundColor3 = Theme.Panel
	frame.BorderSizePixel = 0
	addCorner(frame, radius or 14)
	addStroke(frame, Theme.Stroke, 0.9, 1)
end

local function softButton(btn, opts)
	opts = opts or {}
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.Font = opts.Font or Enum.Font.Gotham
	btn.TextSize = opts.TextSize or 13
	btn.TextColor3 = opts.TextColor3 or Theme.Text
	btn.BackgroundColor3 = opts.BackgroundColor3 or Theme.Surface
	addCorner(btn, opts.CornerRadius or 10)
	addStroke(btn, Theme.Stroke, opts.StrokeTransparency or 0.88, 1)

	local normal = btn.BackgroundColor3
	local hover = opts.HoverColor3 or Theme.Surface2
	local selected = opts.SelectedColor3 or Theme.Accent
	local selectedText = opts.SelectedTextColor3 or Color3.fromRGB(20, 20, 22)

	btn.MouseEnter:Connect(function()
		if btn:GetAttribute("Selected") then
			tween(btn, TweenInfo.new(0.15), { BackgroundColor3 = selected }):Play()
		else
			tween(btn, TweenInfo.new(0.15), { BackgroundColor3 = hover }):Play()
		end
	end)

	btn.MouseLeave:Connect(function()
		if btn:GetAttribute("Selected") then
			tween(btn, TweenInfo.new(0.15), { BackgroundColor3 = selected, TextColor3 = selectedText }):Play()
		else
			tween(btn, TweenInfo.new(0.15), { BackgroundColor3 = normal }):Play()
		end
	end)
end

local function softInput(input, opts)
	opts = opts or {}
	input.BorderSizePixel = 0
	input.BackgroundColor3 = opts.BackgroundColor3 or Theme.Surface
	input.TextColor3 = opts.TextColor3 or Theme.Text
	input.PlaceholderColor3 = opts.PlaceholderColor3 or Theme.Muted
	input.Font = opts.Font or Enum.Font.Gotham
	input.TextSize = opts.TextSize or 13
	addCorner(input, opts.CornerRadius or 10)
	addStroke(input, Theme.Stroke, opts.StrokeTransparency or 0.88, 1)
end

local function softLabel(lbl, muted)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Gotham
	lbl.TextColor3 = muted and Theme.Muted or Theme.Text
end

local function setSelected(btn, selected)
	btn:SetAttribute("Selected", selected and true or false)
	if selected then
		btn.BackgroundColor3 = Theme.Accent
		btn.TextColor3 = Color3.fromRGB(22, 20, 22)
	else
		btn.BackgroundColor3 = Theme.Surface
		btn.TextColor3 = Theme.Text
	end
end

-- ===== UI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "imationGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Name = "Main"
mainFrame.Size = UDim2.new(0, 430, 0, 360)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = Theme.BG
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui
softPanel(mainFrame, 16)

local mainGradient = Instance.new("UIGradient")
mainGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 18, 22)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 13, 16)),
})
mainGradient.Rotation = 90
mainGradient.Parent = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 38)
titleBar.BackgroundColor3 = Theme.Panel
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
addCorner(titleBar, 16)

local titleClip = Instance.new("Frame")
titleClip.Name = "TitleClip"
titleClip.Size = UDim2.new(1, 0, 0, 20)
titleClip.Position = UDim2.new(0, 0, 1, -20)
titleClip.BackgroundColor3 = Theme.Panel
titleClip.BorderSizePixel = 0
titleClip.Parent = titleBar

local titleGradient = Instance.new("UIGradient")
titleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(29, 29, 35)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 25)),
})
titleGradient.Rotation = 90
titleGradient.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -168, 1, 0)
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "imation"
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 15
titleLabel.TextColor3 = Theme.Text
titleLabel.Parent = titleBar

local titleSub = Instance.new("TextLabel")
titleSub.Size = UDim2.new(1, -168, 1, 0)
titleSub.Position = UDim2.new(0, 14, 0, 15)
titleSub.BackgroundTransparency = 1
titleSub.Text = "Lets get that freak on😛"
titleSub.TextXAlignment = Enum.TextXAlignment.Left
titleSub.Font = Enum.Font.Gotham
titleSub.TextSize = 10
titleSub.TextColor3 = Theme.Muted
titleSub.Parent = titleBar

local function makeTitleButton(text, posX, bg, hover, textColor)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 28, 0, 28)
	btn.Position = UDim2.new(1, posX, 0, 5)
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.TextColor3 = textColor or Theme.Text
	btn.BackgroundColor3 = bg or Theme.Surface
	btn.Parent = titleBar
	softButton(btn, {
		CornerRadius = 10,
		BackgroundColor3 = bg or Theme.Surface,
		HoverColor3 = hover or Theme.Surface2,
		TextColor3 = textColor or Theme.Text,
		StrokeTransparency = 0.9,
		TextSize = 14,
	})
	return btn
end

local closeBtn = makeTitleButton("×", -8, Theme.Danger, Theme.DangerHover, Theme.Text)
local minimizeBtn = makeTitleButton("–", -42, Theme.Surface, Theme.Surface2, Theme.Text)
local infoBtn = makeTitleButton("i", -76, Theme.Surface, Theme.AccentHover, Theme.Text)

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchBox"
searchBox.Size = UDim2.new(1, -18, 0, 32)
searchBox.Position = UDim2.new(0, 9, 0, 44)
searchBox.PlaceholderText = "Search animations..."
searchBox.BackgroundColor3 = Theme.Surface
searchBox.TextColor3 = Theme.Text
searchBox.Font = Enum.Font.Gotham
searchBox.Text = ""
searchBox.TextSize = 13
searchBox.ClearTextOnFocus = false
searchBox.Parent = mainFrame
softInput(searchBox, { BackgroundColor3 = Theme.Surface, StrokeTransparency = 0.9 })

local tabsFrame = Instance.new("ScrollingFrame")
tabsFrame.Name = "Tabs"
tabsFrame.Size = UDim2.new(0, 124, 1, -84)
tabsFrame.Position = UDim2.new(0, 0, 0, 84)
tabsFrame.BackgroundTransparency = 1
tabsFrame.BorderSizePixel = 0
tabsFrame.Parent = mainFrame
tabsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
tabsFrame.ScrollBarThickness = 6
tabsFrame.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
tabsFrame.ScrollingDirection = Enum.ScrollingDirection.Y
addPadding(tabsFrame, 10, 6, 6, 6)

local tabsList = Instance.new("UIListLayout")
tabsList.Parent = tabsFrame
tabsList.Padding = UDim.new(0, 8)
tabsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabsList.SortOrder = Enum.SortOrder.LayoutOrder

tabsList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	local total = tabsList.AbsoluteContentSize.Y
	tabsFrame.CanvasSize = UDim2.new(0, 0, 0, total + 12)
end)

local contentFrame = Instance.new("Frame")
contentFrame.Name = "Content"
contentFrame.Size = UDim2.new(1, -124, 1, -84)
contentFrame.Position = UDim2.new(0, 124, 0, 84)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = mainFrame

local tabContentFolder = Instance.new("Folder")
tabContentFolder.Name = "TabContents"
tabContentFolder.Parent = contentFrame

local searchContent = Instance.new("Frame")
searchContent.Name = "Search_Content"
searchContent.Size = UDim2.new(1, 0, 1, 0)
searchContent.BackgroundTransparency = 1
searchContent.Parent = tabContentFolder
searchContent.Visible = false

local searchScroll = Instance.new("ScrollingFrame")
searchScroll.Size = UDim2.new(1, -14, 1, -14)
searchScroll.Position = UDim2.new(0, 7, 0, 7)
searchScroll.BackgroundTransparency = 1
searchScroll.BorderSizePixel = 0
searchScroll.Parent = searchContent
searchScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
searchScroll.ScrollBarThickness = 6
searchScroll.ScrollingDirection = Enum.ScrollingDirection.Y

local searchListLayout = Instance.new("UIListLayout")
searchListLayout.Parent = searchScroll
searchListLayout.SortOrder = Enum.SortOrder.LayoutOrder
searchListLayout.Padding = UDim.new(0, 8)

local buttonStates = {
	normal = Theme.Surface,
	hover = Theme.Surface2,
	selected = Theme.Accent,
	playing = Theme.AccentDeep,
	disabled = Color3.fromRGB(58, 58, 64)
}

local function styleButton(btn)
	btn.BackgroundColor3 = buttonStates.normal
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 13
	btn.TextColor3 = Theme.Text
	btn.Size = UDim2.new(1, -12, 0, 40)
	btn.AnchorPoint = Vector2.new(0, 0)
	addCorner(btn, 10)
	addStroke(btn, Theme.Stroke, 0.9, 1)

	btn.MouseEnter:Connect(function()
		if btn.BackgroundColor3 ~= buttonStates.playing and btn.BackgroundColor3 ~= buttonStates.selected then
			tween(btn, TweenInfo.new(0.15), { BackgroundColor3 = buttonStates.hover }):Play()
		end
	end)

	btn.MouseLeave:Connect(function()
		if btn.BackgroundColor3 ~= buttonStates.playing and btn.BackgroundColor3 ~= buttonStates.selected then
			tween(btn, TweenInfo.new(0.15), { BackgroundColor3 = buttonStates.normal }):Play()
		end
	end)
end

-- Runtime & playback
local currentTabName = nil
local tabButtons = {}
local animationButtons = {}
local searchAnimationButtons = {}
local selectedAnim = nil

local currentTrack = nil
local currentConnections = {}
local currentMeta = nil
local currentlyPlayingButton = nil

local function resetHipHeight()
	local char = character or player.Character
	if not char then
		originalHipHeight = nil
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid and originalHipHeight ~= nil then
		pcall(function()
			humanoid.HipHeight = originalHipHeight
		end)
	end
	originalHipHeight = nil
end

local function cleanupCurrent()
	if currentTrack then
		pcall(function() currentTrack:Stop(0) end)
	end
	for _, disconnect in ipairs(currentConnections) do
		pcall(function() disconnect() end)
	end
	currentConnections = {}
	currentTrack = nil
	currentMeta = nil

	if currentlyPlayingButton then
		currentlyPlayingButton.BackgroundColor3 = buttonStates.normal
		currentlyPlayingButton.TextColor3 = Theme.Text
		currentlyPlayingButton = nil
	end

	for _, btnList in pairs(animationButtons) do
		if type(btnList) == "table" then
			for _, btn in ipairs(btnList) do
				if btn.BackgroundColor3 == buttonStates.playing then
					btn.BackgroundColor3 = buttonStates.normal
					btn.TextColor3 = Theme.Text
				end
			end
		end
	end
	for _, btn in ipairs(searchAnimationButtons) do
		if btn.BackgroundColor3 == buttonStates.playing then
			btn.BackgroundColor3 = buttonStates.normal
			btn.TextColor3 = Theme.Text
		end
	end

	resetHipHeight()
end

local function getAnimator()
	local char = character or player.Character
	if not char then return nil end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animController = humanoid:FindFirstChildOfClass("Animator")
	if not animController then
		animController = Instance.new("Animator")
		animController.Parent = humanoid
	end
	return animController
end

local function playAnimation(animId, startTime, endTime, button, hipOffset, pingpong, speed)
	if button == currentlyPlayingButton and currentTrack then
		cleanupCurrent()
		return
	end

	if currentTrack then
		for _, disconnect in ipairs(currentConnections) do
			pcall(function() disconnect() end)
		end
		currentConnections = {}
		pcall(function() currentTrack:Stop(0) end)
		currentTrack = nil
		currentMeta = nil

		if currentlyPlayingButton then
			currentlyPlayingButton.BackgroundColor3 = buttonStates.normal
			currentlyPlayingButton.TextColor3 = Theme.Text
			currentlyPlayingButton = nil
		end
		resetHipHeight()
	end

	animator = getAnimator()
	if not animator then
		warn("[imation] No animator/humanoid available.")
		return
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	pcall(function() anim.Priority = Enum.AnimationPriority.Action end)

	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if not ok or not track then
		warn("[imation] Failed to load animation:", animId)
		anim:Destroy()
		return
	end

	pcall(function()
		if track.Priority then
			track.Priority = Enum.AnimationPriority.Action
		end
	end)

	currentTrack = track
	currentlyPlayingButton = button
	currentMeta = {
		animationId = animId,
		start = startTime,
		finish = endTime,
		looping = true,
		pingpong = pingpong,
		speed = speed or 1,
	}

	if button then
		button.BackgroundColor3 = buttonStates.playing
		button.TextColor3 = Color3.fromRGB(28, 22, 24)
	end

	if hipOffset ~= nil then
		local char = character or player.Character
		if char then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				if originalHipHeight == nil then
					originalHipHeight = humanoid.HipHeight
				end
				local clamped = math.clamp(tonumber(hipOffset) or 0, -5, 5)
				pcall(function()
					humanoid.HipHeight = originalHipHeight + clamped
				end)
			end
		end
	end

	local actualStart = startTime or 0
	local actualEnd = endTime or (track.Length or 9999)
	if actualEnd <= actualStart then
		warn("[imation] Invalid segment: end time must be greater than start time")
		cleanupCurrent()
		return
	end

	track.Looped = true
	track:Play()
	track.TimePosition = actualStart

	local speedFactor = speed or 1

	if pingpong then
		local direction = 1
		track:AdjustSpeed(direction * speedFactor)

		local heartbeatConn
		heartbeatConn = RunService.Heartbeat:Connect(function()
			if not track or not track.IsPlaying then
				return
			end
			local okPos, currentPos = pcall(function() return track.TimePosition end)
			if not okPos then return end

			if direction == 1 and currentPos >= actualEnd then
				direction = -1
				track:AdjustSpeed(direction * speedFactor)
				track.TimePosition = actualEnd
			elseif direction == -1 and currentPos <= actualStart then
				direction = 1
				track:AdjustSpeed(direction * speedFactor)
				track.TimePosition = actualStart
			end
		end)

		table.insert(currentConnections, function()
			if heartbeatConn and heartbeatConn.Connected then
				heartbeatConn:Disconnect()
			end
		end)
	else
		track:AdjustSpeed(speedFactor)
		local heartbeatConn
		heartbeatConn = RunService.Heartbeat:Connect(function()
			if not track or not track.IsPlaying then
				return
			end
			local okPos, currentPos = pcall(function() return track.TimePosition end)
			if not okPos then return end

			if currentPos >= actualEnd then
				track.TimePosition = actualStart
			end
		end)

		table.insert(currentConnections, function()
			if heartbeatConn and heartbeatConn.Connected then
				heartbeatConn:Disconnect()
			end
		end)
	end

	local stoppedConn
	stoppedConn = track.Stopped:Connect(function()
		cleanupCurrent()
	end)
	table.insert(currentConnections, function()
		if stoppedConn and stoppedConn.Connected then
			stoppedConn:Disconnect()
		end
	end)
end

-- Search
local function performSearch(searchText)
	searchText = string.lower(searchText)
	for _, btn in ipairs(searchAnimationButtons) do
		btn:Destroy()
	end
	searchAnimationButtons = {}

	if searchText == "" then
		searchContent.Visible = false
		if currentTabName then
			for _, child in ipairs(tabContentFolder:GetChildren()) do
				if child:IsA("Frame") and child.Name == currentTabName .. "_Content" then
					child.Visible = true
				end
			end
		end
		return
	end

	for _, child in ipairs(tabContentFolder:GetChildren()) do
		if child:IsA("Frame") then
			child.Visible = false
		end
	end
	searchContent.Visible = true

	local allAnimations = {}
	for _, tab in ipairs(tabConfig) do
		for _, anim in ipairs(tab.animations or {}) do
			table.insert(allAnimations, {
				data = anim,
				tabName = tab.name
			})
		end
	end

	local searchResults = {}
	for _, animData in ipairs(allAnimations) do
		local animName = string.lower(animData.data.name or "")
		if string.find(animName, searchText, 1, true) then
			table.insert(searchResults, animData)
		end
	end

	for i, result in ipairs(searchResults) do
		local anim = result.data
		local btn = Instance.new("TextButton")
		btn.Name = ("SearchAnimBtn_%d"):format(i)
		styleButton(btn)
		btn.Text = anim.name .. " (" .. result.tabName .. ")"
		btn.Parent = searchScroll

		local meta = {
			rawId = anim.id,
			name = anim.name or btn.Text,
			start = anim.start,
			finish = anim.finish,
			hipHeight = anim.hipHeight,
			pingpong = anim.pingpong,
			speed = anim.speed or 1,
		}

		table.insert(searchAnimationButtons, btn)

		btn.MouseButton1Click:Connect(function()
			for _, b in ipairs(searchAnimationButtons) do
				if b ~= btn then
					b.BackgroundColor3 = buttonStates.normal
					b.TextColor3 = Theme.Text
				end
			end

			local normalized = normalizeAnimationId(meta.rawId)
			if not normalized then
				warn("[imation] Invalid animation id:", meta.rawId)
				return
			end
			playAnimation(normalized, meta.start, meta.finish, btn, meta.hipHeight, meta.pingpong, meta.speed)
		end)
	end

	local function updateSearchCanvas()
		local total = searchListLayout.AbsoluteContentSize.Y
		searchScroll.CanvasSize = UDim2.new(0, 0, 0, total + 12)
	end
	updateSearchCanvas()
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	performSearch(searchBox.Text)
end)

-- Create tab content
local function createTabContent(tabName, animations)
	local content = Instance.new("Frame")
	content.Name = tabName .. "_Content"
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.Parent = tabContentFolder
	content.Visible = false

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -14, 1, -14)
	scroll.Position = UDim2.new(0, 7, 0, 7)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Parent = content
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y

	local listLayout = Instance.new("UIListLayout")
	listLayout.Parent = scroll
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)

	animationButtons[tabName] = {}

	local function buildButtons()
		for _, child in ipairs(scroll:GetChildren()) do
			if child ~= listLayout and not (child:IsA("UITextSizeConstraint")) then
				child:Destroy()
			end
		end
		animationButtons[tabName] = {}

		for i, anim in ipairs(animations or {}) do
			local btn = Instance.new("TextButton")
			btn.Name = ("AnimBtn_%d"):format(i)
			styleButton(btn)
			btn.Text = (anim.name or ("Anim " .. tostring(i)))
			btn.Parent = scroll

			local meta = {
				rawId = anim.id,
				name = anim.name or btn.Text,
				start = anim.start,
				finish = anim.finish,
				hipHeight = anim.hipHeight,
				pingpong = anim.pingpong,
				speed = anim.speed or 1,
			}

			table.insert(animationButtons[tabName], btn)

			btn.MouseButton1Click:Connect(function()
				if btn == currentlyPlayingButton then
					cleanupCurrent()
					return
				end

				for _, b in ipairs(animationButtons[tabName]) do
					if b ~= btn then
						b.BackgroundColor3 = buttonStates.normal
						b.TextColor3 = Theme.Text
					end
				end

				local normalized = normalizeAnimationId(meta.rawId)
				if not normalized then
					warn("[imation] Invalid animation id:", meta.rawId)
					return
				end
				playAnimation(normalized, meta.start, meta.finish, btn, meta.hipHeight, meta.pingpong, meta.speed)
			end)

			btn.MouseButton2Click:Connect(function()
				local modalBg = Instance.new("TextButton")
				modalBg.Size = UDim2.new(1, 0, 1, 0)
				modalBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				modalBg.BackgroundTransparency = 0.45
				modalBg.Text = ""
				modalBg.AutoButtonColor = false
				modalBg.Parent = screenGui
				modalBg.ZIndex = 50

				local modal = Instance.new("Frame")
				modal.Size = UDim2.new(0, 340, 0, 214)
				modal.Position = UDim2.new(0.5, -170, 0.5, -107)
				modal.AnchorPoint = Vector2.new(0.5, 0.5)
				modal.BackgroundColor3 = Theme.Panel
				modal.BorderSizePixel = 0
				modal.Parent = modalBg
				modal.ZIndex = 51
				softPanel(modal, 16)

				local mg = Instance.new("UIGradient")
				mg.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 27, 33)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(19, 19, 24)),
				})
				mg.Rotation = 90
				mg.Parent = modal

				local title = Instance.new("TextLabel")
				title.Size = UDim2.new(1, -20, 0, 22)
				title.Position = UDim2.new(0, 10, 0, 10)
				title.BackgroundTransparency = 1
				title.Text = "Edit animation"
				title.Font = Enum.Font.GothamBold
				title.TextSize = 14
				title.TextColor3 = Theme.Text
				title.Parent = modal
				title.ZIndex = 52

				local function makeModalLabel(text, y, width)
					local l = Instance.new("TextLabel")
					l.Size = UDim2.new(0, width or 92, 0, 18)
					l.Position = UDim2.new(0, 10, 0, y)
					l.BackgroundTransparency = 1
					l.Text = text
					l.Font = Enum.Font.Gotham
					l.TextSize = 12
					l.TextColor3 = Theme.Muted
					l.Parent = modal
					l.ZIndex = 52
					return l
				end

				local function makeModalBox(text, y, x, width)
					local b = Instance.new("TextBox")
					b.Size = UDim2.new(0, width or 208, 0, 22)
					b.Position = UDim2.new(0, x or 102, 0, y)
					b.ClearTextOnFocus = false
					b.Text = text or ""
					b.Font = Enum.Font.Gotham
					b.TextSize = 12
					b.TextColor3 = Theme.Text
					b.BackgroundColor3 = Theme.Surface
					b.Parent = modal
					b.ZIndex = 52
					softInput(b, { BackgroundColor3 = Theme.Surface, StrokeTransparency = 0.9, TextSize = 12 })
					return b
				end

				makeModalLabel("Name:", 38, 84)
				local nameBox = makeModalBox(anim.name or "", 36, 102, 226)

				makeModalLabel("Tab:", 68, 84)
				local tabBox = makeModalBox(tabName, 66, 102, 226)
				tabBox.PlaceholderText = "Type tab name (existing or new)"
				tabBox.TextColor3 = Theme.Text

				makeModalLabel("Ping-pong:", 98, 84)
				local pingpongCheck = Instance.new("TextButton")
				pingpongCheck.Size = UDim2.new(0, 24, 0, 24)
				pingpongCheck.Position = UDim2.new(0, 102, 0, 94)
				pingpongCheck.Text = anim.pingpong and "✓" or ""
				pingpongCheck.Font = Enum.Font.GothamBold
				pingpongCheck.TextSize = 14
				pingpongCheck.TextColor3 = Theme.Text
				pingpongCheck.Parent = modal
				pingpongCheck.ZIndex = 52
				softButton(pingpongCheck, {
					CornerRadius = 8,
					BackgroundColor3 = anim.pingpong and Theme.Accent or Theme.Surface,
					HoverColor3 = anim.pingpong and Theme.AccentHover or Theme.Surface2,
					TextColor3 = anim.pingpong and Color3.fromRGB(22, 20, 22) or Theme.Text,
					TextSize = 14,
				})
				local pingEnabled = anim.pingpong and true or false

				pingpongCheck.MouseButton1Click:Connect(function()
					pingEnabled = not pingEnabled
					pingpongCheck.Text = pingEnabled and "✓" or ""
					pingpongCheck.BackgroundColor3 = pingEnabled and Theme.Accent or Theme.Surface
					pingpongCheck.TextColor3 = pingEnabled and Color3.fromRGB(22, 20, 22) or Theme.Text
				end)

				makeModalLabel("Speed:", 128, 84)
				local speedBox = makeModalBox(tostring(anim.speed or 1), 126, 102, 80)
				speedBox.PlaceholderText = "0.1 - 3"

				local saveBtn = Instance.new("TextButton")
				saveBtn.Size = UDim2.new(0, 78, 0, 26)
				saveBtn.Position = UDim2.new(1, -86, 1, -36)
				saveBtn.Text = "Save"
				saveBtn.Font = Enum.Font.GothamBold
				saveBtn.TextSize = 12
				saveBtn.TextColor3 = Color3.fromRGB(22, 20, 22)
				saveBtn.Parent = modal
				saveBtn.ZIndex = 52
				softButton(saveBtn, {
					CornerRadius = 10,
					BackgroundColor3 = Theme.Accent,
					HoverColor3 = Theme.AccentHover,
					TextColor3 = Color3.fromRGB(22, 20, 22),
				})

				local delBtn = Instance.new("TextButton")
				delBtn.Size = UDim2.new(0, 78, 0, 26)
				delBtn.Position = UDim2.new(0, 10, 1, -36)
				delBtn.Text = "Delete"
				delBtn.Font = Enum.Font.GothamBold
				delBtn.TextSize = 12
				delBtn.TextColor3 = Theme.Text
				delBtn.Parent = modal
				delBtn.ZIndex = 52
				softButton(delBtn, {
					CornerRadius = 10,
					BackgroundColor3 = Theme.Danger,
					HoverColor3 = Theme.DangerHover,
					TextColor3 = Theme.Text,
				})

				local closeModal = function()
					modalBg:Destroy()
				end

				modalBg.MouseButton1Click:Connect(closeModal)

				saveBtn.MouseButton1Click:Connect(function()
					local newName = nameBox.Text or anim.name or ""
					local newTab = tabBox.Text or tabName
					local newSpeed = tonumber(speedBox.Text)
					if not newSpeed then newSpeed = 1 end
					newSpeed = math.clamp(newSpeed, 0.1, 3)

					local srcIdx = findTabIndexByName(tabName)
					if not srcIdx then closeModal(); return end

					local srcTab = tabConfig[srcIdx]
					local animIdx = nil
					for ii, a in ipairs(srcTab.animations or {}) do
						if a.id == anim.id then animIdx = ii; break end
					end
					if not animIdx then closeModal(); return end

					srcTab.animations[animIdx].name = newName
					srcTab.animations[animIdx].pingpong = pingEnabled
					srcTab.animations[animIdx].speed = newSpeed

					if newTab ~= tabName then
						local movingAnim = srcTab.animations[animIdx]
						table.remove(srcTab.animations, animIdx)
						local dstIdx = ensureTabExists(newTab)
						table.insert(tabConfig[dstIdx].animations, movingAnim)
					end

					writeLocalFile(serializeConfig(tabConfig))
					refreshTabsUI()
					closeModal()
				end)

				delBtn.MouseButton1Click:Connect(function()
					local srcIdx = findTabIndexByName(tabName)
					if not srcIdx then closeModal(); return end
					local srcTab = tabConfig[srcIdx]
					for ii, a in ipairs(srcTab.animations or {}) do
						if a.id == anim.id then
							table.remove(srcTab.animations, ii)
							break
						end
					end
					writeLocalFile(serializeConfig(tabConfig))
					refreshTabsUI()
					closeModal()
				end)
			end)
		end

		local function updateCanvas()
			local total = listLayout.AbsoluteContentSize.Y
			scroll.CanvasSize = UDim2.new(0, 0, 0, total + 12)
		end
		listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
		updateCanvas()
	end

	buildButtons()

	return content, function()
		for _, t in ipairs(tabConfig) do
			if t.name == tabName then
				animations = t.animations or {}
				break
			end
		end
		buildButtons()
	end
end

local builtTabEntries = {}

local function clearTabsUI()
	for _, entry in pairs(builtTabEntries) do
		if entry.button and entry.button.Parent then entry.button:Destroy() end
		if entry.content and entry.content.Parent then entry.content:Destroy() end
	end
	builtTabEntries = {}
	tabButtons = {}
	animationButtons = {}
	currentTabName = nil
end

local function buildTabsUI()
	clearTabsUI()

	for idx, tab in ipairs(tabConfig) do
		local tabName = tab.name or ("Tab" .. idx)
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = ("TabBtn_" .. tabName)
		tabBtn.Size = UDim2.new(1, -12, 0, 36)
		tabBtn.BackgroundColor3 = Theme.Surface
		tabBtn.BorderSizePixel = 0
		tabBtn.Font = Enum.Font.Gotham
		tabBtn.Text = tabName
		tabBtn.TextSize = 13
		tabBtn.TextColor3 = Theme.Text
		tabBtn.Parent = tabsFrame
		tabBtn.LayoutOrder = idx
		softButton(tabBtn, {
			CornerRadius = 10,
			BackgroundColor3 = Theme.Surface,
			HoverColor3 = Theme.Surface2,
			TextColor3 = Theme.Text,
			StrokeTransparency = 0.9,
			TextSize = 13,
		})

		table.insert(tabButtons, tabBtn)

		local content, refreshFn = createTabContent(tabName, tab.animations)
		builtTabEntries[tabName] = { button = tabBtn, content = content, refresh = refreshFn }

		tabBtn.MouseButton1Click:Connect(function()
			if currentTabName == tabName then return end
			currentTabName = tabName
			for _, tbtn in ipairs(tabButtons) do
				setSelected(tbtn, false)
			end
			setSelected(tabBtn, true)
			searchContent.Visible = false
			searchBox.Text = ""
			for _, child in ipairs(tabContentFolder:GetChildren()) do
				if child:IsA("Frame") then
					child.Visible = (child == content)
				end
			end
		end)

		if idx == 1 then
			setSelected(tabBtn, true)
			content.Visible = true
			currentTabName = tabName
		end
	end
end

function refreshTabsUI()
	buildTabsUI()
end

buildTabsUI()

-- ===== Test Window =====
local expandedMainSize = UDim2.new(0, 430, 0, 360)
local collapsedMainSize = UDim2.new(0, 430, 0, 38)

local isMinimized = false
local testWindowOpen = false
local addWindowOpen = false
local infoWindowOpen = false

local testWindow = Instance.new("Frame")
testWindow.Name = "TestWindow"
testWindow.Size = UDim2.new(1, 0, 0, 170)
testWindow.Position = UDim2.new(0, 0, 1, 40)
testWindow.BackgroundColor3 = Theme.Panel2
testWindow.BorderSizePixel = 0
testWindow.Parent = mainFrame
testWindow.Visible = false
softPanel(testWindow, 14)

local testGradient = Instance.new("UIGradient")
testGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 27, 33)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(21, 21, 26)),
})
testGradient.Rotation = 90
testGradient.Parent = testWindow

local testIdLabel = Instance.new("TextLabel")
testIdLabel.Size = UDim2.new(0, 80, 0, 22)
testIdLabel.Position = UDim2.new(0, 10, 0, 10)
softLabel(testIdLabel, true)
testIdLabel.Text = "Test ID:"
testIdLabel.Parent = testWindow

local testIdBox = Instance.new("TextBox")
testIdBox.Size = UDim2.new(1, -150, 0, 28)
testIdBox.Position = UDim2.new(0, 84, 0, 8)
testIdBox.ClearTextOnFocus = false
testIdBox.Text = ""
testIdBox.PlaceholderText = "123456 or rbxassetid://..."
testIdBox.Font = Enum.Font.Gotham
testIdBox.TextSize = 13
testIdBox.TextColor3 = Theme.Text
testIdBox.BackgroundColor3 = Theme.Surface
testIdBox.Parent = testWindow
softInput(testIdBox, { BackgroundColor3 = Theme.Surface, StrokeTransparency = 0.9 })

local playBtn = Instance.new("TextButton")
playBtn.Size = UDim2.new(0, 58, 0, 28)
playBtn.Position = UDim2.new(1, -122, 0, 8)
playBtn.Text = "Play"
playBtn.Font = Enum.Font.GothamBold
playBtn.TextSize = 13
playBtn.TextColor3 = Color3.fromRGB(22, 20, 22)
playBtn.BackgroundColor3 = Theme.Accent
playBtn.Parent = testWindow
softButton(playBtn, {
	CornerRadius = 10,
	BackgroundColor3 = Theme.Accent,
	HoverColor3 = Theme.AccentHover,
	TextColor3 = Color3.fromRGB(22, 20, 22),
})

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(0, 58, 0, 28)
stopBtn.Position = UDim2.new(1, -58, 0, 8)
stopBtn.Text = "Stop"
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 13
stopBtn.TextColor3 = Theme.Text
stopBtn.BackgroundColor3 = Theme.Danger
stopBtn.Parent = testWindow
softButton(stopBtn, {
	CornerRadius = 10,
	BackgroundColor3 = Theme.Danger,
	HoverColor3 = Theme.DangerHover,
	TextColor3 = Theme.Text,
})

local sliderLabel = Instance.new("TextLabel")
sliderLabel.Size = UDim2.new(0, 160, 0, 18)
sliderLabel.Position = UDim2.new(0, 10, 0, 48)
softLabel(sliderLabel, true)
sliderLabel.Text = "Loop Segment (drag handles)"
sliderLabel.Parent = testWindow

local sliderFrame = Instance.new("Frame")
sliderFrame.Size = UDim2.new(1, -20, 0, 28)
sliderFrame.Position = UDim2.new(0, 10, 0, 70)
sliderFrame.BackgroundColor3 = Theme.Surface
sliderFrame.BorderSizePixel = 0
sliderFrame.Parent = testWindow
addCorner(sliderFrame, 10)
addStroke(sliderFrame, Theme.Stroke, 0.9, 1)

local sliderBar = Instance.new("Frame")
sliderBar.Size = UDim2.new(1, -18, 0, 6)
sliderBar.Position = UDim2.new(0, 9, 0, 11)
sliderBar.BackgroundColor3 = Color3.fromRGB(72, 72, 82)
sliderBar.BorderSizePixel = 0
sliderBar.Parent = sliderFrame
addCorner(sliderBar, 999)

local rangeFill = Instance.new("Frame")
rangeFill.Size = UDim2.new(0, 0, 0, 6)
rangeFill.Position = UDim2.new(0, 0, 0, 11)
rangeFill.BackgroundColor3 = Theme.Accent
rangeFill.BorderSizePixel = 0
rangeFill.Parent = sliderFrame
addCorner(rangeFill, 999)

local handleA = Instance.new("ImageButton")
handleA.Size = UDim2.new(0, 12, 0, 18)
handleA.Position = UDim2.new(0, 0, 0, 5)
handleA.AnchorPoint = Vector2.new(0.5, 0)
handleA.BackgroundTransparency = 1
handleA.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
handleA.Parent = sliderFrame

local handleB = handleA:Clone()
handleB.Name = "HandleB"
handleB.Position = UDim2.new(1, 0, 0, 5)
handleB.Parent = sliderFrame

local timeLabel = Instance.new("TextLabel")
timeLabel.Size = UDim2.new(1, -20, 0, 16)
timeLabel.Position = UDim2.new(0, 10, 0, 100)
softLabel(timeLabel, true)
timeLabel.Text = "Start: 0.00s  End: 0.00s"
timeLabel.Parent = testWindow

local dragging = nil
local sliderAbsoluteX, sliderAbsoluteWidth
local currentAnimationLength = 10

local function updateSliderValues()
	sliderAbsoluteX = sliderFrame.AbsolutePosition.X
	sliderAbsoluteWidth = sliderFrame.AbsoluteSize.X
	local ax = handleA.AbsolutePosition.X + handleA.AbsoluteSize.X / 2 - sliderAbsoluteX
	local bx = handleB.AbsolutePosition.X + handleB.AbsoluteSize.X / 2 - sliderAbsoluteX
	local aNorm = math.clamp(ax / math.max(sliderAbsoluteWidth, 1), 0, 1)
	local bNorm = math.clamp(bx / math.max(sliderAbsoluteWidth, 1), 0, 1)
	local start = math.min(aNorm, bNorm) * currentAnimationLength
	local finish = math.max(aNorm, bNorm) * currentAnimationLength
	timeLabel.Text = ("Start: %.2fs  End: %.2fs"):format(start, finish)
	local left = math.min(aNorm, bNorm)
	local width = math.abs(bNorm - aNorm)
	rangeFill.Position = UDim2.new(left, 0, 0, 11)
	rangeFill.Size = UDim2.new(width, 0, 0, 6)
	return start, finish
end

local function beginDrag(handle, which)
	dragging = which
	updateSliderValues()
end

local function stopDrag()
	dragging = nil
end

handleA.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		beginDrag(handleA, "A")
	end
end)
handleB.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		beginDrag(handleB, "B")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		stopDrag()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging then
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local mouseX = input.Position.X
			local rel = (mouseX - sliderAbsoluteX) / math.max(sliderAbsoluteWidth, 1)
			rel = math.clamp(rel, 0, 1)
			if dragging == "A" then
				handleA.Position = UDim2.new(rel, 0, 0, 5)
			else
				handleB.Position = UDim2.new(rel, 0, 0, 5)
			end
			updateSliderValues()
		end
	end
end)

sliderFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	updateSliderValues()
end)
sliderFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
	updateSliderValues()
end)

playBtn.MouseButton1Click:Connect(function()
	local raw = ""
	if testIdBox and tostring(testIdBox.Text) ~= "" then
		raw = testIdBox.Text
	elseif idBox and tostring(idBox.Text) ~= "" then
		raw = idBox.Text
	end

	local animId = normalizeAnimationId(raw)
	if not animId then
		warn("[imation] Invalid test ID:", raw)
		return
	end

	animator = getAnimator()
	if animator then
		local testAnim = Instance.new("Animation")
		testAnim.AnimationId = animId
		local ok, testTrack = pcall(function() return animator:LoadAnimation(testAnim) end)
		if ok and testTrack then
			currentAnimationLength = testTrack.Length or 10
			testTrack:Destroy()
		else
			currentAnimationLength = 10
		end
		testAnim:Destroy()
	end

	local start, finish = updateSliderValues()
	local useFullAnimation = (start <= 0.1 and finish >= currentAnimationLength - 0.1) or (math.abs(finish - start) < 0.1)

	if useFullAnimation then
		start, finish = nil, nil
		timeLabel.Text = "Playing full animation"
	else
		timeLabel.Text = ("Segment: %.2fs to %.2fs"):format(start, finish)
	end

	playAnimation(animId, start, finish, nil, nil, false, 1)
end)

stopBtn.MouseButton1Click:Connect(function()
	cleanupCurrent()
	timeLabel.Text = "Start: 0.00s  End: 0.00s"
end)

-- ===== Manage/Add Window =====
local addWindow = Instance.new("Frame")
addWindow.Name = "AddWindow"
addWindow.Size = UDim2.new(1, 0, 0, 220)
addWindow.Position = UDim2.new(0, 0, 1, 40)
addWindow.BackgroundColor3 = Theme.Panel2
addWindow.BorderSizePixel = 0
addWindow.Parent = mainFrame
addWindow.Visible = false
softPanel(addWindow, 14)

local addGradient = Instance.new("UIGradient")
addGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 27, 33)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(21, 21, 26)),
})
addGradient.Rotation = 90
addGradient.Parent = addWindow

local idLabel = Instance.new("TextLabel")
idLabel.Size = UDim2.new(0, 80, 0, 22)
idLabel.Position = UDim2.new(0, 10, 0, 10)
softLabel(idLabel, true)
idLabel.Text = "Anim ID:"
idLabel.Parent = addWindow

local idBox = Instance.new("TextBox")
idBox.Size = UDim2.new(1, -150, 0, 28)
idBox.Position = UDim2.new(0, 84, 0, 8)
idBox.ClearTextOnFocus = false
idBox.Text = ""
idBox.PlaceholderText = "123456 or rbxassetid://..."
idBox.Font = Enum.Font.Gotham
idBox.TextSize = 13
idBox.TextColor3 = Theme.Text
idBox.BackgroundColor3 = Theme.Surface
idBox.Parent = addWindow
softInput(idBox, { BackgroundColor3 = Theme.Surface, StrokeTransparency = 0.9 })

local newNameLabel = Instance.new("TextLabel")
newNameLabel.Size = UDim2.new(0, 80, 0, 18)
newNameLabel.Position = UDim2.new(0, 10, 0, 42)
softLabel(newNameLabel, true)
newNameLabel.Text = "Anim Name:"
newNameLabel.Parent = addWindow

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(0, 170, 0, 22)
nameBox.Position = UDim2.new(0, 84, 0, 40)
nameBox.ClearTextOnFocus = false
nameBox.Text = ""
nameBox.PlaceholderText = "Optional name"
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 12
nameBox.TextColor3 = Theme.Text
nameBox.BackgroundColor3 = Theme.Surface
nameBox.Parent = addWindow
softInput(nameBox, { BackgroundColor3 = Theme.Surface, StrokeTransparency = 0.9, TextSize = 12 })

local addTabLabel = Instance.new("TextLabel")
addTabLabel.Size = UDim2.new(0, 80, 0, 18)
addTabLabel.Position = UDim2.new(0, 10, 0, 68)
softLabel(addTabLabel, true)
addTabLabel.Text = "Tab name:"
addTabLabel.Parent = addWindow

local addTabBox = Instance.new("TextBox")
addTabBox.Size = UDim2.new(0, 170, 0, 22)
addTabBox.Position = UDim2.new(0, 84, 0, 66)
addTabBox.ClearTextOnFocus = false
addTabBox.Text = ""
addTabBox.PlaceholderText = "Existing or new tab"
addTabBox.Font = Enum.Font.Gotham
addTabBox.TextSize = 12
addTabBox.TextColor3 = Theme.Text
addTabBox.BackgroundColor3 = Theme.Surface
addTabBox.Parent = addWindow
softInput(addTabBox, { BackgroundColor3 = Theme.Surface, StrokeTransparency = 0.9, TextSize = 12 })

local addPingpongLabel = Instance.new("TextLabel")
addPingpongLabel.Size = UDim2.new(0, 100, 0, 20)
addPingpongLabel.Position = UDim2.new(0, 10, 0, 92)
softLabel(addPingpongLabel, true)
addPingpongLabel.Text = "Ping-pong loop:"
addPingpongLabel.Parent = addWindow

local addPingpongCheck = Instance.new("TextButton")
addPingpongCheck.Size = UDim2.new(0, 24, 0, 24)
addPingpongCheck.Position = UDim2.new(0, 110, 0, 89)
addPingpongCheck.BackgroundColor3 = Theme.Surface
addPingpongCheck.Text = ""
addPingpongCheck.Font = Enum.Font.GothamBold
addPingpongCheck.TextSize = 14
addPingpongCheck.TextColor3 = Theme.Text
addPingpongCheck.AutoButtonColor = false
addPingpongCheck.Parent = addWindow
softButton(addPingpongCheck, {
	CornerRadius = 8,
	BackgroundColor3 = Theme.Surface,
	HoverColor3 = Theme.Surface2,
	TextColor3 = Theme.Text,
	TextSize = 14,
})
local addPingpongActive = false
addPingpongCheck.MouseButton1Click:Connect(function()
	addPingpongActive = not addPingpongActive
	addPingpongCheck.BackgroundColor3 = addPingpongActive and Theme.Accent or Theme.Surface
	addPingpongCheck.Text = addPingpongActive and "✓" or ""
	addPingpongCheck.TextColor3 = addPingpongActive and Color3.fromRGB(22, 20, 22) or Theme.Text
end)

local addSpeedLabel = Instance.new("TextLabel")
addSpeedLabel.Size = UDim2.new(0, 100, 0, 20)
addSpeedLabel.Position = UDim2.new(0, 10, 0, 118)
softLabel(addSpeedLabel, true)
addSpeedLabel.Text = "Speed (0.1–3):"
addSpeedLabel.Parent = addWindow

local addSpeedBox = Instance.new("TextBox")
addSpeedBox.Size = UDim2.new(0, 70, 0, 22)
addSpeedBox.Position = UDim2.new(0, 110, 0, 116)
addSpeedBox.ClearTextOnFocus = false
addSpeedBox.Text = "1"
addSpeedBox.Font = Enum.Font.Gotham
addSpeedBox.TextSize = 12
addSpeedBox.TextColor3 = Theme.Text
addSpeedBox.BackgroundColor3 = Theme.Surface
addSpeedBox.Parent = addWindow
softInput(addSpeedBox, { BackgroundColor3 = Theme.Surface, StrokeTransparency = 0.9, TextSize = 12 })

local addAnimBtn = Instance.new("TextButton")
addAnimBtn.Size = UDim2.new(0, 92, 0, 28)
addAnimBtn.Position = UDim2.new(1, -192, 0, 40)
addAnimBtn.Text = "Add Anim"
addAnimBtn.Font = Enum.Font.GothamBold
addAnimBtn.TextSize = 12
addAnimBtn.TextColor3 = Color3.fromRGB(22, 20, 22)
addAnimBtn.Parent = addWindow
softButton(addAnimBtn, {
	CornerRadius = 10,
	BackgroundColor3 = Theme.Accent,
	HoverColor3 = Theme.AccentHover,
	TextColor3 = Color3.fromRGB(22, 20, 22),
})

local addTabBtn = Instance.new("TextButton")
addTabBtn.Size = UDim2.new(0, 92, 0, 28)
addTabBtn.Position = UDim2.new(1, -192, 0, 70)
addTabBtn.Text = "Add Tab"
addTabBtn.Font = Enum.Font.GothamBold
addTabBtn.TextSize = 12
addTabBtn.TextColor3 = Color3.fromRGB(22, 20, 22)
addTabBtn.Parent = addWindow
softButton(addTabBtn, {
	CornerRadius = 10,
	BackgroundColor3 = Theme.AccentSoft,
	HoverColor3 = Theme.AccentHover,
	TextColor3 = Color3.fromRGB(22, 20, 22),
})

local deleteTabBtn = Instance.new("TextButton")
deleteTabBtn.Size = UDim2.new(0, 92, 0, 28)
deleteTabBtn.Position = UDim2.new(1, -96, 0, 70)
deleteTabBtn.Text = "Delete Tab"
deleteTabBtn.Font = Enum.Font.GothamBold
deleteTabBtn.TextSize = 12
deleteTabBtn.TextColor3 = Theme.Text
deleteTabBtn.Parent = addWindow
softButton(deleteTabBtn, {
	CornerRadius = 10,
	BackgroundColor3 = Theme.Danger,
	HoverColor3 = Theme.DangerHover,
	TextColor3 = Theme.Text,
})

local function updateBodyVisibility()
	local bodyVisible = not isMinimized

	searchBox.Visible = bodyVisible
	tabsFrame.Visible = bodyVisible
	contentFrame.Visible = bodyVisible

	testWindow.Visible = bodyVisible and testWindowOpen
	addWindow.Visible = bodyVisible and addWindowOpen

	mainFrame.Size = bodyVisible and expandedMainSize or collapsedMainSize
end

local function closeInfoWindow()
	infoWindowOpen = false
	if infoOverlay then
		infoOverlay:Destroy()
		infoOverlay = nil
	end
end

local function openInfoWindow()
	if infoOverlay then
		infoWindowOpen = true
		infoOverlay.Visible = true
		return
	end

	infoWindowOpen = true

	infoOverlay = Instance.new("Frame")
	infoOverlay.Name = "InfoOverlay"
	infoOverlay.Size = UDim2.new(1, 0, 1, 0)
	infoOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	infoOverlay.BackgroundTransparency = 0.42
	infoOverlay.BorderSizePixel = 0
	infoOverlay.Parent = screenGui
	infoOverlay.ZIndex = 100

	local modal = Instance.new("Frame")
	modal.Size = UDim2.new(0, 390, 0, 310)
	modal.Position = UDim2.new(0.5, -195, 0.5, -155)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = Theme.Panel
	modal.BorderSizePixel = 0
	modal.Parent = infoOverlay
	modal.ZIndex = 101
	softPanel(modal, 16)

	local mg = Instance.new("UIGradient")
	mg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 28, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 25)),
	})
	mg.Rotation = 90
	mg.Parent = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -48, 0, 24)
	title.Position = UDim2.new(0, 14, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "Info / Credits"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = Theme.Text
	title.Parent = modal
	title.ZIndex = 102
	softLabel(title, false)

	local close = Instance.new("TextButton")
	close.Size = UDim2.new(0, 28, 0, 28)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Text = "×"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 15
	close.TextColor3 = Theme.Text
	close.BackgroundColor3 = Theme.Danger
	close.Parent = modal
	close.ZIndex = 102
	softButton(close, {
		CornerRadius = 10,
		BackgroundColor3 = Theme.Danger,
		HoverColor3 = Theme.DangerHover,
		TextColor3 = Theme.Text,
	})

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -28, 1, -54)
	body.Position = UDim2.new(0, 14, 0, 42)
	body.BackgroundTransparency = 1
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.RichText = false
	body.Font = Enum.Font.Gotham
	body.TextSize = 13
	body.TextColor3 = Theme.Text
	body.Parent = modal
	body.ZIndex = 102
	body.Text =
		"Credits:\n" ..
		"• @cvtmvtt on Discord.\n" ..
		"• UI restyle and extra controls added in this version.\n" ..
		"• Remote config source: " .. CONFIG_URL .. "\n" ..
		"• Mobile(delta) fallback logic.\n\n" ..
		"How to use:\n" ..
		"• Pick a tab on the left to browse animations.\n" ..
		"• Use Search to find animation names fast.\n" ..
		"• Right-click an animation to edit, move, or delete it.\n" ..
		"• Open Manage to add animations or tabs.\n" ..
		"• Open Test to preview a custom animation ID and segment.\n\n" ..
		"Files:\n" ..
		"• Local cache path: " .. LOCAL_FILE .. "\n" ..
		"• If local file support is unavailable(mobile), the script uses the GitHub URL or fallback data."

	close.MouseButton1Click:Connect(closeInfoWindow)
	infoOverlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mouse = UserInputService:GetMouseLocation()
			local absPos, absSize = modal.AbsolutePosition, modal.AbsoluteSize
			if not (mouse.X >= absPos.X and mouse.X <= absPos.X + absSize.X and mouse.Y >= absPos.Y and mouse.Y <= absPos.Y + absSize.Y) then
				closeInfoWindow()
			end
		end
	end)
end

-- Add animation button behavior
addAnimBtn.MouseButton1Click:Connect(function()
	local raw = idBox.Text
	local animId = normalizeAnimationId(raw)
	if not animId then
		warn("[imation] Invalid ID for new animation:", raw)
		return
	end
	local animName = nameBox.Text and (#nameBox.Text > 0) and nameBox.Text or nil
	local targetTab = (addTabBox.Text and #addTabBox.Text > 0) and addTabBox.Text or currentTabName or "General"
	local speed = tonumber(addSpeedBox.Text) or 1
	speed = math.clamp(speed, 0.1, 3)

	local tabIdx = ensureTabExists(targetTab)

	local newAnim = { id = animId }
	if animName then newAnim.name = animName end
	if addPingpongActive then newAnim.pingpong = true end
	newAnim.speed = speed
	table.insert(tabConfig[tabIdx].animations, newAnim)

	writeLocalFile(serializeConfig(tabConfig))
	refreshTabsUI()

	idBox.Text = ""
	nameBox.Text = ""
	addPingpongActive = false
	addPingpongCheck.BackgroundColor3 = Theme.Surface
	addPingpongCheck.Text = ""
	addPingpongCheck.TextColor3 = Theme.Text
	addSpeedBox.Text = "1"
end)

addTabBtn.MouseButton1Click:Connect(function()
	local newTabName = addTabBox.Text and (#addTabBox.Text > 0) and addTabBox.Text or nil
	if not newTabName then
		warn("[imation] Enter a tab name to add.")
		return
	end
	if not findTabIndexByName(newTabName) then
		table.insert(tabConfig, { name = newTabName, animations = {} })
		writeLocalFile(serializeConfig(tabConfig))
		refreshTabsUI()
		addTabBox.Text = ""
	end
end)

deleteTabBtn.MouseButton1Click:Connect(function()
	if not currentTabName then
		warn("[imation] No tab selected.")
		return
	end
	if addTabBox.Text ~= currentTabName then
		warn("[imation] To confirm deletion type the current tab name into the 'Tab name' box and press Delete Tab.")
		return
	end
	for i, t in ipairs(tabConfig) do
		if t.name == currentTabName then
			table.remove(tabConfig, i)
			break
		end
	end
	writeLocalFile(serializeConfig(tabConfig))
	addTabBox.Text = ""
	refreshTabsUI()
end)

-- Title bar controls
closeBtn.MouseButton1Click:Connect(function()
	screenGui.Enabled = false
end)

minimizeBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	if isMinimized then
		testWindowOpen = false
		addWindowOpen = false
		closeInfoWindow()
	end
	updateBodyVisibility()
end)

infoBtn.MouseButton1Click:Connect(function()
	if infoWindowOpen then
		closeInfoWindow()
	else
		openInfoWindow()
	end
end)

local function setTestWindowVisible(show)
	testWindowOpen = show and true or false
	if not isMinimized then
		testWindow.Visible = testWindowOpen
	end
end

local function setAddWindowVisible(show)
	addWindowOpen = show and true or false
	if not isMinimized then
		addWindow.Visible = addWindowOpen
	end
end

local function toggleTestWindow()
	setTestWindowVisible(not testWindowOpen)
	if addWindowOpen then
		setAddWindowVisible(false)
	end
end

local function toggleAddWindow()
	setAddWindowVisible(not addWindowOpen)
	if testWindowOpen then
		setTestWindowVisible(false)
	end
end

local function bindHover(btn, normalColor, hoverColor)
	btn.MouseEnter:Connect(function()
		tween(btn, TweenInfo.new(0.15), { BackgroundColor3 = hoverColor }):Play()
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, TweenInfo.new(0.15), { BackgroundColor3 = normalColor }):Play()
	end)
end

bindHover(playBtn, Theme.Accent, Theme.AccentHover)
bindHover(stopBtn, Theme.Danger, Theme.DangerHover)
bindHover(addAnimBtn, Theme.Accent, Theme.AccentHover)
bindHover(addTabBtn, Theme.AccentSoft, Theme.AccentHover)
bindHover(deleteTabBtn, Theme.Danger, Theme.DangerHover)

local testToggleBtn = Instance.new("TextButton")
testToggleBtn.Name = "TestToggle"
testToggleBtn.Size = UDim2.new(0, 78, 1, -10)
testToggleBtn.Position = UDim2.new(1, -110, 0, 5)
testToggleBtn.AnchorPoint = Vector2.new(1, 0)
testToggleBtn.Parent = titleBar
testToggleBtn.BackgroundColor3 = Theme.Surface
testToggleBtn.Font = Enum.Font.GothamBold
testToggleBtn.Text = "Test"
testToggleBtn.TextSize = 12
testToggleBtn.TextColor3 = Theme.Text
softButton(testToggleBtn, {
	CornerRadius = 10,
	BackgroundColor3 = Theme.Surface,
	HoverColor3 = Theme.Surface2,
	TextColor3 = Theme.Text,
	TextSize = 12,
})

local manageBtn = Instance.new("TextButton")
manageBtn.Name = "ManageBtn"
manageBtn.Size = UDim2.new(0, 78, 1, -10)
manageBtn.Position = UDim2.new(1, -192, 0, 5)
manageBtn.AnchorPoint = Vector2.new(1, 0)
manageBtn.Parent = titleBar
manageBtn.BackgroundColor3 = Theme.Surface
manageBtn.Font = Enum.Font.GothamBold
manageBtn.Text = "Manage"
manageBtn.TextSize = 12
manageBtn.TextColor3 = Theme.Text
softButton(manageBtn, {
	CornerRadius = 10,
	BackgroundColor3 = Theme.Surface,
	HoverColor3 = Theme.Surface2,
	TextColor3 = Theme.Text,
	TextSize = 12,
})

testToggleBtn.MouseButton1Click:Connect(function()
	toggleTestWindow()
	updateBodyVisibility()
end)

manageBtn.MouseButton1Click:Connect(function()
	toggleAddWindow()
	updateBodyVisibility()
end)

-- Dragging mainFrame
local dragToggle = false
local dragStart = nil
local startPos = nil

titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragToggle = true
		dragStart = input.Position
		startPos = mainFrame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragToggle = false
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragToggle and input.UserInputType == Enum.UserInputType.MouseMovement then
		if dragStart and startPos then
			local delta = input.Position - dragStart
			mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end
end)

local function ensureAnimatorAvailable()
	animator = getAnimator()
end

handleA.Position = UDim2.new(0, 0, 0, 5)
handleB.Position = UDim2.new(1, 0, 0, 5)
updateSliderValues()

player.CharacterRemoving:Connect(function()
	cleanupCurrent()
end)

if character then
	ensureAnimatorAvailable()
end

updateBodyVisibility()
setTestWindowVisible(false)
setAddWindowVisible(false)

-- expose initial state
if screenGui then
	screenGui.Enabled = true
end
