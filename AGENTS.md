# AGENTS.md

Primary agent guidance for this repository lives in [`CLAUDE.md`](CLAUDE.md)
(architecture, hardware model, test harnesses, release process) and
[`CONTRIBUTING.md`](CONTRIBUTING.md) (branching, build, test, lint commands).
Read those first — they are authoritative and not duplicated here.

## Cursor Cloud specific instructions

This is the **Virtual Jaguar libretro core** — an Atari Jaguar emulator built in
C as a libretro shared library. There is no standalone application; the build
output is `virtualjaguar_libretro.so`, loaded by a libretro frontend/harness.

The base VM image already provides everything needed to build, test, lint, and
run: `gcc`, `clang`, `make`, `python3`, `git`. There are **no project-managed
dependencies** (no package manager, no lockfile), so the startup update script
is intentionally a no-op.

### Standard commands (see CONTRIBUTING.md / CLAUDE.md)

- Build: `make -j$(getconf _NPROCESSORS_ONLN)` → `virtualjaguar_libretro.so`.
- Tests: `make test` (relinks with `TEST_EXPORTS=1` for the wide dlsym ABI;
  plain `make` afterwards restores the shipped `retro_*`-only ABI).
- Lint: `bash scripts/c89-lint.sh` and `bash scripts/check-info-version.sh`.

### Non-obvious caveats for this environment

- **`make test` skips the private-ROM checks** (Iron Soldier, Skyhammer, CD
  discs, etc.). `test/roms/private` is a symlink to a ROM tree that lives
  **outside** the repo and is not present on a fresh cloud VM. Those `Skipped
  checks` lines are expected — not failures. The suite still exits 0 and runs
  all self-contained white-box tests.
- **Self-contained end-to-end run:** two public/homebrew ROMs are committed at
  `test/roms/yarc.j64` and `test/roms/jagniccc.j64`, with reference screenshots
  in `test/baselines/`. Use these to prove the core loads a ROM and renders
  without any private corpus.
- **Running the core headlessly:** the core is a libretro `.so`, so it needs a
  frontend. `test/tools/cart_boot_probe` (built from `test/harness/`) is the
  network-free option. `test/regression_test.sh` builds the `miniretro` frontend
  by cloning `github.com/davidgfnet/miniretro` (needs network) and dumps
  screenshots.
- **ImageMagick is NOT preinstalled.** `test/regression_test.sh` uses `compare`
  and `montage` for pixel diffs; without them it falls back to strict byte
  `cmp`, which can report spurious FAILs due to headless vs. host framebuffer
  differences (see the "Headless framebuffer caveat" in `CLAUDE.md`). Install
  `imagemagick` via apt only if you need the diff images.
- **Optional CI lint tools** (`cppcheck`, `editorconfig-checker`/`ec`,
  `clang-tidy`) are advisory gates listed in `CONTRIBUTING.md` and are not
  preinstalled; `apt-get install` them on demand.
- **`gpu_wedge` / crash-detect log lines** when running some demo ROMs headless
  (e.g. `yarc.j64` logs `gpu_wedge` around frame 181) are expected diagnostics
  for GPU-only homebrew under HLE, not a setup or emulator failure — the frame
  still renders and matches the baseline.
- The `jaguar-demos` suite (`make jaguar-demos-smoke`) clones public-domain
  homebrew from `codeberg.org` (network required); it works in this
  environment.
