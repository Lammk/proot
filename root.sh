#!/bin/sh
set -e

UBUNTU_VERSION="24.04"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
ROOT_DIR=${UBUNTU_FAKEROOT_DIR:-"$SCRIPT_DIR/ubuntu-${UBUNTU_VERSION}-fakeroot"}
ROOTFS_DIR="$ROOT_DIR/rootfs"
ROOTFS_TAR="$ROOT_DIR/ubuntu-base-${UBUNTU_VERSION}.tar.gz"
PROOT_LOCAL="$ROOT_DIR/proot"

ARCH_HOST=$(uname -m 2>/dev/null || echo unknown)
case "$ARCH_HOST" in
    x86_64|amd64) UBUNTU_ARCH="amd64" ;;
    aarch64|arm64) UBUNTU_ARCH="arm64" ;;
    armv7l|armv7|armhf) UBUNTU_ARCH="armhf" ;;
    ppc64le) UBUNTU_ARCH="ppc64el" ;;
    riscv64) UBUNTU_ARCH="riscv64" ;;
    s390x) UBUNTU_ARCH="s390x" ;;
    *)
        echo "[-] Warning: architecture '$ARCH_HOST' not recognized; using amd64 as default." >&2
        UBUNTU_ARCH="amd64"
        ;;
esac

UBUNTU_ROOTFS_URL=${UBUNTU_ROOTFS_URL:-"https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-24.04.3-base-${UBUNTU_ARCH}.tar.gz"}

case "$ARCH_HOST" in
    x86_64|amd64) PROOT_ARCH="x86_64" ;;
    aarch64|arm64) PROOT_ARCH="aarch64" ;;
    armv7l|armv7|armhf) PROOT_ARCH="arm" ;;
    *) PROOT_ARCH="" ;;
esac

if [ -n "$PROOT_ARCH" ]; then
    PROOT_URL_DEFAULT="https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-x86_64-static"
else
    PROOT_URL_DEFAULT=""
fi
PROOT_URL=${PROOT_URL:-"$PROOT_URL_DEFAULT"}

download() {
    url="$1"
    dest="$2"

    if [ -e "$dest" ]; then
        echo "[*] File $dest already exists, skipping download."
        return 0
    fi

    echo "[*] Downloading $url ..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --tries=3 --waitretry=2 -O "$dest" "$url"
    else
        echo "[!] Error: 'curl' or 'wget' required to download $url" >&2
        exit 1
    fi
}

ensure_proot() {
    if [ -n "${PROOT_BIN:-}" ] && [ -x "$PROOT_BIN" ]; then
        echo "[*] Using PRoot from PROOT_BIN: $PROOT_BIN"
        return 0
    fi

    if command -v proot >/dev/null 2>&1; then
        PROOT_BIN=$(command -v proot)
        echo "[*] Using system PRoot: $PROOT_BIN"
        return 0
    fi

    if [ -x "$PROOT_LOCAL" ]; then
        PROOT_BIN="$PROOT_LOCAL"
        echo "[*] Using local PRoot: $PROOT_BIN"
        return 0
    fi

    if [ -z "$PROOT_URL" ]; then
        echo "[!] Error: PRoot not found and no download URL for architecture '$ARCH_HOST'." >&2
        echo "    Please install PRoot manually or set PROOT_BIN to a valid PRoot binary." >&2
        exit 1
    fi

    mkdir -p "$ROOT_DIR"
    echo "[*] Downloading PRoot to $PROOT_LOCAL ..."
    download "$PROOT_URL" "$PROOT_LOCAL"
    chmod +x "$PROOT_LOCAL"
    PROOT_BIN="$PROOT_LOCAL"
    echo "[*] PRoot download complete: $PROOT_BIN"
}

ensure_rootfs() {
    if [ -d "$ROOTFS_DIR" ] && [ -d "$ROOTFS_DIR/bin" ]; then
        echo "[*] Rootfs already exists at $ROOTFS_DIR"
        return 0
    fi

    mkdir -p "$ROOT_DIR"
    echo "[*] Preparing Ubuntu $UBUNTU_VERSION ($UBUNTU_ARCH) rootfs ..."
    download "$UBUNTU_ROOTFS_URL" "$ROOTFS_TAR"

    mkdir -p "$ROOTFS_DIR"
    echo "[*] Extracting rootfs ..."
    tar -xpf "$ROOTFS_TAR" -C "$ROOTFS_DIR"
    echo "[*] Rootfs extracted to $ROOTFS_DIR"
}

setup_dns() {
    mkdir -p "$ROOTFS_DIR/etc"
    if [ ! -f "$ROOTFS_DIR/etc/resolv.conf" ] || [ ! -s "$ROOTFS_DIR/etc/resolv.conf" ]; then
        cat > "$ROOTFS_DIR/etc/resolv.conf" <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    fi
}

setup_sources_list() {
    mkdir -p "$ROOTFS_DIR/etc/apt"
    
    # Xóa tất cả sources cũ để tránh xung đột
    rm -rf "$ROOTFS_DIR/etc/apt/sources.list.d" 2>/dev/null || true
    mkdir -p "$ROOTFS_DIR/etc/apt/sources.list.d"
    
    if [ "$UBUNTU_ARCH" = "arm64" ] || [ "$UBUNTU_ARCH" = "armhf" ]; then
        cat > "$ROOTFS_DIR/etc/apt/sources.list" <<EOF
deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse
deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports noble-updates main restricted universe multiverse
deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports noble-security main restricted universe multiverse
EOF
    else
        cat > "$ROOTFS_DIR/etc/apt/sources.list" <<EOF
deb [trusted=yes] http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb [trusted=yes] http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb [trusted=yes] http://archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF
    fi
}

fix_dpkg_status() {
    DPKG_STATUS="$ROOTFS_DIR/var/lib/dpkg/status"
    mkdir -p "$ROOTFS_DIR/var/lib/dpkg"
    mkdir -p "$ROOTFS_DIR/var/lib/dpkg/info"
    mkdir -p "$ROOTFS_DIR/var/lib/dpkg/updates"
    mkdir -p "$ROOTFS_DIR/var/lib/dpkg/triggers"
    
    touch "$DPKG_STATUS"
    touch "$ROOTFS_DIR/var/lib/dpkg/available"
    touch "$ROOTFS_DIR/var/lib/dpkg/diversions"
    touch "$ROOTFS_DIR/var/lib/dpkg/statoverride"
    
    mkdir -p "$ROOTFS_DIR/var/log"
    touch "$ROOTFS_DIR/var/log/dpkg.log"
    
    mkdir -p "$ROOTFS_DIR/var/cache/apt/archives/partial"
    mkdir -p "$ROOTFS_DIR/var/lib/apt/lists/partial"
}

fix_apt_sandbox() {
    mkdir -p "$ROOTFS_DIR/etc/apt/apt.conf.d"
    cat > "$ROOTFS_DIR/etc/apt/apt.conf.d/99proot-fixes" <<EOF
APT::Sandbox::User "root";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
Acquire::Check-Valid-Until "false";
APT::Get::AllowUnauthenticated "true";
Dpkg::Options:: "--force-confnew";
Dpkg::Options:: "--force-overwrite";
EOF
}

create_policy_rc() {
    mkdir -p "$ROOTFS_DIR/usr/sbin"
    cat > "$ROOTFS_DIR/usr/sbin/policy-rc.d" <<EOF
#!/bin/sh
exit 101
EOF
    chmod +x "$ROOTFS_DIR/usr/sbin/policy-rc.d"
}

fix_passwd_group() {
    mkdir -p "$ROOTFS_DIR/etc"
    
    if [ ! -f "$ROOTFS_DIR/etc/passwd" ]; then
        cat > "$ROOTFS_DIR/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
games:x:5:60:games:/usr/games:/usr/sbin/nologin
man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
gnats:x:41:41:Gnats Bug-Reporting System:/var/lib/gnats:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
_apt:x:100:65534::/nonexistent:/usr/sbin/nologin
messagebus:x:101:101::/nonexistent:/usr/sbin/nologin
EOF
    fi
    
    if [ ! -f "$ROOTFS_DIR/etc/group" ]; then
        cat > "$ROOTFS_DIR/etc/group" <<EOF
root:x:0:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:8:
news:x:9:
uucp:x:10:
man:x:12:
proxy:x:13:
kmem:x:15:
dialout:x:20:
fax:x:21:
voice:x:22:
cdrom:x:24:
floppy:x:25:
tape:x:26:
sudo:x:27:
audio:x:29:
dip:x:30:
www-data:x:33:
backup:x:34:
operator:x:37:
list:x:38:
irc:x:39:
src:x:40:
gnats:x:41:
shadow:x:42:
utmp:x:43:
video:x:44:
sasl:x:45:
plugdev:x:46:
staff:x:50:
games:x:60:
users:x:100:
nogroup:x:65534:
messagebus:x:101:
EOF
    fi
    
    mkdir -p "$ROOTFS_DIR/root"
}

install_ucf_stubs() {
    UDIR="$ROOTFS_DIR/usr/bin"
    mkdir -p "$UDIR"

    cat > "$UDIR/ucf" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$UDIR/ucf"

    cat > "$UDIR/ucfr" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$UDIR/ucfr"

    cat > "$UDIR/ucfq" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$UDIR/ucfq"

    mkdir -p "$ROOTFS_DIR/var/lib/ucf"
    touch "$ROOTFS_DIR/var/lib/ucf/hashfile"
    touch "$ROOTFS_DIR/var/lib/ucf/registry"
}

stub_system_services() {
    mkdir -p "$ROOTFS_DIR/usr/bin"
    mkdir -p "$ROOTFS_DIR/bin"
    
    for cmd in invoke-rc.d update-rc.d start-stop-daemon; do
        stub="$ROOTFS_DIR/usr/bin/$cmd"
        cat > "$stub" <<'EOF'
#!/bin/sh
exit 0
EOF
        chmod +x "$stub"
    done
}

fix_ld_preload() {
    mkdir -p "$ROOTFS_DIR/etc"
    rm -f "$ROOTFS_DIR/etc/ld.so.preload" 2>/dev/null || true
    touch "$ROOTFS_DIR/etc/ld.so.preload"
}

init_rootfs() {
    setup_dns
    setup_sources_list
    fix_dpkg_status
    fix_apt_sandbox
    create_policy_rc
    fix_passwd_group
    install_ucf_stubs
    stub_system_services
    fix_ld_preload
    
    mkdir -p "$ROOTFS_DIR/tmp"
    mkdir -p "$ROOTFS_DIR/run"
    mkdir -p "$ROOTFS_DIR/var/tmp"
    chmod 1777 "$ROOTFS_DIR/tmp" 2>/dev/null || true
    chmod 1777 "$ROOTFS_DIR/var/tmp" 2>/dev/null || true
}

launch_shell() {
    if [ -x "$ROOTFS_DIR/bin/bash" ]; then
        GUEST_SHELL="/bin/bash"
    elif [ -x "$ROOTFS_DIR/usr/bin/bash" ]; then
        GUEST_SHELL="/usr/bin/bash"
    else
        GUEST_SHELL="/bin/sh"
    fi

    HOST_NAME=${UBUNTU_HOSTNAME:-"ubuntu-fakeroot"}
    PROMPT="root@${HOST_NAME}:\\w# "

    echo "[*] Entering Ubuntu $UBUNTU_VERSION fakeroot environment (PRoot) ..."
    
    exec "$PROOT_BIN" \
        --kill-on-exit \
        -0 \
        -r "$ROOTFS_DIR" \
        -b /dev \
        -b /proc \
        -b /sys \
        -b /dev/urandom:/dev/random \
        -w /root \
        /usr/bin/env -i \
        HOME=/root \
        USER=root \
        LOGNAME=root \
        TERM="${TERM:-xterm-256color}" \
        LANG=C.UTF-8 \
        LC_ALL=C.UTF-8 \
        HOSTNAME="$HOST_NAME" \
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        DEBIAN_FRONTEND=noninteractive \
        DPKG_FRONTEND=noninteractive \
        PS1="$PROMPT" \
        TMPDIR=/tmp \
        TMP=/tmp \
        "$GUEST_SHELL" -l
}

clean_all() {
    if [ -d "$ROOT_DIR" ]; then
        echo "[*] Removing all data from $ROOT_DIR ..."
        rm -rf "$ROOT_DIR"
        echo "[*] Cleanup complete."
    else
        echo "[*] Nothing to remove in $ROOT_DIR"
    fi
}

show_help() {
    echo "Usage: $0 [-r] [-h]"
    echo "  -r    Remove all rootfs and data"
    echo "  -h    Show this help message"
}

main() {
    CLEAN=0
    while getopts "rh" opt; do
        case "$opt" in
            r) CLEAN=1 ;;
            h) show_help; exit 0 ;;
            *) show_help; exit 1 ;;
        esac
    done

    if [ "$CLEAN" -eq 1 ]; then
        clean_all
        exit 0
    fi

    mkdir -p "$ROOT_DIR"
    ensure_proot
    ensure_rootfs
    init_rootfs
    launch_shell
}

main "$@"