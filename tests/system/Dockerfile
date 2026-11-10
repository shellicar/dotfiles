# The image tests/system/run.sh runs each case in: Ubuntu 24.04 with git and
# sysctl, an ordinary user called tester for the command to run as, and a sudo
# that only records that it was called, so a case can show nothing asked for
# root. The repo is copied in by root, so git is told to trust any owner.
FROM ubuntu:24.04
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends git procps >/dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m tester \
 && git config --system --add safe.directory '*' \
 && printf '#!/bin/sh\necho "sudo $*" >> /work/sudo/called\nexit 1\n' > /usr/local/bin/sudo \
 && chmod 0755 /usr/local/bin/sudo
