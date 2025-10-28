-- server/shared.lua
-- Shared helper functions used by server files

ESX = ESX or nil
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

local function trim(s) if not s then return nil end return tostring(s):match('^%s*(.-)%s*$') end

function NormalizePlate(p)
  if not p then return nil end
  return string.upper(trim(p))
end

function generateKeyId()
  math.randomseed(GetGameTimer() + os.time())
  local tpl = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(tpl, '[xy]', function(c)
    local v = (c == 'x') and math.random(0,15) or math.random(8,11)
    return string.format('%x', v)
  end)
end

function logAction(action, plate, actor, target, meta)
  if not Config.EnableLogging then return end
  local meta_json = meta and json.encode(meta) or nil
  exports.oxmysql:execute('INSERT INTO vehicle_key_logs (action, plate, actor_identifier, target_identifier, meta) VALUES (?, ?, ?, ?, ?)', {
    action, plate, actor, target, meta_json
  }, function(_) end)
end

function giveKeyItemToPlayer(playerServerId, plate, keyId, ownerIdentifier, customLabel)
  local metadata = { plate = plate, key_id = keyId, owner = ownerIdentifier }
  metadata.label = (customLabel and tostring(customLabel)) or ('Schlüssel - '..tostring(plate))
  if exports and exports.ox_inventory and type(exports.ox_inventory.AddItem) == 'function' then
    pcall(function() exports.ox_inventory:AddItem(playerServerId, Config.KeyItemName, 1, metadata) end)
    return
  end
  pcall(function() TriggerEvent('ox:addItem', playerServerId, Config.KeyItemName, 1, metadata) end)
end

function removeKeyItemFromPlayer(playerServerId, plate, keyId)
  local metadata = { plate = plate, key_id = keyId }
  if exports and exports.ox_inventory and type(exports.ox_inventory.RemoveItem) == 'function' then
    pcall(function() exports.ox_inventory:RemoveItem(playerServerId, Config.KeyItemName, 1, metadata) end); return
  end
  pcall(function() TriggerEvent('ox:removeItem', playerServerId, Config.KeyItemName, 1, metadata) end)
end

function playerHasKeyItemForPlate(playerServerId, plate)
  if not plate or plate == '' then return false, nil end
  local norm = NormalizePlate(plate)
  if exports and exports.ox_inventory then
    local ok, item = pcall(function() if exports.ox_inventory.GetItem then return exports.ox_inventory:GetItem(playerServerId, Config.KeyItemName) end end)
    if ok and item and type(item) == 'table' then
      if item.metadata and item.metadata.plate and NormalizePlate(item.metadata.plate) == norm then return true, item.metadata end
      for _, it in pairs(item) do
        if type(it) == 'table' and it.metadata and it.metadata.plate and NormalizePlate(it.metadata.plate) == norm then
          return true, it.metadata
        end
      end
    end

    local ok2, inv = pcall(function() if exports.ox_inventory.GetInventory then return exports.ox_inventory:GetInventory(playerServerId) end end)
    if ok2 and type(inv) == 'table' then
      local function scan(tbl)
        for _, it in pairs(tbl) do
          if type(it) == 'table' and it.name == Config.KeyItemName and it.metadata and it.metadata.plate and NormalizePlate(it.metadata.plate) == norm then
            return true, it.metadata
          end
        end
        return false, nil
      end
      if type(inv.items) == 'table' then local ok3, meta = scan(inv.items); if ok3 then return true, meta end end
      local ok4, meta2 = scan(inv); if ok4 then return true, meta2 end
    end
  end
  return false, nil
end