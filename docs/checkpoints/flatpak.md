# 0.7 checkpoint: the Flatpak

Date: 2026-10-23. On `flatpak`, off `develop`. Decisions: [ADR 0084](../adr/0084-flatpak.md) (proposed), which amends ADR 0009 and ADR 0028 and reopens D18.

## Done

**The manifest** (`eng/packaging/flatpak/io.github.stavroskasidis.Codalus.yml`): the release's `.tar.gz` on org.freedesktop.Platform 25.08, with git 2.56.0 built from the kernel.org tarball (no Perl, Python, Tcl/Tk or Rust), AppStream metadata, and the desktop entry and icon under the app id.
- `codalus-flatpak.sh` is the `codalus` command: it points `DOTNET_ROOT` at `~/.dotnet` (unless one is set) and puts it on the `PATH`.
- `host-tool.sh` is `/app/libexec/host-tools/docker` and `podman`: the host's program through `flatpak-spawn --host`. The launcher puts on the `PATH` only those the host has, and sets `SHELL` to bash (Flatpak's `/bin/sh` reads no `~/.bashrc`).
- Permissions: the host's files and its `/tmp`, network, X11, DRI, the SSH agent, `--allow=devel` for netcoredbg, `org.freedesktop.Flatpak` and `org.freedesktop.secrets`.

**`eng/flatpak.sh [--test] <version> <packages> [out]`** builds the bundle (`codalus-<version>-linux-<arch>.flatpak`, its runtime from Flathub) and its `SHA256SUMS-flatpak-linux-<arch>.txt`. With `--test`, it installs the bundle for the user, runs `codalus --version` and `git --version` in it, checks the host-tool commands, and uninstalls it.

**The pipeline's `flatpak` job** (`linux-x64`, `linux-arm64`) runs it on the `packages` job's `.tar.gz` and uploads `packages-flatpak-<rid>`, which `publish` takes with the other packages. `publish` now needs it.

**Updates**: `InstallKind.Flatpak`, detected by `/.flatpak-info`, says that a release is out and links its page (a bundle has no remote for `flatpak update`).

**Docs**: the user guide's install table and update settings, the Download page (the file and a Flatpak card), ADR 0084, and the roadmap's D18 and deferred work.

## Validation

Linux (Bazzite, Fedora 44 base, x86_64) only; the `flatpak` job proves linux-x64 and linux-arm64 in CI:
- `eng/flatpak.sh --test` on the 0.7.0-nightly.20261023.532 `.tar.gz`: built (a 107 MB bundle), installed, `Codalus IDE 0.7.0-nightly.20261023.532` / `.NET 11.0.0 on Freedesktop SDK 25.08 (Flatpak runtime) (X64)`, `git version 2.56.0`, uninstalled.
- In the installed sandbox, with the SDK in `~/.dotnet`: `dotnet --list-runtimes` shows 11.0.0-rc.2, `dotnet new console` and `dotnet build` succeed.
- A host bash through `flatpak-spawn --host` in a pseudo-terminal has no controlling terminal ("no job control in this shell"): why the terminal stays in the sandbox.
- **The full smoke test on the installed Flatpak** (`eng/smoke-test.sh` through `flatpak run`, the command sweep skipped as `--packages` does): 89 passed, 1 failed, 12 skipped. The failure is `containers.run`: the host's podman runs the app with `-v <bin>:/app`, which SELinux (Fedora, Bazzite) denies without a `:z` label. `develop`'s `ContainerRuntimeTests` fails the same way on this machine, outside the Flatpak: not the Flatpak's. The skips are Windows-only steps, no Chromium, and the sweep. Aspire passed, through the host's podman.
- The first smoke run found two launcher bugs, both fixed: a `docker` shim with no docker on the host hid podman, and the sandbox's own `/tmp` kept the report (and a container's bind mounts) from the host.
- `dotnet build Codalus.slnx`: no warnings. `dotnet test --solution Codalus.slnx`: 2730 tests, 2585 passed, 6 failed, 139 skipped. Five of the failures fail on unmodified `develop` here too (a .NET 10.0.300 SDK not installed beside 11, podman under SELinux, three Avalonia headless UI checks: IntelliSense popups, menu rows, the data tip). `RemoteShellTests`' remote terminal step is flaky on both (develop 2 of 3, this branch 1 of 5 when run alone). `eng/validate.sh` stops at `eng/get-runtimes.sh` on Bazzite, which has no `dpkg-deb`.
- The website export: 65 files, no broken links.
- actionlint 1.7.7 (with shellcheck) on `.github/`, and shellcheck 0.10.0 on the new scripts: clean.

## Deferred

- `TODO(issue)`: a host shell in the integrated terminal (a pseudo-terminal on the host, as `host-spawn` does).
- `TODO(issue)`: Flathub, or a Flatpak repository beside the apt and dnf ones, so `flatpak update` updates installs.
- `TODO(issue)`: the full smoke test on the Flatpak in CI.
