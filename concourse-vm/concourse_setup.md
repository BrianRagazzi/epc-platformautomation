# Concourse CI Single-Node Setup on Ubuntu 22.04

This guide will help you install and configure Concourse CI with PostgreSQL, web, and worker components all on a single VM with automatic startup.

## Prerequisites

- Ubuntu 22.04 VM with at least 2 CPU cores and 4GB RAM
- Root or sudo access
- Internet connectivity

## Step 1: Install PostgreSQL

```bash
# Update package lists
sudo apt update

# Install PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Start and enable PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

## Step 2: Configure PostgreSQL Database

```bash
# Create database and user for Concourse
sudo -u postgres psql << EOF
CREATE DATABASE concourse;
CREATE USER concourse WITH ENCRYPTED PASSWORD 'concourse-password';
GRANT ALL PRIVILEGES ON DATABASE concourse TO concourse;
\c concourse
GRANT ALL ON SCHEMA public TO concourse;
EOF
```

**Important:** Change `concourse-password` to a secure password of your choice.

## Step 3: Download Concourse Binary and Resources

```bash
# Create directories for Concourse
sudo mkdir -p /opt/concourse/bin
sudo mkdir -p /opt/concourse/resource-types
cd /tmp

# Download the latest Concourse binary (check https://github.com/concourse/concourse/releases for latest version)
CONCOURSE_VERSION="7.14.1"
wget https://github.com/concourse/concourse/releases/download/v${CONCOURSE_VERSION}/concourse-${CONCOURSE_VERSION}-linux-amd64.tgz

# Extract
tar -xzf concourse-${CONCOURSE_VERSION}-linux-amd64.tgz

# Move binary to final location
sudo mv concourse/bin/concourse /opt/concourse/bin/
sudo chmod +x /opt/concourse/bin/concourse

# Move fly binaries
sudo mv concourse/fly-assets /opt/concourse/

# Move resource types (keep rootfs.tgz files as-is)
sudo mv concourse/resource-types /opt/concourse/

# Clean up
rm -rf concourse concourse-${CONCOURSE_VERSION}-linux-amd64.tgz
```

## Step 4: Generate Keys

```bash
# Create keys directory
sudo mkdir -p /opt/concourse/keys/web /opt/concourse/keys/worker

# Generate web keys
sudo /opt/concourse/bin/concourse generate-key -t rsa -f /opt/concourse/keys/web/session_signing_key
sudo /opt/concourse/bin/concourse generate-key -t ssh -f /opt/concourse/keys/web/tsa_host_key

# Generate worker key
sudo /opt/concourse/bin/concourse generate-key -t ssh -f /opt/concourse/keys/worker/worker_key

# Authorize worker
sudo cp /opt/concourse/keys/worker/worker_key.pub /opt/concourse/keys/web/authorized_worker_keys
```

## Step 5: Create Concourse User

```bash
# Create a system user for Concourse
sudo useradd -r -s /bin/false -d /opt/concourse concourse

# Set ownership
sudo chown -R concourse:concourse /opt/concourse
```

## Step 6: Create Systemd Service for Concourse Web

Create `/etc/systemd/system/concourse-web.service`:

```ini
[Unit]
Description=Concourse CI Web
After=postgresql.service
Requires=postgresql.service

[Service]
User=concourse
Group=concourse
Type=simple
ExecStart=/opt/concourse/bin/concourse web \
  --postgres-host=127.0.0.1 \
  --postgres-port=5432 \
  --postgres-database=concourse \
  --postgres-user=concourse \
  --postgres-password=concourse-password \
  --session-signing-key=/opt/concourse/keys/web/session_signing_key \
  --tsa-host-key=/opt/concourse/keys/web/tsa_host_key \
  --tsa-authorized-keys=/opt/concourse/keys/web/authorized_worker_keys \
  --external-url=http://localhost:8080 \
  --add-local-user=admin:admin \
  --main-team-local-user=admin
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Important:** 
- Replace `concourse-password` with your PostgreSQL password
- Change `http://localhost:8080` to your VM's actual hostname/IP if accessing remotely
- Change the default admin credentials (`admin:admin`) for production use

## Step 7: Create Systemd Service for Concourse Worker

Create `/etc/systemd/system/concourse-worker.service`:

```ini
[Unit]
Description=Concourse CI Worker
After=concourse-web.service
Requires=concourse-web.service

[Service]
User=root
Type=simple
ExecStart=/opt/concourse/bin/concourse worker \
  --work-dir=/opt/concourse/worker \
  --tsa-host=127.0.0.1:2222 \
  --tsa-public-key=/opt/concourse/keys/web/tsa_host_key.pub \
  --tsa-worker-private-key=/opt/concourse/keys/worker/worker_key \
  --baggageclaim-driver=naive \
  --runtime=containerd \
  --containerd-bin=/usr/bin/containerd \
  --containerd-init-bin=/usr/bin/containerd-shim-runc-v2 \
  --containerd-cni-plugins-dir=/opt/cni/bin \
  --resource-types=/opt/concourse/resource-types
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Note:** The worker runs as root and manages its own embedded containerd instance. The system containerd service should be disabled to avoid conflicts.

## Step 8: Create Worker Directory

```bash
# Create work directory for worker
sudo mkdir -p /opt/concourse/worker
sudo chown -R root:root /opt/concourse/worker
```

## Step 9: Install Container Runtime and Configure

Concourse worker needs a container runtime and CNI plugins. Install and configure them:

```bash
# Install containerd and runc (but we won't run the system containerd service)
sudo apt install -y containerd runc

# Stop and disable the system containerd service (Concourse will run its own)
sudo systemctl stop containerd
sudo systemctl disable containerd

# Install CNI plugins
sudo mkdir -p /opt/cni/bin
CNI_VERSION="v1.3.0"
wget https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz
sudo tar -xzf cni-plugins-linux-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin
rm cni-plugins-linux-amd64-${CNI_VERSION}.tgz

# Verify CNI plugins are installed
ls /opt/cni/bin/
# Should see: bridge, loopback, firewall, portmap, etc.

# Create containerd config for the worker (version 2)
sudo mkdir -p /opt/concourse/worker
containerd config default | sudo tee /opt/concourse/worker/containerd.toml > /dev/null
sudo sed -i 's/version = 3/version = 2/g' /opt/concourse/worker/containerd.toml

# Verify containerd binary location
which containerd
# Should output: /usr/bin/containerd

# Verify containerd-shim-runc-v2 location (this is the init binary)
which containerd-shim-runc-v2
# Should output: /usr/bin/containerd-shim-runc-v2
```

## Step 10: Start Services

```bash
# Reload systemd to pick up new services
sudo systemctl daemon-reload

# Enable services to start on boot
sudo systemctl enable concourse-web
sudo systemctl enable concourse-worker

# Start services
sudo systemctl start concourse-web

# Wait a few seconds for web to initialize
sleep 10

# Start worker
sudo systemctl start concourse-worker
```

## Step 11: Verify Installation

```bash
# Check service status
sudo systemctl status concourse-web
sudo systemctl status concourse-worker

# Check logs if needed
sudo journalctl -u concourse-web -f
sudo journalctl -u concourse-worker -f
```

## Step 12: Access Concourse

Open your browser and navigate to:
- **URL:** `http://your-vm-ip:8080`
- **Username:** `admin`
- **Password:** `admin`

## Step 13: Install Fly CLI (Optional)

```bash
# Download fly CLI from your Concourse instance
wget http://localhost:8080/api/v1/cli?arch=amd64&platform=linux -O fly

# Make executable
chmod +x fly

# Move to system path
sudo mv fly /usr/local/bin/

# Login
fly -t main login -c http://localhost:8080 -u admin -p admin
```

## Troubleshooting

### Services won't start
```bash
# Check logs
sudo journalctl -u concourse-web -n 50
sudo journalctl -u concourse-worker -n 50

# Verify PostgreSQL is running
sudo systemctl status postgresql
```

### Worker not connecting
```bash
# Verify TSA keys are correct
sudo ls -la /opt/concourse/keys/web/
sudo ls -la /opt/concourse/keys/worker/

# Check if worker is registered
fly -t main workers
```

### Database connection issues
```bash
# Test PostgreSQL connection
sudo -u postgres psql -d concourse -c "SELECT version();"

# Verify PostgreSQL is listening
sudo netstat -plnt | grep 5432
```

## Security Recommendations

1. **Change default credentials:** Update the admin password immediately
2. **Use strong PostgreSQL password:** Replace the example password
3. **Configure firewall:** Only allow necessary ports (8080 for web UI)
4. **Use HTTPS:** Configure a reverse proxy (nginx/Apache) with SSL/TLS
5. **Regular updates:** Keep Concourse and system packages updated

## Automatic Startup

All services are configured to start automatically on boot via systemd:
- PostgreSQL starts first
- Concourse web starts after PostgreSQL
- Concourse worker starts after web

To test automatic startup, reboot your VM:
```bash
sudo reboot
```

After reboot, verify all services are running:
```bash
sudo systemctl status postgresql concourse-web concourse-worker
```

## Maintenance Commands

```bash
# Restart all Concourse services
sudo systemctl restart concourse-web concourse-worker

# Stop all services
sudo systemctl stop concourse-worker concourse-web

# View logs
sudo journalctl -u concourse-web --since today
sudo journalctl -u concourse-worker --since today

# Clean up worker (if needed for troubleshooting)
sudo systemctl stop concourse-worker
# Unmount any active overlays
sudo umount -l /opt/concourse/worker/overlays/* 2>/dev/null || true
sudo umount -l /opt/concourse/worker/volumes/live/*/volume 2>/dev/null || true
# Remove worker directory
sudo rm -rf /opt/concourse/worker
sudo mkdir -p /opt/concourse/worker
sudo chown -R root:root /opt/concourse/worker
sudo systemctl start concourse-worker
```

## Resource Configuration

To adjust resource limits, edit the service files:

**For Web:** Edit `/etc/systemd/system/concourse-web.service` and add:
```ini
Environment="CONCOURSE_WORKER_GARDEN_MAX_CONTAINERS=250"
```

**For Worker:** Edit `/etc/systemd/system/concourse-worker.service` and add:
```ini
Environment="CONCOURSE_GARDEN_MAX_CONTAINERS=250"
```

After editing, reload and restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart concourse-web concourse-worker
```