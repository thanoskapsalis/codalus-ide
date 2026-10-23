#!/bin/sh
# The Flatpak's codalus command (ADR 0084). The sandbox's /usr is the runtime's, so the hosts (framework-dependent .NET
# apps) can't find a .NET in /usr/share/dotnet or /usr/lib/dotnet: the SDK is the one in ~/.dotnet, where the IDE's own
# Install .NET puts it (ADR 0080). A DOTNET_ROOT the user set wins.
if [ -z "${DOTNET_ROOT:-}" ] && [ -x "$HOME/.dotnet/dotnet" ]; then
  export DOTNET_ROOT="$HOME/.dotnet"
fi
if [ -n "${DOTNET_ROOT:-}" ]; then
  export PATH="$DOTNET_ROOT:$HOME/.dotnet/tools:$PATH"
fi
# Flatpak sets SHELL to /bin/sh, which is bash in POSIX mode: it reads no ~/.bashrc, so the terminal and the login PATH
# (LoginShellPath) would miss what the user's startup files add. The runtime's shell is bash.
if [ "${SHELL:-/bin/sh}" = /bin/sh ]; then
  export SHELL=/usr/bin/bash
fi
# docker and podman run on the host (host-tool.sh). Only the ones the host has go on the PATH: the IDE takes the first
# engine it finds, and a docker that isn't there would hide the host's podman.
tools="${XDG_RUNTIME_DIR:-/tmp}/codalus-host-tools"
mkdir -p "$tools" && rm -f "$tools"/*
for tool in $(flatpak-spawn --host sh -c 'for t in docker podman; do command -v "$t" > /dev/null && echo "$t"; done' 2> /dev/null); do
  ln -sf "/app/libexec/host-tools/$tool" "$tools/$tool"
done
export PATH="$tools:$PATH"
exec /app/codalus/codalus "$@"
