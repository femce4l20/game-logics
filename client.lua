local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local mathClamp = math.clamp
local mathMax = math.max
local mathMin = math.min
local mathAbs = math.abs
local mathSin = math.sin
local mathCos = math.cos
local mathRad = math.rad
local mathHuge = math.huge
local CFrameNew = CFrame.new
local CFrameAngles = CFrame.Angles
local Vector3New = Vector3.new
local Vector3Zero = Vector3.zero

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

local DEFAULT_MODE = "waist"

-- ================================================================
--  CONFIGS (per accessory type)
-- ================================================================

local CONFIGS = {}

CONFIGS.waist = {
	STIFFNESS     = 50,
	DAMPING       = 2.2,
	INERTIA_SCALE = 0.045,

	SIDE_DEADZONE    = 0.8,
	FORWARD_DEADZONE = 0.75,

	FORWARD_DRAG_BIAS     = -0.008,
	FORWARD_YAW_REDUCTION = 0.40,
	FORWARD_MOTION_FULL   = 10,
	YAW_UNLOCK_ANGLE      = mathRad(12),
	YAW_FULL_UNLOCK       = mathRad(24),

	MOTION_TRAIL_SMOOTHING = 0.25,
	MOTION_ACCEL_INFLUENCE = 0.03,
	TRAIL_RELEASE          = 0.22,

	ROTATION_YAW_INFLUENCE   = 0.025,
	ROTATION_ROLL_INFLUENCE  = 0.38,
	ROTATION_PITCH_INFLUENCE = 0.04,
	ROTATION_SMOOTHING       = 0.35,

	ROLL_STIFFNESS = 25,
	ROLL_DAMPING   = 0.85,
	MAX_ROLL_ANGLE = mathRad(28),
	YAW_TO_ROLL    = 0.18,
	SIDE_TO_ROLL   = 0.012,

	WHIP_THRESHOLD = 4.0,
	WHIP_STRENGTH  = 0.9,
	WHIP_COOLDOWN  = 0.30,

	SMEAR_MAX_ANGLE  = mathRad(60),
	SMEAR_SPEED_FULL = 18,

	WAG_SPEED               = 3.5,
	WAG_AMPLITUDE           = 0.15,
	WAG_FADE_SPEED          = 0.20,
	WAG_SECONDARY_SPEED     = 3.0,
	WAG_SECONDARY_AMPLITUDE = 0.015,
	WAG_PITCH_BOB           = mathRad(0.1),
	WAG_ROLL_AMPLITUDE      = mathRad(2.0),
	WAG_ROLL_SPEED          = 3.0,

	ANIMATION_INFLUENCE        = 0.30,
	ANIMATION_LINEAR_INFLUENCE = 0.18,
	ANIMATION_MOTOR_INFLUENCE  = 0.22,
	ANIMATION_BLEND_SMOOTHING  = 0.35,

	YAW_TO_PITCH_COUPLING     = 0.015,
	PITCH_TO_YAW_COUPLING     = 0.012,
	YAW_VELOCITY_TO_PITCH     = 0.0010,
	PITCH_VELOCITY_TO_YAW     = 0.0008,

	CHAOS_STRENGTH = 0.004,
	CHAOS_RESPONSE = 0.04,
	CHAOS_DAMPING  = 0.96,

	SPRINT_SPEED           = 16,
	MIN_INVERSION_STRENGTH  = 0.12,
	MAX_INVERSION_STRENGTH  = 0.70,

	MAX_ANGLE = mathRad(60),
	TIMESTEP = 1 / 120,

	FLOOR_CHECK_DIST    = 2.0,
	FLOOR_MIN_PART_SIZE = 4,
	FLOOR_PUSH_STRENGTH = 90,
	FLOOR_CONTACT_DIST  = 0.35,

	RESTING_ROLL_BIAS = mathRad(18),
}

-- ================================================================
--  ACCESSORY CLASSIFICATION
-- ================================================================

local SUPPORTED_TORSO_ATTACHMENT_NAMES = {
	WaistFrontAttachment = true,
	WaistCenterAttachment = true,
	WaistBackAttachment = true,

	BodyFrontAttachment = true,
	BodyBackAttachment = true,
	BodyCenterAttachment = true,

	TailAttachment = true,
	AccessoryAttachment = true,
}

local ATTACHMENT_SEARCH_ORDER_R15 = {
	"WaistBackAttachment",
	"WaistCenterAttachment",
	"WaistFrontAttachment",
	"BodyBackAttachment",
	"BodyCenterAttachment",
	"BodyFrontAttachment",
	"TailAttachment",
	"AccessoryAttachment",
}

local ATTACHMENT_SEARCH_ORDER_R6 = {
	"BodyBackAttachment",
	"WaistBackAttachment",
	"WaistCenterAttachment",
	"BodyCenterAttachment",
	"WaistFrontAttachment",
	"BodyFrontAttachment",
	"TailAttachment",
	"AccessoryAttachment",
}

local function findAttachmentByOrder(container, orderedNames)
	for _, name in ipairs(orderedNames) do
		local att = container:FindFirstChild(name, true)
		if att and att:IsA("Attachment") then
			return att
		end
	end
	return nil
end

local function findMatchingAttachmentPair(handle, characterModel, rigType)
	local searchOrder = (rigType == Enum.HumanoidRigType.R6) and ATTACHMENT_SEARCH_ORDER_R6 or ATTACHMENT_SEARCH_ORDER_R15

	for _, name in ipairs(searchOrder) do
		local accAtt = handle:FindFirstChild(name, true)
		if accAtt and accAtt:IsA("Attachment") then
			local matching = characterModel:FindFirstChild(name, true)
			if matching and matching:IsA("Attachment") then
				return accAtt, matching
			end

			-- Keep the accessory attachment even if the character lacks a matching
			-- attachment object. This avoids falling back to a centered pivot on R6.
			return accAtt, nil
		end
	end

	return nil, nil
end

local function classifyAccessory(acc, mode, char)
	if mode ~= "waist" and mode ~= "both" then
		return nil
	end

	local handle = acc:FindFirstChild("Handle")
	if not handle then
		return nil
	end

	local rigType = Enum.HumanoidRigType.R15
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		rigType = humanoid.RigType
	end

	local accAttachment = findAttachmentByOrder(handle,
		(rigType == Enum.HumanoidRigType.R6) and ATTACHMENT_SEARCH_ORDER_R6 or ATTACHMENT_SEARCH_ORDER_R15
	)

	if not accAttachment then
		return nil
	end

	if not SUPPORTED_TORSO_ATTACHMENT_NAMES[accAttachment.Name] then
		return nil
	end

	return "waist"
end

-- ================================================================
--  SMALL HELPERS
-- ================================================================

local function clamp01(x)
	return mathClamp(x, 0, 1)
end

local function smoothstep(edge0, edge1, x)
	if edge0 == edge1 then
		return x >= edge1 and 1 or 0
	end
	local t = mathClamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function hashString(str)
	local h = 0
	for i = 1, #str do
		h = (h * 33 + string.byte(str, i)) % 100000
	end
	return h
end

local WORLD_UP = Vector3New(0, 1, 0)
local WORLD_DOWN = Vector3New(0, -1, 0)

local function isValidFloorPart(part)
	return part
		and part:IsA("BasePart")
		and part.CanCollide
		and part.Transparency < 1
end

local function raycastVisibleFloor(origin, direction, baseParams)
	local ignoreList = {}

	for i, inst in ipairs(baseParams.FilterDescendantsInstances) do
		ignoreList[i] = inst
	end

	for _ = 1, 8 do
		local params = RaycastParams.new()
		params.FilterType = baseParams.FilterType
		params.IgnoreWater = baseParams.IgnoreWater == true
		params.FilterDescendantsInstances = ignoreList

		local result = workspace:Raycast(origin, direction, params)
		if not result then
			return nil
		end

		if isValidFloorPart(result.Instance) then
			return result
		end

		table.insert(ignoreList, result.Instance)
	end

	return nil
end

local function getFloorSupportState(rootCF)
	local up = rootCF.UpVector
	local right = rootCF.RightVector
	local look = rootCF.LookVector

	local upY = mathAbs(up.Y)
	local rightY = mathAbs(right.Y)
	local lookY = mathAbs(look.Y)

	local sideLying = upY < 0.48 and rightY > lookY and rightY > 0.55
	local faceDown = upY < 0.48 and lookY >= rightY and lookY > 0.55

	if not sideLying and not faceDown then
		return WORLD_DOWN, "upright"
	end

	local dir = -up
	if dir.Magnitude < 1e-4 then
		dir = WORLD_DOWN
	else
		dir = dir.Unit
	end

	return dir, sideLying and "side" or "face"
end

-- ================================================================
--  ANIMATION SAMPLING
-- ================================================================

local MOTOR_WEIGHTS = {
	rootjoint = 1.00,
	root      = 1.00,
	waist     = 0.95,
	neck      = 0.55,
}

local function getMotorWeight(name)
	local lower = name:lower()
	local cached = MOTOR_WEIGHTS[lower]
	if cached then return cached end
	if lower:find("hip") then return 0.30 end
	if lower:find("shoulder") then return 0.18 end
	if lower:find("knee") or lower:find("elbow") then return 0.08 end
	return 0.10
end

local function collectAnimationMotors(char)
	local tracked = {}
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("Motor6D") then
			table.insert(tracked, {
				motor = desc,
				weight = getMotorWeight(desc.Name),
				prevTransform = nil,
			})
		end
	end
	return tracked
end

local function cframeDeltaToLocalVectors(prevCF, currentCF, dt)
	dt = mathMax(dt, 1e-3)
	local delta = prevCF:Inverse() * currentCF
	local axis, angle = delta:ToAxisAngle()
	return (currentCF.Position - prevCF.Position) / dt, axis * (angle / dt)
end

-- ================================================================
--  WELD DETECTION
-- ================================================================

local function findAccessoryWeld(handle)
	local named = handle:FindFirstChild("AccessoryWeld")
	if named and named:IsA("Weld") then
		return named
	end

	for _ = 1, 30 do
		local w = handle:FindFirstChildWhichIsA("Weld")
		if w then
			return w
		end
		task.wait(0.05)
	end

	return nil
end

-- ================================================================
--  SMART PIVOT DETECTION
-- ================================================================

local NAMED_ATTACHMENT_CANDIDATES = {
	"AccessoryAttachment",
	"BodyBackAttachment",
	"WaistBackAttachment",
	"WaistFrontAttachment",
	"WaistCenterAttachment",
	"BodyFrontAttachment",
	"BodyCenterAttachment",
	"TailAttachment",
	"WingAttachment",
	"NeckAttachment",
	"RootAttachment",
}

local function findBestPivot(handle, weld, part0)
	for _, name in ipairs(NAMED_ATTACHMENT_CANDIDATES) do
		local att = handle:FindFirstChild(name)
		if att and att:IsA("Attachment") then
			return att.Position
		end
	end

	local att = handle:FindFirstChildOfClass("Attachment")
	if att then
		local maxDim = mathMax(handle.Size.X, handle.Size.Y, handle.Size.Z)
		if (att.Position - weld.C0.Position).Magnitude < maxDim * 0.55 then
			return att.Position
		end
	end

	local ok, part0Local = pcall(function()
		return handle.CFrame:PointToObjectSpace(part0.Position)
	end)

	if ok then
		local half = handle.Size * 0.5
		local faces = {
			Vector3New(-half.X, 0, 0), Vector3New(half.X, 0, 0),
			Vector3New(0, -half.Y, 0), Vector3New(0, half.Y, 0),
			Vector3New(0, 0, -half.Z), Vector3New(0, 0, half.Z),
		}

		local bestFace, bestDist = Vector3Zero, mathHuge
		for _, face in ipairs(faces) do
			local d = (face - part0Local).Magnitude
			if d < bestDist then
				bestDist = d
				bestFace = face
			end
		end

		local shiftDist = (bestFace - weld.C0.Position).Magnitude
		if shiftDist > handle.Size.Magnitude * 0.12 then
			return weld.C0.Position:Lerp(bestFace, 0.55)
		end
	end

	return weld.C0.Position
end

-- ================================================================
--  SIZE-BASED CONFIG SCALING
-- ================================================================

local SCALE_REF_SIZE = 3.0

local function applyScaledConfig(dest, baseConfig, handle)
	for k in pairs(dest) do
		dest[k] = nil
	end
	for k, v in pairs(baseConfig) do
		dest[k] = v
	end

	local maxDim = mathMax(handle.Size.X, handle.Size.Y, handle.Size.Z)
	local scale = mathClamp(maxDim / SCALE_REF_SIZE, 0.5, 5.0)

	if scale <= 1.15 then
		return dest
	end

	local excess = scale - 1.0
	dest.DAMPING = baseConfig.DAMPING * (1 + excess * 0.40)
	dest.ROLL_DAMPING = baseConfig.ROLL_DAMPING * (1 + excess * 0.35)
	dest.SIDE_DEADZONE = baseConfig.SIDE_DEADZONE * (1 + excess * 0.30)
	dest.FORWARD_DEADZONE = baseConfig.FORWARD_DEADZONE * (1 + excess * 0.25)
	dest.INERTIA_SCALE = baseConfig.INERTIA_SCALE / (1 + excess * 0.35)
	dest.CHAOS_STRENGTH = baseConfig.CHAOS_STRENGTH / (1 + excess * 0.60)
	dest.WAG_AMPLITUDE = baseConfig.WAG_AMPLITUDE / (1 + excess * 0.30)
	dest.WAG_SECONDARY_AMPLITUDE = baseConfig.WAG_SECONDARY_AMPLITUDE / (1 + excess * 0.30)
	dest.WAG_PITCH_BOB = baseConfig.WAG_PITCH_BOB / (1 + excess * 0.20)
	dest.WAG_ROLL_AMPLITUDE = baseConfig.WAG_ROLL_AMPLITUDE / (1 + excess * 0.20)
	dest.MOTION_TRAIL_SMOOTHING = baseConfig.MOTION_TRAIL_SMOOTHING / (1 + excess * 0.20)
	dest.STIFFNESS = baseConfig.STIFFNESS / (1 + excess * 0.25)
	dest.ROLL_STIFFNESS = baseConfig.ROLL_STIFFNESS / (1 + excess * 0.25)
	dest.WHIP_THRESHOLD = baseConfig.WHIP_THRESHOLD * (1 + excess * 0.20)

	return dest
end

-- ================================================================
--  CORE PHYSICS SETUP
-- ================================================================

local activeConnections = {}

local function cleanupAll()
	for _, c in ipairs(activeConnections) do
		if typeof(c) == "RBXScriptConnection" then
			c:Disconnect()
		end
	end
	activeConnections = {}
end

local function waitForRigParts(char)
	local humanoid = char:WaitForChild("Humanoid")
	local root = char:WaitForChild("HumanoidRootPart")

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		char:WaitForChild("Torso")
	else
		char:WaitForChild("UpperTorso")
		char:WaitForChild("LowerTorso")
	end

	return humanoid, root
end

local function setupPhysicsAccessory(accessory, char, baseConfig, accType)
	local handle = accessory:FindFirstChild("Handle")
	if not handle then
		warn("[TailPhysics] No Handle:", accessory.Name)
		return
	end

	local weld = findAccessoryWeld(handle)
	if not weld then
		warn("[TailPhysics] No Weld:", accessory.Name)
		return
	end

	local part0 = weld.Part0
	if not part0 then
		warn("[TailPhysics] Weld has no Part0:", accessory.Name)
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		warn("[TailPhysics] Missing Humanoid or HRP:", accessory.Name)
		return
	end

	local rigType = humanoid.RigType

	local floorRayParams = RaycastParams.new()
	floorRayParams.FilterDescendantsInstances = { char }
	floorRayParams.FilterType = Enum.RaycastFilterType.Exclude
	floorRayParams.IgnoreWater = true

	local CONFIG = {}
	applyScaledConfig(CONFIG, baseConfig, handle)

	local cfgTimestep             = CONFIG.TIMESTEP
	local cfgStiffness            = CONFIG.STIFFNESS
	local cfgDamping              = CONFIG.DAMPING
	local cfgInertiaScale         = CONFIG.INERTIA_SCALE
	local cfgSideDeadzone         = CONFIG.SIDE_DEADZONE
	local cfgForwardDeadzone      = CONFIG.FORWARD_DEADZONE
	local cfgForwardDragBias      = CONFIG.FORWARD_DRAG_BIAS
	local cfgForwardYawReduction  = CONFIG.FORWARD_YAW_REDUCTION
	local cfgYawUnlockAngle       = CONFIG.YAW_UNLOCK_ANGLE
	local cfgYawFullUnlock        = CONFIG.YAW_FULL_UNLOCK
	local cfgMotionTrailSmoothing = CONFIG.MOTION_TRAIL_SMOOTHING
	local cfgMotionAccelInfluence = CONFIG.MOTION_ACCEL_INFLUENCE
	local cfgRotYawInfluence      = CONFIG.ROTATION_YAW_INFLUENCE
	local cfgRotRollInfluence     = CONFIG.ROTATION_ROLL_INFLUENCE
	local cfgRotPitchInfluence    = CONFIG.ROTATION_PITCH_INFLUENCE
	local cfgRotSmoothing         = CONFIG.ROTATION_SMOOTHING
	local cfgRollStiffness        = CONFIG.ROLL_STIFFNESS
	local cfgRollDamping          = CONFIG.ROLL_DAMPING
	local cfgMaxRollAngle         = CONFIG.MAX_ROLL_ANGLE
	local cfgYawToRoll            = CONFIG.YAW_TO_ROLL
	local cfgSideToRoll           = CONFIG.SIDE_TO_ROLL
	local cfgWhipThreshold        = CONFIG.WHIP_THRESHOLD
	local cfgWhipStrength         = CONFIG.WHIP_STRENGTH
	local cfgWhipCooldown         = CONFIG.WHIP_COOLDOWN
	local cfgSmearMaxAngle        = CONFIG.SMEAR_MAX_ANGLE
	local cfgSmearSpeedFull       = CONFIG.SMEAR_SPEED_FULL
	local cfgWagSpeed             = CONFIG.WAG_SPEED
	local cfgWagAmplitude         = CONFIG.WAG_AMPLITUDE
	local cfgWagFadeSpeed         = CONFIG.WAG_FADE_SPEED
	local cfgWagSecondarySpeed    = CONFIG.WAG_SECONDARY_SPEED
	local cfgWagSecondaryAmpl     = CONFIG.WAG_SECONDARY_AMPLITUDE
	local cfgWagPitchBob          = CONFIG.WAG_PITCH_BOB
	local cfgWagRollAmplitude     = CONFIG.WAG_ROLL_AMPLITUDE
	local cfgWagRollSpeed         = CONFIG.WAG_ROLL_SPEED
	local cfgAnimInfluence        = CONFIG.ANIMATION_INFLUENCE
	local cfgAnimLinearInfluence  = CONFIG.ANIMATION_LINEAR_INFLUENCE
	local cfgAnimMotorInfluence   = CONFIG.ANIMATION_MOTOR_INFLUENCE
	local cfgAnimBlendSmoothing   = CONFIG.ANIMATION_BLEND_SMOOTHING
	local cfgYawToPitchCoupling   = CONFIG.YAW_TO_PITCH_COUPLING
	local cfgPitchToYawCoupling   = CONFIG.PITCH_TO_YAW_COUPLING
	local cfgYawVelToPitch        = CONFIG.YAW_VELOCITY_TO_PITCH
	local cfgPitchVelToYaw        = CONFIG.PITCH_VELOCITY_TO_YAW
	local cfgChaosStrength        = CONFIG.CHAOS_STRENGTH
	local cfgChaosResponse        = CONFIG.CHAOS_RESPONSE
	local cfgChaosDamping         = CONFIG.CHAOS_DAMPING
	local cfgSprintSpeed          = CONFIG.SPRINT_SPEED
	local cfgMinInversion         = CONFIG.MIN_INVERSION_STRENGTH
	local cfgMaxInversion         = CONFIG.MAX_INVERSION_STRENGTH
	local cfgMaxAngle             = CONFIG.MAX_ANGLE
	local cfgFloorCheckDist       = CONFIG.FLOOR_CHECK_DIST
	local cfgFloorMinPartSize     = CONFIG.FLOOR_MIN_PART_SIZE
	local cfgFloorPushStrength    = CONFIG.FLOOR_PUSH_STRENGTH
	local cfgFloorContactDist     = CONFIG.FLOOR_CONTACT_DIST
	local cfgRestingRollBias      = CONFIG.RESTING_ROLL_BIAS

	local accessoryAttachment, characterAttachment = findMatchingAttachmentPair(handle, char, rigType)

	local pivotPos
	if accessoryAttachment then
		pivotPos = accessoryAttachment.Position
	else
		pivotPos = findBestPivot(handle, weld, part0)
	end

	local baseC0 = weld.C0
	if characterAttachment then
		baseC0 = characterAttachment.CFrame
	end

	-- Small R6-only bias so torso-mounted accessories do not collapse toward the
	-- body center when the rig doesn't expose a matching attachment.
	local r6PivotBias = Vector3Zero
	if rigType == Enum.HumanoidRigType.R6 then
		local attachmentName = accessoryAttachment and accessoryAttachment.Name or ""
		local lowerAccessoryName = accessory.Name:lower()
		local maxDim = mathMax(handle.Size.X, handle.Size.Y, handle.Size.Z)
		local bias = mathMax(0.12, maxDim * 0.12)

		if attachmentName:find("Back", 1, true) or lowerAccessoryName:find("back", 1, true) or lowerAccessoryName:find("tail", 1, true) then
			r6PivotBias = Vector3New(0, 0, bias)
		elseif attachmentName:find("Front", 1, true) or lowerAccessoryName:find("front", 1, true) then
			r6PivotBias = Vector3New(0, 0, -bias)
		end
	end

	local baseC0Rot = CFrameNew(-(pivotPos + r6PivotBias)) * baseC0

	local yawAngle, yawVel = 0, 0
	local pitchAngle, pitchVel = 0, 0
	local rollAngle, rollVel = 0, 0

	local accumulator = 0
	local wagTime = 0
	local lastRootPos = root.Position
	local firstFrame = true

	local idleTime = 0
	local IDLE_SPEED_THRESH = 0.6
	local IDLE_BLEED_DELAY = 1.8
	local IDLE_BLEED_RATE = 0.018

	local prevRootCF = root.CFrame
	local smoothedYawRate = 0

	local prevMotionDir = Vector3Zero
	local whipCooldown = 0

	local WOBBLE_FLIP_DECAY = 7
	local WOBBLE_FLIP_THRESHOLD = 5
	local WOBBLE_MIN_VEL = 0.6
	local WOBBLE_HARD_VEL_LIMIT = 35
	local WOBBLE_STABILIZE_DURATION = 0.45
	local WOBBLE_STABILIZE_VEL_DRAG = 0.88
	local WOBBLE_STABILIZE_ANGLE_PULL = 0.06

	local yawFlipScore, prevYawVelSign = 0, 0
	local pitchFlipScore, prevPitchVelSign = 0, 0
	local rollFlipScore, prevRollVelSign = 0, 0
	local stabilizeTimer = 0

	local animationMotors = collectAnimationMotors(char)
	local lastBodyRelativeCF = nil
	local smoothedLocalVel = Vector3Zero
	local smoothedAnimLinear = Vector3Zero
	local smoothedAnimAngular = Vector3Zero
	local motionMemory = Vector3Zero
	local prevMotionMemory = Vector3Zero
	local chaosYaw, chaosPitch = 0, 0
	local chaosYawVel, chaosPitchVel = 0, 0

	local seed = (hashString(accessory.Name) % 1000) / 1000
	local chaosPhase = seed * math.pi * 2

	local floorProximity = 0
	local floorContact = false
	local floorState = "upright"

	local function trackFlip(vel, lastSign, score)
		local s = vel > WOBBLE_MIN_VEL and 1
			or vel < -WOBBLE_MIN_VEL and -1
			or 0
		if s ~= 0 and lastSign ~= 0 and s ~= lastSign then
			score += 1
		end
		return s ~= 0 and s or lastSign, score
	end

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		dt = mathClamp(dt, 0.001, 0.1)

		accumulator = mathMin(accumulator + dt, cfgTimestep * 8)
		wagTime += dt
		whipCooldown = mathMax(0, whipCooldown - dt)

		if not char.Parent or not part0.Parent or not weld.Parent then
			if conn then conn:Disconnect() end
			return
		end

		if not root or not root.Parent then
			root = char:FindFirstChild("HumanoidRootPart")
		end
		if not humanoid or not humanoid.Parent then
			humanoid = char:FindFirstChildOfClass("Humanoid")
		end
		if not root or not humanoid then
			return
		end

		if #animationMotors == 0 then
			animationMotors = collectAnimationMotors(char)
		end

		do
			local floorDown
			floorDown, floorState = getFloorSupportState(root.CFrame)

			local floorCheckDist = cfgFloorCheckDist
			local floorContactDist = cfgFloorContactDist

			if floorState ~= "upright" then
				floorCheckDist *= 1.35
				floorContactDist *= 1.35
			end

			local origin = handle.Position + (floorDown * 0.15)
			local rayDir = floorDown * floorCheckDist
			local result = raycastVisibleFloor(origin, rayDir, floorRayParams)

			floorProximity = 0
			floorContact = false

			if result then
				local hitPart = result.Instance
				if hitPart and hitPart:IsA("BasePart") then
					local partSize = hitPart.Size
					local maxDim = mathMax(partSize.X, mathMax(partSize.Y, partSize.Z))
					if maxDim >= cfgFloorMinPartSize or floorState ~= "upright" then
						floorProximity = 1 - mathClamp(result.Distance / floorCheckDist, 0, 1)
						floorContact = result.Distance <= floorContactDist
					end
				end
			end
		end

		local curPos = root.Position
		local charVel
		if firstFrame then
			charVel = Vector3Zero
			firstFrame = false
		else
			charVel = (curPos - lastRootPos) / dt
		end
		lastRootPos = curPos

		local rootCF = root.CFrame
		local localVel = rootCF:VectorToObjectSpace(charVel)
		local moveIntent = humanoid.MoveDirection * humanoid.WalkSpeed
		local moveLocal = rootCF:VectorToObjectSpace(moveIntent)

		local rotDelta = prevRootCF:Inverse() * rootCF
		local rotAxis, rotAngle = rotDelta:ToAxisAngle()
		local rawYawRate = rotAxis.Y * rotAngle / mathMax(dt, 1e-3)
		smoothedYawRate = smoothedYawRate + (rawYawRate - smoothedYawRate) * cfgRotSmoothing
		prevRootCF = rootCF

		local bodyRelativeCF = rootCF:ToObjectSpace(part0.CFrame)
		local bodyPoseLinear = Vector3Zero
		local bodyPoseAngular = Vector3Zero
		if lastBodyRelativeCF then
			bodyPoseLinear, bodyPoseAngular = cframeDeltaToLocalVectors(lastBodyRelativeCF, bodyRelativeCF, dt)
		end
		lastBodyRelativeCF = bodyRelativeCF

		local motorPoseLinear = Vector3Zero
		local motorPoseAngular = Vector3Zero
		for _, tracker in ipairs(animationMotors) do
			local motor = tracker.motor
			if motor and motor.Parent and motor.Part0 then
				local currentTransform = motor.Transform
				if tracker.prevTransform then
					local delta2 = tracker.prevTransform:Inverse() * currentTransform
					local axis2, angle2 = delta2:ToAxisAngle()
					local invDt = 1 / mathMax(dt, 1e-3)
					local localAngular2 = axis2 * (angle2 * invDt)
					local localLinear2 = (currentTransform.Position - tracker.prevTransform.Position) * invDt
					local p0CF = motor.Part0.CFrame
					motorPoseLinear += rootCF:VectorToObjectSpace(p0CF:VectorToWorldSpace(localLinear2)) * tracker.weight
					motorPoseAngular += rootCF:VectorToObjectSpace(p0CF:VectorToWorldSpace(localAngular2)) * tracker.weight
				end
				tracker.prevTransform = currentTransform
			end
		end

		local rawLocalVel =
			(localVel * 0.62) +
			(moveLocal * 0.16) +
			(bodyPoseLinear * cfgAnimLinearInfluence) +
			(motorPoseLinear * cfgAnimMotorInfluence)

		local rawAnimAngular =
			rootCF:VectorToObjectSpace(part0.AssemblyAngularVelocity) * 0.55 +
			(bodyPoseAngular * cfgAnimInfluence) +
			(motorPoseAngular * cfgAnimMotorInfluence)

		smoothedLocalVel = smoothedLocalVel:Lerp(rawLocalVel, cfgAnimBlendSmoothing)
		smoothedAnimLinear = smoothedAnimLinear:Lerp(bodyPoseLinear + motorPoseLinear, cfgAnimBlendSmoothing)
		smoothedAnimAngular = smoothedAnimAngular:Lerp(rawAnimAngular, cfgAnimBlendSmoothing)

		local effectiveLocalVel = smoothedLocalVel + smoothedAnimLinear * 0.20

		local currentSpeed = effectiveLocalVel.Magnitude
		if currentSpeed < IDLE_SPEED_THRESH then
			idleTime += dt
		else
			idleTime = 0
		end

		local flatVelX = effectiveLocalVel.X
		local flatVelZ = effectiveLocalVel.Z
		local flatSpeed = math.sqrt(flatVelX * flatVelX + flatVelZ * flatVelZ)

		if flatSpeed > 0.1 then
			local invFlat = 1 / flatSpeed
			local flatDirX = flatVelX * invFlat
			local flatDirZ = flatVelZ * invFlat
			if prevMotionDir.Magnitude > 0.1 then
				local dotDir = flatDirX * prevMotionDir.X + flatDirZ * prevMotionDir.Z
				if dotDir < -0.35 and flatSpeed >= cfgWhipThreshold and whipCooldown <= 0 and stabilizeTimer <= 0 then
					local whipBase = cfgInertiaScale * cfgWhipStrength
					yawVel += -effectiveLocalVel.X * whipBase * 60
					pitchVel += effectiveLocalVel.Z * whipBase * 60
					rollVel += -effectiveLocalVel.X * cfgSideToRoll * cfgWhipStrength * 40
					whipCooldown = cfgWhipCooldown
				end
			end
			prevMotionDir = Vector3New(flatDirX, 0, flatDirZ)
		end

		prevMotionMemory = motionMemory
		motionMemory = motionMemory:Lerp(effectiveLocalVel, cfgMotionTrailSmoothing)
		local motionDelta = (motionMemory - prevMotionMemory) / mathMax(dt, 1e-3)

		while accumulator >= cfgTimestep do
			local ts = cfgTimestep
			local motion = motionMemory + (motionDelta * cfgMotionAccelInfluence)

			local speed = motion.Magnitude
			local speedFactor = smoothstep(0, cfgSprintSpeed, speed)

			local forwardMotion = mathMax(-motion.Z, 0)
			local backwardMotion = mathMax(motion.Z, 0)
			local sideMotion = motion.X

			local sideAbs = mathAbs(sideMotion)
			local sideEase = smoothstep(cfgSideDeadzone * 0.65, cfgSideDeadzone * 2.0, sideAbs)
			sideMotion *= sideEase

			local forwardAbs = mathAbs(motion.Z)
			if forwardAbs < cfgForwardDeadzone then
				motion = Vector3New(motion.X, motion.Y, 0)
				forwardMotion = 0
				backwardMotion = 0
			end

			local yawUnlock = smoothstep(cfgYawUnlockAngle, cfgYawFullUnlock, mathAbs(pitchAngle))
			local yawGate = (0.20 + 0.80 * yawUnlock) * (1 - speedFactor * cfgForwardYawReduction)

			local inversionStrength = cfgMinInversion + (cfgMaxInversion - cfgMinInversion) * speedFactor

			local targetYaw = -sideMotion * cfgInertiaScale * yawGate
			local targetPitch = (-motion.Z * cfgInertiaScale * 0.55) * inversionStrength
			targetPitch += forwardMotion * cfgForwardDragBias * inversionStrength
			targetPitch -= backwardMotion * cfgForwardDragBias * (0.45 + 0.55 * speedFactor)

			targetYaw += -smoothedYawRate * cfgRotYawInfluence
			targetPitch += mathAbs(smoothedYawRate) * cfgRotPitchInfluence * 0.015

			targetYaw += smoothedAnimAngular.Y * 0.035
			targetYaw += smoothedAnimLinear.X * 0.006
			targetPitch += -smoothedAnimAngular.X * 0.045
			targetPitch += -smoothedAnimLinear.Z * 0.012

			targetPitch += mathAbs(targetYaw) * cfgYawToPitchCoupling
			targetYaw += pitchAngle * cfgPitchToYawCoupling
			targetPitch += yawVel * cfgYawVelToPitch
			targetYaw += pitchVel * cfgPitchVelToYaw

			local targetRoll = yawAngle * cfgYawToRoll
				+ sideMotion * cfgSideToRoll
			- smoothedYawRate * cfgRotRollInfluence * 0.04

			local wagFadeEarly = mathMax(0, 1 - speed * cfgWagFadeSpeed * 0.5)
			targetRoll += cfgRestingRollBias * wagFadeEarly

			chaosPhase += ts * (1.8 + speedFactor * 2.4)
			local chaoticDrive = clamp01((motionDelta.Magnitude / mathMax(cfgSprintSpeed, 1)) * 1.35)
			local chaosWaveA = mathSin(chaosPhase * 1.7 + seed * 9.1)
			local chaosWaveB = mathCos(chaosPhase * 2.3 + seed * 5.7)
			local chaosWaveC = mathSin(chaosPhase * 0.9 + seed * 13.3)

			local chaosIdleSuppress = mathMax(0, 1 - smoothstep(IDLE_BLEED_DELAY, IDLE_BLEED_DELAY + 1.5, idleTime))

			local chaosTargetYaw = (chaosWaveA * 0.65 + chaosWaveB * 0.35) * cfgChaosStrength * chaoticDrive * chaosIdleSuppress
			local chaosTargetPitch = (chaosWaveC * 0.70 + chaosWaveA * 0.30) * (cfgChaosStrength * 0.72) * chaoticDrive * chaosIdleSuppress

			local chaosDecay = 1 - cfgChaosDamping
			chaosYawVel += ((chaosTargetYaw - chaosYaw) * cfgChaosResponse - chaosYawVel * chaosDecay) * ts * 60
			chaosPitchVel += ((chaosTargetPitch - chaosPitch) * cfgChaosResponse - chaosPitchVel * chaosDecay) * ts * 60
			chaosYaw += chaosYawVel * ts
			chaosPitch += chaosPitchVel * ts

			targetYaw += chaosYaw
			targetPitch += chaosPitch

			local wagFade = mathMax(0, 1 - speed * cfgWagFadeSpeed)
			local idleStrength = wagFade * wagFade

			local primaryWag = mathSin(wagTime * cfgWagSpeed)
			local secondaryWag = mathSin(wagTime * cfgWagSecondarySpeed + 0.8)

			targetYaw += (primaryWag * cfgWagAmplitude + secondaryWag * cfgWagSecondaryAmpl) * idleStrength
			targetPitch += mathAbs(primaryWag) * cfgWagPitchBob * idleStrength
			targetRoll += mathSin(wagTime * cfgWagRollSpeed) * cfgWagRollAmplitude * idleStrength

			if floorProximity > 0 then
				local pushForce = floorProximity * floorProximity * cfgFloorPushStrength

				if floorState ~= "upright" then
					pushForce *= 0.55
				end

				pitchVel += pushForce * ts

				if floorContact then
					local settleStrength = (floorState ~= "upright") and 0.12 or 0.25

					if pitchAngle < 0 then
						pitchAngle *= (1 - settleStrength * (ts * 60))
					end

					if pitchVel < 0 then
						pitchVel = 0
					end

					if floorState ~= "upright" then
						yawVel *= 0.92
						rollVel *= 0.92
					end
				end
			end

			yawVel += (-cfgStiffness * (yawAngle - targetYaw) - cfgDamping * yawVel) * ts
			yawAngle += yawVel * ts

			pitchVel += (-cfgStiffness * (pitchAngle - targetPitch) - cfgDamping * pitchVel) * ts
			pitchAngle += pitchVel * ts

			rollVel += (-cfgRollStiffness * (rollAngle - targetRoll) - cfgRollDamping * rollVel) * ts
			rollAngle += rollVel * ts

			accumulator -= cfgTimestep
		end

		if idleTime > IDLE_BLEED_DELAY then
			local bleedStrength = mathMin(1, (idleTime - IDLE_BLEED_DELAY) * 0.5)
			local velDecay = 1 - IDLE_BLEED_RATE * bleedStrength * (dt * 60)
			yawVel *= velDecay
			pitchVel *= velDecay
			rollVel *= velDecay
		end

		yawVel = mathClamp(yawVel, -WOBBLE_HARD_VEL_LIMIT, WOBBLE_HARD_VEL_LIMIT)
		pitchVel = mathClamp(pitchVel, -WOBBLE_HARD_VEL_LIMIT, WOBBLE_HARD_VEL_LIMIT)
		rollVel = mathClamp(rollVel, -WOBBLE_HARD_VEL_LIMIT, WOBBLE_HARD_VEL_LIMIT)

		local flipDecay = dt * WOBBLE_FLIP_DECAY
		yawFlipScore = mathMax(0, yawFlipScore - flipDecay)
		pitchFlipScore = mathMax(0, pitchFlipScore - flipDecay)
		rollFlipScore = mathMax(0, rollFlipScore - flipDecay)

		prevYawVelSign, yawFlipScore = trackFlip(yawVel, prevYawVelSign, yawFlipScore)
		prevPitchVelSign, pitchFlipScore = trackFlip(pitchVel, prevPitchVelSign, pitchFlipScore)
		prevRollVelSign, rollFlipScore = trackFlip(rollVel, prevRollVelSign, rollFlipScore)

		if yawFlipScore >= WOBBLE_FLIP_THRESHOLD
			or pitchFlipScore >= WOBBLE_FLIP_THRESHOLD
			or rollFlipScore >= WOBBLE_FLIP_THRESHOLD then
			stabilizeTimer = WOBBLE_STABILIZE_DURATION
			yawFlipScore, pitchFlipScore, rollFlipScore = 0, 0, 0
		end

		if stabilizeTimer > 0 then
			stabilizeTimer = mathMax(0, stabilizeTimer - dt)
			local strength = stabilizeTimer / WOBBLE_STABILIZE_DURATION
			local velMul = 1 - (1 - WOBBLE_STABILIZE_VEL_DRAG) * strength
			local angleBleed = WOBBLE_STABILIZE_ANGLE_PULL * strength
			local oneMinusBleed = 1 - angleBleed
			yawVel *= velMul
			yawAngle *= oneMinusBleed
			pitchVel *= velMul
			pitchAngle *= oneMinusBleed
			rollVel *= velMul
			rollAngle *= oneMinusBleed
		end

		local smearFactor = smoothstep(0, cfgSmearSpeedFull, motionMemory.Magnitude)
		local dynamicMax = cfgMaxAngle + (cfgSmearMaxAngle - cfgMaxAngle) * smearFactor

		yawAngle = mathClamp(yawAngle, -dynamicMax, dynamicMax)
		pitchAngle = mathClamp(pitchAngle, -dynamicMax, dynamicMax)
		rollAngle = mathClamp(rollAngle, -cfgMaxRollAngle, cfgMaxRollAngle)

		local physRot = CFrameAngles(pitchAngle, yawAngle, rollAngle)
		weld.C0 = CFrameNew(pivotPos)
			* physRot
			* CFrameNew(0, 0, -0.2)
			* baseC0Rot
	end)

	return conn
end

--  CHARACTER INIT

local function initCharacter(char, mode)
	character = char
	cleanupAll()

	local humanoid, root = waitForRigParts(char)

	task.wait(0.25)

	local function trySetup(child)
		if not child:IsA("Accessory") then
			return
		end

		local accType = classifyAccessory(child, mode, char)
		if accType then
			local conn = setupPhysicsAccessory(child, char, CONFIGS[accType], accType)
			if conn then
				table.insert(activeConnections, conn)
			end
		end
	end

	for _, child in ipairs(char:GetChildren()) do
		trySetup(child)
	end

	local childAddedConn = char.ChildAdded:Connect(function(child)
		task.wait(0.1)
		trySetup(child)
	end)
	table.insert(activeConnections, childAddedConn)
end

--  ENTRY POINT

if character then
	initCharacter(character, DEFAULT_MODE)
end

player.CharacterAdded:Connect(function(char)
	initCharacter(char, DEFAULT_MODE)
end)

player.CharacterRemoving:Connect(cleanupAll)
