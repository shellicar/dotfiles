#!/bin/sh
docker run --rm -it \
    --name df-shellcheck \
    -v "${PWD}":/usr/src:ro \
    --workdir /usr/src \
    koalaman/shellcheck:stable ./test.sh
