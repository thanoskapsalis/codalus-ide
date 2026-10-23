#!/bin/sh
# Runs the host's program of this name (/app/libexec/host-tools/docker and podman, which codalus-flatpak.sh puts on the
# PATH when the host has them; ADR 0084): the container CLIs talk to a daemon or user namespaces the sandbox can't reach.
# flatpak-spawn keeps the working folder, and the host's paths under /home, /var/home, /tmp and the like are the
# sandbox's (--filesystem=host and /tmp).
exec flatpak-spawn --host --watch-bus -- "$(basename "$0")" "$@"
