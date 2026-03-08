#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/opt/minecraft/minecraft.log"
FABRIC_META_ROOT="https://meta.fabricmc.net/v2/versions"
FABRIC_MAVEN_ROOT="https://maven.fabricmc.net/net/fabricmc/fabric-installer"

apt update
apt install -y wget curl jq unzip ca-certificates gnupg tmux ufw iproute2 iputils-ping

network_summary() {
  local default_route default_if gateway ipv4 nameservers

  default_route=$(ip -4 route show default | head -1 || true)
  default_if=$(awk '{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }}' <<<"$default_route")
  gateway=$(awk '{print $3}' <<<"$default_route")

  if [[ -n "$default_if" ]]; then
    ipv4=$(ip -4 -o addr show dev "$default_if" scope global up | awk '{print $4}' | head -1 || true)
  else
    ipv4=""
  fi

  nameservers=$(awk '/^nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf | paste -sd ',' -)
  printf 'Interface: %s\n' "${default_if:-missing}"
  printf 'IPv4: %s\n' "${ipv4:-missing}"
  printf 'Gateway: %s\n' "${gateway:-missing}"
  printf 'Nameservers: %s\n' "${nameservers:-missing}"
}

fail_network_check() {
  local message=${1:-"Networking sanity check failed."}
  echo "ERROR: ${message}" >&2
  network_summary >&2
  exit 1
}

ensure_networking() {
  local default_route default_if gateway ipv4

  default_route=$(ip -4 route show default | head -1 || true)
  [[ -n "$default_route" ]] || fail_network_check "No default IPv4 route found."

  default_if=$(awk '{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }}' <<<"$default_route")
  [[ -n "$default_if" ]] || fail_network_check "Could not determine the primary network interface."

  ipv4=$(ip -4 -o addr show dev "$default_if" scope global up | awk '{print $4}' | head -1 || true)
  [[ -n "$ipv4" ]] || fail_network_check "No non-loopback IPv4 address is assigned to ${default_if}."

  gateway=$(awk '{print $3}' <<<"$default_route")
  [[ -n "$gateway" ]] || fail_network_check "Could not determine the default gateway."
  ping -4 -c 1 -W 2 "$gateway" >/dev/null 2>&1 || fail_network_check "Default gateway ${gateway} is unreachable."

  awk '/^nameserver[[:space:]]+/ { found = 1 } END { exit(found ? 0 : 1) }' /etc/resolv.conf \
    || fail_network_check "No nameserver entries found in /etc/resolv.conf."

  getent ahostsv4 meta.fabricmc.net >/dev/null 2>&1 \
    || fail_network_check "DNS lookup failed for meta.fabricmc.net."
  getent ahostsv4 maven.fabricmc.net >/dev/null 2>&1 \
    || fail_network_check "DNS lookup failed for maven.fabricmc.net."

  curl -4fsSL --max-time 15 -o /dev/null "${FABRIC_META_ROOT}/game" \
    || fail_network_check "Unable to reach Fabric metadata over HTTPS."
  curl -4fsSL --max-time 15 -o /dev/null "${FABRIC_MAVEN_ROOT}/maven-metadata.xml" \
    || fail_network_check "Unable to reach Fabric Maven over HTTPS."
}

ensure_java() {
  # Prefer OpenJDK 21; fallback to Amazon Corretto 21 via APT keyring (no sudo in LXC).
  if apt-get install -y openjdk-21-jre-headless 2>/dev/null; then
    return
  fi

  getent ahostsv4 apt.corretto.aws >/dev/null 2>&1 \
    || fail_network_check "DNS lookup failed for apt.corretto.aws."
  curl -4fsSL --max-time 15 -o /dev/null https://apt.corretto.aws/corretto.key \
    || fail_network_check "Unable to reach Amazon Corretto over HTTPS."

  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://apt.corretto.aws/corretto.key | gpg --dearmor -o /usr/share/keyrings/corretto.gpg
  echo "deb [signed-by=/usr/share/keyrings/corretto.gpg] https://apt.corretto.aws stable main" > /etc/apt/sources.list.d/corretto.list
  apt-get update
  apt-get install -y java-21-amazon-corretto-jre || apt-get install -y java-21-amazon-corretto-jdk
}

ensure_networking
ensure_java

mkdir -p /opt/minecraft
if ! id -u minecraft >/dev/null 2>&1; then
  useradd -r -m -s /bin/bash minecraft
fi
chown -R minecraft:minecraft /opt/minecraft
cd /opt/minecraft

printf '%s\n' "eula=true" > eula.txt

# Autosize memory: Xmx=RAM/2 with floors/caps retained from the current installer.
mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_mb=$((mem_kb / 1024))
xmx=$((mem_mb / 2))
if (( xmx < 2048 )); then
  xmx=2048
fi
if (( xmx > 16384 )); then
  xmx=16384
fi
xms=$xmx

LATEST_VERSION=$(curl -fsSL "${FABRIC_META_ROOT}/game" | jq -r 'map(select(.stable == true))[0].version // .[0].version')
if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
  echo "ERROR: Unable to determine the latest stable Minecraft version for Fabric." >&2
  exit 1
fi

LATEST_INSTALLER_VERSION=$(curl -fsSL "${FABRIC_META_ROOT}/installer" | jq -r 'map(select(.stable == true))[0].version // .[0].version')
if [[ -z "$LATEST_INSTALLER_VERSION" || "$LATEST_INSTALLER_VERSION" == "null" ]]; then
  echo "ERROR: Unable to determine the latest Fabric installer version." >&2
  exit 1
fi

LOADER_VERSION=$(curl -fsSL "${FABRIC_META_ROOT}/loader/${LATEST_VERSION}" | jq -r 'map(select((.loader.stable // true) == true))[0].loader.version // .[0].loader.version')
if [[ -z "$LOADER_VERSION" || "$LOADER_VERSION" == "null" ]]; then
  echo "ERROR: Unable to determine a Fabric loader version for Minecraft ${LATEST_VERSION}." >&2
  exit 1
fi

INSTALLER_JAR="fabric-installer-${LATEST_INSTALLER_VERSION}.jar"
INSTALLER_URL="${FABRIC_MAVEN_ROOT}/${LATEST_INSTALLER_VERSION}/${INSTALLER_JAR}"

curl -fL --retry 3 --retry-delay 2 -o "${INSTALLER_JAR}" "${INSTALLER_URL}"
EXPECTED_SHA=$(curl -fsSL "${INSTALLER_URL}.sha256" | tr -d '[:space:]')
ACTUAL_SHA=$(sha256sum "${INSTALLER_JAR}" | awk '{print $1}')
if [[ -z "$EXPECTED_SHA" || "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "ERROR: SHA256 mismatch for Fabric installer (expected ${EXPECTED_SHA:-missing}, got ${ACTUAL_SHA})." >&2
  exit 1
fi

installer_size=$(stat -c '%s' "${INSTALLER_JAR}")
if (( installer_size < 262144 )); then
  echo "ERROR: Downloaded Fabric installer is too small (${installer_size} bytes)." >&2
  exit 1
fi

java -jar "${INSTALLER_JAR}" server -downloadMinecraft -mcversion "${LATEST_VERSION}" -loader "${LOADER_VERSION}" -dir /opt/minecraft

launcher_jar="fabric-server-launch.jar"
if [[ ! -f "${launcher_jar}" ]]; then
  echo "ERROR: Fabric launcher ${launcher_jar} was not generated." >&2
  exit 1
fi

launcher_size=$(stat -c '%s' "${launcher_jar}")
if (( launcher_size < 131072 )); then
  echo "ERROR: Fabric launcher ${launcher_jar} is unexpectedly small (${launcher_size} bytes)." >&2
  exit 1
fi

if [[ ! -f server.jar ]]; then
  echo "ERROR: Minecraft server.jar was not generated." >&2
  exit 1
fi

server_size=$(stat -c '%s' server.jar)
if (( server_size < 5242880 )); then
  echo "ERROR: Downloaded Minecraft server.jar is too small (${server_size} bytes)." >&2
  exit 1
fi

if (( xmx > 12288 )); then
  aikar_gc_flags="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=40 -XX:G1MaxNewSizePercent=50 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=15 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=20 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1"
else
  aikar_gc_flags="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1"
fi

cat > start.sh <<E2
#!/usr/bin/env bash
exec java -Xms${xms}M -Xmx${xmx}M ${aikar_gc_flags} -Dusing.aikars.flags=https://docs.papermc.io/paper/aikars-flags -Daikars.new.flags=true -jar fabric-server-launch.jar nogui
E2
chmod +x start.sh

ufw allow 25565/tcp >/dev/null
if ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw status | grep -Fq "25565/tcp" || {
    echo "ERROR: UFW is active but 25565/tcp is still not allowed." >&2
    exit 1
  }
  echo "UFW active: confirmed allow rule for 25565/tcp."
else
  echo "UFW inactive: added allow rule for 25565/tcp but did not enable the firewall."
fi
echo "NOTE: Proxmox host firewalls and upstream router/NAT rules must be verified outside the container."

chown -R minecraft:minecraft /opt/minecraft

if runuser -u minecraft -- tmux has-session -t minecraft 2>/dev/null; then
  echo "tmux session 'minecraft' already exists; not starting a second server."
else
  runuser -u minecraft -- bash -lc 'tmux new-session -d -s minecraft "cd /opt/minecraft && ./start.sh 2>&1 | tee -a /opt/minecraft/minecraft.log"'
fi

echo "✅ Minecraft Fabric setup complete (LXC). Attach: runuser -u minecraft -- tmux attach -t minecraft"
