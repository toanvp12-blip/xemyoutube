#!/usr/bin/env bash
set -e

sudo apt-get update
sudo apt-get install -y git curl build-essential fakeroot unzip zstd dpkg-dev clang libncurses6 libncurses-dev libxml2

export THEOS=/opt/theos
sudo git clone --recursive --depth=1 https://github.com/theos/theos.git $THEOS

# Tai iOS Toolchain (ho tro bien dich Swift & Clang cho iOS ARM64 tren Linux)
sudo mkdir -p $THEOS/toolchain/linux/iphone
curl -fsSL "https://github.com/sbingner/llvm-project/releases/latest/download/linux-arm64-toolchain.tar.lzma" -o toolchain.tar.lzma
sudo tar --lzma -xf toolchain.tar.lzma -C $THEOS/toolchain/linux/iphone --strip-components=1
rm -f toolchain.tar.lzma

# Tai iOS SDK
curl -fsSL "https://github.com/theos/sdks/archive/master.zip" -o sdks.zip
unzip -q sdks.zip
sudo mv sdks-master/*.sdk $THEOS/sdks/
rm -rf sdks.zip sdks-master

# Cai dat ldid de ky ma ung dung iOS
sudo curl -fsSL "https://github.com/ProcursusTeam/ldid/releases/latest/download/ldid_linux_x86_64" -o /usr/local/bin/ldid
sudo chmod +x /usr/local/bin/ldid

cd src
chmod +x layout/DEBIAN/postinst
mkdir -p ../public/debs2

# 1. Bien dich Rootful (iphoneos-arm)
make clean && make package FINALPACKAGE=1
cp packages/*.deb ../public/debs2/com.xemyoutube_2.1.3_iphoneos-arm.deb

# 2. Bien dich Rootless (iphoneos-arm64) & RootHide (iphoneos-arm64e)
make clean && THEOS_PACKAGE_SCHEME=rootless make package FINALPACKAGE=1
cp packages/*.deb ../public/debs2/com.xemyoutube_2.1.3_iphoneos-arm64.deb
cp packages/*.deb ../public/debs2/com.xemyoutube_2.1.3_iphoneos-arm64e.deb

cd ../public/debs2
mkdir -p tmp_rh
dpkg-deb -R com.xemyoutube_2.1.3_iphoneos-arm64e.deb tmp_rh
sed -i 's/^Architecture.*/Architecture: iphoneos-arm64e/' tmp_rh/DEBIAN/control
dpkg-deb -b tmp_rh com.xemyoutube_2.1.3_iphoneos-arm64e.deb
rm -rf tmp_rh

cd ..
dpkg-scanpackages -m debs2 > Packages
gzip -9c Packages > Packages.gz
zstd -19 -f Packages -o Packages.zst

cat <<EOF > Release
Origin: XemYouTube
Label: XemYouTube
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: Kho luu tru XemYouTube CarPlay
MD5Sum:
 $(md5sum Packages | cut -d' ' -f1) $(wc -c < Packages) Packages
 $(md5sum Packages.gz | cut -d' ' -f1) $(wc -c < Packages.gz) Packages.gz
 $(md5sum Packages.zst | cut -d' ' -f1) $(wc -c < Packages.zst) Packages.zst
SHA256:
 $(sha256sum Packages | cut -d' ' -f1) $(wc -c < Packages) Packages
 $(sha256sum Packages.gz | cut -d' ' -f1) $(wc -c < Packages.gz) Packages.gz
 $(sha256sum Packages.zst | cut -d' ' -f1) $(wc -c < Packages.zst) Packages.zst
EOF