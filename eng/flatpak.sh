#!/usr/bin/env bash
# Builds the Flatpak of a release (ADR 0084) from its Linux .tar.gz, for this machine's architecture: the manifest in
# eng/packaging/flatpak, git built from source, and a single-file bundle that installs with
# `flatpak install --user codalus-<version>-linux-<arch>.flatpak` (its runtime comes from Flathub).
# With --test, the bundle is then installed for this user, codalus --version and git --version run in it, and it is
# uninstalled.
# Usage: eng/flatpak.sh [--test] <version> <folder with codalus-<version>-linux-<arch>.tar.gz> [out folder]
# Output: <out>/codalus-<version>-linux-<arch>.flatpak and <out>/SHA256SUMS-flatpak-linux-<arch>.txt (default out:
# artifacts/flatpak).
# Prerequisites: flatpak with the flathub remote, and flatpak-builder (the program, or the org.flatpak.Builder app).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
test=false
if [ "${1:-}" = "--test" ]; then test=true; shift; fi
version="${1:?usage: eng/flatpak.sh [--test] <version> <packages> [out]}" packages="${2:?}" out="${3:-$repo/artifacts/flatpak}"
app=io.github.stavroskasidis.Codalus

case "$(uname -m)" in
  x86_64) arch=x64 ;;
  aarch64) arch=arm64 ;;
  *) echo "error: no Flatpak for $(uname -m)" >&2; exit 2 ;;
esac
tarball="$packages/codalus-$version-linux-$arch.tar.gz"
[ -f "$tarball" ] || { echo "error: $tarball is missing" >&2; exit 1; }

if command -v flatpak-builder > /dev/null; then
  builder=(flatpak-builder)
elif flatpak info org.flatpak.Builder > /dev/null 2>&1; then
  builder=(flatpak run org.flatpak.Builder)
else
  echo "error: no flatpak-builder (install it, or: flatpak install --user flathub org.flatpak.Builder)" >&2
  exit 1
fi

# The manifest's sources, side by side: it names them relative to itself.
work="$repo/artifacts/flatpak-work"
rm -rf "$work"
mkdir -p "$work/source" "$out"
cp "$repo"/eng/packaging/flatpak/* "$work/source/"
cp "$repo/eng/packaging/linux/codalus.desktop" "$repo/assets/logo/png/codalus-256.png" "$work/source/"
cp "$tarball" "$work/source/codalus.tar.gz"

echo "== flatpak-builder ($app $version, linux-$arch)"
"${builder[@]}" --user --install-deps-from=flathub --force-clean --disable-rofiles-fuse \
  --state-dir="$work/state" --repo="$work/repo" "$work/build" "$work/source/$app.yml"

name="codalus-$version-linux-$arch"
echo "== Bundle: $name.flatpak"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo "$work/repo" "$out/$name.flatpak" "$app"
(cd "$out" && sha256sum "$name.flatpak") > "$out/SHA256SUMS-flatpak-linux-$arch.txt"

if $test; then
  echo "== Install, run and uninstall the bundle"
  flatpak install --user -y --noninteractive "$out/$name.flatpak"
  trap 'flatpak uninstall --user -y --noninteractive "$app" > /dev/null 2>&1 || true' EXIT
  reported="$(flatpak run "$app" --version)"
  echo "$reported"
  case "$reported" in *"$version"*) ;; *) echo "error: codalus --version said '$reported', not $version" >&2; exit 1 ;; esac
  flatpak run --command=git "$app" --version
  flatpak run --command=sh "$app" -c 'test -x /app/libexec/host-tools/docker && test -x /app/libexec/host-tools/podman && test -f /app/codalus/codalus'
fi

rm -rf "$work"
echo "== $out/$name.flatpak"
