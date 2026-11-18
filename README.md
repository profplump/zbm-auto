# zbm-auto

A custom [ZFSBootMenu](https://github.com/zbm-dev/zfsbootmenu) (ZBM) build
that tracks failed boot attempts per boot environment (BE) and
automatically redirects `bootfs` to a known-good fallback BE after too many
failures in a row -- no user interaction required.

This repo builds:

- a ZBM initramfs with extra hooks that record boot attempts and perform
  the rollback redirect, and
- `zbmefi`, a small post-boot command-line tool for managing the rollback
  state (marking a boot as successful, blessing a fallback BE) from inside
  the booted OS.

This is a tool for people who already run ZFS-on-root with ZFSBootMenu and
are comfortable building and deploying their own EFI boot chain. It assumes
familiarity with ZFS boot environments, EFI boot variables, and
ZFSBootMenu's own build process.

## How it works

- Every boot, a hook records an attempt counter (keyed by the booting BE's
  ZFS GUID) into EFI NVRAM, then increments it.
- If the counter reaches the failure threshold (2, hard-coded in
  `hooks/boot-sel.d/10-record-boot-attempt.sh`) and a fallback BE has
  been configured, ZBM sets `bootfs` to that fallback and reboots
  immediately instead of continuing to boot the failing BE.
- Once your OS boots successfully, you (or your own automation) run
  `zbmefi --attempt` to reset that BE's counter back to `0`. Nothing does
  this for you automatically -- see "Marking a boot successful" below.
- A separate NVRAM variable, `ZBM.ROLLBACK`, holds the GUID of the fallback
  BE. It's set with `zbmefi --rollback` and is only ever read, never
  written, by the initramfs side.

All state lives in plain EFI NVRAM variables under one vendor GUID; nothing
is written to disk, and nothing depends on the OS you're running as long as
it can call `efivar`.

## Requirements

- A ZFS-on-root system that boots via [ZFSBootMenu](https://github.com/zbm-dev/zfsbootmenu)
  and UEFI (not BIOS/legacy boot).
- `efivar`-capable firmware (standard on essentially all x86_64 UEFI
  systems).
- Podman or Docker, to run the container-based ZBM build.
- Git, with submodule support, to fetch the pinned ZFSBootMenu checkout.

## Building

```sh
git clone --recurse-submodules <this-repo-url>
cd zbm-auto
./build.sh
```

`build.sh` builds the local container image from `Dockerfile`, then
runs the pinned ZFSBootMenu builder (`zfsbootmenu/`, a submodule)
against this directory as the build directory. Output lands in
`./build/` (an EFI bundle, kernel, and initramfs -- exact contents
depend on your `config.yaml`).

If you cloned without `--recurse-submodules`, run
`git submodule update --init` first.

Anything you pass to `./build.sh` is forwarded to the container's
`build-init.sh` / `generate-zbm`; run `build-init.sh -h` inside the image
for the full list of options (EFI signing, split kernel/initramfs output,
etc).

To add packages to the build image (for example, a different EFI tool),
extend `EXTRA_PACKAGES` in `Dockerfile`.

## Deploying

Deployment is the same as any other ZFSBootMenu EFI build: copy the EFI
bundle from `build/` to your EFI System Partition (ESP) and register it
as a boot entry (`efibootmgr`, or your firmware's boot manager), or let
your existing ZBM installation process do it. This repo doesn't script
that step, since it's identical to deploying upstream ZBM and your layout
(single vs. mirrored ESPs, `efibootmgr` flags, etc.) is specific to your
system.

`config.yaml` sets `zbm.timeout=1`, a 1-second auto-boot countdown.
The expected use of this boot automation tool tool is unattended, so don't
wait long for users. Be aware that the rollback hooks only function in
automatic mode and do not affect user-driven usage of ZBM

## Using `zbmefi`

`zbmefi` is a self-contained POSIX shell script (no bashisms, no
dependency on the rest of this repo) meant to run from inside your booted
OS. It needs `efivar`, `findmnt`, and the `zfs` userland tools available
on your running system.

```
Usage: zbmefi [--guid <guid>] [--attempt] [--rollback]

  --guid <guid>   Target this BE's guid instead of the running BE
  --attempt       Reset the target's attempt counter to 0 (mark success)
  --rollback      Set ZBM.ROLLBACK to the target's guid (bless it)
```

With no flags, it prints the current rollback target and the attempt
counter for the running (or `--guid`-specified) BE -- useful for checking
the mechanism is actually armed.

### Marking a boot successful

Nothing resets a BE's attempt counter automatically. After confirming a
boot environment is good, run:

```sh
zbmefi --attempt
```

Typically you'd wire this into whatever already confirms your system is
healthy after boot -- a systemd unit gated on reaching `multi-user.target`,
a health check in your own startup scripts, etc. This repo intentionally
doesn't make that decision for you.

### Choosing a fallback BE

Pick a BE you trust (usually your current, known-good one) and bless it:

```sh
zbmefi --rollback
```

This sets `ZBM.ROLLBACK` to the *running* BE's GUID by default; pass
`--guid <guid>` to bless a different BE instead. Until this is set, the
rollback mechanism is inert -- boots are still counted, but nothing will
ever redirect `bootfs`.

### Checking rollback state from the initramfs side

`ZBM.ROLLBACK`'s presence and validity is logged on every boot (not just
failures), specifically so a missing or stale value gets noticed early.
Check the ESP-backed boot log (`boot.log` / `boot.last` in the root of your
ESP) or `efivar -p` the vendor GUID's variables directly for details.

## Troubleshooting

Every hook logs to a boot log on the ESP (`boot.log` for the current boot,
`boot.last` for the previous one), falling back to stderr if the ESP isn't
mounted. Each build stamps a random build ID into that log so you can
confirm what's actually installed matches what you expect, independent of
how it got onto the ESP.

If rollback never seems to trigger, check in order:
1. `zbmefi` with no flags -- does it show a resolved `ZBM.ROLLBACK` BE?
2. The boot log -- does `ZBM.ROLLBACK` resolve to a real dataset there too?
3. Is `zbm.timeout` still set low enough to take the auto-boot path?

## License

MIT -- see [`LICENSE`](LICENSE). ZFSBootMenu itself is also MIT-licensed
