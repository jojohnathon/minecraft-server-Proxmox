# Minecraft Server on Proxmox – Version 2.0 (updated 2025-11-08)

<img title="" src="assets/banner.png" alt="Banner" width="326" data-align="center">

<p align="center"><em>Minecraft Server on Proxmox</em></p>

<p align="center">
  <a href="https://github.com/jojohnathon/minecraft-server-Proxmox/stargazers"><img alt="GitHub Stars" src="https://img.shields.io/github/stars/jojohnathon/minecraft-server-Proxmox?style=flat&color=yellow"></a>
  <a href="https://github.com/jojohnathon/minecraft-server-Proxmox/fork"><img alt="GitHub Forks" src="https://img.shields.io/github/forks/jojohnathon/minecraft-server-Proxmox?style=flat&color=blue"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/jojohnathon/minecraft-server-Proxmox?style=flat"></a>
  <a href="https://github.com/jojohnathon/minecraft-server-Proxmox/releases/latest"><img alt="Latest Release" src="https://img.shields.io/github/v/release/jojohnathon/minecraft-server-Proxmox?include_prereleases&style=flat"></a>
  <a href="https://buymeacoffee.com/timintech"><img alt="Buy Me A Coffee" src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?logo=buymeacoffee&logoColor=000&labelColor=grey&style=flat"></a>
</p>

---

## Quick Links

- Server Commands: [SERVER_COMMANDS.md](SERVER_COMMANDS.md)
- Simulation Guide: [SIMULATION.md](SIMULATION.md)
- Bedrock Networking: [docs/BEDROCK_NETWORKING.md](docs/BEDROCK_NETWORKING.md)
- Copilot Workflow: [.github/copilot-instructions.md](.github/copilot-instructions.md)
- Issues — https://github.com/jojohnathon/minecraft-server-Proxmox/issues

---

## ✅ Requirements

- Proxmox VE: 7.4+ / 8.x / 9.x
- Guest OS: Debian 12/13 or Ubuntu 24.04
- CPU/RAM: ≥2 vCPU, ≥2–4 GB RAM (Java), ≥1–2 GB (Bedrock)
- Storage: ≥10 GB SSD
- Network: Bridged NIC (vmbr0), ports 25565/TCP and 19132/UDP

Java 21 is required. If OpenJDK 21 is missing in your repositories, the installers automatically fall back to Amazon Corretto 21 (APT with signed-by keyring).
**Note:** The LXC installer now installs `ufw` itself, validates guest networking before downloading Fabric, and auto-sizes JVM memory (see [Configuration](#configuration)).

---

## Introduction

This repository provisions a performant Minecraft server (Java & Bedrock) on Proxmox in minutes. VM and LXC are supported. CLI-first setup, updater, and backup examples are provided.

> Simulation only: Do not execute commands in this workspace. See SIMULATION.md.

## Technologies & Dependencies

![Proxmox](https://img.shields.io/badge/Proxmox-VE-EE7F2D?logo=proxmox&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-12%20%2F%2013-A81D33?logo=debian&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)
![Java](https://img.shields.io/badge/OpenJDK-17%20%2F%2021-007396?logo=java&logoColor=white)
![Minecraft](https://img.shields.io/badge/Minecraft-Java%20%2F%20Bedrock-62B47A?logo=minecraft&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-%E2%9C%94-4EAA25?logo=gnubash&logoColor=white)
![Systemd](https://img.shields.io/badge/systemd-%E2%9C%94-FFDD00?logo=linux&logoColor=black)
![Screen](https://img.shields.io/badge/screen-%E2%9C%94-0077C2?logo=gnu&logoColor=white)
![tmux](https://img.shields.io/badge/tmux-%E2%9C%94-1BB91F?logo=tmux&logoColor=white)

## 📊 Status

Stable. VM and LXC tested. Bedrock updates remain manual.

## Quickstart

### VM (DHCP)

```bash
wget https://raw.githubusercontent.com/jojohnathon/minecraft-server-Proxmox/main/setup_minecraft.sh
chmod +x setup_minecraft.sh
./setup_minecraft.sh
sudo -u minecraft screen -r minecraft
```

> **Debian 12/13:** If you encounter screen socket errors, see [Integrity & Firewall](#integrity--firewall) for `/run/screen` setup.

### VM (Static IP)

```bash
sudo tee /etc/netplan/01-mc.yaml >/dev/null <<'YAML'
network:
  version: 2
  ethernets:
    ens18:
      addresses: [192.168.1.50/24]
      routes: [{ to: default, via: 192.168.1.1 }]
      nameservers: { addresses: [1.1.1.1,8.8.8.8] }
YAML
sudo netplan apply
```

### LXC/CT

```bash
wget https://raw.githubusercontent.com/jojohnathon/minecraft-server-Proxmox/main/setup_minecraft_lxc.sh
chmod +x setup_minecraft_lxc.sh
./setup_minecraft_lxc.sh
runuser -u minecraft -- tmux attach -t minecraft
```

> The LXC installer provisions Fabric, validates guest IPv4/default-route/DNS/HTTPS reachability, and adds `25565/tcp` to UFW without forcing UFW to be enabled.

### Bedrock

```bash
wget https://raw.githubusercontent.com/jojohnathon/minecraft-server-Proxmox/main/setup_bedrock.sh
chmod +x setup_bedrock.sh
./setup_bedrock.sh
sudo -u minecraft screen -r bedrock
```

## 🗃 Backups

### Option A: systemd

```bash
sudo tee /etc/mc_backup.conf >/dev/null <<'EOF'
MC_SRC_DIR=/opt/minecraft
MC_BEDROCK_DIR=/opt/minecraft-bedrock
BACKUP_DIR=/var/backups/minecraft
RETAIN_DAYS=7
EOF

sudo tee /etc/systemd/system/mc-backup.service >/dev/null <<'EOF'
[Unit]
Description=Minecraft backup (tar)
[Service]
Type=oneshot
EnvironmentFile=/etc/mc_backup.conf
ExecStart=/bin/mkdir -p "${BACKUP_DIR}"
ExecStart=/bin/bash -c 'tar -czf "${BACKUP_DIR}/java-$(date +%%F).tar.gz" "${MC_SRC_DIR}"'
ExecStart=/bin/bash -c '[ -d "${MC_BEDROCK_DIR}" ] && tar -czf "${BACKUP_DIR}/bedrock-$(date +%%F).tar.gz" "${MC_BEDROCK_DIR}" || true'
ExecStartPost=/bin/bash -c 'find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +"${RETAIN_DAYS:-7}" -delete'
EOF

sudo tee /etc/systemd/system/mc-backup.timer >/dev/null <<'EOF'
[Unit]
Description=Nightly Minecraft backup
[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mc-backup.timer
```

### Option B: cron

```bash
crontab -e
30 3 * * * tar -czf /var/backups/minecraft/mc-$(date +\%F).tar.gz /opt/minecraft
45 3 * * * tar -czf /var/backups/minecraft/bedrock-$(date +\%F).tar.gz /opt/minecraft-bedrock
```

## ♻ Auto-Update

Java Edition: `update.sh` (created by `setup_minecraft.sh`) pulls the latest PaperMC build with SHA256 and size validation.

```bash
cd /opt/minecraft && ./update.sh
crontab -e
0 4 * * 0 /opt/minecraft/update.sh >> /var/log/minecraft-update.log 2>&1
```
> Bedrock requires a manual download. See [Integrity & Firewall](#integrity--firewall) for checksum enforcement details.
## Configuration

### JVM memory (Java)


The VM installer sets `Xms ≈ RAM/4` and `Xmx ≈ RAM/2` with floors `1024M/2048M` and an `Xmx` cap of `≤16G`. The LXC installer sets `Xms = Xmx ≈ RAM/2` with the same `2048M` floor and `≤16G` cap, then applies Aikar's G1GC flags. Override in `/opt/minecraft/start.sh`.

## Integrity & Firewall

**Java VM (PaperMC):**

- Paper download is verified via **SHA256** in installer/updater.
- Minimum size `server.jar > 5 MB` to avoid saving HTML error pages.

**Java LXC (Fabric):**

- Fabric metadata is resolved from the official Fabric meta API.
- The Fabric installer JAR is verified via published **SHA256** and minimum-size checks.
- Generated `fabric-server-launch.jar` and `server.jar` are checked after install.
- The installer fails fast if the container is missing IPv4, a default route, nameservers, DNS resolution, gateway reachability, or outbound HTTPS to required upstreams.

**Bedrock:**

- Default: `REQUIRE_BEDROCK_SHA=1`. Set `REQUIRED_BEDROCK_SHA256=<sha>`. Override with `REQUIRE_BEDROCK_SHA=0`.
- The installer validates MIME type via HTTP HEAD (application/zip|octet-stream), checks size, and tests the ZIP via `unzip -tq` before extracting.

**screen socket (Debian 12/13, VM/Bedrock paths):**

```bash
sudo install -d -m 0775 -o root -g utmp /run/screen
printf 'd /run/screen 0775 root utmp -\n' | sudo tee /etc/tmpfiles.d/screen.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/screen.conf
```

**UFW:**

```bash
sudo apt-get install -y ufw
sudo ufw allow 25565/tcp
sudo ufw allow 19132/udp
sudo ufw enable
```

LXC note: `setup_minecraft_lxc.sh` installs `ufw`, adds `25565/tcp`, and verifies the rule when UFW is active. It does not enable UFW automatically, and it cannot validate Proxmox host firewalls or router/NAT rules from inside the container.

## 🕹 Admin/Commands

See **[SERVER_COMMANDS.md](SERVER_COMMANDS.md)**.

## ☕ Support / Donate

If this project saves you time, consider supporting continued maintenance via [Buy Me A Coffee](https://buymeacoffee.com/timintech).

## Troubleshooting

- Not enough RAM in LXC → reduce values in `start.sh`.
- Missing `/run/screen` on VM/Bedrock installs → see [Integrity & Firewall](#integrity--firewall) section for setup commands.
- LXC networking check failed → verify the container has a bridged NIC, a non-loopback IPv4 address, a default gateway, working DNS, and outbound HTTPS access to Fabric and package repositories.
- Bedrock ZIP MIME-Type issue → revisit the Mojang download page.

Use the PR template. Do not execute anything in this workspace. See **[SIMULATION.md](SIMULATION.md)** for safe workflow details and **[.github/copilot-instructions.md](.github/copilot-instructions.md)** for step-by-step Copilot CLI workflow.


## References

- PaperMC: [https://papermc.io/](https://papermc.io/)
- Fabric Meta: [https://meta.fabricmc.net/](https://meta.fabricmc.net/)
- Fabric Maven: [https://maven.fabricmc.net/](https://maven.fabricmc.net/)
- Proxmox Wiki: [https://pve.proxmox.com/wiki/Main_Page](https://pve.proxmox.com/wiki/Main_Page)
- Mojang Bedrock Server: [https://www.minecraft.net/en-us/download/server/bedrock](https://www.minecraft.net/en-us/download/server/bedrock)

## License

[MIT](LICENSE)

> Proxmox Helper: `scripts/proxmox_create_ct_bedrock.sh` creates a Debian 12/13 container and installs Bedrock.
