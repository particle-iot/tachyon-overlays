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

-- Remember the user-selected profile and route across reboots. With the
-- split HiFi/HDMI verbs the HDMI profile is only offered while DP audio is
-- actually probeable, so restoring saved state can no longer strand audio
-- on a missing output.
device_defaults.properties["use-persistent-storage"] = true

-- Do not pin application streams to a previously restored sink after reboot.
stream_defaults.properties["restore-target"] = false
