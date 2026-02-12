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

cat >/usr/bin/ucfr <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x /usr/bin/ucfr

mkdir -p /var/lib/ucf
chmod 777 /var/lib/ucf 2>/dev/null || true

dpkg --configure -a
