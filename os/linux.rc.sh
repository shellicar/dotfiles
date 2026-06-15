#!/bin/sh
# Linux interactive.

remove_bom() {
    find . -type f -not -path '*/.git/*' -print0 | \
    xargs -0 grep -rl $'^\xEF\xBB\xBF' | \
    xargs -d '\n' sed -i '1s/^\xEF\xBB\xBF//'
}
