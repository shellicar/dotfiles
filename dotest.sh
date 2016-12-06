#!/bin/sh
docker run --rm -it \
    --name df-shellcheck \
    -v "${PWD}":/usr/src:ro \
    --workdir /usr/src \
    r.j3ss.co/shellcheck ./test.sh
