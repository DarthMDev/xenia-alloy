<p align="center">
    <img height="192px" src="https://raw.githubusercontent.com/xenia-canary/xenia/master/assets/icon/256.png" />
</p>

<h1 align="center">Xenia Canary for macOS — native Metal build</h1>

<p align="center">
An unofficial fork of <a href="https://github.com/xenia-canary/xenia-canary">Xenia Canary</a>
that runs natively on Apple Silicon Macs, with an ARM64 JIT and a Metal GPU backend.<br>
No CrossOver, no Rosetta, no Wine.
</p>

> **This is not an official Xenia project.** It is not affiliated with or endorsed by the
> Xenia or Xenia Canary teams. Please **do not report issues from this fork to the Xenia
> developers** — open them here instead.

## How it started

It began with a simple wish: to play **Fable II** on a Mac. The Metal backend from
[wmarti's Xenia macOS port](https://github.com/wmarti/xenia-mac) (Xenia Edge macOS v0.2.1)
showed that Xenia on Metal was possible, but it was built on an older emulator core.
This fork moves that backend onto the current Xenia Canary core, uses Canary's ARM64 JIT,
and fixes the remaining CPU, memory, and GPU problems until real games became
playable — first Fable II, then Forza Horizon.

## Game status

Tested on an Apple M4 with macOS 27. Anything not listed here is untested — reports are welcome.

| Game | Title ID | Status | Notes |
| --- | --- | --- | --- |
| Fable II | 4D5307F1 | **Playable** | ~20–28 FPS. Hero, dog and clothing textures correct. `metal_force_linear_filter = true` recommended. |
| Forza Horizon | 4D5309C9 | **Playable** | Races complete, ~20–29 FPS. Short stutters while new shaders compile. A crash after returning to the menu several times is under investigation. |
| Project Gotham Racing 4 | 4D5307F9 | **Playable** | Runs without visible issues, ~28–30 FPS over a 20+ minute session. Tested with the World disc. |
| Saints Row | 545107D1 | **In-game** | Free roam works, ~28 FPS on average with occasional drops. Minor graphical glitches; audio can lag behind in cutscenes after a hitch. The zero page is unprotected automatically for this title (fixes the character creation crash). Tested with the World disc. |
| The Darkness | 545407EE | **In-game** | Menus and gameplay work. The screen band, flickering polygons and the crosshatch (shadow acne) pattern are fixed. ~28 FPS (the zero-copy shared memory is replaced with an on-demand copy for this title, float24 depth conversion is enabled). Remaining: a small flickering rectangle in the bottom-right corner, scenes can look slightly overexposed. Tested with the USA/Europe disc, v1.0. |

## What is in this build

**Platform (macOS / Apple Silicon)**
- Native ARM64 application bundle with the Canary ARM64 JIT (W^X via `MAP_JIT`,
  correct handling of large guest functions).
- Guest memory mapped into one contiguous reservation, with support for 16 KB host
  pages. Guest page protection is reapplied when memory is reused without a host
  commit, which fixes crashes in games that reload modules (Forza Horizon).
- macOS exception handling for MMIO and write watches (`SA_NODEFER`, correct
  register-state write-back), which fixes audio (XMA) hangs and "Disc Read Error" loops.
- Cocoa windowing, file picker, and application packaging. Logs go to
  `~/.local/share/Xenia/logs` rather than into the signed app bundle.

**Metal GPU backend**
- Guest shaders are translated DXBC → DXIL → Metal with Apple's Metal Shader Converter.
  An experimental SPIR-V → SPIRV-Cross → MSL path is available
  (`metal_use_spirvcross`, needed for future iOS work).
- Utility shaders are compiled from Canary's XeSL sources for MSL. Fixes include
  `first_one_bit_high` and the EDRAM MSAA sample layout.
- Pipeline binary archive (a disk cache) plus multithreaded shader and pipeline compilation.
- Tessellation and geometry emulation, with a depth-bias workaround for tessellated
  depth-only passes (`metal_tessellated_depth_only_bias`).
- Alpha to coverage is emulated in the pixel shader like on D3D12 and Vulkan, not
  applied by the hardware a second time.
- **GPU → CPU synchronization for games that read GPU results back.** Some games (for
  example Fable II, which generates character textures on the GPU and reads them back)
  need the CPU to wait for the GPU before a fence becomes visible. The following options
  control this:
  - `metal_sync_gpu_writes_for_guest`: enable for all games.
  - `metal_sync_gpu_writes_for_guest_titles`: list of title IDs to enable it for. The
    default is Fable II only, so other games are not slowed down.
  - `metal_sync_gpu_writes_skip_after_frames`: skip the wait for targets that are
    re-rendered every frame (GPU-only data). Default 90; 0 always waits.

Windows and Linux code paths from upstream are kept, and the project still builds with
the standard Canary CMake setup on those platforms (not tested by this fork).

## Building

Requirements: Apple Silicon Mac, macOS 15 or newer, Apple Command Line Tools (full
Xcode is not needed), CMake 3.20+, Ninja, Python 3.9+.

```sh
git clone --recursive <this repository>
cd <repository folder>
./tools/build_macos.sh          # fetches pinned dependencies, builds, bundles and signs
python3 tools/test_macos.py     # optional: base, CPU and Metal tests
open build-macos-arm64/bin/macOS/xenia_canary.app
```

Use `JOBS=2 ./tools/build_macos.sh` to reduce the load while building. The build
produces an ad-hoc signed app. Pinned dependency versions are listed in
[docs/macos-source-lock.json](docs/macos-source-lock.json).

You need your own legally obtained game dumps. Open them with **File → Open**. Settings
and saves are stored in `~/.local/share/Xenia` (change this with `--storage_root=...`).

## Debugging and diagnostics

- `--metal_perf_log=true`: once per second, logs FPS, the slowest frame, draw calls,
  GPU wait time, and time spent compiling pipelines and shaders. Useful for finding
  stutter sources.
- `--log_level=3`: verbose logging, including guest XEX heap operations.
- `--a64_function_map_path=<file>`: writes the host address range and source map of
  every JIT-compiled guest function. This lets you map host addresses from macOS
  `sample` / Instruments profiles back to guest (PowerPC) code:
  `sample xenia_canary 10 -file profile.txt`.
- `--metal_sync_gpu_writes_for_guest=true`: try this if a game shows missing or corrupted
  textures that the game generates at runtime.
- `python3 tools/test_macos.py --metal-only`: checks Metal shader compilation and
  GPU compute on your machine.

## Credits

- **The Xenia team**: Ben Vanik and all contributors to the original
  [Xenia](https://github.com/xenia-project/xenia) emulator.
- **The Xenia Canary team and contributors**: the emulator core, ARM64 JIT and
  everything this fork is built on.
- **wmarti**: the [Xenia macOS port](https://github.com/wmarti/xenia-mac) (Xenia Edge
  macOS), whose Metal backend, metal-cpp and Metal Shader Converter integration are the
  foundation of the GPU side here.
- Apple's [metal-cpp](https://developer.apple.com/metal/cpp/) and Metal Shader
  Converter, Microsoft's DirectX Shader Compiler, and Khronos's SPIRV-Cross.

Most of the porting and debugging work in this fork was done together with **Claude**
(Anthropic's large language model, Opus 5.5), which wrote and reviewed much of the code.
Every change was tested by hand on real games.

## License

Xenia is licensed under the BSD license — see [LICENSE](LICENSE). This fork keeps that
license and all original copyright notices. Third-party components keep their own
licenses. Discussing or sharing pirated games is not allowed.
