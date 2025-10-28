-- client/locksmith.lua
-- NPC spawn + NUI open/close + player selection for give
-- Uses event-based RPC (vehiclekeys:locksmith:requestKeys / sendKeys)

local ESX = nil
local isOpen = false
local locksmithPed = nil
local locksmithBlip = nil

CreateThread(function()
  while ESX == nil do
    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
    Wait(100)
  end
  spawnLocksmithPed()
end)

local function notify(msg)
  if ESX and ESX.ShowNotification then
    ESX.ShowNotification(msg)
  else
    TriggerEvent('chat:addMessage', { args = { '^1' .. tostring(msg) } })
  end
end

function spawnLocksmithPed()
  if locksmithPed and DoesEntityExist(locksmithPed) then return end
  local cfg = Config.Locksmith
  if not cfg or not cfg.model then return end
  local modelHash = GetHashKey(cfg.model)
  RequestModel(modelHash)
  local t0 = GetGameTimer()
  while not HasModelLoaded(modelHash) and (GetGameTimer() - t0) < 2000 do Wait(10) end
  if not HasModelLoaded(modelHash) then
    print('[vks] model load failed:', cfg.model)
    return
  end

  locksmithPed = CreatePed(4, modelHash, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.heading or 0.0, false, false)
  SetEntityAsMissionEntity(locksmithPed, true, true)
  FreezeEntityPosition(locksmithPed, true)
  SetBlockingOfNonTemporaryEvents(locksmithPed, true)
  SetPedCanRagdoll(locksmithPed, false)
  SetModelAsNoLongerNeeded(modelHash)

  if cfg.blip and cfg.blip.enabled then
    locksmithBlip = AddBlipForCoord(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    SetBlipSprite(locksmithBlip, cfg.blip.sprite or 72)
    SetBlipColour(locksmithBlip, cfg.blip.color or 46)
    SetBlipScale(locksmithBlip, cfg.blip.scale or 0.8)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(cfg.blip.text or 'Schlüsseldienst'); EndTextCommandSetBlipName(locksmithBlip)
  end
end

local function getNearbyPlayers(range)
  local out = {}
  local players = GetActivePlayers()
  local ped = PlayerPedId()
  local pcoords = GetEntityCoords(ped)
  range = range or (Config.Locksmith and Config.Locksmith.giveRange or 5.0)
  for _, pid in ipairs(players) do
    if pid ~= PlayerId() then
      local otherPed = GetPlayerPed(pid)
      if otherPed and otherPed ~= 0 and DoesEntityExist(otherPed) then
        local coords = GetEntityCoords(otherPed)
        local dst = #(pcoords - coords)
        if dst <= range then
          table.insert(out, {
            serverId = GetPlayerServerId(pid),
            name = GetPlayerName(pid) or ('Player ' .. tostring(GetPlayerServerId(pid))),
            distance = math.floor(dst * 10) / 10
          })
        end
      end
    end
  end
  table.sort(out, function(a,b) return (a.distance or 0) < (b.distance or 0) end)
  return out
end

-- Open UI: request keys from server via event, server will respond with sendKeys event
local function openLocksmithUI()
  if isOpen then return end
  -- request keys (server must handle vehiclekeys:locksmith:requestKeys and reply with vehiclekeys:locksmith:sendKeys)
  TriggerServerEvent('vehiclekeys:locksmith:requestKeys')
  -- response handled in RegisterNetEvent('vehiclekeys:locksmith:sendKeys', ...)
end

local function closeLocksmithUI()
  if not isOpen then return end
  SendNUIMessage({ action = 'close' })
  SetNuiFocus(false, false)
  isOpen = false
end

-- Receive keys from server (fallback for ESX.TriggerServerCallback)
RegisterNetEvent('vehiclekeys:locksmith:sendKeys', function(keys)
  local players = getNearbyPlayers(Config.Locksmith.giveRange or 5.0)
  SendNUIMessage({ action = 'open', cost = Config.Locksmith.duplicateCost or 0, keys = keys or {}, players = players })
  SetNuiFocus(true, true)
  isOpen = true
end)

-- NUI -> client callbacks (duplicate/give/close)
RegisterNUICallback('duplicate', function(data, cb)
  if not data or not data.key_id then cb({ ok = false }); return end
  TriggerServerEvent('vehiclekeys:locksmith:duplicate', data.key_id)
  cb({ ok = true })
end)

RegisterNUICallback('give', function(data, cb)
  if not data or not data.key_id then cb({ ok = false }); return end
  if data.targetServerId and tonumber(data.targetServerId) then
    TriggerServerEvent('vehiclekeys:locksmith:giveTo', data.key_id, tonumber(data.targetServerId))
    cb({ ok = true }); return
  end
  local nearby = getNearbyPlayers(Config.Locksmith.giveRange or 5.0)
  if not nearby or #nearby == 0 then
    notify('Kein Spieler in Reichweite gefunden.')
    cb({ ok = false }); return
  end
  TriggerServerEvent('vehiclekeys:locksmith:giveTo', data.key_id, nearby[1].serverId)
  cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
  closeLocksmithUI()
  cb({ ok = true })
end)

-- When server notifies of result, refresh keys via requestKeys event (avoid ESX.TriggerServerCallback)
RegisterNetEvent('vehiclekeys:client:locksmithResult', function(success, message)
  if message and message ~= '' then notify(message) end
  if isOpen then
    -- refresh keys list from server
    TriggerServerEvent('vehiclekeys:locksmith:requestKeys')
  end
end)

RegisterNetEvent('vehiclekeys:client:locksmithNotify', function(msg)
  if msg then notify(msg) end
end)

-- Interaction loop: show help and open on E
CreateThread(function()
  local cfg = Config.Locksmith or {}
  local interactRange = cfg.interactRange or 2.0
  local coords = cfg.coords or vector3(0,0,0)
  while true do
    Wait(250)
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local dist = #(pcoords - vector3(coords.x, coords.y, coords.z))
    if dist <= (interactRange + 1.5) then
      while dist <= (interactRange + 1.5) do
        Wait(5)
        pcoords = GetEntityCoords(ped)
        dist = #(pcoords - vector3(coords.x, coords.y, coords.z))
        if dist <= interactRange then
          if ESX and ESX.ShowHelpNotification then
            ESX.ShowHelpNotification("Drücke ~INPUT_CONTEXT~ um den Schlüsseldienst zu öffnen")
          else
            BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName("Drücke ~INPUT_CONTEXT~ um den Schlüsseldienst zu öffnen"); EndTextCommandDisplayHelp(0, false, true, -1)
          end
          if IsControlJustReleased(0, 38) then openLocksmithUI() end
        end
        if isOpen and dist > (interactRange + 2.0) then closeLocksmithUI() end
      end
    end
  end
end)

-- cleanup on resource stop
AddEventHandler('onResourceStop', function(name)
  if name ~= GetCurrentResourceName() then return end
  if isOpen then SetNuiFocus(false, false) end
end)