# Ubuntu 24.04 PRoot Fakeroot Environment

This script creates an isolated Ubuntu 24.04 LTS environment using **PRoot** and **fakeroot**, allowing you to install packages and run services without requiring actual root privileges on the host system.

## 🎯 Key Features

### ✅ Improvements Over Previous Versions

#### 1. **Ubuntu 24.04 LTS (Long-Term Support)**
- **Extended Support**: Fully supported until April 2029
- **No EOL Issues**: Unlike Ubuntu 22.04 which reached end-of-life in April 2024
- **Stable Repositories**: `archive.ubuntu.com` works reliably without 404 errors

#### 2. **Optimized APT & DPKG**
- **Improved APT Configuration**: Signature verification disabled for fakeroot compatibility
  - `AllowInsecureRepositories: true`
  - `Check-Valid-Until: false`
  - Allows package downgrades when needed
  
- **Automated DPKG**: 
  - Force file overwrites to prevent conflicts
  - Force confnew for config file changes
  - Auto-creates status files and dpkg database

- **Policy-rc.d**: Prevents unnecessary service auto-start
- **APT Sandbox**: Safely runs APT as root within PRoot isolation

#### 3. **PRoot v5.3.0**
- **Stable Binary**: 41,673+ downloads, battle-tested
- **Multi-architecture Support**: x86_64, ARM64, ARMv7, PPC64LE, RISC-V, s390x
- **Auto-detection**: Checks system PRoot → local cache → downloads if needed

#### 4. **DNS & Networking**
- Pre-configured DNS (Google & Cloudflare nameservers)
- Bind mount support for `/dev`, `/proc`, `/sys`

#### 5. **System Services Enabled**
- `systemctl` and `service` are **NOT stubbed** - real services work
- Only basic commands are stubbed (invoke-rc.d, update-rc.d)
- Full service discovery and management inside rootfs

#### 6. **UCF (Update Configuration Files)**
- Simplified stub with just `exit 0` instead of complex handling
- Appropriate since UCF is unnecessary in fakeroot

---

## ⚠️ Limitations & Weaknesses

### 1. **Performance**
- **PRoot Overhead**: Every system call is translated, ~2-10x slower than native
- **I/O Performance**: Filesystem operations significantly slower
- **Not Suitable For**: High-performance applications, large database servers

### 2. **Limited Functionality**
- **Incomplete ptrace**: Some debuggers and profilers won't work
- **seccomp/selinux**: Bypassed, no real security isolation
- **Hardware Access**: Cannot access hardware directly (GPIO, USB, etc.)
- **Kernel Modules**: Cannot load real kernel modules inside rootfs
- **cgroup/namespace**: Limited cgroup v2 and user namespace support

### 3. **Package Ecosystem Issues**
- **Systemd Limitations**: Some systemd features don't fully work
  - Timer units may not trigger correctly
  - Device dependencies may be ignored
  - cgroup integration is incomplete

- **Network Services**: 
  - Binding to ports < 1024 requires workarounds
  - Network namespaces aren't real
  - Container networking plugins unavailable

### 4. **Compatibility Issues**
- **Glibc Version**: Depends on host's glibc
- **Kernel Features**: Limited by host kernel capabilities
- **Some Packages**: May fail if they require unsupported features

### 5. **Security**
- **Not Real Sandboxing**: Users can escape rootfs via vulnerabilities
- **Permission Bypass**: File permissions ignored when running as root
- **Shared Kernel**: All rootfs instances share the host kernel; kernel bugs affect everything

### 6. **Complex Setup**
- **Rootfs Preparation**: Download 29MB, extract, initialize from scratch
- **Maintenance**: Requires manual updates for security patches
- **Difficult Debugging**: Issues can be complex; hard to trace PRoot to host

---

## 📋 System Requirements

- **Linux Kernel**: 3.10 or higher
- **curl or wget**: For downloading PRoot and rootfs
- **tar**: For extracting rootfs
- **Disk Space**: ~500MB (50MB PRoot + 400MB rootfs + overhead)
- **RAM**: Minimum 256MB (512MB+ recommended)

---

## 🚀 Usage

### Normal Run (Create/Initialize rootfs)
```bash
sh root.sh
```

### Clean Everything (Fresh Start)
```bash
sh root.sh -r
```

### Custom Configuration
```bash
# Change rootfs directory
UBUNTU_FAKEROOT_DIR=/custom/path sh root.sh

# Use custom PRoot binary
PROOT_BIN=/path/to/proot sh root.sh

# Set custom hostname
UBUNTU_HOSTNAME=my-ubuntu sh root.sh
```

### Inside the Rootfs
```bash
# Update packages
apt update && apt upgrade -y

# Install tools
apt install -y build-essential python3 vim

# Run services
service nginx start
systemctl status nginx
```

---

## 📊 Comparison with Other Solutions

| Feature | root.sh (PRoot) | Docker | Chroot | LXC |
|---------|-----------------|--------|--------|-----|
| No Root Required | ✅ | ❌ | ❌ | ❌ |
| Speed | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Isolation | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐⭐⭐ |
| Easy Setup | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Compatibility | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Resource Usage | ⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |

---

## 🔧 Technical Details

### Directory Structure
```
ubuntu-24.04-fakeroot/
├── proot                          # PRoot v5.3.0 binary
├── ubuntu-base-24.04.tar.gz       # Rootfs tarball
└── rootfs/                        # Extracted rootfs
    ├── bin, lib, usr, etc/        # Standard Linux directories
    ├── etc/apt/sources.list       # Ubuntu 24.04 repositories
    ├── etc/resolv.conf            # DNS configuration
    └── ...
```

### Environment Variables
- `UBUNTU_FAKEROOT_DIR`: Root directory path (default: `./ubuntu-24.04-fakeroot`)
- `PROOT_BIN`: Path to PRoot binary (auto-detected)
- `UBUNTU_HOSTNAME`: Hostname inside rootfs (default: `ubuntu-fakeroot`)
- `UBUNTU_ROOTFS_URL`: Custom rootfs URL

---

## 📝 Troubleshooting

### APT Error: "Conflicting values set for option Trusted"
- **Cause**: Duplicate entries in sources.list.d
- **Fix**: Script automatically removes sources.list.d on setup

### PRoot 404 Error
- **Cause**: Old binary URL doesn't exist
- **Fix**: Script uses v5.3.0 (41K+ downloads, proven stable)

### Package Installation Fails
- **Cause**: Repository unavailable or package doesn't exist
- **Fix**: Run `apt update` first, or use `--no-install-recommends`

### Services Won't Start
- **Cause**: systemd doesn't fully work in PRoot
- **Workaround**: Use init scripts directly or start manually

### UCF Configuration Errors When Installing Packages
**Problem**: When installing packages like `neofetch`, `curl`, or `ghostscript`, you may get errors like:
```
Errors were encountered while processing:
libpaper1:amd64
libgs9:amd64
libpaper-utils
ghostscript
```

**Solution**: The default UCF stub is too simple. Replace it with a functional version:

**Step 1**: Create proper UCF implementation
```bash
cat >/usr/bin/ucf <<'EOF'
#!/bin/sh
if [ "$1" = "--purge" ] && [ -n "$2" ]; then
  rm -f "$2" 2>/dev/null || true
  exit 0
fi
if [ $# -ge 2 ]; then
  new="$1"
  dest="$2"
  if [ -f "$new" ]; then
    d=$(dirname "$dest")
    mkdir -p "$d" 2>/dev/null || true
    cp -f "$new" "$dest" 2>/dev/null || true
  fi
fi
exit 0
EOF
chmod +x /usr/bin/ucf
```

**Step 2**: Create UCFR stub
```bash
cat >/usr/bin/ucfr <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x /usr/bin/ucfr
```

**Step 3**: Ensure UCF state directory exists and is writable
```bash
mkdir -p /var/lib/ucf
chmod 777 /var/lib/ucf 2>/dev/null || true
```

**Step 4**: Reconfigure packages
```bash
dpkg --configure -a
```

If no more errors appear, you're done! You can now install problematic packages.

---

## 📄 License & Credits

Script designed to create lightweight dev environments for Ubuntu 24.04 LTS using PRoot.

**Version**: 24.04-v1 (2025-12-03)
**Base OS**: Ubuntu 24.04 LTS (Noble Numbat)
**PRoot**: v5.3.0 (static x86_64)
