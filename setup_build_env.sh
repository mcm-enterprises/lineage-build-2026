#!/bin/bash
set -e

echo ">> Detecting OS version..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    # UBUNTU_CODENAME, VERSION_ID are loaded
    echo "   Detected: $NAME $VERSION_ID ($UBUNTU_CODENAME)"
fi

echo ">> 1. Installing Core Build Packages (Wiki List)..."
sudo apt-get update
sudo apt-get install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf \
    imagemagick protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev libelf-dev \
    libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2-dev libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc zip zlib1g-dev python-is-python3

# Logic for Ubuntu 23.10+ (Mantic/Noble/Plucky)
# Wiki says: Install libncurses5 manually because it was removed from repositories
if dpkg --compare-versions "$VERSION_ID" "ge" "23.10"; then
    echo ">> 2. Newer Ubuntu detected ($VERSION_ID). Enabling legacy support for libncurses5..."
    
    # Check if already installed
    if ! dpkg -l | grep -q libncurses5; then
        echo "   Downloading libtinfo5 and libncurses5 DEBs (Version 6.4)..."
        # Using Noble (24.04) compatible static links
        wget http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.4-2_amd64.deb
        wget http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncurses5_6.4-2_amd64.deb
        
        echo "   Installing DEBs..."
        sudo dpkg -i libtinfo5_6.4-2_amd64.deb
        sudo dpkg -i libncurses5_6.4-2_amd64.deb
        
        echo "   Cleaning up DEBs..."
        rm -f libtinfo5_6.4-2_amd64.deb libncurses5_6.4-2_amd64.deb
    else
        echo "   libncurses5 already installed."
    fi
else
    # Older Ubuntu (Standard repo)
    echo ">> 2. Standard Ubuntu detected. Installing libncurses5 from apt..."
    sudo apt-get install -y libncurses5 libncurses5-dev lib32ncurses5-dev
fi

echo ">> 3. Setting up 'repo' tool..."
mkdir -p ~/bin
if [ ! -f ~/bin/repo ]; then
    curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
    chmod a+x ~/bin/repo
fi

# Ensure PATH for this script session
export PATH=~/bin:$PATH

echo ">> 4. Configuring Git..."
git config --global --add safe.directory '*'
git lfs install

echo ">> 5. Setting up CCACHE..."
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G

echo ">> SETUP COMPLETE!"
