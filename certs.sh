#!/bin/sh
# CA bundles for Node and Python requests, which ignore the system store.
# load.sh sources this after os/<os>.env.sh, which supplies only CA_BUNDLE_OS.

# A parent such as the Claude Code sandbox sets these to its own bundle, and it
# must win. -f rather than := because an inherited path can outlive its file
# (a tmux server started in the sandbox keeps a per-session path that is later
# deleted); a dead one falls back to the OS bundle.
if [ -n "${CA_BUNDLE_OS:-}" ]; then
  [ -f "${NODE_EXTRA_CA_CERTS:-}" ] || NODE_EXTRA_CA_CERTS=$CA_BUNDLE_OS
  [ -f "${REQUESTS_CA_BUNDLE:-}" ] || REQUESTS_CA_BUNDLE=$CA_BUNDLE_OS
  export NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE
fi
unset CA_BUNDLE_OS
