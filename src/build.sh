#!/usr/bin/env bash
set -e

sudo apt-get update
sudo apt-get install -y git curl build-essential fakeroot unzip zstd dpkg-dev clang libncurses6 libncurses-dev libxml2 sudo python3

export THEOS=/opt/theos
export NONINTERACTIVE=1
sudo rm -rf $THEOS

bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)" || true

curl -fsSL "https://github.com/theos/sdks/archive/master.zip" -o /tmp/sdks.zip
unzip -q /tmp/sdks.zip -d /tmp
sudo mkdir -p $THEOS/sdks
sudo cp -rn /tmp/sdks-master/*.sdk $THEOS/sdks/
rm -rf /tmp/sdks.zip /tmp/sdks-master

cd src
chmod 0755 layout/DEBIAN/postinst
rm -rf ../public/debs2
mkdir -p ../public/debs2

# 1. Bien dich Rootful (iphoneos-arm)
rm -rf packages .theos && make clean && make package FINALPACKAGE=1
cp packages/*.deb ../public/debs2/com.xemyoutube_2.7.0_iphoneos-arm.deb

# 2. Bien dich Rootless (iphoneos-arm64) & RootHide (iphoneos-arm64e)
rm -rf packages .theos && make clean && THEOS_PACKAGE_SCHEME=rootless make package FINALPACKAGE=1
cp packages/*.deb ../public/debs2/com.xemyoutube_2.7.0_iphoneos-arm64.deb
cp packages/*.deb ../public/debs2/com.xemyoutube_2.7.0_iphoneos-arm64e.deb

cd ../public/debs2

# Dam bao postinst va Version 2.7.0 chuan xac trong tung goi .deb
for arch in iphoneos-arm iphoneos-arm64 iphoneos-arm64e; do
    deb="com.xemyoutube_2.7.0_${arch}.deb"
    rm -rf tmp_edit
    mkdir -p tmp_edit
    dpkg-deb -R "$deb" tmp_edit
    sed -i "s/^Architecture.*/Architecture: ${arch}/" tmp_edit/DEBIAN/control
    sed -i "s/^Version.*/Version: 2.7.0/" tmp_edit/DEBIAN/control
    cp ../../src/layout/DEBIAN/postinst tmp_edit/DEBIAN/postinst
    chmod 0755 tmp_edit/DEBIAN/postinst
    dpkg-deb -Zxz -b tmp_edit "$deb"
    rm -rf tmp_edit
done

cd ..
dpkg-scanpackages -m debs2 > Packages
gzip -9c Packages > Packages.gz
zstd -19 -f Packages -o Packages.zst

cat <<EOF > Release
Origin: XemYouTube
Label: XemYouTube
Suite: stable
Version: 2.7.0
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