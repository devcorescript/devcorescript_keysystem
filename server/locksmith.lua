ESX = ESX or nil

-- ensure ESX is available (attempt, but continue even if not)
local function ensureESX(timeoutMs)
  timeoutMs = timeoutMs or 5000
  local t0 = os.time() * 1000
  if ESX then return true end
  repeat
    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
    if ESX then break end
    Citizen.Wait(100)
  until (os.time() * 1000 - t0) >= timeoutMs
  return ESX ~= nil
end

if ensureESX() then
  print('[vks][locksmith] ESX available.')
else
  print('[vks][locksmith] WARN: ESX not available (fallbacks enabled).')
end

-- helper: decode JSON meta safely
local function decodeMeta(meta)
  if not meta then return nil end
  if type(meta) == 'table' then return meta end
  if type(meta) == 'string' then
    local ok, dec = pcall(json.decode, meta)
    if ok and dec then return dec end
  end
  return nil
end

-- Fetch keys for a player (shared logic)
local function fetchKeysForPlayer(src, cb)
  local xPlayer = ESX and ESX.GetPlayerFromId(src) or nil
  if not xPlayer then
    -- if ESX missing, we cannot resolve identifier reliably; return empty
    cb({})
    return
  end
  local identifier = xPlayer.identifier
  exports.oxmysql:execute('SELECT key_id, plate, meta FROM vehicle_keys WHERE owner_identifier = ?', { identifier }, function(rows)
    local out = {}
    if rows and type(rows) == 'table' then
      for _, r in ipairs(rows) do
        local meta = decodeMeta(r.meta)
        table.insert(out, {
          key_id = r.key_id,
          plate  = r.plate,
          label  = (type(meta) == 'table' and meta.label) or ('Schlüssel - '..tostring(r.plate))
        })
      end
    end
    cb(out)
  end)
end

-- If ESX supports RegisterServerCallback, register the callback for compatibility with ESX.TriggerServerCallback
if ESX and ESX.RegisterServerCallback and type(ESX.RegisterServerCallback) == 'function' then
  ESX.RegisterServerCallback('vehiclekeys:locksmith:getKeys', function(source, cb)
    fetchKeysForPlayer(source, cb)
  end)
  print('[vks][locksmith] Registered ESX callback: vehiclekeys:locksmith:getKeys')
else
  print('[vks][locksmith] ESX.RegisterServerCallback not available — fallback event registered.')
end

-- Fallback event-based API so clients that cannot use ESX.TriggerServerCallback can still request keys.
-- Client -> Server: TriggerServerEvent('vehiclekeys:locksmith:requestKeys')
-- Server -> Client: TriggerClientEvent('vehiclekeys:locksmith:sendKeys', src, keysTable)
RegisterNetEvent('vehiclekeys:locksmith:requestKeys', function()
  local src = source
  fetchKeysForPlayer(src, function(keys)
    TriggerClientEvent('vehiclekeys:locksmith:sendKeys', src, keys)
  end)
end)

-- Cooldown store for duplicate operation
local cooldowns = {} -- identifier -> timestamp (os.time)

-- Duplicate key handler
RegisterNetEvent('vehiclekeys:locksmith:duplicate', function(key_id)
  local src = source
  local xPlayer = ESX and ESX.GetPlayerFromId(src) or nil
  if not xPlayer then
    TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Spieler nicht gefunden.')
    return
  end

  local identifier = xPlayer.identifier
  if not key_id or key_id == '' then
    TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Ungültiger Schlüssel.')
    return
  end

  -- Cooldown check
  local now = os.time()
  local nextAllowed = cooldowns[identifier] or 0
  if now < nextAllowed then
    TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, ('Bitte warte %s Sekunden.'):format(nextAllowed - now))
    return
  end

  -- Validate ownership & get meta
  exports.oxmysql:execute('SELECT * FROM vehicle_keys WHERE key_id = ? AND owner_identifier = ?', { key_id, identifier }, function(rows)
    if not rows or #rows == 0 then
      TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Du besitzt diesen Schlüssel nicht.')
      return
    end

    local row = rows[1]
    local plateVal = tostring(row.plate)
    local meta = decodeMeta(row.meta)

    -- require physical key in inventory?
    if Config.Locksmith and Config.Locksmith.requireKeyInInventory then
      if type(playerHasKeyItemForPlate) == 'function' then
        local ok, has = pcall(playerHasKeyItemForPlate, src, plateVal)
        if not ok or not has then
          TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Du musst den Schlüssel im Inventar haben, um ihn zu duplizieren.')
          return
        end
      end
    end

    -- charge money if configured
    local cost = tonumber((Config.Locksmith and Config.Locksmith.duplicateCost) or Config.DuplicateCost or 0)
    if cost and cost > 0 then
      local ok, err = pcall(function()
        if xPlayer.removeAccountMoney and type(xPlayer.removeAccountMoney) == 'function' then
          xPlayer.removeAccountMoney('bank', cost)
        else
          xPlayer.removeMoney(cost)
        end
      end)
      if not ok then
        TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Bezahlung fehlgeschlagen.')
        return
      end
    end

    -- create new key in DB and give item
    local newKeyId = generateKeyId()
    local metaTable = (type(meta) == 'table') and meta or { label = ('Schlüssel - %s'):format(plateVal) }
    exports.oxmysql:execute('INSERT INTO vehicle_keys (key_id, plate, owner_identifier, meta) VALUES (?, ?, ?, ?)', {
      newKeyId, plateVal, identifier, json.encode(metaTable)
    }, function(affected)
      giveKeyItemToPlayer(src, plateVal, newKeyId, identifier, metaTable.label)
      cooldowns[identifier] = now + tonumber((Config.Locksmith and Config.Locksmith.duplicateCooldownSec) or 10)
      logAction('duplicate', plateVal, identifier, nil, { new_key_id = newKeyId })
      TriggerClientEvent('vehiclekeys:client:locksmithResult', src, true, 'Schlüssel dupliziert.')
    end)
  end)
end)

-- Give key to target player (duplicate or transfer)
RegisterNetEvent('vehiclekeys:locksmith:giveTo', function(key_id, targetServerId)
  local src = source
  local xPlayer = ESX and ESX.GetPlayerFromId(src) or nil
  if not xPlayer then
    TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Spieler nicht gefunden.')
    return
  end

  local identifier = xPlayer.identifier
  local targetId = tonumber(targetServerId)
  if not targetId then
    TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Ungültiger Empfänger.')
    return
  end

  local targetX = ESX and ESX.GetPlayerFromId(targetId) or nil
  if not targetX then
    TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Empfänger nicht gefunden.')
    return
  end

  -- Validate ownership
  exports.oxmysql:execute('SELECT * FROM vehicle_keys WHERE key_id = ? AND owner_identifier = ?', { key_id, identifier }, function(rows)
    if not rows or #rows == 0 then
      TriggerClientEvent('vehiclekeys:client:locksmithResult', src, false, 'Du besitzt diesen Schlüssel nicht.')
      return
    end

    local row = rows[1]
    local plateVal = tostring(row.plate)
    local meta = decodeMeta(row.meta)

    if Config.AllowSharedKeys then
      -- create duplicate
      local newKeyId = generateKeyId()
      local metaJson = meta and (type(meta) == 'table' and json.encode(meta) or tostring(meta)) or json.encode({ label = ('Schlüssel - %s'):format(plateVal) })
      exports.oxmysql:execute('INSERT INTO vehicle_keys (key_id, plate, owner_identifier, meta) VALUES (?, ?, ?, ?)', {
        newKeyId, plateVal, targetX.identifier, metaJson
      }, function(insertRes)
        giveKeyItemToPlayer(targetId, plateVal, newKeyId, targetX.identifier, (type(meta) == 'table' and meta.label) or ('Schlüssel - ' .. plateVal))
        logAction('give_locksmith_dup', plateVal, identifier, targetX.identifier, { new_key_id = newKeyId })
        TriggerClientEvent('vehiclekeys:client:locksmithResult', src, true, 'Schlüssel dupliziert und übergeben.')
        TriggerClientEvent('vehiclekeys:client:locksmithNotify', targetId, ('Du hast einen Schlüssel für %s erhalten.'):format(plateVal))
      end)
    else
      -- transfer: update DB and move item
      exports.oxmysql:execute('UPDATE vehicle_keys SET owner_identifier = ? WHERE key_id = ?', { targetX.identifier, key_id }, function(affected)
        -- remove from giver inventory (best-effort)
        pcall(function()
          if exports and exports.ox_inventory and type(exports.ox_inventory.RemoveItem) == 'function' then
            exports.ox_inventory:RemoveItem(src, Config.KeyItemName, 1, { plate = plateVal, key_id = key_id })
          else
            TriggerEvent('ox:removeItem', src, Config.KeyItemName, 1, { plate = plateVal, key_id = key_id })
          end
        end)
        giveKeyItemToPlayer(targetId, plateVal, key_id, targetX.identifier, (type(meta) == 'table' and meta.label) or ('Schlüssel - ' .. plateVal))
        logAction('give_locksmith_transfer', plateVal, identifier, targetX.identifier, {})
        TriggerClientEvent('vehiclekeys:client:locksmithResult', src, true, 'Schlüssel übertragen.')
        TriggerClientEvent('vehiclekeys:client:locksmithNotify', targetId, ('Du hast den Schlüssel für %s erhalten.'):format(plateVal))
      end)
    end
  end)
end)

-- Export: getPlayerKeys(identifier, cb)
exports('getPlayerKeys', function(identifier, cb)
  if not identifier or identifier == '' then if cb then cb({}) end; return end
  exports.oxmysql:execute('SELECT key_id, plate, meta FROM vehicle_keys WHERE owner_identifier = ?', { identifier }, function(rows)
    local out = {}
    if rows and type(rows) == 'table' then
      for _, r in ipairs(rows) do
        local meta = decodeMeta(r.meta)
        table.insert(out, { key_id = r.key_id, plate = r.plate, meta = meta })
      end
    end
    if cb then cb(out) end
  end)
end)

-- End of server/locksmith.lua