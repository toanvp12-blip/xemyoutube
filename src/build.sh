#!/usr/bin/env bash
set -e

sudo apt-get update
sudo apt-get install -y git curl build-essential fakeroot unzip zstd dpkg-dev clang libncurses6 libncurses-dev libxml2 sudo python3 libpython3-dev libcurl4-openssl-dev

# 1. Cai dat tron bo Theos + iOS Clang Toolchain + iOS SDK
export THEOS=/opt/theos
export NONINTERACTIVE=1
sudo rm -rf $THEOS
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"

# 2. Cai dat Swift Toolchain cho Ubuntu 24.04 va lien ket swiftc vao Theos Toolchain
SWIFT_URL="https://download.swift.org/swift-5.10.1-release/ubuntu2404/swift-5.10.1-RELEASE/swift-5.10.1-RELEASE-ubuntu24.04.tar.gz"
curl -fsSL "$SWIFT_URL" -o /tmp/swift.tar.gz
sudo mkdir -p /opt/swift
sudo tar -xzf /tmp/swift.tar.gz -C /opt/swift --strip-components=1
rm -f /tmp/swift.tar.gz

sudo ln -sf /opt/swift/usr/bin/swiftc $THEOS/toolchain/linux/iphone/bin/swiftc
sudo ln -sf /opt/swift/usr/bin/swift $THEOS/toolchain/linux/iphone/bin/swift
sudo ln -sf /opt/swift/usr/bin/swift-frontend $THEOS/toolchain/linux/iphone/bin/swift-frontend
sudo ln -sf /opt/swift/usr/lib/swift $THEOS/toolchain/linux/iphone/lib/swift

cd src
chmod +x layout/DEBIAN/postinst
mkdir -p ../public/debs2

# 3. Bien dich Rootful (iphoneos-arm)
make clean && make package FINALPACKAGE=1
cp packages/*.deb ../public/debs2/com.xemyoutube_2.1.3_iphoneos-arm.deb

# 4. Bien dich Rootless (iphoneos-arm64) & RootHide (iphoneos-arm64e)
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