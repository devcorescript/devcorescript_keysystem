-- client.lua (aktualisiert)
-- Core client logic: ESX init, key polling, engine start enforcement, helper functions and keybinds

local ESX = nil
CreateThread(function()
  while ESX == nil do
    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
    Wait(100)
  end
end)

local Keys = {
  ["U"] = 303, ["K"] = 311, ["X"] = 73
}

local NoAutoStartPlates = {} -- plates flagged by server (admin spawns)
local TempStartAllowed = {}  -- plate -> true for temporary start permission

local function showNotification(msg)
  if not msg then return end
  if ESX and ESX.ShowNotification then ESX.ShowNotification(tostring(msg))
  else TriggerEvent('chat:addMessage', { args = { '^1' .. tostring(msg) } }) end
end

local function Trim(s) if not s then return s end return tostring(s):match('^%s*(.-)%s*$') end
local function NormalizePlate(plate) if not plate then return nil end return string.upper(Trim(plate)) end

local function getClosestVehicleAndPlate(range)
  local ped = PlayerPedId()
  local pcoords = GetEntityCoords(ped)
  local handle, veh = FindFirstVehicle()
  local success
  local found = nil
  repeat
    if DoesEntityExist(veh) then
      local vcoords = GetEntityCoords(veh)
      local dist = #(pcoords - vcoords)
      if dist <= (range or Config.InteractRange) then
        found = veh
        break
      end
    end
    success, veh = FindNextVehicle(handle)
  until not success
  EndFindVehicle(handle)
  if found and DoesEntityExist(found) then
    return found, NormalizePlate(GetVehicleNumberPlateText(found))
  end
  return nil, nil
end

-- Notification bridge from server
RegisterNetEvent('vehiclekeys:client:notify', function(msg)
  if msg and msg ~= '' then showNotification(msg) end
end)

-- Lock/unlock visual/sound effects handler (unchanged behaviour)
RegisterNetEvent('vehiclekeys:client:setVehicleLockState', function(plate, locked, actorServerId)
  if not plate then return end
  local norm = NormalizePlate(plate)
  local veh = nil
  local handle, v = FindFirstVehicle(); local success
  repeat
    if DoesEntityExist(v) then
      if NormalizePlate(GetVehicleNumberPlateText(v)) == norm then veh = v; break end
    end
    success, v = FindNextVehicle(handle)
  until not success
  EndFindVehicle(handle)
  if not veh then return end

  -- apply lock/unlock state
  if locked then
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDoorsLockedForPlayer(veh, PlayerId(), true)
    PlaySoundFromEntity(-1, "REMOTE_WINDOW_CLOSE", veh, 0, 0, 0)
    SetVehicleLights(veh, 2) Wait(150) SetVehicleLights(veh, 0)
  else
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)
    PlaySoundFromEntity(-1, "REMOTE_WINDOW_OPEN", veh, 0, 0, 0)
    SetVehicleLights(veh, 2) Wait(150) SetVehicleLights(veh, 0)
  end

  -- notification logic:
  -- show notification only for players in range AND not the actor (actor receives server's Config.Notify)
  local myServerId = GetPlayerServerId(PlayerId())
  if actorServerId and tonumber(actorServerId) == tonumber(myServerId) then
    -- skip: actor will receive server notification
    return
  end

  if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh)) <= (Config.NotifyRange or 5.0) then
    if locked then
      showNotification('Fahrzeug verriegelt.')
    else
      showNotification('Fahrzeug entriegelt.')
    end
  end
end)

-- Server response whether start is allowed
RegisterNetEvent('vehiclekeys:client:startAllowed', function(allowed)
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if allowed then
    if veh and veh ~= 0 and DoesEntityExist(veh) and GetPedInVehicleSeat(veh, -1) == ped then
      local plate = NormalizePlate(GetVehicleNumberPlateText(veh))
      SetVehicleEngineOn(veh, true, true, true)
      TempStartAllowed[plate] = true
      -- optional timeout from config
      local t = tonumber(Config.DefaultTempAccessSeconds or 0)
      if t and t > 0 then
        CreateThread(function()
          Wait(t * 1000)
          TempStartAllowed[plate] = nil
        end)
      end
      showNotification('Motor gestartet.')
    else
      showNotification('Du musst im Fahrersitz sitzen, um den Motor zu starten.')
    end
  else
    showNotification('Du hast keinen Schlüssel für dieses Fahrzeug.')
    if veh and veh ~= 0 and DoesEntityExist(veh) and GetPedInVehicleSeat(veh, -1) == ped then
      SetVehicleEngineOn(veh, false, true, true)
      local plate = NormalizePlate(GetVehicleNumberPlateText(veh))
      TempStartAllowed[plate] = nil
    end
  end
end)

RegisterNetEvent('vehiclekeys:client:spawnVehicleForAdmin', function(model, plate)
  if not model or model == '' then if ESX and ESX.ShowNotification then ESX.ShowNotification('Kein Model angegeben.') end return end
  local modelHash = GetHashKey(model)
  if not IsModelInCdimage(modelHash) or not IsModelAVehicle(modelHash) then if ESX and ESX.ShowNotification then ESX.ShowNotification('Ungültiges Fahrzeugmodel: ' .. tostring(model)) end return end

  RequestModel(modelHash)
  local timeout = 5000; local t0 = GetGameTimer()
  while not HasModelLoaded(modelHash) and (GetGameTimer() - t0) < timeout do Wait(10) end
  if not HasModelLoaded(modelHash) then if ESX and ESX.ShowNotification then ESX.ShowNotification('Vehicle Modell konnte nicht geladen werden.') end return end

  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  local forward = GetEntityForwardVector(ped)
  local spawnPos = vector3(pos.x + forward.x * 5.0, pos.y + forward.y * 5.0, pos.z + 0.5)
  local heading = GetEntityHeading(ped)

  local veh = CreateVehicle(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, false)
  if not DoesEntityExist(veh) then if ESX and ESX.ShowNotification then ESX.ShowNotification('Fahrzeug konnte nicht erstellt werden.') end SetModelAsNoLongerNeeded(modelHash); return end

  SetVehicleNumberPlateText(veh, tostring(plate))
  SetVehicleOnGroundProperly(veh)
  SetEntityAsMissionEntity(veh, true, true)
  TaskWarpPedIntoVehicle(ped, veh, -1)
  SetVehicleEngineOn(veh, false, true, true)
  SetVehicleUndriveable(veh, false)
  SetVehRadioStation(veh, 'OFF')
  NoAutoStartPlates[NormalizePlate(tostring(plate))] = true
  local netId = NetworkGetNetworkIdFromEntity(veh); SetNetworkIdCanMigrate(netId, true)
  Wait(50); SetModelAsNoLongerNeeded(modelHash)
  showNotification(('Fahrzeug %s mit Kennzeichen %s gespawnt (Motor aus).'):format(model, plate))
end)

-- Keybinds thread: U = lock toggle, X = engine toggle, K = locksmith UI
CreateThread(function()
  local lockKey = Keys[(Config.Keybinds and Config.Keybinds.LockToggle) or "U"]
  local menuKey = Keys[(Config.Keybinds and Config.Keybinds.OpenKeyMenu) or "K"]
  local engineKey = Keys[(Config.Keybinds and Config.Keybinds.EngineToggle) or "X"]

  while true do
    Wait(0)
    if IsControlJustReleased(0, lockKey) then
      local veh, plate = getClosestVehicleAndPlate(Config.InteractRange)
      if not veh or not plate then showNotification('Kein Fahrzeug in Reichweite gefunden.') else
        TriggerServerEvent('vehiclekeys:server:toggleLock', plate)
      end
      Wait(200)
    end

    if IsControlJustReleased(0, engineKey) then
      local ped = PlayerPedId()
      local veh = GetVehiclePedIsIn(ped, false)
      if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
        local plate = NormalizePlate(GetVehicleNumberPlateText(veh))
        local engineOn = GetIsVehicleEngineRunning(veh)
        if engineOn then
          SetVehicleEngineOn(veh, false, true, true)
          TempStartAllowed[plate] = nil
          showNotification('Motor gestoppt.')
        else
          TriggerServerEvent('vehiclekeys:server:attemptStart', plate)
        end
      else
        showNotification('Du musst im Fahrersitz sitzen, um den Motor zu starten/stoppen.')
      end
      Wait(200)
    end

    if IsControlJustReleased(0, menuKey) then
      TriggerServerEvent('vehiclekeys:locksmith:requestKeys')
      Wait(200)
    end
  end
end)

-- Enforce engine-block on entry if server denies start
CreateThread(function()
  local prevVeh = 0
  while true do
    Wait(250)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
      if veh ~= prevVeh then
        prevVeh = veh
        local plate = NormalizePlate(GetVehicleNumberPlateText(veh))
        -- if admin-spawned vehicle flagged, ensure engine stays off until permitted, or always check normally
        TempStartAllowed[plate] = false
        -- Ask server whether start is allowed (server will reply with vehiclekeys:client:startAllowed)
        TriggerServerEvent('vehiclekeys:server:attemptStart', plate)
        -- short grace period for server response; if engine running but not allowed, turn off
        local checks = 0
        while checks < 10 do -- up to ~1s (10 * 100ms)
          Wait(100)
          checks = checks + 1
          if TempStartAllowed[plate] then break end
          if GetIsVehicleEngineRunning(veh) then
            -- If engine running and we don't have temp permission, force off
            SetVehicleEngineOn(veh, false, true, true)
          end
        end
        -- if after waiting still no temp permission and engine on, immediate enforce off
        if not TempStartAllowed[plate] and GetIsVehicleEngineRunning(veh) then
          SetVehicleEngineOn(veh, false, true, true)
          showNotification('Motor automatisch deaktiviert (kein Schlüssel).')
        end
      end
    else
      prevVeh = 0
    end
  end
end)
