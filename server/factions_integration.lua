-- server/factions_integration.lua
-- Listens for vks_factions:vehicleCreated and creates a faction-owned key entry
ESX = ESX or nil
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

RegisterNetEvent('vks_factions:vehicleCreated', function(info)
  -- info = { plate, jobName, creator, created_at, giveToServerId }
  if not info or not info.plate or not info.jobName then return end
  local plate = NormalizePlate(info.plate)
  local job = tostring(info.jobName)
  local creator = info.creator or 'system'

  -- create faction-owned key
  local keyId = generateKeyId()
  local ownerIdentifier = ('faction:%s'):format(job)
  local meta = { label = ('Fraktionsschlüssel - %s'):format(plate), created_by = creator, faction = job }

  exports.oxmysql:execute('INSERT INTO vehicle_keys (key_id, plate, owner_identifier, meta) VALUES (?, ?, ?, ?)', {
    keyId, plate, ownerIdentifier, json.encode(meta)
  }, function()
    logAction('faction_create_key_owner', plate, creator, ownerIdentifier, { job = job, key_id = keyId })
    print(('[vks] faction-owned key created for %s (%s) -> key %s'):format(plate, job, keyId))
  end)
end)