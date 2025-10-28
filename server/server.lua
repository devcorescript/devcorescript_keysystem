-- server/server.lua
-- Core logic for vehicle keys (no faction code here)

ESX = ESX or nil
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

local VehicleLocks = {}

local function isPlayerAdmin(xPlayer)
  if not xPlayer then return false end
  local id = xPlayer.identifier
  for _, adminId in ipairs(Config.Admins or {}) do if adminId == id then return true end end
  local ok, group = pcall(function() if xPlayer.getGroup then return xPlayer:getGroup() end end)
  return ok and (group == 'admin' or group == 'superadmin' or group == 'mod')
end

RegisterNetEvent('vehiclekeys:server:createKey', function(plate, targetPlayerId)
  local src = source
  local xPlayer = ESX.GetPlayerFromId(src)
  if not xPlayer then return end
  local targetId = tonumber(targetPlayerId) or src
  local targetX = ESX.GetPlayerFromId(targetId)
  if not targetX then Config.Notify(src, 'Zielspieler nicht gefunden.'); return end

  local plateVal = NormalizePlate(plate or tostring(math.random(1000,9999)))
  local keyId = generateKeyId()
  local meta = { label = ('Schlüssel - %s'):format(plateVal), created_by = xPlayer.identifier }

  exports.oxmysql:execute('INSERT INTO vehicle_keys (key_id, plate, owner_identifier, meta) VALUES (?, ?, ?, ?)', {
    keyId, plateVal, targetX.identifier, json.encode(meta)
  }, function(_)
    giveKeyItemToPlayer(targetId, plateVal, keyId, targetX.identifier, meta.label)
    logAction('create', plateVal, xPlayer.identifier, targetX.identifier, meta)
    Config.Notify(targetId, ('Du hast einen Schlüssel für %s erhalten.'):format(plateVal))
  end)
end)

ESX.RegisterServerCallback('vehiclekeys:server:hasKey', function(source, cb, plate)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then cb(false); return end
  local plateVal = NormalizePlate(plate)
  exports.oxmysql:execute('SELECT COUNT(1) as c FROM vehicle_keys WHERE plate = ? AND owner_identifier = ?', {
    plateVal, xPlayer.identifier
  }, function(result)
    local count = result and result[1] and tonumber(result[1].c) or 0
    cb(count > 0)
  end)
end)

RegisterNetEvent('vehiclekeys:server:giveKey', function(key_id, targetPlayerId)
  local src = source
  local xPlayer = ESX.GetPlayerFromId(src)
  if not xPlayer then return end
  if not key_id or not targetPlayerId then Config.Notify(src, 'Ungültige Parameter.'); return end

  local targetX = ESX.GetPlayerFromId(tonumber(targetPlayerId))
  if not targetX then Config.Notify(src, 'Zielspieler nicht gefunden.'); return end

  exports.oxmysql:execute('SELECT * FROM vehicle_keys WHERE key_id = ? AND owner_identifier = ?', { key_id, xPlayer.identifier }, function(rows)
    if not rows or #rows == 0 then Config.Notify(src, 'Du besitzt diesen Schlüssel nicht.'); return end
    local plateVal = NormalizePlate(rows[1].plate)
    local meta = rows[1].meta
    if type(meta) == 'string' then local ok, decoded = pcall(function() return json.decode(meta) end) if ok and decoded then meta = decoded end end

    if Config.AllowSharedKeys then
      local newKeyId = generateKeyId()
      local metaJson = meta and (type(meta) == 'table' and json.encode(meta) or tostring(meta)) or json.encode({ label = ('Schlüssel - %s'):format(plateVal) })
      exports.oxmysql:execute('INSERT INTO vehicle_keys (key_id, plate, owner_identifier, meta) VALUES (?, ?, ?, ?)', {
        newKeyId, plateVal, targetX.identifier, metaJson
      }, function(affected)
        removeKeyItemFromPlayer(src, plateVal, key_id)
        local label = (type(meta) == 'table' and meta.label) or ('Schlüssel - ' .. plateVal)
        giveKeyItemToPlayer(targetPlayerId, plateVal, newKeyId, targetX.identifier, label)
        logAction('give', plateVal, xPlayer.identifier, targetX.identifier, { new_key_id = newKeyId })
        Config.Notify(src, 'Schlüssel weitergegeben.')
        Config.Notify(targetPlayerId, ('Du hast einen Schlüssel für %s erhalten.'):format(plateVal))
      end)
    else
      exports.oxmysql:execute('UPDATE vehicle_keys SET owner_identifier = ? WHERE key_id = ?', { targetX.identifier, key_id }, function(affected)
        removeKeyItemFromPlayer(src, plateVal, key_id)
        local label = (type(meta) == 'table' and meta.label) or ('Schlüssel - ' .. plateVal)
        giveKeyItemToPlayer(targetPlayerId, plateVal, key_id, targetX.identifier, label)
        logAction('transfer', plateVal, xPlayer.identifier, targetX.identifier, {})
        Config.Notify(src, 'Schlüssel übertragen.')
        Config.Notify(targetPlayerId, ('Du hast den Schlüssel für %s erhalten.'):format(plateVal))
      end)
    end
  end)
end)

RegisterNetEvent('vehiclekeys:server:toggleLock', function(plate)
  local src = source
  local xPlayer = ESX.GetPlayerFromId(src)
  if not xPlayer then return end
  local plateVal = NormalizePlate(plate or '')
  if plateVal == '' then Config.Notify(src, 'Ungültiges Kennzeichen.'); return end

  exports.oxmysql:execute('SELECT COUNT(1) as c FROM vehicle_keys WHERE plate = ? AND owner_identifier = ?', { plateVal, xPlayer.identifier }, function(result)
    local hasDB = result and result[1] and tonumber(result[1].c) > 0 or false
    if not hasDB then Config.Notify(src, 'Du besitzt keinen Schlüssel (DB).'); return end

    local hasItem, itemMeta = false, nil
    if hasDB then hasItem, itemMeta = playerHasKeyItemForPlate(src, plateVal) end

    if not hasItem then Config.Notify(src, 'Du musst den Schlüssel im Inventar haben, um das Fahrzeug zu verriegeln/entriegeln.'); return end

    local current = VehicleLocks[plateVal]
    local newState = not current and true or not current
    VehicleLocks[plateVal] = newState

    -- SEND ACTOR SERVER ID (src) AS LAST PARAMETER
    TriggerClientEvent('vehiclekeys:client:setVehicleLockState', -1, plateVal, newState, src)
    logAction('toggle_lock', plateVal, xPlayer.identifier, nil, { locked = newState })
    Config.Notify(src, (newState and 'Fahrzeug verriegelt.' or 'Fahrzeug entriegelt.'))
  end)
end)

RegisterNetEvent('vehiclekeys:server:attemptStart', function(plate)
  local src = source
  local xPlayer = ESX.GetPlayerFromId(src)
  if not xPlayer then return end
  local plateVal = NormalizePlate(plate or '')
  if plateVal == '' then TriggerClientEvent('vehiclekeys:client:startAllowed', src, false); return end

  exports.oxmysql:execute('SELECT COUNT(1) as c FROM vehicle_keys WHERE plate = ? AND owner_identifier = ?', { plateVal, xPlayer.identifier }, function(result)
    local hasDB = result and result[1] and tonumber(result[1].c) > 0 or false
    local hasItem, itemMeta = false, nil
    if hasDB then hasItem, itemMeta = playerHasKeyItemForPlate(src, plateVal) end

    if hasDB and hasItem then
      TriggerClientEvent('vehiclekeys:client:startAllowed', src, true)
      logAction('start_allowed', plateVal, xPlayer.identifier, nil, { reason = 'has_db_and_item' })
      return
    end

    local locked = VehicleLocks[plateVal]
    if locked == nil or locked == false then
      TriggerClientEvent('vehiclekeys:client:startAllowed', src, true)
      logAction('start_allowed', plateVal, xPlayer.identifier, nil, { reason = 'vehicle_unlocked' })
    else
      TriggerClientEvent('vehiclekeys:client:startAllowed', src, false)
      logAction('start_blocked', plateVal, xPlayer.identifier, nil, { hasDB = hasDB, hasItem = hasItem })
    end
  end)
end)

RegisterCommand('vks_spawn', function(source, args, raw)
  local src = source
  if src == 0 then print('[vehiclekeys] /vks_spawn cannot be used from console.'); return end
  local xPlayer = ESX.GetPlayerFromId(src)
  if not xPlayer then return end
  if not isPlayerAdmin(xPlayer) then Config.Notify(src, 'Keine Berechtigung.'); return end

  local model = args[1]
  if not model or model == '' then Config.Notify(src, 'Verwendung: /vks_spawn <model> [plate]'); return end

  local plateVal = args[2] and NormalizePlate(args[2]) or tostring(math.random(1000,9999))
  local keyId = generateKeyId()
  local meta = { label = ("Schlüssel - %s"):format(plateVal), created_by = xPlayer.identifier }

  exports.oxmysql:execute('INSERT INTO vehicle_keys (key_id, plate, owner_identifier, meta) VALUES (?, ?, ?, ?)', {
    keyId, plateVal, xPlayer.identifier, json.encode(meta)
  }, function(result)
    giveKeyItemToPlayer(src, plateVal, keyId, xPlayer.identifier, meta.label)
    logAction('admin_spawn_createkey', plateVal, xPlayer.identifier, nil, { model = model, key_id = keyId })
    TriggerClientEvent('vehiclekeys:client:spawnVehicleForAdmin', src, model, plateVal)
    Config.Notify(src, ('Fahrzeug %s mit Kennzeichen %s gespawnt und Schlüssel hinzugefügt.'):format(model, plateVal))
  end)
end, false)

exports('hasKey', function(identifier, plate, cb)
  exports.oxmysql:execute('SELECT COUNT(1) as c FROM vehicle_keys WHERE plate = ? AND owner_identifier = ?', { NormalizePlate(plate), identifier }, function(result)
    local count = result and result[1] and tonumber(result[1].c) or 0
    if cb then cb(count > 0) end
  end)
end)
