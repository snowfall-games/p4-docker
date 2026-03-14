# --------------------------------------------------------------------------------
# Docker configuration for P4D
# --------------------------------------------------------------------------------

FROM ubuntu:noble

# Update Ubuntu and add Perforce Package Source
RUN apt-get update && \
  apt-get install -y wget gnupg2 && \
  wget -qO - https://package.perforce.com/perforce.pubkey | gpg --dearmor -o /usr/share/keyrings/perforce-archive-keyring.gpg && \
  echo "deb [signed-by=/usr/share/keyrings/perforce-archive-keyring.gpg] http://package.perforce.com/apt/ubuntu noble release" > /etc/apt/sources.list.d/perforce.list && \
  apt-get update

# --------------------------------------------------------------------------------
# Docker BUILD
# --------------------------------------------------------------------------------

# Create perforce user and install Perforce Server
# Note: helix-p4d has been replaced by p4-server
# Installing latest available versions from the repository
RUN apt-get update && apt-get install -y p4-server helix-swarm-triggers unzip

# Install AWS CLI v2 (awscli not available via apt on Noble)
RUN wget -q "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -O /tmp/awscliv2.zip && \
  unzip -q /tmp/awscliv2.zip -d /tmp && \
  /tmp/aws/install && \
  rm -rf /tmp/awscliv2.zip /tmp/aws
# Add external files
COPY files/restore.sh /usr/local/bin/restore.sh
COPY files/setup.sh /usr/local/bin/setup.sh
COPY files/init.sh /usr/local/bin/init.sh
COPY files/latest_checkpoint.sh /usr/local/bin/latest_checkpoint.sh
COPY files/p4-typemap.txt /usr/local/bin/p4-typemap.txt
COPY files/P4-p4-snowfall.railway.internal.license /usr/local/bin/license
COPY files/s3-migrate.sh /usr/local/bin/s3-migrate.sh

# S3 Storage Environment (Railway Bucket)
ENV S3_ENDPOINT="" \
  S3_BUCKET="" \
  S3_ACCESS_KEY_ID="" \
  S3_SECRET_ACCESS_KEY="" \
  S3_REGION=""

# Default Environment
ARG NAME=snowfall-perforce
ARG P4NAME=snowfall-main
ARG P4USER=admin
ARG P4PASSWD=SnowfallGames!
ARG P4CASE=-C0
ARG P4CHARSET=utf8
ARG PORT=1666
ARG P4PORT=tcp6:1666

# Dynamic Environment
ENV NAME=$NAME \
  P4NAME=$P4NAME \
  P4PORT=$P4PORT \
  PORT=$PORT \
  P4USER=$P4USER \
  P4PASSWD=$P4PASSWD \
  P4CASE=$P4CASE \
  P4CHARSET=$P4CHARSET \
  JNL_PREFIX=$P4NAME

# Base Environment
ENV P4HOME=/p4

# Derived Environment
ENV P4ROOT=$P4HOME/root \
  P4DEPOTS=$P4HOME/depots \
  P4CKP=$P4HOME/checkpoints

# Performance Environment for Game Development
ENV P4JOURNAL=$P4CKP/journal \
  P4LOG=$P4ROOT/logs/log \
  P4FILESYS=NFS

EXPOSE $PORT

RUN \
  chmod +x /usr/local/bin/restore.sh && \
  chmod +x /usr/local/bin/setup.sh && \
  chmod +x /usr/local/bin/init.sh && \
  chmod +x /usr/local/bin/latest_checkpoint.sh && \
  chmod +x /usr/local/bin/s3-migrate.sh

# --------------------------------------------------------------------------------
# Docker RUN
# --------------------------------------------------------------------------------

ENTRYPOINT \
  /usr/local/bin/init.sh && \
  /usr/bin/tail -F $P4ROOT/logs/log

HEALTHCHECK \
  --interval=2m \
  --timeout=10s \
  CMD p4 info -s > /dev/null || exit 1
