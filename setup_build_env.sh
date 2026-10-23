#!/usr/bin/env bash
set -euo pipefail
# Ubuntu 22.04 is the supported baseline. Use Docker on newer hosts.
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 && $(uname -m) == x86_64 ]] || {
    echo "Host setup supports Ubuntu 22.04 x86_64. Use ./bootstrap_docker.sh on other Linux releases." >&2
    exit 1
}
sudo apt-get update
sudo apt-get install -y bc bison build-essential ca-certificates curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf \
    imagemagick protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev libelf-dev \
    libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2-dev libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc zip zlib1g-dev python-is-python3 python3 util-linux unzip \
    libncurses5 libncurses5-dev lib32ncurses5-dev
mkdir -p "$HOME/bin"
repo_tmp=$(mktemp "$HOME/bin/repo.XXXXXX")
trap 'rm -f "$repo_tmp"' EXIT
curl --fail --location --retry 3 https://storage.googleapis.com/git-repo-downloads/repo -o "$repo_tmp"
chmod 0755 "$repo_tmp"
mv "$repo_tmp" "$HOME/bin/repo"
git lfs install
echo 'Setup complete. Configure git user.name and user.email, then run ./build-lineage.sh check.'
