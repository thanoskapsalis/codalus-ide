# 0084. The Flatpak

- **Status:** proposed (0.7.0, 2026-10-23), implemented on `flatpak`; the maintainer accepts it, and reopens D18, by merging the pull request
- **Date:** 2026-10-23
- **Deciders:** maintainer
- **Amends:** [ADR 0009](0009-packaging-and-release.md) (the Flatpak manifest is now built), [ADR 0028](0028-release-cycle-and-installers.md) (the Flatpak is a release package and a release gate)

## Context

D18 (2026-10-10) chose an AppImage, a `.deb` and an `.rpm` from our own repositories, and the `.tar.gz`, with "no Flatpak for now". ADR 0009 kept a manifest in `eng/packaging/flatpak` that nothing built: an IDE in a sandbox has to reach the host's SDK and git, which needed testing first.

Immutable distributions (Fedora Silverblue and Kinoite, Bazzite, SteamOS, Endless) install desktop apps as Flatpaks. Their `/usr` is read-only, so the `.rpm` needs `rpm-ostree install` and a reboot, and the `.deb` doesn't apply. The AppImage works but doesn't show up in the software center and needs FUSE or `--appimage-extract-and-run`.

What the sandbox has, checked on org.freedesktop.Platform 25.08 (Bazzite, 2026-10-23):
- ICU 77, OpenSSL 3, fontconfig, X11, libsecret, zlib, bash, curl, tar, ssh and gpg: enough for the Native AOT shell and for framework-dependent .NET hosts.
- No git, and no .NET. With `--filesystem=host` the host's home and other folders are the sandbox's, but its `/usr` is the runtime's (the host's is under `/run/host`, linked against the host's libraries). So `/usr/share/dotnet`, `/usr/lib/dotnet` and the host's git aren't there.
- A .NET SDK in `~/.dotnet` (dotnet-install, which is what Install .NET does on Linux, ADR 0080) runs in the sandbox: `dotnet --list-runtimes`, `dotnet new console` and `dotnet build` work.
- `flatpak-spawn --host` runs host programs, but gives them no controlling terminal: a host bash in the integrated terminal has no job control ("cannot set terminal process group", `tty` fails).

## Decision

**A Flatpak of every release** (nightly and stable), `io.github.stavroskasidis.Codalus`, as a single-file bundle on the GitHub release: `codalus-<version>-linux-x64.flatpak` and `-linux-arm64.flatpak`. `flatpak install --user <file>` installs it, and its runtime comes from Flathub (`--runtime-repo`).

**The manifest** (`eng/packaging/flatpak/io.github.stavroskasidis.Codalus.yml`) packages the release's `.tar.gz` as it is, like the AUR package, on org.freedesktop.Platform 25.08:
- **git is built in**, from the kernel.org release tarball (pinned and checksummed; 2.56.0 without Perl, Python, Tcl/Tk or Rust).
- **.NET is the user's `~/.dotnet`.** The `codalus` command is `codalus-flatpak.sh`, which sets `DOTNET_ROOT` to `~/.dotnet` (unless one is set) and puts it on the `PATH`, so the hosts' app hosts find their runtime. The first-run setup's Install .NET already installs there. A .NET SDK extension from Flathub (`org.freedesktop.Sdk.Extension.dotnet*`) isn't used: it lags the releases the hosts need (.NET 11 release candidates today), and the user's own SDK is what their solutions build with on every other install.
- **docker and podman run on the host**: `/app/libexec/host-tools/docker` and `podman` are `host-tool.sh`, which runs the host's program of that name through `flatpak-spawn --host`. The container CLIs talk to a daemon or to user namespaces the sandbox can't reach. At startup, `codalus-flatpak.sh` asks the host which of the two it has (one `flatpak-spawn`, about 20 ms) and puts only those on the `PATH`: the IDE takes the first engine it finds, and a docker shim with no docker behind it hid the host's podman in the first smoke run.
- **`SHELL` is bash.** Flatpak sets `SHELL=/bin/sh`, which is the runtime's bash in POSIX mode: it reads no `~/.bashrc`, so the terminal and the login `PATH` (`LoginShellPath`) missed what the user's startup files add. The launcher sets `/usr/bin/bash` instead (the runtime has no zsh or fish).
- **Permissions:** `--filesystem=host` (projects can be anywhere) and `--filesystem=/tmp` (the host's `/tmp`, not a private one: host programs get the IDE's paths, such as a container's bind mounts), `--share=network` (NuGet, AI providers, the update check), `--socket=x11` and `--device=dri` (Avalonia draws through X11, XWayland on Wayland), `--socket=ssh-auth` (git over SSH), `--allow=devel` (netcoredbg uses ptrace, which the sandbox's seccomp filter otherwise refuses), `org.freedesktop.Flatpak` (`flatpak-spawn --host`) and `org.freedesktop.secrets` (SecretStorage's libsecret).
- AppStream metadata (`io.github.stavroskasidis.Codalus.metainfo.xml`) and the desktop entry with the app id as its icon, so software centers list it.

**Updates:** a new `InstallKind.Flatpak`, detected by `/.flatpak-info` at the sandbox's root. Velopack can't replace files under `/app`, and a bundle installed from a file has no remote for `flatpak update`, so the IDE says that a release is out, with Download Page (the release's page), like the zip and the `.tar.gz`.

**Built and tested in the pipeline:** the `flatpak` job (`linux-x64` and `linux-arm64`) takes the `packages` job's `.tar.gz`, builds the bundle with flatpak-builder (`eng/flatpak.sh`), installs it, runs `codalus --version` and `git --version` in it, checks the host-tool commands, and uninstalls it. A release publishes only when it passes, and the bundles go out with the other packages (and into `SHA256SUMS.txt`).

## Consequences

- Bazzite, Silverblue and SteamOS users install without layering packages or FUSE. Other distributions can use it too, or keep the `.deb`, `.rpm`, AUR package or AppImage.
- A single-file bundle doesn't update itself: `flatpak update` updates an install from a remote only. Until it is on Flathub or our own Flatpak repository, a new release means installing the new bundle (the IDE's notification links the release). Then `InstallKind.Flatpak` says "flatpak update" instead.
- The integrated terminal runs bash from the runtime, inside the sandbox: dotnet and git work there, and the host's own programs (`rpm-ostree`, `toolbox`) don't.
- The full smoke test doesn't run on the Flatpak in CI: `--version` and git prove the bundle, and the app inside is the `.tar.gz` that the `packages` job smoke-tests.

## Deferred

- `TODO(issue)`: a host shell in the integrated terminal. It needs a pseudo-terminal on the host side (what `host-spawn` does), since `flatpak-spawn --host` gives the program none.
- `TODO(issue)`: Flathub, or a Flatpak repository next to the apt and dnf ones on GitHub Pages (`eng/linux-repos.sh`), so that `flatpak update` updates installs. Flathub needs the maintainer's account and its review of `--filesystem=host` and `org.freedesktop.Flatpak`.
- `TODO(issue)`: the full smoke test on the Flatpak in CI (`eng/smoke-test.sh --packages`), with the steps that need the host's tools (containers, debugging older .NET) checked or skipped there.
