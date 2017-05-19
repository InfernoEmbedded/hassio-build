#!/bin/bash
set -e

BUILD_CONTAINER_NAME=homeassistant-build-$$
DOCKER_PUSH="false"
DOCKER_CACHE="true"
DOCKER_HUB=homeassistant

cleanup() {
    echo "[INFO] Cleanup."

    # Stop docker container
    echo "[INFO] Cleaning up homeassistant-build container."
    docker stop $BUILD_CONTAINER_NAME 2> /dev/null || true
    docker rm --volumes $BUILD_CONTAINER_NAME 2> /dev/null || true

    if [ "$1" == "fail" ]; then
        exit 1
    fi
}
trap 'cleanup fail' SIGINT SIGTERM

help () {
    cat << EOF
Script for homeassistant docker build
create_homeassistant [options]

Options:
    -h, --help
        Display this help and exit.

    -h, --hub hubname
        Set user of dockerhub build.

    -m, --machine name
        Machine type for HomeAssistant build.
    -v, --version X.Y
        Version/Tag/branch of HomeAssistant build.
    -p, --push
        Upload the build to docker hub.
    -n, --no-cache
        Disable build from cache
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key=$1
    case $key in
        -h|--help)
            help
            exit 0
            ;;
        -h|--hub)
            DOCKER_HUB=$2
            shift
            ;;
        -m|--machine)
            MACHINE=$2
            shift
            ;;
        -v|--version)
            DOCKER_TAG=$2
            shift
            ;;
        -p|--push)
            DOCKER_PUSH="true"
            ;;
        -n|--no-cache)
            DOCKER_CACHE="false"
            ;;
        *)
            echo "[WARNING] $0 : Argument '$1' unknown. Ignoring."
            ;;
    esac
    shift
done

# Sanity checks
if [ -z "$MACHINE" ]; then
    echo "[ERROR] please set a machine!"
    help
    exit 1
fi
if [ -z "$DOCKER_TAG" ]; then
    echo "[ERROR] please set a version/branch!"
    help
    exit 1
fi

# Get the absolute script location
pushd "$(dirname "$0")" > /dev/null 2>&1
SCRIPTPATH=$(pwd)
popd > /dev/null 2>&1

DOCKER_IMAGE=$DOCKER_HUB/$MACHINE-homeassistant
BUILD_DIR=${BUILD_DIR:=$SCRIPTPATH}
WORKSPACE=$BUILD_DIR/hass-$MACHINE
HASS_GIT=$WORKSPACE/homeassistant

# generate base image
case $MACHINE in
    "raspberrypi1")
        BASE_IMAGE="resin\/raspberry-pi-alpine-python:3.6"
    ;;
    "raspberrypi2")
        BASE_IMAGE="resin\/raspberry-pi2-alpine-python:3.6"
    ;;
    "raspberrypi3")
        BASE_IMAGE="resin\/raspberry-pi3-alpine-python:3.6"
    ;;
    *)
        BASE_IMAGE="resin\/${MACHINE}-alpine-python:3.6"
    ;;
esac

# setup docker
echo "[INFO] Setup docker for homeassistant"
mkdir -p "$BUILD_DIR"
mkdir -p "$WORKSPACE"

echo "[INFO] load homeassistant"
cp ../../homeassistant/Dockerfile "$WORKSPACE/Dockerfile"

sed -i "s/%%BASE_IMAGE%%/${BASE_IMAGE}/g" "$WORKSPACE/Dockerfile"
sed -i "s/%%VERSION%%/${DOCKER_TAG}/g" "$WORKSPACE/Dockerfile"
echo "LABEL io.hass.version=\"$DOCKER_TAG\" io.hass.type=\"homeassistant\" io.hass.machine=\"$MACHINE\"" >> "$WORKSPACE/Dockerfile"

git clone --depth 1 -b "$DOCKER_TAG" https://github.com/home-assistant/home-assistant "$HASS_GIT" > /dev/null
DOCKER_TAG="$(python3 "$HASS_GIT/setup.py" -V | sed -e "s:^\(.\...\)\.0$:\1:g" -e "s:^\(.\...\)\.0.dev0$:\1-dev:g")"

if [ -z "$DOCKER_TAG" ]; then
    echo "[ERROR] Can't read homeassistant version!"
    exit 1
fi
echo "[INFO] prepare done for $DOCKER_IMAGE:$DOCKER_TAG"

# Run build
echo "[INFO] start docker build"
docker stop $BUILD_CONTAINER_NAME 2> /dev/null || true
docker rm --volumes $BUILD_CONTAINER_NAME 2> /dev/null || true
docker run --rm \
    -v "$WORKSPACE":/docker \
    -v ~/.docker:/root/.docker \
    -e DOCKER_PUSH=$DOCKER_PUSH \
    -e DOCKER_CACHE=$DOCKER_CACHE \
    -e DOCKER_IMAGE="$DOCKER_IMAGE" \
    -e DOCKER_TAG="$DOCKER_TAG" \
    --name $BUILD_CONTAINER_NAME \
    --privileged \
    homeassistant/docker-build-env \
    /run-docker.sh

echo "[INFO] cleanup WORKSPACE"
cd "$BUILD_DIR"
rm -rf "$WORKSPACE"

cleanup "okay"
exit 0
