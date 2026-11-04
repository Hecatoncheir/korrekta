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
bin_home="${KORREKTA_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$target" "${XDG_DATA_HOME:-$HOME/.local/share}/applications" "$bin_home"
line=$(awk '/^__ARCHIVE__$/ { print NR + 1; exit }' "$0")
tail -n "+$line" "$0" | tar -xz -C "$target"
chmod +x "$target/korrekta"
ln -sfn "$target/korrekta" "$bin_home/korrekta"
sed -e "s|^Exec=.*|Exec=\"$target/korrekta\"|" -e "s|^Icon=.*|Icon=$target/korrekta.png|" \
  "$target/korrekta.desktop" > "${XDG_DATA_HOME:-$HOME/.local/share}/applications/korrekta.desktop"
printf 'Корректа установлена. Откройте её из меню приложений.\n'
exit 0
__ARCHIVE__
INSTALLER
cat release/payload.tar.gz >> "release/Korrekta-${version}-linux-x64.run"
chmod +x "release/Korrekta-${version}-linux-x64.run"
