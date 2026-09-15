#!/usr/bin/env bash
set -euo pipefail
# QLI already supplies these. Never install a second container/network stack.
rpm -q docker-moby docker-moby-cli docker-compose upower networkmanager modemmanager >/dev/null
for group in sudo video render input plugdev netdev dialout audio docker; do
  getent group "$group" >/dev/null || groupadd --system "$group"
done
if ! id particle >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo,video,render,input,plugdev,netdev,dialout,audio,docker particle
else
  usermod -aG sudo,video,render,input,plugdev,netdev,dialout,audio,docker particle
fi
# Setup supplies the password hash. Leave it locked until then.
install -d -m 0750 -o particle -g particle /home/particle
install -d -m 0700 -o particle -g particle /home/particle/.ssh /home/particle/.particle
install -d -m 0755 /etc/particle /etc/sudoers.d /etc/polkit-1/rules.d
printf '%%sudo ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/particle
chmod 0440 /etc/sudoers.d/particle
visudo -cf /etc/sudoers.d/particle
cat > /etc/polkit-1/rules.d/49-particle-network.rules <<'RULE'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 && subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
RULE
install -d /etc/systemd/system/particle-tachyon-rild.service.d
cat > /etc/systemd/system/particle-tachyon-rild.service.d/qli.conf <<'UNIT'
[Unit]
Wants=ModemManager.service NetworkManager.service
After=ModemManager.service NetworkManager.service
[Service]
Environment=PARTICLE_RIL_DATA_MANAGER=NetworkManager
UNIT
for service in particle-linux particle-tachyon-rild particle-tachyon-gnss particle-tachyon-gnss-resume particle-tachyon-syscon; do
  systemctl enable "$service.service"
done
# All three aliases use the same Node 22 executable, including container credentials.
for executable in particled particlectl docker-credential-particle-linux lpa particle-tachyon-ril-ctl particle-tachyon-syscon-ctl; do
  command -v "$executable" >/dev/null
done
test -s /etc/particle/distro_versions.json
jq -e '.distro.distribution == "qualcomm-linux" and .distro.distribution_version == "2.0" and .distro.board == "formfactor_dvt"' /etc/particle/distro_versions.json >/dev/null
