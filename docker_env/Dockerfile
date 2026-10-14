FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc bison build-essential ca-certificates curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf \
    imagemagick protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev libelf-dev \
    libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2-dev libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc zip zlib1g-dev python-is-python3 python3 util-linux unzip \
    libncurses5 libncurses5-dev lib32ncurses5-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --retry 3 https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
    && chmod 0755 /usr/local/bin/repo
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN test "$HOST_UID" -ne 0 \
    && (getent group "$HOST_GID" || groupadd -g "$HOST_GID" builder) \
    && useradd -u "$HOST_UID" -g "$HOST_GID" -m -s /bin/bash builder \
    && mkdir -p /android/lineage \
    && chown "$HOST_UID:$HOST_GID" /android/lineage
COPY build-lineage.sh /opt/lineage-build/build-lineage.sh
COPY profiles/ /opt/lineage-build/profiles/
COPY scripts/ /opt/lineage-build/scripts/
COPY local_manifests/ /opt/lineage-build/local_manifests/
COPY docker_env/src/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /opt/lineage-build/build-lineage.sh /usr/local/bin/entrypoint.sh
USER builder
ENV HOME=/home/builder BUILD_DIR=/android/lineage OUTPUT_DIR=/android/zips LOG_DIR=/android/logs
WORKDIR /android/lineage
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["all"]
