# 📘 Minecraft Server Control – Commands & Admin Guide (LXC/VM)

This guide contains useful commands to manage a Minecraft server (Java or Bedrock Edition) installed via Proxmox LXC container or VM.

---

## 📂 Directory Structure

```bash
cd /opt/minecraft         # Java Edition
cd /opt/minecraft-bedrock # Bedrock Edition
```

---

## ▶️ Starting the Server

```bash
cd /opt/minecraft
./start.sh
```

To run in the background via `screen` on the VM/Paper path:

```bash
cd /opt/minecraft
screen -S minecraft ./start.sh
```

For the LXC/Fabric path, use `tmux`:

```bash
runuser -u minecraft -- tmux new-session -d -s minecraft 'cd /opt/minecraft && ./start.sh'
```

Reconnect to the session:

```bash
runuser -u minecraft -- tmux attach -t minecraft   # LXC/Fabric
screen -r minecraft
```

Detach without stopping the server:

```bash
tmux: CTRL + B, then D
screen: CTRL + A, then D
```

---

## 🔁 Stopping the Server (from Terminal)

In the active `tmux` or `screen` session with the server running:

```bash
stop
```

This cleanly shuts down the server.

---

## 📦 Updating the Java (PaperMC) Server

```bash
cd /opt/minecraft
./update.sh
```

Downloads the latest PaperMC version and replaces `server.jar`.

---

## ❗ Bedrock Edition Notice

Bedrock **cannot be updated automatically**. Instead, run:

```bash
cd /opt/minecraft-bedrock
./bedrock_helper.sh
```

This script shows the manual download link.

---

## ⚙️ Advanced Options

### Adjusting RAM Allocation (Java)

Edit the `start.sh` file:

```bash
nano /opt/minecraft/start.sh
```

Example modification for the LXC/Fabric launcher:

```bash
java -Xms4G -Xmx4G -jar fabric-server-launch.jar nogui
```

---

## 🧼 Log Files

```bash
tail -f /opt/minecraft/minecraft.log   # LXC/Fabric
cd /opt/minecraft/logs/                # VM/Paper
```

---

# 🧠 Useful In-Game Admin Commands

If you're listed as OP (`ops.json`):

```mcfunction
/gamemode creative
/give @p minecraft:diamond 64
/ban <playername>
```

---

## ✅ Grant OP Status (via Console or In-Game)

```bash
op <playername>
```

Example:

```bash
op TimInTech
```

---

## 📜 Frequently Used Commands

| Command                        | Description                          |
| ------------------------------ | ------------------------------------ |
| /gamemode creative             | Switches to Creative Mode            |
| /gamemode survival             | Switches to Survival Mode            |
| /give @p minecraft\:diamond 64 | Gives 64 diamonds to nearest player  |
| /time set day                  | Sets time to day                     |
| /weather clear                 | Clears the weather                   |
| /tp                            | Teleports player1 to player2         |
| /teleport @s 100 70 -100       | Teleports you to coordinates (x y z) |
| /ban                           | Permanently bans a player            |
| /pardon                        | Unbans a player                      |
| /kick                          | Kicks player with optional reason    |
| /stop                          | Shuts down the server                |

---

## 🧪 Tips for Enabling Cheats

To use these commands:

* Multiplayer: You must have **OP status**
* Singleplayer: **Enable cheats** (e.g., via LAN menu)

---

## 📁 Editing the `ops.json` File (optional)

Located at:

```bash
/opt/minecraft/ops.json
```

Example content:

```json
[
  {
    "uuid": "PLAYER-UUID",
    "name": "TimInTech",
    "level": 4,
    "bypassesPlayerLimit": false
  }
]
```

---

# 🎮 Command Blocks (Java & Bedrock)

Command blocks enable automation using Redstone and custom logic.

## 📦 Activation

Enable them in the `server.properties` file:

```properties
enable-command-block=true
```

---

## 🧩 Example Command Block Uses

| Command                                 | Description                            |
| --------------------------------------- | -------------------------------------- |
| /say Welcome to the server!             | Sends a message to all players         |
| /tp @a 100 65 -100                      | Teleports all players to coordinates   |
| /effect @p minecraft\:levitation 5 2    | Gives levitation effect for 5 seconds  |
| /title @a title {"text":"Bossfight!"}   | Displays a title screen to all players |
| /fill \~-5 \~-1 \~-5 \~5 \~-1 \~5 stone | Fills an area with stone               |
| /summon minecraft\:zombie \~ \~1 \~     | Spawns a zombie above the block        |

---

# 🪨 Bedrock-Specific Commands

| Command                              | Description                    |                                      |
| ------------------------------------ | ------------------------------ | ------------------------------------ |
| /setmaxplayers                       | Sets maximum number of players |                                      |
| /ability  fly \<true                 | false>                         | Enables/disables flying for a player |
| /structure save                      | Saves a structure              |                                      |
| /structure load  \~ \~ \~            | Loads a saved structure        |                                      |
| /event entity @e minecraft\:on\_fire | Triggers an entity event       |                                      |
| /camera shake @a 3 5                 | Creates a camera shake effect  |                                      |

---

Happy crafting and managing your Minecraft server! 🧱
