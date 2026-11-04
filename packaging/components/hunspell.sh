#!/usr/bin/env bash
set -euo pipefail
target="$1"
mkdir -p work/components-source work/components-native/bin work/components-native/licenses release
curl --fail --location --retry 3 https://github.com/hunspell/hunspell/releases/download/v1.7.5/hunspell-1.7.5.tar.gz -o work/components-source/hunspell.tar.gz
echo '2e559f0c2a592ba48e421477f58e9bf7e01062277a4a7821afb52fc9401010ae  work/components-source/hunspell.tar.gz' | shasum -a 256 --check
tar -xzf work/components-source/hunspell.tar.gz -C work/components-source
project_root="$PWD"
cd work/components-source/hunspell-1.7.5
if [[ "$target" == macos-universal ]]; then
  export CFLAGS='-O2 -arch arm64 -arch x86_64'
  export CXXFLAGS='-O2 -arch arm64 -arch x86_64'
  export LDFLAGS='-arch arm64 -arch x86_64'
fi
./configure --disable-shared --enable-static --disable-nls --with-ui=no --without-readline --prefix="$project_root/work/components-install"
make -j3
make install
cd "$project_root"
cp work/components-install/bin/hunspell work/components-native/bin/
cp work/components-source/hunspell-1.7.5/COPYING* work/components-native/licenses/
cp packaging/components/NOTICE.md work/components-native/licenses/
if [[ "$target" == macos-universal ]]; then
  lipo work/components-native/bin/hunspell -verify_arch arm64 x86_64
  otool -L work/components-native/bin/hunspell
else
  ldd work/components-native/bin/hunspell
fi
work/components-native/bin/hunspell -v
tar -czf "release/hunspell-1.7.5-$target.tar.gz" -C work/components-native .
cp work/components-source/hunspell.tar.gz release/hunspell-1.7.5-source.tar.gz
