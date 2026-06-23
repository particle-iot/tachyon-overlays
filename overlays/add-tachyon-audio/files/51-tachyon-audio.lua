table.insert(alsa_monitor.rules, {
  matches = {
    {
      { "device.name", "equals", "alsa_card.platform-sound" },
    },
  },
  apply_properties = {
    ["api.alsa.use-ucm"] = true,
    ["api.acp.auto-profile"] = true,
    ["api.acp.auto-port"] = true,
  },
})

-- Re-evaluate the active audio route on every boot instead of restoring stale
-- state from a previous HDMI / DP cabling scenario.
device_defaults.properties["use-persistent-storage"] = false

-- Do not pin application streams to a previously restored sink after reboot.
stream_defaults.properties["restore-target"] = false
