FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install Dependencies (LineageOS Wiki + Utilities)
RUN apt-get update && apt-get install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf \
    imagemagick protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev libelf-dev \
    libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc zip zlib1g-dev python-is-python3 \
    sudo nano htop screen python3-pip \
    libncurses5 libncurses5-dev lib32ncurses5-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Repo Tool
RUN mkdir -p /usr/local/bin && \
    curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo && \
    chmod a+x /usr/local/bin/repo

# 3. Setup Environment
# We do NOT create a user here. We do it in entrypoint to match Host UID.
ENV USE_CCACHE=1
ENV CCACHE_EXEC=/usr/bin/ccache

# Copy the brain
COPY src/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /android/lineage

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
