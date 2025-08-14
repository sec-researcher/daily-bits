#!/bin/bash
set -e

# ================================
# CONFIG
# ================================
SYNC_SCRIPT_PATH="/usr/local/bin/docker-hosts-sync.sh"
SERVICE_NAME="docker-hosts-sync"
SYSTEMD_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# ================================
# CREATE SYNC SCRIPT
# ================================
echo "[1/3] Creating Docker hosts sync script..."
cat > "$SYNC_SCRIPT_PATH" << 'EOF'
#!/bin/bash
HOSTS_FILE="/etc/hosts"
MARKER_START="# >>> docker-containers-start"
MARKER_END="# <<< docker-containers-end"

update_hosts() {
    # Remove old block
    sudo sed -i "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

    # Build new block
    {
        echo "$MARKER_START"
        docker ps --format '{{.ID}} {{.Names}}' | while read -r id name; do
            ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$id")
            if [ -n "$ip" ]; then
                echo "$ip $name"
            fi
        done
        echo "$MARKER_END"
    } | sudo tee -a "$HOSTS_FILE" > /dev/null
}

update_hosts
EOF

chmod +x "$SYNC_SCRIPT_PATH"

# ================================
# CREATE SYSTEMD SERVICE
# ================================
echo "[2/3] Creating systemd service..."
cat > "$SYSTEMD_PATH" << EOF
[Unit]
Description=Auto-update /etc/hosts with Docker container names
After=docker.service
Requires=docker.service

[Service]
ExecStart=/bin/bash -c 'docker events --filter "event=start" --filter "event=stop" --filter "event=die" | while read -r event; do $SYNC_SCRIPT_PATH; done'
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# ================================
# ENABLE AND START SERVICE
# ================================
echo "[3/3] Enabling and starting service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# ================================
# INITIAL SYNC
# ================================
"$SYNC_SCRIPT_PATH"

echo "✅ Setup complete. Docker container names will now resolve automatically from the host."

