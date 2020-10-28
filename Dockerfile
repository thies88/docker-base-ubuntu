FROM alpine:3.11 as rootfs-stage

# environment
ENV REL=bionic
ENV ARCH=amd64
# install packages
RUN \
 apk add --no-cache \
        bash \
        curl \
        tzdata \
        xz

# grab base tarball
RUN \
 mkdir /root-out && \
 curl -o \
	/rootfs.tar.gz -L \
	https://partner-images.canonical.com/core/${REL}/current/ubuntu-${REL}-core-cloudimg-${ARCH}-root.tar.gz && \
 tar xf \
        /rootfs.tar.gz -C \
        /root-out

# Runtime stage
FROM scratch
COPY --from=rootfs-stage /root-out/ /
ARG BUILD_DATE
ARG VERSION
LABEL build_version="version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="Thies88"

# set version for s6 overlay
#ARG OVERLAY_VERSION="v1.22.0.0"
ARG OVERLAY_VERSION="v2.1.0.2"
ARG OVERLAY_ARCH="amd64"

# set environment variables
ARG DEBIAN_FRONTEND="noninteractive"
ENV HOME="/root" \
LANGUAGE="en_US.UTF-8" \
LANG="en_US.UTF-8" \
TERM="xterm"

# copy sources (replaced with sed: See RUN)
# COPY sources.list /etc/apt/

# temp s6 overlay fix for ubuntu 20.04

# tar xfz \
#        /tmp/s6-overlay.tar.gz -C / --exclude="./bin" && \
# tar xzf \
#        /tmp/s6-overlay.tar.gz -C /usr ./bin && \

# add local files
COPY root/ /

RUN \
 echo "Enable Ubuntu Universe, Multiverse, and deb-src for main. Disable backports" && \
 sed -i 's/^#\s*\(*main restricted\)$/\1/g' /etc/apt/sources.list && \
 sed -i 's/^#\s*\(*universe\)$/\1/g' /etc/apt/sources.list && \
 sed -i 's/^#\s*\(*multiverse\)$/\1/g' /etc/apt/sources.list && \
 sed -i '/-backports/s/^/#/' /etc/apt/sources.list && \
 echo "**** Ripped from Ubuntu Docker Logic ****" && \
 set -xe && \
 echo '#!/bin/sh' \
	> /usr/sbin/policy-rc.d && \
 echo 'exit 101' \
	>> /usr/sbin/policy-rc.d && \
 chmod +x \
	/usr/sbin/policy-rc.d && \
 dpkg-divert --local --rename --add /sbin/initctl && \
 cp -a \
	/usr/sbin/policy-rc.d \
	/sbin/initctl && \
 sed -i \
	's/^exit.*/exit 0/' \
	/sbin/initctl && \
 echo 'force-unsafe-io' \
	> /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
 echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
	> /etc/apt/apt.conf.d/docker-clean && \
 echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
	>> /etc/apt/apt.conf.d/docker-clean && \
 echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' \
	>> /etc/apt/apt.conf.d/docker-clean && \
 echo 'Acquire::Languages "none";' \
	> /etc/apt/apt.conf.d/docker-no-languages && \
 echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' \
	> /etc/apt/apt.conf.d/docker-gzip-indexes && \
 echo 'Apt::AutoRemove::SuggestsImportant "false";' \
	> /etc/apt/apt.conf.d/docker-autoremove-suggests && \
 mkdir -p /run/systemd && \
 echo 'docker' \
	> /run/systemd/container && \
 echo "**** install apt-utils and locales ****" && \
 apt-get update && \
 apt-get install -y \
	apt-utils \
	locales && \
 echo "**** generate locale ****" && \
 locale-gen en_US.UTF-8 && \
 echo "**** install packages ****" && \
 apt-get install -y \
	curl \
	tzdata \
	apt-transport-https \
	gnupg2 && \
 echo "**** add s6 overlay ****" && \
 curl -o \
 /tmp/s6-overlay.tar.gz -L \
	"https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}.tar.gz" && \
 tar xfz \
        /tmp/s6-overlay.tar.gz -C / && \
 echo "**** create abc user and make our folders ****" && \
 useradd -u 911 -U -d /config -s /bin/false abc && \
 usermod -G users abc && \
 mkdir -p \
	/app \
	/config \
	/defaults && \
 echo "**** cleanup ****" && \
 #apt-get --purge autoremove -y --allow-remove-essential e2fsprogs && \
 apt-get autoremove && \
 apt-get clean && \
 rm -rf \
	/tmp/* \
	/var/cache/apt \
	/var/lib/apt/lists/* \
	/var/tmp/* \
	/var/log/* \
	/usr/share/locale/* \
	/usr/share/man/* \
        /usr/share/doc/* \
	/usr/share/info \
	/usr/share/zoneinfo/* \
	/var/cache/debconf/*

# Fix some permissions for copied files
#RUN \
# chmod +x /etc/s6/init/init-stage2 && \
# chmod -R 500 /etc/cont-init.d/ && \
# chmod -R 500 /docker-mods

ENTRYPOINT ["/init"]
