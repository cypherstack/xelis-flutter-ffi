# Xelis Wallet FFI Bindings for Flutter
This repo is set up to be a drop-in library for Flutter applications, allowing easy access to the native Rust wallet methods from `xelis-blockchain` without the need for any rewrites. This is enabled by the `flutter_rust_bridge_codegen` tool, as well as the automated build & dependency conventions used within this repository.

The continued adoption of Genesix features and dev QOL needs for apps are the primary points of focus for this library, helping to facilitate Xelis integration and adoption for the community.

## Compatibility

![Flutter](https://img.shields.io/badge/flutter-3.47.2%2B-blue.svg)
![Rust](https://img.shields.io/badge/rust-1.91.0-orange.svg)

## Getting started

### Requirements

Every machine that builds an app depending on this package needs:

- **Flutter 3.47.2 or newer** (Dart 3.13+). The Rust crate is compiled and bundled by Flutter native assets (build hooks).
- **[rustup](https://rustup.rs).** The first build downloads the pinned toolchain (Rust 1.91.0, minimal profile) and every cross-compilation target listed in `rust/rust-toolchain.toml`; installed, that is roughly 1.9 GB on disk, about 1.4 GB of it for the cross-compilation targets. The list covers all platforms Flutter can target so that a single checkout builds everywhere.
  Cargo must be able to find `rustc`: with a standard rustup install (`~/.cargo/bin` on `PATH`) nothing needs to be done; with Homebrew's rustup add `$(brew --prefix rustup)/bin` to `PATH`, otherwise the build fails with `could not execute process rustc -vV`.
  Builds started from Xcode (Product > Run / Archive) do not see your shell's `PATH`; they get the system one from `/etc/paths`. Homebrew puts only `rustup` itself in `/opt/homebrew/bin` and keeps the `cargo`/`rustc` proxies in its keg, which is on no `PATH`, so the build fails there even though it works in a terminal. Link the proxies into `/usr/local/bin` (always on the system `PATH`) once:

  ```bash
  sudo mkdir -p /usr/local/bin && sudo ln -s "$(brew --prefix rustup)"/bin/* /usr/local/bin/
  ```
- **Windows hosts:** Visual Studio Build Tools with the "Desktop development with C++" workload. The Rust `*-pc-windows-msvc` host toolchain needs its `link.exe`, also for Android-only builds.
- **Android only:** NDK r27 or newer (the NDK Flutter installs by default satisfies this). The library is linked against your app's `minSdk` API level and, for 64-bit ABIs, with 16 KB page alignment regardless of the NDK version.

### Adding the dependency

Add a git dependency to your Flutter app's `pubspec.yaml`:

```yaml
xelis_flutter:
  git:
    url: https://github.com/xelis-project/xelis-flutter-ffi.git
    ref: v0.4.0 # use a release tag; releases track specific xelis-blockchain versions
```

When `flutter run`, `flutter build`, or `flutter test` is invoked, Flutter runs this package's `hook/build.dart`, which compiles the Rust crate for the target platform with Cargo and bundles the resulting library into the app. No CocoaPods, CMake, or Gradle configuration is required on your side.

### Build behaviour worth knowing

- The Rust crate is always compiled with Cargo's release profile, also for Flutter debug builds (build hooks have no notion of the Flutter build mode). The first build of each target architecture takes several minutes; later builds are incremental and the hook only re-runs when Rust sources, `Cargo.toml`, `Cargo.lock`, or `rust-toolchain.toml` change.
- Build artifacts live under the app's `.dart_tool/hooks_runner/`, one Cargo target directory per build configuration (target platform and architecture, and debug and release builds separately), so the first release build after debug builds compiles the crate again. `flutter clean` deletes them all, so the next build starts from scratch. On Windows hosts, `flutter_rust_bridge_hooks` keeps paths short by placing the Cargo target directory under `%TEMP%\frb_native_assets_<hash>` instead; `flutter clean` does not remove those, delete them manually to reclaim disk space.
- The hook runs `cargo build --locked`: a `Cargo.toml` change without a matching `Cargo.lock` update fails the build instead of silently re-resolving dependencies.
- Build hooks run with a filtered environment. Flutter passes through `PATH`, `HOME`, `TMPDIR`/`TEMP`, `ANDROID_HOME`, `ANDROID_NDK*`, and a few OS variables, but not `RUSTUP_HOME`, `CARGO_HOME`, `RUSTFLAGS`, or `CARGO_*`. Non-default rustup/cargo locations configured through those variables are therefore not seen by the build, and the toolchain is installed under `~/.rustup`.
- `flutter test` also runs the hook and installs the host library under `build/native_assets/<macos|linux|windows>/`. On Windows that directory is on `PATH` during the test run, so the bindings load it. On macOS and Linux the bindings look the library up by name and will not find it there; point them at it: `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR=build/native_assets/macos/ flutter test` (use `linux/` on Linux). Tests that never touch Rust are unaffected apart from the hook's compile time.

## Regenerating the bindings

The FFI bindings are committed; there is no need to regenerate them unless you modify the files in `rust/`. Regeneration needs LLVM/Clang (libclang) and `cargo` on `PATH`, plus `rustfmt` for the pinned toolchain, which the minimal profile in `rust/rust-toolchain.toml` does not install:

```bash
rustup component add rustfmt --toolchain 1.91.0
```

Without it the generator still succeeds but writes an unformatted `rust/src/frb_generated.rs`, which shows up as a large spurious diff.

```bash
cd tool
dart run generate_bindings.dart
```

The script locates the package root (the parent of `tool/`), installs the `flutter_rust_bridge_codegen` version matching the `flutter_rust_bridge` pin in `pubspec.yaml` (built with `cargo install --locked`) into the package root's `.dart_tool/frb_bin` on first use, then regenerates the package's `lib/src/` and `rust/src/frb_generated.rs`. It is a separate Dart package on purpose: running it does not trigger this package's build hook, so it keeps working when a Rust API change has made the previously generated `frb_generated.rs` uncompilable.

The script detects LLVM through `llvm-config`. If LLVM is installed in a custom location, set `LLVM_PATH` or pass the path directly to `flutter_rust_bridge_codegen` with `--llvm-path`.

## Usage

In your app's `main` entry point, be sure to initialize the RustLib. This will enable the use of imported bindings anywhere in your app.
```dart
import 'package:xelis_flutter/src/frb_generated.dart' as xelis_flutter; // name required if the app uses multiple FFI libraries

Future<void> main() async {
  await xelis_flutter.RustLib.init();
  // ... Rest of your main() code
}
```

Here is an example of using the api crate through FFI to create a Xelis Wallet instance.
```dart
import 'package:xelis_flutter/src/api/wallet.dart' as x_wallet;
import 'package:xelis_flutter/src/api/network.dart' as x_network;
import 'package:xelis_flutter/src/api/precomputed_tables.dart' as x_tables;

Future<void> createXelisWallet() async {
  final String name = "example-wallet";
  final String directory = "<local app path for xelis files>";
  final String password = "password";

  final wallet = await x_wallet.createXelisWallet(
    name: name,
    directory: directory, // local wallet data on the Rust side will be stored under directory/name/
    password: password,
    network: x_network.Network.mainnet,
    precomputedTablesPath: directory, // precomputed tables will be written to this location
    // lightweight precomputed tables; see PrecomputedTableType for the other variants
    precomputedTableType: const x_tables.PrecomputedTableType.l1Low(),
  );

  final mnemonic = await wallet.getSeed();

  // ... use wallet and mnemonic as required
}
```
