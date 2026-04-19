# Goose Setup Options

Configuration options for running Goose with Ollama across different hardware setups.

---

## Option 1 — Local (MacBook only)

The simplest setup — Ollama and Goose both run on your MacBook.

```zsh
# Install and start Ollama
brew install ollama
ollama serve

# Pull models
ollama pull qwen3-coder:30b
ollama pull gemma4:latest
ollama pull qwen2.5-coder:7b

# Run Goose
goose run --model gemma4:latest --recipe ~/goose-recipes/<recipe>.yaml --no-session
```

**Trade-offs**: Simple, no network dependency, but inference heats up the MacBook and competes with your foreground work for unified memory.

---

## Option 2 — Remote Ollama on a Dedicated Machine (Mac Mini or similar)

Offload inference to a dedicated local machine — keeps your MacBook cool and frees unified memory for your actual work. Goose stays on the MacBook; only inference moves to the remote host.

---

### On the Mac Mini (inference server)

**Install Ollama**

```zsh
brew install ollama
```

**Configure Ollama to listen on all interfaces**

By default Ollama only listens on `localhost`. Override this with a launchd plist so it survives reboots:

```zsh
mkdir -p ~/Library/LaunchAgents

cat > ~/Library/LaunchAgents/com.ollama.server.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ollama.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/ollama</string>
    <string>serve</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OLLAMA_HOST</key>
    <string>0.0.0.0:11434</string>
    <key>OLLAMA_KEEP_ALIVE</key>
    <string>30m</string>
    <key>OLLAMA_NUM_PARALLEL</key>
    <string>1</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/ollama.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/ollama-err.log</string>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.ollama.server.plist
```

**Pull models on the Mac Mini**

```zsh
ollama pull qwen3-coder:30b
ollama pull gemma4:latest
ollama pull qwen2.5-coder:7b
ollama pull qwen2.5:7b
```

**Verify Ollama is listening remotely**

```zsh
# From the Mac Mini
curl http://localhost:11434/api/tags

# Get the Mac Mini's local IP
ipconfig getifaddr en0
# e.g. 192.168.1.50
```

**Allow Ollama through the macOS firewall**

```
System Settings → Network → Firewall → Options
Add /opt/homebrew/bin/ollama → Allow incoming connections
```

---

### On your MacBook (Goose client)

**Point Goose at the remote Ollama instance**

```zsh
# Option A — per session (temporary)
export OLLAMA_HOST=http://192.168.1.50:11434

# Option B — permanent (recommended)
echo 'export OLLAMA_HOST=http://192.168.1.50:11434' >> ~/.zshrc
source ~/.zshrc
```

**Verify the MacBook can reach the Mac Mini**

```zsh
curl http://192.168.1.50:11434/api/tags
# Should return a JSON list of available models
```

**Run Goose as normal — no other changes needed**

```zsh
goose run --model gemma4:latest \
  --recipe ~/goose-recipes/daily-cluster-health.yaml \
  --no-session
```

Goose picks up `OLLAMA_HOST` automatically and routes all inference to the Mac Mini.

---

### Use a stable hostname instead of IP

DHCP-assigned IPs can change. Use one of these approaches for a stable address:

```zsh
# Option A — mDNS hostname (works on same subnet, zero config)
export OLLAMA_HOST=http://mac-mini.local:11434

# Option B — set a static IP on the Mac Mini
# System Settings → Network → Wi-Fi/Ethernet → Details → TCP/IP
# Set Configure IPv4 to Manually, assign e.g. 192.168.1.50

# Option C — add a hostname alias on the MacBook
echo "192.168.1.50  ollama-server" | sudo tee -a /etc/hosts
export OLLAMA_HOST=http://ollama-server:11434
```

Add whichever you choose to `~/.zshrc` permanently.

---

### Create a custom model variant on the Mac Mini

For the daily health check, create a model with a larger context window to prevent mid-run exits:

```zsh
# On the Mac Mini
cat > /tmp/Modelfile-health << 'EOF'
FROM gemma4:latest
PARAMETER num_ctx 32768
PARAMETER num_predict 4096
EOF

ollama create gemma4-health -f /tmp/Modelfile-health

# Then on the MacBook use:
goose run --model gemma4-health \
  --recipe ~/goose-recipes/daily-cluster-health.yaml \
  --no-session
```

---

### Setup summary

| Step | Where | What |
|---|---|---|
| Install Ollama | Mac Mini | `brew install ollama` |
| Set `OLLAMA_HOST=0.0.0.0:11434` | Mac Mini | launchd plist env var |
| Set `OLLAMA_KEEP_ALIVE=30m` | Mac Mini | launchd plist env var |
| Pull models | Mac Mini | `ollama pull <model>` |
| Allow firewall on port 11434 | Mac Mini | System Settings → Network → Firewall |
| Set `OLLAMA_HOST=http://<mini-ip>:11434` | MacBook | `~/.zshrc` |
| Install Goose, kubectl, recipes | MacBook | No Ollama needed locally |
| Run Goose as normal | MacBook | No other changes |

---

## Option 3 — Docker / Podman (advanced)

Run Ollama in a container on any host. Useful if you want to run on a Linux box or NAS.

```zsh
# On the remote host (Linux or Mac with Docker)
docker run -d \
  --name ollama \
  -p 11434:11434 \
  -v ollama:/root/.ollama \
  --restart unless-stopped \
  ollama/ollama

# Pull models into the container
docker exec ollama ollama pull gemma4:latest
docker exec ollama ollama pull qwen3-coder:30b

# On your MacBook — same as Option 2
export OLLAMA_HOST=http://<host-ip>:11434
```

For GPU passthrough on Linux add `--gpus all` (requires nvidia-container-toolkit or ROCm).

---

## Environment Variables Reference

| Variable | Where to set | Description |
|---|---|---|
| `OLLAMA_HOST` | MacBook `~/.zshrc` | Points Goose/Ollama client at remote server |
| `OLLAMA_HOST` | Mac Mini launchd plist | Binds server to all interfaces (`0.0.0.0:11434`) |
| `OLLAMA_KEEP_ALIVE` | Mac Mini launchd plist | How long to keep model loaded between requests (e.g. `30m`) |
| `OLLAMA_NUM_PARALLEL` | Mac Mini launchd plist | Number of parallel inference requests (set to `1` for single-user) |
| `OLLAMA_MAX_LOADED_MODELS` | Mac Mini launchd plist | Max models loaded in memory simultaneously (default `1`) |

---

## Troubleshooting Remote Ollama

| Symptom | Fix |
|---|---|
| `connection refused` on MacBook | Check `OLLAMA_HOST` is set; verify Ollama is running on Mini with `curl http://<mini-ip>:11434` |
| `model not found` | Models must be pulled on the Mac Mini, not the MacBook |
| Connection drops mid-recipe | Set `OLLAMA_KEEP_ALIVE=30m` in the launchd plist on the Mac Mini |
| Firewall blocking | Add Ollama binary to firewall allowlist on Mac Mini |
| mDNS not resolving | Ensure both machines are on the same subnet; try IP address directly |
| Slow inference | Check Mac Mini is using its GPU — `ollama ps` shows active models and which device is in use |
