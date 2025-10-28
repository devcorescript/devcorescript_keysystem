-- config.lua
Config = {}

Config.KeyItemName = "car_key"
Config.AllowSharedKeys = true
Config.DuplicateCost = 250
Config.DefaultTempAccessSeconds = 0

Config.Keybinds = {
  LockToggle = "U",
  OpenKeyMenu = "K",
  EngineToggle = "X"
}

Config.InteractRange = 2.0
Config.NotifyRange = 5.0
Config.EnableLogging = true

Config.Admins = {
  "admin"
}

Config.Locksmith = {
  coords = vector3(150.7628, 6647.9443, 31.5982),
  heading = 132.8475,
  model = "s_m_m_autoshop_01",
  blip = { enabled = true, sprite = 72, color = 46, scale = 0.8, text = "Schlüsseldienst" },
  interactRange = 2.0,
  giveRange = 5.0,
  duplicateCost = 250,
  duplicateCooldownSec = 10,
  requireKeyInInventory = true
}

Config.Notify = function(src, msg)
  TriggerClientEvent('vehiclekeys:client:notify', src, msg)
end