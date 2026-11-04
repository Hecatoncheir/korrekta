#!/usr/bin/env bash
set -euo pipefail
version="$1"
mkdir -p release/linux-stage
cp -a app/build/linux/x64/release/bundle/. release/linux-stage/
cp app/assets/mark.png release/linux-stage/korrekta.png
cat > release/linux-stage/korrekta.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Корректа
Comment=Локальная проверка русского текста
Exec=korrekta
Icon=korrekta
Categories=Office;Utility;
Terminal=false
DESKTOP
tar -C release/linux-stage -czf release/payload.tar.gz .
cat > "release/Korrekta-${version}-linux-x64.run" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
target="${XDG_DATA_HOME:-$HOME/.local/share}/korrekta"
parent_pid=""
relaunch=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --wait-pid) parent_pid="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --log) exec >> "$2" 2>&1; shift 2 ;;
    --relaunch) relaunch=true; shift ;;
    *) exit 2 ;;
  esac
done
if [ -n "$parent_pid" ]; then
  for attempt in {1..60}; do
    if ! kill -0 "$parent_pid" 2>/dev/null; then break; fi
    sleep 1
  done
  if kill -0 "$parent_pid" 2>/dev/null; then exit 1; fi
fi
bin_home="${KORREKTA_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$target" "${XDG_DATA_HOME:-$HOME/.local/share}/applications" "$bin_home"
line=$(awk '/^__ARCHIVE__$/ { print NR + 1; exit }' "$0")
stage=$(mktemp -d "$(dirname "$target")/.korrekta-update.XXXXXX")
mkdir "$stage/new"
tail -n "+$line" "$0" | tar -xz -C "$stage/new"
chmod +x "$stage/new/korrekta"
mv "$target" "$stage/previous"
if ! mv "$stage/new" "$target"; then
  mv "$stage/previous" "$target"
  exit 1
fi
ln -sfn "$target/korrekta" "$bin_home/korrekta"
sed -e "s|^Exec=.*|Exec=\"$target/korrekta\"|" -e "s|^Icon=.*|Icon=$target/korrekta.png|" \
  "$target/korrekta.desktop" > "${XDG_DATA_HOME:-$HOME/.local/share}/applications/korrekta.desktop"
printf 'Корректа установлена. Откройте её из меню приложений.\n'
if "$relaunch"; then nohup "$target/korrekta" >/dev/null 2>&1 & fi
exit 0
__ARCHIVE__
INSTALLER
cat release/payload.tar.gz >> "release/Korrekta-${version}-linux-x64.run"
chmod +x "release/Korrekta-${version}-linux-x64.run"
