local CHECK_INTERVAL = 1000
local DIST_THRESHOLD = 35.0
local flagTimes = {}

local function isPlayerInVehicle()
    return IsPedInAnyVehicle(PlayerPedId(), false)
end

local function isPlayerDead()
    return IsEntityDead(PlayerPedId())
end

local function isInCutsceneOrPaused()
    return IsScreenFadedOut() or IsPauseMenuActive()
end

local function checkCamera()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    if isPlayerDead() or isPlayerInVehicle() or isInCutsceneOrPaused() then return end

    local camX, camY, camZ = table.unpack(GetGameplayCamCoord())
    local px, py, pz = table.unpack(GetEntityCoords(ped, true))
    local dist = #(vector3(camX, camY, camZ) - vector3(px, py, pz))

    if dist >= DIST_THRESHOLD then
        TriggerServerEvent("fg:freecamFlag", dist)
    end
end

Citizen.CreateThread(function()
    while true do
        checkCamera()
        Citizen.Wait(CHECK_INTERVAL)
    end
end)