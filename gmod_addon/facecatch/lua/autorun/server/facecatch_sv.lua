if CLIENT then return end

local TAG = "[FaceCatch] "
local AUTHOR = "Kobeblyat"
local AUTHOR_URL = "https://space.bilibili.com/3546897006463032"

local NET_FRAME_C2S = "facecatch_frame_c2s"
local NET_FRAME_S2C = "facecatch_frame_s2c"
local NET_TARGET_S2C = "facecatch_target_s2c"

util.AddNetworkString(NET_FRAME_C2S)
util.AddNetworkString(NET_FRAME_S2C)
util.AddNetworkString(NET_TARGET_S2C)

AddCSLuaFile("autorun/client/facecatch.lua")
AddCSLuaFile("weapons/gmod_tool/stools/facecatch.lua")

local CV_ALLOW_TOOL = CreateConVar("facecatch_allow_tool", "1", FCVAR_ARCHIVE, "Allow players to use the FaceCatch toolgun.")
local CV_ADMIN_ONLY = CreateConVar("facecatch_admin_only_tool", "0", FCVAR_ARCHIVE, "Only admins can use the FaceCatch toolgun.")
local CV_PLAYER_TARGETS = CreateConVar("facecatch_allow_player_targets", "0", FCVAR_ARCHIVE, "Allow targeting other players. Off by default to prevent griefing.")
local CV_MAX_RATE = CreateConVar("facecatch_sv_max_rate", "30", FCVAR_ARCHIVE, "Maximum FaceCatch frames per second accepted from each player.")

local playerState = {}
local targetOwner = {}

local function notify(ply, message)
    if IsValid(ply) then
        ply:ChatPrint("[FaceCatch] " .. message)
    end
end

local function canUseTool(ply)
    if not CV_ALLOW_TOOL:GetBool() then return false, "FaceCatch tool is disabled on this server." end
    if CV_ADMIN_ONLY:GetBool() and not ply:IsAdmin() then return false, "Only admins can use the FaceCatch tool." end
    return true
end

local function canTarget(ply, ent)
    if not IsValid(ply) then return false, "Invalid player." end
    if not IsValid(ent) then return false, "Aim at an NPC, ragdoll, model entity, or yourself." end
    if ent:IsWorld() then return false, "World cannot be a FaceCatch target." end

    if ent:IsPlayer() and ent ~= ply then
        if not CV_PLAYER_TARGETS:GetBool() and not ply:IsAdmin() then
            return false, "Targeting other players is disabled. Use an NPC/model instead."
        end
    end

    if ent == ply then return true end
    if ent:IsNPC() then return true end
    if ent:GetClass() == "prop_ragdoll" then return true end
    if ent:GetModel() and ent:GetModel() ~= "" then return true end

    return false, "This entity has no usable model."
end

local function sendTarget(source, target, receiver)
    net.Start(NET_TARGET_S2C)
    net.WriteEntity(source)
    net.WriteEntity(IsValid(target) and target or source)
    if IsValid(receiver) then net.Send(receiver) else net.Broadcast() end
end

function FaceCatch_SetTarget(ply, ent)
    local ok, reason = canUseTool(ply)
    if not ok then notify(ply, reason) return false end

    ok, reason = canTarget(ply, ent)
    if not ok then notify(ply, reason) return false end

    playerState[ply] = playerState[ply] or {}

    local oldTarget = playerState[ply].target
    if IsValid(oldTarget) and targetOwner[oldTarget] == ply then
        targetOwner[oldTarget] = nil
    end

    if ent ~= ply then
        local owner = targetOwner[ent]
        if IsValid(owner) and owner ~= ply then
            notify(ply, "That target is already driven by " .. owner:Nick() .. ".")
            if IsValid(oldTarget) then targetOwner[oldTarget] = ply end
            return false
        end
        targetOwner[ent] = ply
        playerState[ply].target = ent
    else
        playerState[ply].target = nil
    end

    sendTarget(ply, ent, nil)

    if ent == ply then
        notify(ply, "Face target reset to yourself.")
    else
        notify(ply, "Face target set to " .. tostring(ent) .. ".")
    end
    return true
end

function FaceCatch_ClearTarget(ply)
    if not IsValid(ply) then return false end
    playerState[ply] = playerState[ply] or {}
    local oldTarget = playerState[ply].target
    if IsValid(oldTarget) and targetOwner[oldTarget] == ply then
        targetOwner[oldTarget] = nil
    end
    playerState[ply].target = nil
    sendTarget(ply, ply, nil)
    notify(ply, "Face target cleared.")
    return true
end

net.Receive(NET_FRAME_C2S, function(_, ply)
    if not IsValid(ply) then return end

    local state = playerState[ply] or {}
    playerState[ply] = state

    local now = CurTime()
    local maxRate = math.Clamp(CV_MAX_RATE:GetFloat(), 1, 60)
    if state.nextFrame and now < state.nextFrame then return end
    state.nextFrame = now + (1 / maxRate)

    local length = net.ReadUInt(16)
    if length <= 0 or length > 12000 then return end

    local payload = net.ReadData(length)
    if not payload or #payload ~= length then return end

    local target = IsValid(state.target) and state.target or ply

    net.Start(NET_FRAME_S2C)
    net.WriteEntity(ply)
    net.WriteEntity(target)
    net.WriteUInt(length, 16)
    net.WriteData(payload, length)
    net.Broadcast()
end)

hook.Add("PlayerInitialSpawn", "FaceCatchSyncTargets", function(ply)
    timer.Simple(2, function()
        if not IsValid(ply) then return end
        for source, state in pairs(playerState) do
            if IsValid(source) then
                sendTarget(source, IsValid(state.target) and state.target or source, ply)
            end
        end
    end)
end)

hook.Add("PlayerDisconnected", "FaceCatchCleanup", function(ply)
    local state = playerState[ply]
    if state and IsValid(state.target) and targetOwner[state.target] == ply then
        targetOwner[state.target] = nil
    end
    playerState[ply] = nil
end)

hook.Add("EntityRemoved", "FaceCatchTargetCleanup", function(ent)
    targetOwner[ent] = nil
end)

concommand.Add("facecatch_target_self", function(ply)
    if not IsValid(ply) then return end
    FaceCatch_SetTarget(ply, ply)
end)

concommand.Add("facecatch_target_clear", function(ply)
    if not IsValid(ply) then return end
    FaceCatch_ClearTarget(ply)
end)

print(TAG .. "Multiplayer server relay loaded. Created by " .. AUTHOR .. " | " .. AUTHOR_URL)
