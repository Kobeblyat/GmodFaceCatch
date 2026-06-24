if SERVER then return end

local TAG = "[FaceCatch] "
local AUTHOR = "Kobeblyat"
local AUTHOR_URL = "https://space.bilibili.com/3546897006463032"

if _G.FaceCatchClientInstance and _G.FaceCatchClientInstance.Shutdown then
    _G.FaceCatchClientInstance.Shutdown("reload")
end
_G.FaceCatchClientLoadId = (_G.FaceCatchClientLoadId or 0) + 1
local INSTANCE_ID = _G.FaceCatchClientLoadId

local URL = CreateClientConVar("facecatch_url", "ws://127.0.0.1:8667", true, false)
local ENABLED = CreateClientConVar("facecatch_enabled", "1", true, false)
local SMOOTHING = CreateClientConVar("facecatch_smoothing", "14", true, false)
local FLEX_SCALE = CreateClientConVar("facecatch_flex_scale", "1", true, false)
local EYE_SENSITIVITY = CreateClientConVar("facecatch_eye_sensitivity", "1", true, false)
local MOUTH_SENSITIVITY = CreateClientConVar("facecatch_mouth_sensitivity", "1", true, false)
local HEAD_ENABLED = CreateClientConVar("facecatch_head_enabled", "1", true, false)
local HEAD_SCALE = CreateClientConVar("facecatch_head_scale", "0.65", true, false)
local HEAD_AXIS_PRESET = CreateClientConVar("facecatch_head_axis_preset", "5", true, false)
local HEAD_PITCH_SCALE = CreateClientConVar("facecatch_head_pitch_scale", "1", true, false)
local HEAD_YAW_SCALE = CreateClientConVar("facecatch_head_yaw_scale", "1", true, false)
local HEAD_ROLL_SCALE = CreateClientConVar("facecatch_head_roll_scale", "0", true, false)
local HEAD_PITCH_AXIS = CreateClientConVar("facecatch_head_pitch_axis", "1", true, false)
local HEAD_YAW_AXIS = CreateClientConVar("facecatch_head_yaw_axis", "2", true, false)
local HEAD_ROLL_AXIS = CreateClientConVar("facecatch_head_roll_axis", "3", true, false)
local CAPTURE_ENABLED = CreateClientConVar("facecatch_capture_enabled", "1", true, false)
local MULTIPLAYER = CreateClientConVar("facecatch_multiplayer", "1", true, false)
local APPLY_REMOTE = CreateClientConVar("facecatch_apply_remote", "1", true, false)
local APPLY_REMOTE_PLAYERS = CreateClientConVar("facecatch_apply_remote_players", "1", true, false)
local NETWORK_RATE = CreateClientConVar("facecatch_network_rate", "20", true, false)
local RENDER_OVERRIDE = CreateClientConVar("facecatch_render_override", "1", true, false)
local ENTITY_RENDER_OVERRIDE = CreateClientConVar("facecatch_entity_render_override", "1", true, false)
local AUTO_VIEW = CreateClientConVar("facecatch_auto_view", "1", true, false)

local NET_FRAME_C2S = "facecatch_frame_c2s"
local NET_FRAME_S2C = "facecatch_frame_s2c"
local NET_TARGET_S2C = "facecatch_target_s2c"

local socket
local connected = false
local reconnectAt = 0
local latest
local latestRaw
local nextNetworkSend = 0
local gwsocketsMissing = false
local captureAutoDisabled = false
local socketHadError = false
local lastSocketError = ""
local activeProfile = "generic"
local sourceTargets = {}
local remoteFrames = {}
local entityStates = {}

local blendshapeNames = {
    "_neutral",
    "browDownLeft", "browDownRight", "browInnerUp",
    "browOuterUpLeft", "browOuterUpRight", "cheekPuff",
    "cheekSquintLeft", "cheekSquintRight", "eyeBlinkLeft",
    "eyeBlinkRight", "eyeLookDownLeft", "eyeLookDownRight",
    "eyeLookInLeft", "eyeLookInRight", "eyeLookOutLeft",
    "eyeLookOutRight", "eyeLookUpLeft", "eyeLookUpRight",
    "eyeSquintLeft", "eyeSquintRight", "eyeWideLeft",
    "eyeWideRight", "jawForward", "jawLeft", "jawOpen",
    "jawRight", "mouthClose", "mouthDimpleLeft",
    "mouthDimpleRight", "mouthFrownLeft", "mouthFrownRight",
    "mouthFunnel", "mouthLeft", "mouthLowerDownLeft",
    "mouthLowerDownRight", "mouthPressLeft", "mouthPressRight",
    "mouthPucker", "mouthRight", "mouthRollLower",
    "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper",
    "mouthSmileLeft", "mouthSmileRight", "mouthStretchLeft",
    "mouthStretchRight", "mouthUpperUpLeft", "mouthUpperUpRight",
    "noseSneerLeft", "noseSneerRight"
}

local shapeIndexes = {}
for index, name in ipairs(blendshapeNames) do
    shapeIndexes[name] = index
end

local aliases = {
    eyeBlinkLeft = {
        "blinkleft", "leftblink", "eyeblinkleft", "leftlidclose",
        "eyesirolsl00defcl"
    },
    eyeBlinkRight = {
        "blinkright", "rightblink", "eyeblinkright", "rightlidclose",
        "eyesirorsr00defcl"
    },
    eyeWideLeft = {"eyewideleft", "leftlidraiser"},
    eyeWideRight = {"eyewideright", "rightlidraiser"},
    eyeSquintLeft = {"eyesquintleft", "leftsquint"},
    eyeSquintRight = {"eyesquintright", "rightsquint"},
    browDownLeft = {"browdownleft", "leftbrowdown", "leftbrowlowerer"},
    browDownRight = {"browdownright", "rightbrowdown", "rightbrowlowerer"},
    browInnerUp = {"browinnerup", "innerbrowraiser"},
    browOuterUpLeft = {"browouterupleft", "leftouterbrowraiser"},
    browOuterUpRight = {"browouterupright", "rightouterbrowraiser"},
    cheekPuff = {"cheekpuff", "puff"},
    jawOpen = {"jawopen", "jawdrop", "mouthopen", "openmouth"},
    jawLeft = {"jawleft"},
    jawRight = {"jawright"},
    mouthClose = {"mouthclose", "jawclench"},
    mouthFunnel = {"mouthfunnel", "funnel"},
    mouthPucker = {"mouthpucker", "pucker"},
    mouthSmileLeft = {
        "mouthsmileleft", "leftsmile", "smileleft",
        "eyesirolsl00egaoop", "eyesirolsl00egaocl"
    },
    mouthSmileRight = {
        "mouthsmileright", "rightsmile", "smileright",
        "eyesirorsr00egaoop", "eyesirorsr00egaocl"
    },
    mouthFrownLeft = {"mouthfrownleft", "leftfrown", "frownleft"},
    mouthFrownRight = {"mouthfrownright", "rightfrown", "frownright"},
    mouthLeft = {"mouthleft"},
    mouthRight = {"mouthright"},
    mouthStretchLeft = {"mouthstretchleft", "leftmouthstretch"},
    mouthStretchRight = {"mouthstretchright", "rightmouthstretch"},
    mouthUpperUpLeft = {"mouthupperupleft", "leftupperlipraiser"},
    mouthUpperUpRight = {"mouthupperupright", "rightupperlipraiser"},
    mouthLowerDownLeft = {"mouthlowerdownleft", "leftlowerlipdepressor"},
    mouthLowerDownRight = {"mouthlowerdownright", "rightlowerlipdepressor"},
    noseSneerLeft = {"nosesneerleft", "leftnosesneer"},
    noseSneerRight = {"nosesneerright", "rightnosesneer"}
}

local combinedAliases = {
    blink = {
        "blink", "eyeblink", "eyesclosed", "eyeclosed",
        "eyefacef00defcl", "eyenosenl00defcl"
    },
    smile = {
        "smile", "happy", "mouthsmile",
        "eyefacef00egaoop", "eyefacef00egaocl"
    },
    frown = {"frown", "sad", "mouthfrown"},
    mouthOpen = {"jawdrop", "jawopen", "mouthopen", "openmouth"}
}

local function normalize(value)
    local normalized = string.lower(value or ""):gsub("[^a-z0-9]", "")
    return normalized
end

local function clamp01(value)
    return math.Clamp(tonumber(value) or 0, 0, 1)
end

local function remap(value, low, high)
    return clamp01((clamp01(value) - low) / math.max(high - low, 0.001))
end

local function average(a, b)
    return (clamp01(a) + clamp01(b)) * 0.5
end

local function shape(data, name)
    local index = shapeIndexes[name]
    return index and data.blendshapes and clamp01(data.blendshapes[index]) or 0
end

local function blinkValue(data, name)
    local raw = shape(data, name)
    if raw >= 0.43 then return 1 end
    local value = remap(raw, 0.24, 0.46)
    return clamp01(value * value * (3 - 2 * value) * EYE_SENSITIVITY:GetFloat())
end

local function mouthOpenValue(data)
    local geometry = data.mouth_metrics and data.mouth_metrics.mouthOpenGeo or 0
    return clamp01(math.max(
        remap(shape(data, "jawOpen"), 0.035, 0.46),
        remap(geometry, 0.015, 0.56)
    ) * MOUTH_SENSITIVITY:GetFloat())
end

local function mouthRoundValue(data)
    local geometry = data.mouth_metrics and data.mouth_metrics.mouthRoundGeo or 0
    return math.max(
        shape(data, "mouthFunnel"),
        shape(data, "mouthPucker"),
        remap(geometry, 0.08, 0.72)
    )
end

local function mouthWideValue(data)
    local geometry = data.mouth_metrics and data.mouth_metrics.mouthWideGeo or 0
    return math.max(
        average(shape(data, "mouthStretchLeft"), shape(data, "mouthStretchRight")),
        remap(geometry, 0.42, 0.86)
    )
end

local function mouthNarrowValue(data)
    local geometry = data.mouth_metrics and data.mouth_metrics.mouthNarrowGeo or 0
    return math.max(
        shape(data, "mouthPucker"),
        remap(geometry, 0.82, 1.0)
    )
end

local function tomorinMouthValue(data, vowel)
    local open = mouthOpenValue(data)
    if open <= 0 then return 0 end

    local round = mouthRoundValue(data)
    local wide = mouthWideValue(data)
    local narrow = mouthNarrowValue(data)

    if vowel == "a" then
        return clamp01(open * (1 - round * 0.55) * (1 - wide * 0.25) * 1.25)
    end
    if vowel == "o" then return clamp01(open * round * 1.3) end
    if vowel == "e" then return clamp01(open * wide * 1.2) end
    if vowel == "u" then return clamp01(open * narrow * 1.2) end
    return 0
end

local function matches(name, candidates)
    for _, candidate in ipairs(candidates or {}) do
        if name == candidate then return true end
    end
    return false
end

local function sourceForTomorin(normalizedName)
    if normalizedName == "eyeclosel" then
        return function(data) return blinkValue(data, "eyeBlinkLeft") end, "eyeBlinkLeft"
    end
    if normalizedName == "eyecloser" then
        return function(data) return blinkValue(data, "eyeBlinkRight") end, "eyeBlinkRight"
    end
    if normalizedName == "moutha" then
        return function(data) return tomorinMouthValue(data, "a") end, "viseme-A"
    end
    if normalizedName == "moutho" then
        return function(data) return tomorinMouthValue(data, "o") end, "viseme-O"
    end
    if normalizedName == "mouthe" then
        return function(data) return tomorinMouthValue(data, "e") end, "viseme-E"
    end
    if normalizedName == "mouth" then
        return function(data) return tomorinMouthValue(data, "u") end, "viseme-U"
    end

    return nil
end

local function sourceForFlex(normalizedName, modelName)
    if modelName == "models/edward/tomorin/pm/tomorin_pm.mdl" then
        return sourceForTomorin(normalizedName)
    end

    for shapeName, names in pairs(aliases) do
        local candidates = table.Copy(names)
        local normalizedShapeName = normalize(shapeName)
        table.insert(candidates, normalizedShapeName)
        if matches(normalizedName, candidates) then
            if shapeName == "eyeBlinkLeft" or shapeName == "eyeBlinkRight" then
                return function(data) return blinkValue(data, shapeName) end, shapeName
            end
            if shapeName == "jawOpen" then
                return mouthOpenValue, shapeName
            end
            return function(data) return shape(data, shapeName) end, shapeName
        end
    end

    if matches(normalizedName, combinedAliases.blink) then
        return function(data)
            return average(
                blinkValue(data, "eyeBlinkLeft"),
                blinkValue(data, "eyeBlinkRight")
            )
        end, "blink"
    end

    if matches(normalizedName, combinedAliases.smile) then
        return function(data)
            return average(shape(data, "mouthSmileLeft"), shape(data, "mouthSmileRight"))
        end, "smile"
    end

    if matches(normalizedName, combinedAliases.frown) then
        return function(data)
            return average(shape(data, "mouthFrownLeft"), shape(data, "mouthFrownRight"))
        end, "frown"
    end

    if matches(normalizedName, combinedAliases.mouthOpen) then
        return mouthOpenValue, "mouthOpen"
    end
end

local function stateForEntity(ent)
    if not IsValid(ent) then return nil end

    local id = ent:EntIndex()
    local state = entityStates[id]
    if not state or state.entity ~= ent then
        state = {
            entity = ent,
            model = "",
            bindings = {},
            suppressed = {},
            headBone = nil,
            currentHead = Angle(0, 0, 0),
            profile = "generic"
        }
        entityStates[id] = state
    end
    return state
end

local function headAngleFromPose(pose)
    local scale = HEAD_SCALE:GetFloat()
    local pitch = (tonumber(pose.pitch) or 0) * HEAD_PITCH_SCALE:GetFloat() * scale
    local yaw = (tonumber(pose.yaw) or 0) * HEAD_YAW_SCALE:GetFloat() * scale
    local roll = (tonumber(pose.roll) or 0) * HEAD_ROLL_SCALE:GetFloat() * scale
    local preset = HEAD_AXIS_PRESET:GetInt()

    local function addAxis(axis, value, angle)
        if axis == 0 then
            angle.p = angle.p + value
        elseif axis == 1 then
            angle.y = angle.y + value
        elseif axis == 2 then
            angle.r = angle.r + value
        end
    end

    local angle = Angle(0, 0, 0)

    -- New axis-router mode. 0 = Angle.p, 1 = Angle.y, 2 = Angle.r, 3 = off.
    -- It exists because many MMD/PM playermodels have Head bone axes that do
    -- not match ValveBiped. Tomorin currently needs pitch away from the legacy
    -- axis, otherwise looking up/down barely moves.
    if preset >= 5 then
        addAxis(math.Clamp(HEAD_PITCH_AXIS:GetInt(), 0, 3), -pitch, angle)
        addAxis(math.Clamp(HEAD_YAW_AXIS:GetInt(), 0, 3), yaw, angle)
        addAxis(math.Clamp(HEAD_ROLL_AXIS:GetInt(), 0, 3), -roll, angle)
        return angle
    end

    -- Compatibility presets for older saved configs.
    if preset == 0 then
        return Angle(-pitch, yaw, -roll)
    elseif preset == 1 then
        return Angle(-pitch, yaw, 0)
    elseif preset == 2 then
        return Angle(0, -pitch, yaw + roll)
    elseif preset == 3 then
        return Angle(-pitch, -yaw, 0)
    elseif preset == 4 then
        return Angle(0, yaw, -pitch + roll)
    end

    return Angle(0, -pitch, yaw)
end

local function rebuildBindings(ent, state)
    state.bindings = {}
    state.suppressed = {}
    state.model = string.lower(ent:GetModel() or "")
    state.headBone = nil
    state.currentHead = Angle(0, 0, 0)
    state.profile = state.model == "models/edward/tomorin/pm/tomorin_pm.mdl"
        and "tomorin-safe" or "generic"

    local flexNum = ent.GetFlexNum and ent:GetFlexNum() or 0
    for id = 0, flexNum - 1 do
        ent:SetFlexWeight(id, 0)
        local flexName = ent:GetFlexName(id) or ""
        local getter, sourceName = sourceForFlex(normalize(flexName), state.model)
        if getter then
            state.bindings[#state.bindings + 1] = {
                id = id,
                name = flexName,
                source = sourceName,
                get = getter,
                value = 0,
                response = string.StartWith(sourceName, "eyeBlink") and 55
                    or string.StartWith(sourceName, "viseme-") and 38
                    or nil
            }
        elseif state.profile == "tomorin-safe" then
            state.suppressed[#state.suppressed + 1] = id
        end
    end

    local headNames = {
        "ValveBiped.Bip01_Head1", "bip_head", "Head", "head",
        "cf_J_Head", "J_Bip_C_Head"
    }
    for _, boneName in ipairs(headNames) do
        local boneId = ent:LookupBone(boneName)
        if boneId then
            state.headBone = boneId
            break
        end
    end

    if ent == LocalPlayer() then activeProfile = state.profile end

    print(TAG .. "Target: " .. tostring(ent) .. " | Model: " .. state.model)
    print(TAG .. "Profile: " .. state.profile)
    print(TAG .. "Mapped " .. #state.bindings .. " flex controllers.")
    print(TAG .. "Suppressed " .. #state.suppressed .. " automatic controllers.")
end

local function clearPose(ent)
    if not IsValid(ent) then return end
    local state = stateForEntity(ent)
    if not state then return end

    for _, binding in ipairs(state.bindings) do
        ent:SetFlexWeight(binding.id, 0)
        binding.value = 0
    end
    for _, id in ipairs(state.suppressed) do
        ent:SetFlexWeight(id, 0)
    end
    if state.headBone then ent:ManipulateBoneAngles(state.headBone, angle_zero) end
    state.currentHead = Angle(0, 0, 0)
end

local function applyFrame(ent, data, frameTime)
    if not IsValid(ent) or not istable(data) or not istable(data.blendshapes) then return end

    local state = stateForEntity(ent)
    if not state then return end
    local model = string.lower(ent:GetModel() or "")
    if model ~= state.model then rebuildBindings(ent, state) end

    frameTime = math.min(frameTime or FrameTime(), 0.1)
    local smoothing = math.max(SMOOTHING:GetFloat(), 0.1)
    local lerpAmount = 1 - math.exp(-smoothing * frameTime)
    local scale = FLEX_SCALE:GetFloat()

    for _, id in ipairs(state.suppressed) do
        ent:SetFlexWeight(id, 0)
    end

    for _, binding in ipairs(state.bindings) do
        local target = clamp01(binding.get(data) * scale)
        local bindingLerp = lerpAmount
        if binding.response then
            bindingLerp = 1 - math.exp(-binding.response * frameTime)
        end
        if string.StartWith(binding.source, "eyeBlink") and target >= 0.98 then
            binding.value = 1
        else
            binding.value = Lerp(bindingLerp, binding.value, target)
        end
        ent:SetFlexWeight(binding.id, binding.value)
    end

    if HEAD_ENABLED:GetBool() and state.headBone and data.head_pose then
        local target = headAngleFromPose(data.head_pose)
        state.currentHead = LerpAngle(lerpAmount, state.currentHead, target)
        ent:ManipulateBoneAngles(state.headBone, state.currentHead)
    end
end

local function reserveDrivenEntity(driven, ent)
    if not IsValid(ent) then return false end
    local id = ent:EntIndex()
    if driven[id] then return false end
    driven[id] = true
    return true
end

local function localTarget()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end
    local target = sourceTargets[ply:EntIndex()]
    if IsValid(target) then return target end
    return ply
end

local function hasGWSocketsModule()
    local candidates = {
        "lua/bin/gmcl_gwsockets_win64.dll",
        "lua/bin/gmcl_gwsockets_win32.dll",
        "lua/bin/gmcl_gwsockets_linux.dll",
        "lua/bin/gmcl_gwsockets_linux64.dll",
        "lua/bin/gmcl_gwsockets_osx.dll",
        "lua/bin/gmsv_gwsockets_win64.dll",
        "lua/bin/gmsv_gwsockets_win32.dll"
    }

    for _, path in ipairs(candidates) do
        if file.Exists(path, "MOD") or file.Exists(path, "GAME") then
            return true
        end
    end
    return false
end

local function enterViewerOnly(reason)
    connected = false
    socket = nil
    latest = nil
    latestRaw = nil
    reconnectAt = math.huge
    captureAutoDisabled = true
    if reason then print(TAG .. reason) end
    print(TAG .. "Viewer-only mode active. Run FaceCatch.exe, then use facecatch_connect to capture.")
end

local function applyDefaultViewing()
    if not AUTO_VIEW:GetBool() then return end
    RunConsoleCommand("facecatch_apply_remote", "1")
    RunConsoleCommand("facecatch_apply_remote_players", "1")
    RunConsoleCommand("facecatch_render_override", "1")
end

local function connect()
    if not ENABLED:GetBool() or not CAPTURE_ENABLED:GetBool() or socket or gwsocketsMissing or captureAutoDisabled then return end

    if not hasGWSocketsModule() then
        gwsocketsMissing = true
        enterViewerOnly("GWSockets DLL not found on this client.")
        return
    end

    local ok, errorMessage = pcall(require, "gwsockets")
    if not ok then
        gwsocketsMissing = true
        enterViewerOnly("GWSockets could not be loaded: " .. tostring(errorMessage))
        return
    end

    socketHadError = false
    lastSocketError = ""
    socket = GWSockets.createWebSocket(URL:GetString(), false)

    function socket:onConnected()
        connected = true
        socketHadError = false
        captureAutoDisabled = false
        reconnectAt = 0
        print(TAG .. "Connected to " .. URL:GetString())
    end

    function socket:onMessage(message)
        if message == "Initializing streaming" then return end
        if #message > 12000 then return end

        local parsed = util.JSONToTable(message)
        if istable(parsed) and istable(parsed.blendshapes) then
            latest = parsed
            latestRaw = message
        end
    end

    function socket:onError(message)
        socketHadError = true
        lastSocketError = tostring(message)
    end

    function socket:onDisconnected()
        local wasConnected = connected
        connected = false
        socket = nil
        if socketHadError and not wasConnected then
            enterViewerOnly("FaceCatch.exe is not running or refused the connection.")
            if lastSocketError ~= "" then print(TAG .. "WebSocket detail: " .. lastSocketError) end
            return
        end
        reconnectAt = RealTime() + 3
        print(TAG .. "Disconnected; retrying in 3 seconds.")
    end

    socket:open()
end

local function disconnect()
    local oldSocket = socket
    socket = nil
    connected = false
    reconnectAt = 0
    latest = nil
    latestRaw = nil
    if oldSocket then oldSocket:closeNow() end
    clearPose(localTarget())
end

local function clearRemoteFrames()
    for _, frame in pairs(remoteFrames) do
        if frame and IsValid(frame.target) then clearPose(frame.target) end
    end
    remoteFrames = {}
end

local function shutdownInstance()
    disconnect()
    clearRemoteFrames()
    hook.Remove("InitPostEntity", "FaceCatchConnect")
    hook.Remove("Think", "FaceCatchUpdate")
    hook.Remove("PrePlayerDraw", "FaceCatchPrePlayerDraw")
    hook.Remove("PreDrawOpaqueRenderables", "FaceCatchPreDrawEntities")
    hook.Remove("PreDrawTranslucentRenderables", "FaceCatchPreDrawEntitiesTranslucent")
    hook.Remove("ShutDown", "FaceCatchShutdown")
end

_G.FaceCatchClientInstance = {
    Id = INSTANCE_ID,
    Shutdown = shutdownInstance
}

local function sendLatestToServer()
    if not MULTIPLAYER:GetBool() or not latestRaw then return end
    local now = RealTime()
    local rate = math.Clamp(NETWORK_RATE:GetFloat(), 1, 30)
    if now < nextNetworkSend then return end
    nextNetworkSend = now + (1 / rate)

    local length = #latestRaw
    if length <= 0 or length > 12000 then return end

    net.Start(NET_FRAME_C2S)
    net.WriteUInt(length, 16)
    net.WriteData(latestRaw, length)
    net.SendToServer()
end

net.Receive(NET_TARGET_S2C, function()
    local source = net.ReadEntity()
    local target = net.ReadEntity()
    if not IsValid(source) then return end

    local id = source:EntIndex()
    local oldTarget = sourceTargets[id]
    if IsValid(oldTarget) and oldTarget ~= target then
        clearPose(oldTarget)
    end

    if IsValid(target) and target ~= source then
        sourceTargets[id] = target
        if source == LocalPlayer() then
            print(TAG .. "Local face target set to " .. tostring(target))
        end
    else
        sourceTargets[id] = nil
        if source == LocalPlayer() then
            print(TAG .. "Local face target reset to self.")
        end
    end
end)

net.Receive(NET_FRAME_S2C, function()
    if not MULTIPLAYER:GetBool() or not APPLY_REMOTE:GetBool() then return end

    local source = net.ReadEntity()
    local target = net.ReadEntity()
    local length = net.ReadUInt(16)
    if length <= 0 or length > 12000 then return end

    local payload = net.ReadData(length)
    if not IsValid(source) or not payload then return end

    local parsed = util.JSONToTable(payload)
    if not istable(parsed) or not istable(parsed.blendshapes) then return end

    local resolvedTarget = IsValid(target) and target or source
    if resolvedTarget:IsPlayer() and not APPLY_REMOTE_PLAYERS:GetBool() then return end

    remoteFrames[source:EntIndex()] = {
        source = source,
        target = resolvedTarget,
        data = parsed,
        last = RealTime()
    }
end)

hook.Add("InitPostEntity", "FaceCatchConnect", function()
    timer.Simple(0.5, applyDefaultViewing)
    timer.Simple(2, connect)
end)

hook.Add("Think", "FaceCatchUpdate", function()
    if not ENABLED:GetBool() then
        if socket then disconnect() end
        return
    end

    if not CAPTURE_ENABLED:GetBool() then
        if socket then disconnect() end
        latest = nil
        latestRaw = nil
    elseif not socket and RealTime() >= reconnectAt then
        connect()
    end

    local frameTime = FrameTime()
    local driven = {}
    if latest then
        local target = localTarget()
        if reserveDrivenEntity(driven, target) then applyFrame(target, latest, frameTime) end
        sendLatestToServer()
    end

    if not MULTIPLAYER:GetBool() or not APPLY_REMOTE:GetBool() then
        clearRemoteFrames()
        return
    end

    local now = RealTime()
    local localPly = LocalPlayer()
    for id, frame in pairs(remoteFrames) do
        if not IsValid(frame.source) or now - frame.last > 1.5 then
            if IsValid(frame.target) then clearPose(frame.target) end
            remoteFrames[id] = nil
        elseif frame.source ~= localPly then
            local target = IsValid(frame.target) and frame.target or frame.source
            -- Never let another client animate your local player model, and
            -- never write two different sources to the same entity in one tick.
            if target ~= localPly and reserveDrivenEntity(driven, target) then
                applyFrame(target, frame.data, frameTime)
            end
        end
    end
end)

hook.Add("PrePlayerDraw", "FaceCatchPrePlayerDraw", function(ply)
    if not RENDER_OVERRIDE:GetBool() then return end
    if not ENABLED:GetBool() then return end

    local frameTime = math.min(FrameTime(), 0.05)
    local localPly = LocalPlayer()
    if IsValid(localPly) and latest then
        local target = localTarget()
        if target == ply then
            -- Multiplayer player animation and voice flexes can run after Think.
            -- Writing again immediately before drawing makes FaceCatch the final
            -- visual pose instead of fighting the engine every other frame.
            applyFrame(ply, latest, frameTime)
            return
        end
    end

    if not MULTIPLAYER:GetBool() or not APPLY_REMOTE:GetBool() then return end
    if ply == localPly then return end
    if not APPLY_REMOTE_PLAYERS:GetBool() then return end

    for _, frame in pairs(remoteFrames) do
        if frame and frame.target == ply and IsValid(frame.source) then
            applyFrame(ply, frame.data, frameTime)
            return
        end
    end
end)

local function applyEntityRenderOverrides()
    if not ENTITY_RENDER_OVERRIDE:GetBool() then return end
    if not ENABLED:GetBool() then return end

    local frameTime = math.min(FrameTime(), 0.05)
    local driven = {}
    local localPly = LocalPlayer()

    if latest then
        local target = localTarget()
        if IsValid(target) and not target:IsPlayer() and reserveDrivenEntity(driven, target) then
            -- NPCs, ragdolls and model entities often reset flexes during their
            -- own animation update. Write again right before entity rendering,
            -- the same trick used for player models in PrePlayerDraw.
            applyFrame(target, latest, frameTime)
        end
    end

    if not MULTIPLAYER:GetBool() or not APPLY_REMOTE:GetBool() then return end

    for _, frame in pairs(remoteFrames) do
        local target = frame and frame.target
        if IsValid(target) and not target:IsPlayer() and IsValid(frame.source) and frame.source ~= localPly then
            if reserveDrivenEntity(driven, target) then
                applyFrame(target, frame.data, frameTime)
            end
        end
    end
end

hook.Add("PreDrawOpaqueRenderables", "FaceCatchPreDrawEntities", applyEntityRenderOverrides)
hook.Add("PreDrawTranslucentRenderables", "FaceCatchPreDrawEntitiesTranslucent", applyEntityRenderOverrides)

hook.Add("ShutDown", "FaceCatchShutdown", disconnect)

concommand.Add("facecatch_connect", function()
    disconnect()
    gwsocketsMissing = false
    captureAutoDisabled = false
    socketHadError = false
    lastSocketError = ""
    reconnectAt = 0
    connect()
end)

concommand.Add("facecatch_disconnect", disconnect)

concommand.Add("facecatch_status", function()
    local target = localTarget()
    local state = IsValid(target) and stateForEntity(target) or nil
    print(TAG .. (connected and "connected" or "disconnected"))
    print(TAG .. "URL: " .. URL:GetString())
    print(TAG .. "Local target: " .. tostring(target))
    print(TAG .. "Model: " .. (IsValid(target) and tostring(target:GetModel()) or "none"))
    print(TAG .. "Profile: " .. (state and state.profile or activeProfile))
    print(TAG .. "Mapped flexes: " .. (state and #state.bindings or 0))
    print(TAG .. "Capture: " .. tostring(CAPTURE_ENABLED:GetBool()))
    print(TAG .. "GWSockets missing: " .. tostring(gwsocketsMissing))
    print(TAG .. "Capture auto-disabled: " .. tostring(captureAutoDisabled))
    print(TAG .. "Multiplayer: " .. tostring(MULTIPLAYER:GetBool()) .. " @ " .. NETWORK_RATE:GetFloat() .. " fps")
    print(TAG .. "Apply remote: " .. tostring(APPLY_REMOTE:GetBool()))
    print(TAG .. "Apply remote players: " .. tostring(APPLY_REMOTE_PLAYERS:GetBool()))
    print(TAG .. "Render override: " .. tostring(RENDER_OVERRIDE:GetBool()))
    print(TAG .. "Entity render override: " .. tostring(ENTITY_RENDER_OVERRIDE:GetBool()))
    print(TAG .. "Flex scale: " .. tostring(FLEX_SCALE:GetFloat()))
    print(TAG .. "Eye sensitivity: " .. tostring(EYE_SENSITIVITY:GetFloat()))
    print(TAG .. "Mouth sensitivity: " .. tostring(MOUTH_SENSITIVITY:GetFloat()))
    print(TAG .. "Head axis preset: " .. tostring(HEAD_AXIS_PRESET:GetInt()))
    print(TAG .. "Head pitch/yaw/roll scale: " .. tostring(HEAD_PITCH_SCALE:GetFloat()) .. " / " .. tostring(HEAD_YAW_SCALE:GetFloat()) .. " / " .. tostring(HEAD_ROLL_SCALE:GetFloat()))
    print(TAG .. "Head pitch/yaw/roll axis: " .. tostring(HEAD_PITCH_AXIS:GetInt()) .. " / " .. tostring(HEAD_YAW_AXIS:GetInt()) .. " / " .. tostring(HEAD_ROLL_AXIS:GetInt()))
    print(TAG .. "Client instance: " .. tostring(INSTANCE_ID))
end)

concommand.Add("facecatch_head_preset_tomorin", function()
    RunConsoleCommand("facecatch_head_enabled", "1")
    RunConsoleCommand("facecatch_head_axis_preset", "5")
    RunConsoleCommand("facecatch_head_pitch_scale", "1")
    RunConsoleCommand("facecatch_head_yaw_scale", "1")
    RunConsoleCommand("facecatch_head_roll_scale", "0")
    RunConsoleCommand("facecatch_head_pitch_axis", "1")
    RunConsoleCommand("facecatch_head_yaw_axis", "2")
    RunConsoleCommand("facecatch_head_roll_axis", "3")
    print(TAG .. "Head preset: Tomorin/PM safe.")
end)

concommand.Add("facecatch_head_preset_source", function()
    RunConsoleCommand("facecatch_head_enabled", "1")
    RunConsoleCommand("facecatch_head_axis_preset", "5")
    RunConsoleCommand("facecatch_head_pitch_scale", "1")
    RunConsoleCommand("facecatch_head_yaw_scale", "1")
    RunConsoleCommand("facecatch_head_roll_scale", "0")
    RunConsoleCommand("facecatch_head_pitch_axis", "0")
    RunConsoleCommand("facecatch_head_yaw_axis", "1")
    RunConsoleCommand("facecatch_head_roll_axis", "3")
    print(TAG .. "Head preset: Source no-roll.")
end)

concommand.Add("facecatch_head_preset_invert_yaw", function()
    RunConsoleCommand("facecatch_head_enabled", "1")
    RunConsoleCommand("facecatch_head_axis_preset", "5")
    RunConsoleCommand("facecatch_head_pitch_scale", "1")
    RunConsoleCommand("facecatch_head_yaw_scale", "-1")
    RunConsoleCommand("facecatch_head_roll_scale", "0")
    RunConsoleCommand("facecatch_head_pitch_axis", "1")
    RunConsoleCommand("facecatch_head_yaw_axis", "2")
    RunConsoleCommand("facecatch_head_roll_axis", "3")
    print(TAG .. "Head preset: inverted yaw.")
end)

concommand.Add("facecatch_head_preset_pitch_alt", function()
    RunConsoleCommand("facecatch_head_enabled", "1")
    RunConsoleCommand("facecatch_head_axis_preset", "5")
    RunConsoleCommand("facecatch_head_pitch_scale", "1")
    RunConsoleCommand("facecatch_head_yaw_scale", "1")
    RunConsoleCommand("facecatch_head_roll_scale", "0")
    RunConsoleCommand("facecatch_head_pitch_axis", "2")
    RunConsoleCommand("facecatch_head_yaw_axis", "1")
    RunConsoleCommand("facecatch_head_roll_axis", "3")
    print(TAG .. "Head preset: alternate pitch axis.")
end)

concommand.Add("facecatch_head_off", function()
    RunConsoleCommand("facecatch_head_enabled", "0")
    clearPose(localTarget())
    print(TAG .. "Head tracking disabled.")
end)

concommand.Add("facecatch_local_only", function()
    RunConsoleCommand("facecatch_multiplayer", "0")
    RunConsoleCommand("facecatch_apply_remote", "0")
    RunConsoleCommand("facecatch_apply_remote_players", "0")
    clearRemoteFrames()
    print(TAG .. "Local-only mode enabled.")
end)

concommand.Add("facecatch_viewer_only", function()
    RunConsoleCommand("facecatch_capture_enabled", "0")
    RunConsoleCommand("facecatch_apply_remote", "1")
    RunConsoleCommand("facecatch_apply_remote_players", "1")
    RunConsoleCommand("facecatch_render_override", "1")
    disconnect()
    print(TAG .. "Viewer-only mode enabled. Local camera capture is disabled.")
end)

concommand.Add("facecatch_dump_flexes", function()
    local target = localTarget()
    if not IsValid(target) then return end
    print(TAG .. "Flex controllers for " .. tostring(target:GetModel()) .. ":")
    for id = 0, target:GetFlexNum() - 1 do
        print(string.format("%s%03d  %s", TAG, id, tostring(target:GetFlexName(id))))
    end
end)

concommand.Add("facecatch_dump_mappings", function()
    local target = localTarget()
    local state = IsValid(target) and stateForEntity(target) or nil
    if not state then return end
    print(TAG .. "Active mappings:")
    for _, binding in ipairs(state.bindings) do
        print(string.format("%s%03d  %s <- %s", TAG, binding.id, binding.name, binding.source))
    end
end)

concommand.Add("facecatch_target_info", function()
    local target = localTarget()
    if not IsValid(target) then
        print(TAG .. "No valid local target.")
        return
    end

    local state = stateForEntity(target)
    if state and string.lower(target:GetModel() or "") ~= state.model then
        rebuildBindings(target, state)
    end

    local flexNum = target.GetFlexNum and target:GetFlexNum() or 0
    print(TAG .. "Target info")
    print(TAG .. "Entity: " .. tostring(target))
    print(TAG .. "Class: " .. tostring(target:GetClass()))
    print(TAG .. "Model: " .. tostring(target:GetModel()))
    print(TAG .. "Flex controllers: " .. tostring(flexNum))
    print(TAG .. "Mapped controllers: " .. tostring(state and #state.bindings or 0))
    print(TAG .. "Entity render override: " .. tostring(ENTITY_RENDER_OVERRIDE:GetBool()))
end)

cvars.AddChangeCallback("facecatch_enabled", function(_, _, newValue)
    if tonumber(newValue) == 0 then
        disconnect()
    else
        reconnectAt = 0
    end
end, "FaceCatchEnabled")

cvars.AddChangeCallback("facecatch_capture_enabled", function(_, _, newValue)
    if tonumber(newValue) == 0 then
        disconnect()
    else
        gwsocketsMissing = false
        captureAutoDisabled = false
        socketHadError = false
        lastSocketError = ""
        reconnectAt = 0
    end
end, "FaceCatchCaptureEnabled")

cvars.AddChangeCallback("facecatch_multiplayer", function(_, _, newValue)
    if tonumber(newValue) == 0 then clearRemoteFrames() end
end, "FaceCatchMultiplayer")

cvars.AddChangeCallback("facecatch_apply_remote", function(_, _, newValue)
    if tonumber(newValue) == 0 then clearRemoteFrames() end
end, "FaceCatchApplyRemote")

print(TAG .. "Client instance " .. INSTANCE_ID .. " loaded. Created by " .. AUTHOR .. " | " .. AUTHOR_URL)
