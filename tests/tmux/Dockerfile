# The image tests/tmux/run.sh runs each case in: tmux and a POSIX sh (busybox
# ash), and no Node, so nothing can pass by reaching for one.
FROM alpine:3.24
RUN apk add --no-cache tmux
