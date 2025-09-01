# helix-docker

This repository contains a collection of source files for building Docker images for Perforce Helix. It exists purely because there is no working Docker solution in existence for Perforce Helix.

## helix-p4d

This directory contains the source files for building a Perforce Helix core server Docker image. The published Docker images are available as [`sourcegraph/helix-p4d` on Docker Hub](https://hub.docker.com/r/sourcegraph/helix-p4d).

### Build the docker image

The `helix-p4d/build.sh` script will build the docker image for you. If you don't provide a tag to the script it will tag the image as `sourcegraph/helix-p4d:latest`

```
./build.sh <tag>
```

### Usage

To have a disposable Perforce Helix core server running, simply do:

```sh
docker run --rm \
    --publish 1666:1666 \
    sourcegraph/helix-p4d:2023.1
```

The above command makes the server avaialble locally at `:1666`, with a default super user `admin` and its password `pass12349ers`.

All available options and their default values:

```sh
NAME=perforce-server
P4HOME=/p4
P4NAME=master
P4TCP=1666
P4PORT=tcp6:[::]:1666
P4USER=admin
P4PASSWD=pass12349ers
P4CASE=-C0
P4CHARSET=utf8
JNL_PREFIX=perforce-server
```

Use the `--env` flag to override default:

```sh
docker run --rm \
    --publish 1666:1666 \
    --env P4USER=amy \
    --env P4PASSWD=securepassword \
    sourcegraph/helix-p4d:2023.1
```

> [!WARNING]
> Please be noted that although the server survives over restarts (i.e. data are kept), but it may break if you change the options after the initial bootstrap (i.e. the very first run of the image, at when options are getting hard-coded to the Perforce Helix core server own configuration).

To start a long-running production container, do remember to volume the data directory (`P4HOME`) and replace the `--rm` flag with `-d` (detach):

```sh
docker run -d \
    --publish 1666:1666 \
    --env P4PASSWD=securepassword \
    --volume ~/.helix-p4d-home:/p4 \
    sourcegraph/helix-p4d:2023.1
```

Now you have a running server, please read our handbook for [how to set up the client side](https://handbook.sourcegraph.com/departments/technical-success/support/process/p4-enablement/).

### Running Perforce Helix with SSL enabled

Frist, generate some self-signed SSL certificates:

```bash
mkdir ssl
pushd ssl
openssl genrsa -out privatekey.txt 2048
openssl req -new -key privatekey.txt -out certrequest.csr
openssl x509 -req -days 365 -in certrequest.csr -signkey privatekey.txt -out certificate.txt
rm certrequest.csr
popd
```

Next, we need to run the server with `P4SSLDIR` set to a directory containing the SSL files, and set `P4PORT` to use SSL:

```bash
docker run --rm \
    --publish 1666:1666 \
    --env P4PORT=ssl:1666 \
    --env P4SSLDIR=/ssl \
    --volume ./ssl:/ssl \
    sourcegraph/helix-p4d:2023.1
```

### Running Perforce Helix with IPv6 support

By default, the server is configured to bind to IPv6 addresses using the `tcp6` protocol. The server will listen on all available IPv6 interfaces (`[::]`) on port 1666.

#### IPv6-only configuration (default)

```bash
docker run --rm \
    --publish 1666:1666 \
    sourcegraph/helix-p4d:2023.1
```

#### IPv4 and IPv6 dual-stack configuration

To support both IPv4 and IPv6 clients, override the P4PORT to use `tcp64`:

```bash
docker run --rm \
    --publish 1666:1666 \
    --env P4PORT=tcp64:[::]:1666 \
    sourcegraph/helix-p4d:2023.1
```

#### IPv4-only configuration

To revert to IPv4-only mode:

```bash
docker run --rm \
    --publish 1666:1666 \
    --env P4PORT=tcp:1666 \
    sourcegraph/helix-p4d:2023.1
```

#### IPv6 with SSL

For encrypted communication over IPv6:

```bash
docker run --rm \
    --publish 1666:1666 \
    --env P4PORT=ssl6:[::]:1666 \
    --env P4SSLDIR=/ssl \
    --volume ./ssl:/ssl \
    sourcegraph/helix-p4d:2023.1
```

#### Client configuration

When connecting to an IPv6-enabled server, clients should use the appropriate P4PORT format:

```bash
# IPv6-only
export P4PORT=tcp6:[::1]:1666

# IPv4/IPv6 dual-stack (let OS choose)
export P4PORT=tcp:localhost:1666

# Specific IPv6 address
export P4PORT=tcp6:[2001:db8::1]:1666
```

## Credits

This repository is heavily inspired by https://github.com/p4paul/helix-docker and https://github.com/ambakshi/docker-perforce.
