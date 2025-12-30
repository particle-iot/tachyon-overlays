#!/bin/bash

mkdir -p /tmp/kernel

curl --remote-name-all --output-dir /tmp/kernel "https://linux-dist.particle.io/kernel/prerelease/build-264-44b88a8d6/linux-headers-6.8.0-1058-particle_6.8.0-1058.59%2Bparticle1_arm64.deb" \
    "https://linux-dist.particle.io/kernel/prerelease/build-264-44b88a8d6/linux-headers-particle_6.8.0-1058.59%2Bparticle1_arm64.deb" \
    "https://linux-dist.particle.io/kernel/prerelease/build-264-44b88a8d6/linux-image-6.8.0-1058-particle_6.8.0-1058.59%2Bparticle1_arm64.deb" \
    "https://linux-dist.particle.io/kernel/prerelease/build-264-44b88a8d6/linux-image-particle_6.8.0-1058.59%2Bparticle1_arm64.deb" \
    "https://linux-dist.particle.io/kernel/prerelease/build-264-44b88a8d6/linux-modules-6.8.0-1058-particle_6.8.0-1058.59%2Bparticle1_arm64.deb" \
    "https://linux-dist.particle.io/kernel/prerelease/build-264-44b88a8d6/linux-particle_6.8.0-1058.59%2Bparticle1_arm64.deb" \
    "https://linux-dist.particle.io/kernel/prerelease/build-264-44b88a8d6/linux-particle-headers-6.8.0-1058_6.8.0-1058.59%2Bparticle1_all.deb"

chmod 777 -R /tmp/kernel
apt-get install -y --allow-downgrades /tmp/kernel/*.deb
rm -rf /tmp/kernel

exit 0
