#!/bin/bash
# ── OrcaFiles One-Time Setup Script ─────────────────────────────────────────
# Run once to install OrcaFiles and get it live at orcafiles.ai
#   sudo bash ~/Desktop/setup-orcafiles.sh

set -e

echo "=== OrcaFiles Setup ==="
echo ""

# ── Step 1: Install systemd service ─────────────────────────────────────────
echo "[1/5] Installing OrcaFiles systemd service..."

sudo tee /etc/systemd/system/orcafiles-server.service > /dev/null << 'EOF'
[Unit]
Description=OrcaFiles Smart File Manager Backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=keiko
WorkingDirectory=/home/keiko/Desktop/orcafile
ExecStart=/usr/bin/python3 /home/keiko/Desktop/orcafile/orcafiles-server.py
Restart=always
RestartSec=10
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

echo "  ✓ Service file written"

# ── Step 2: Add orcafiles.ai to Cloudflare tunnel config ────────────────────
echo "[2/5] Adding orcafiles.ai to Cloudflare tunnel config..."

# Check if already present
if grep -q "orcafiles.ai" /etc/cloudflared/config.yml; then
    echo "  ✓ Already in config — skipping"
else
    # Insert orcafiles.ai line before the catch-all service line
    sudo sed -i '/^  - service: http/i\  - hostname: orcafiles.ai\n    service: http://localhost:8184' /etc/cloudflared/config.yml
    echo "  ✓ Added orcafiles.ai → localhost:8184"
fi

echo ""
echo "  Current tunnel config:"
cat /etc/cloudflared/config.yml
echo ""

# ── Step 3: Register DNS with Cloudflare ────────────────────────────────────
echo "[3/5] Registering orcafiles.ai DNS record..."
cloudflared tunnel route dns --overwrite-dns smart-contract orcafiles.ai || echo "  ⚠ DNS route command failed — you may need to add it manually in Cloudflare dashboard"
echo ""

# ── Step 4: Enable and start OrcaFiles server ────────────────────────────────
echo "[4/5] Enabling and starting OrcaFiles server..."
sudo systemctl daemon-reload
sudo systemctl enable orcafiles-server
sudo systemctl start orcafiles-server
sleep 3

# ── Step 5: Restart cloudflared to pick up new config ────────────────────────
echo "[5/5] Restarting cloudflared tunnel..."
sudo systemctl restart cloudflared
sleep 4

# ── Status check ─────────────────────────────────────────────────────────────
echo ""
echo "=== Status Check ==="
echo ""

for svc in orcafiles-server cloudflared; do
    STATUS=$(systemctl is-active $svc 2>/dev/null)
    if [ "$STATUS" = "active" ]; then
        echo "  ✓  $svc → RUNNING"
    else
        echo "  ✗  $svc → $STATUS"
        echo "     (check: sudo journalctl -u $svc -n 20)"
    fi
done

echo ""

# Test local server
if curl -s http://localhost:8184/api/health | grep -q '"ok":true'; then
    echo "  ✓  OrcaFiles server responding on port 8184"
else
    echo "  ⚠  Server not responding yet — may still be starting"
fi

echo ""
echo "=== Done! ==="
echo ""
echo "  OrcaFiles → https://orcafiles.ai"
echo "  (DNS may take 1-2 minutes to propagate)"
echo ""
