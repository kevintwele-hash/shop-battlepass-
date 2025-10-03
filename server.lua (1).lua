local punishThreshold = 1
local flagWindow = 3
local playerFlags = {}

RegisterNetEvent("fg:freecamFlag")
AddEventHandler("fg:freecamFlag", function(dist)
    local src = source
    local now = os.time()

    if not playerFlags[src] then playerFlags[src] = {} end
    table.insert(playerFlags[src], {t = now, dist = dist})

    -- alte Flags raus
    local valid = {}
    for _, f in ipairs(playerFlags[src]) do
        if now - f.t <= flagWindow then
            table.insert(valid, f)
        end
    end
    playerFlags[src] = valid

    if #valid >= punishThreshold then
        print(("[FreecamGuard] Player %s gekickt! (Distanz: %.2f)"):format(src, dist))
        DropPlayer(src, "Freecam detected")
        playerFlags[src] = nil
    end
end)

AddEventHandler("playerDropped", function()
    playerFlags[source] = nil
end)

-- server.lua (JSON-ban implementation)
local BAN_FILE = "bans.json"

-- In-memory table
local bans = {}

-- Helper: safe file read/write (uses server file system)
local function saveBans()
    local f = io.open(BAN_FILE, "w+")
    if not f then
        print("[FreecamGuard] Fehler: kann " .. BAN_FILE .. " nicht schreiben")
        return
    end
    f:write(json.encode(bans))
    f:close()
end

local function loadBans()
    local f = io.open(BAN_FILE, "r")
    if not f then
        bans = {}
        saveBans()
        return
    end
    local content = f:read("*a")
    f:close()
    if content and content ~= "" then
        local ok, dec = pcall(json.decode, content)
        if ok and type(dec) == "table" then
            bans = dec
        else
            bans = {}
        end
    else
        bans = {}
    end
end

-- Identifier helper: pick a stable identifier (license/steam) if vorhanden
local function getPrimaryIdentifier(identifiers)
    -- prefer license (fivem license), then steam, then first identifier
    for _, id in ipairs(identifiers) do
        if string.find(id, "license:") then return id end
    end
    for _, id in ipairs(identifiers) do
        if string.find(id, "steam:") then return id end
    end
    return identifiers[1]
end

-- Ban functions
local function addBan(identifier, adminName, reason, durationSeconds)
    -- durationSeconds == nil => permanent
    local expires = nil
    if durationSeconds and type(durationSeconds) == "number" then
        expires = os.time() + durationSeconds
    end
    bans[identifier] = {
        admin = adminName or "console",
        reason = reason or "No reason specified",
        timestamp = os.time(),
        expires = expires
    }
    saveBans()
end

local function removeBan(identifier)
    if bans[identifier] then
        bans[identifier] = nil
        saveBans()
        return true
    end
    return false
end

local function isBanned(identifier)
    local b = bans[identifier]
    if not b then return false, nil end
    if b.expires and os.time() > b.expires then
        -- expired -> remove
        bans[identifier] = nil
        saveBans()
        return false, nil
    end
    return true, b
end

-- Load bans on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    loadBans()
    print("[FreecamGuard] Bans geladen: " .. tostring(#(function() local c=0 for k in pairs(bans) do c=c+1 end return c end)()))
end)

-- Block connecting players if banned
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer(src)
    Citizen.Wait(0)

    local ids = GetPlayerIdentifiers(src)
    local primary = nil
    if ids and #ids > 0 then
        primary = getPrimaryIdentifier(ids)
    end

    -- check all identifiers just in case (some bans may be on steam:)
    for _, id in ipairs(ids or {}) do
        local banned, info = isBanned(id)
        if banned then
            local reason = ("You are banned. Reason: %s | Banned by: %s"):format(info.reason, info.admin)
            if info.expires then
                reason = reason .. (" | Expires: %s"):format(os.date("%Y-%m-%d %H:%M:%S", info.expires))
            else
                reason = reason .. " | Permanent"
            end
            deferrals.done(reason)
            return
        end
    end

    -- also check primary
    if primary then
        local banned, info = isBanned(primary)
        if banned then
            local reason = ("You are banned. Reason: %s | Banned by: %s"):format(info.reason, info.admin)
            if info.expires then
                reason = reason .. (" | Expires: %s"):format(os.date("%Y-%m-%d %H:%M:%S", info.expires))
            else
                reason = reason .. " | Permanent"
            end
            deferrals.done(reason)
            return
        end
    end

    deferrals.done()
end)

-- Admin commands (ACE permission required): anticheat.ban
RegisterCommand("ban", function(src, args, raw)
    if src ~= 0 and not IsPlayerAceAllowed(src, "anticheat.ban") then
        TriggerClientEvent('chat:addMessage', src, { args = { "^1SYSTEM", "Keine Rechte." } })
        return
    end

    -- args: <playerId_or_identifier> <durationSeconds or 'perm'> <reason...>
    if #args < 2 then
        if src == 0 then
            print("Usage: /ban <playerId|identifier> <durationSec|'perm'> <reason>")
        else
            TriggerClientEvent('chat:addMessage', src, { args = { "^1SYSTEM", "Usage: /ban <playerId|identifier> <durationSec|'perm'> <reason>" } })
        end
        return
    end

    local target = args[1]
    local durationArg = args[2]
    local reason = "Banned by admin"
    if #args > 2 then
        reason = table.concat(args, " ", 3)
    end

    local identifier = nil
    local duration = nil

    -- if target is a player id
    local targetSrc = tonumber(target)
    if targetSrc then
        if GetPlayerName(targetSrc) then
            local ids = GetPlayerIdentifiers(targetSrc)
            identifier = getPrimaryIdentifier(ids)
        else
            if src == 0 then print("Player nicht gefunden.") else TriggerClientEvent('chat:addMessage', src, { args = { "^1SYSTEM", "Player nicht gefunden." } }) end
            return
        end
    else
        -- treat as identifier string
        identifier = target
    end

    if durationArg ~= "perm" and tonumber(durationArg) then
        duration = tonumber(durationArg)
    end

    local adminName = (src == 0) and "console" or ("ID:" .. tostring(src))
    addBan(identifier, adminName, reason, duration)
    local msg = ("%s banned (%s) by %s for %s seconds. Reason: %s"):format(identifier, (duration and "temp" or "perm"), adminName, tostring(duration or "perm"), reason)
    print("[FreecamGuard] " .. msg)
    -- optional: broadcast to admins or discord here

    if targetSrc then
        DropPlayer(targetSrc, "You have been banned: " .. reason)
    end
end, false)

RegisterCommand("unban", function(src, args, raw)
    if src ~= 0 and not IsPlayerAceAllowed(src, "anticheat.ban") then
        TriggerClientEvent('chat:addMessage', src, { args = { "^1SYSTEM", "Keine Rechte." } })
        return
    end
    if #args < 1 then
        if src == 0 then print("Usage: /unban <identifier>") else TriggerClientEvent('chat:addMessage', src, { args = { "^1SYSTEM", "Usage: /unban <identifier>" } }) end
        return
    end
    local id = args[1]
    if removeBan(id) then
        local msg = ("Unbanned %s"):format(id)
        print("[FreecamGuard] " .. msg)
    else
        if src == 0 then print("Identifier not banned.") else TriggerClientEvent('chat:addMessage', src, { args = { "^1SYSTEM", "Identifier not banned." } }) end
    end
end, false)

RegisterCommand("banlist", function(src, args, raw)
    if src ~= 0 and not IsPlayerAceAllowed(src, "anticheat.ban") then
        TriggerClientEvent('chat:addMessage', src, { args = { "^1SYSTEM", "Keine Rechte." } })
        return
    end
    -- print simple banlist
    local i = 0
    for id, info in pairs(bans) do
        i = i + 1
        local line = ("%s | by %s | reason: %s | expires: %s"):format(id, info.admin, info.reason, (info.expires and os.date("%Y-%m-%d %H:%M:%S", info.expires) or "perm"))
        if src == 0 then
            print(line)
        else
            TriggerClientEvent('chat:addMessage', src, { args = { "^2BANLIST", line } })
        end
    end
    if i == 0 then
        if src == 0 then print("No bans") else TriggerClientEvent('chat:addMessage', src, { args = { "^2BANLIST", "No bans" } }) end
    end
end, false)
