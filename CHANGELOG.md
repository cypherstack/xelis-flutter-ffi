# 0.4.0

- **Breaking:** the native build moved from Cargokit (podspec / CMake / Gradle FFI plugin) to Flutter native assets: `hook/build.dart` via `flutter_rust_bridge_hooks` and `native_toolchain_rust`. Consumers now need Flutter 3.47.2+ (Dart 3.13+), rustup, and Android NDK r27+ (Windows hosts also need the Visual Studio C++ build tools); nothing else changes on the consumer side (no CocoaPods/CMake/Gradle configuration).
- Removed the `android/`, `ios/`, `macos/`, `linux/`, `windows/`, and `cargokit/` plugin scaffolding; the package is a Dart package with a build hook (`.metadata` now says `package`).
- Bumped `flutter_rust_bridge` to 2.13.0 and regenerated the bindings; bumped `freezed` to 4.0.1 and regenerated the `*.freezed.dart` parts (Dart 3.13 no longer accepts `final` on constructor parameters, which freezed 3 emitted).
- `rust/rust-toolchain.toml` pins Rust 1.91.0 and lists every cross-compilation target; rustup downloads the toolchain (minimal profile) and targets automatically on the first build (roughly 1.9 GB on disk once installed).
- Build behaviour: Rust is always compiled with the release profile (also in Flutter debug builds); artifacts live under the app's `.dart_tool/hooks_runner/`, one Cargo target directory per build configuration (target platform/architecture, debug and release separately), and `flutter clean` removes them (on Windows hosts the Cargo target directory is placed under `%TEMP%\frb_native_assets_<hash>` and is not removed by `flutter clean`); the hook re-runs when Rust sources, `Cargo.toml`, `Cargo.lock` or `rust-toolchain.toml` change.
- The hook runs `cargo build --locked`, links the Android library against the app's `minSdk` API level (as Cargokit did), and forces 16 KB page alignment for 64-bit Android ABIs regardless of the NDK version.
- `flutter test` in a dependent app now runs the hook too and installs the host library under `build/native_assets/<os>/`; on macOS and Linux host tests that call into Rust need `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR=build/native_assets/<os>/` (see README), on Windows it is found automatically.
- The bindings regeneration script is its own Dart package under `tool/`: `cd tool && dart run generate_bindings.dart` (maintainers need `rustup component add rustfmt --toolchain 1.91.0`, since the toolchain now uses the minimal profile). It reads the codegen version from the `flutter_rust_bridge` pin in `pubspec.yaml`; the unused `[build-dependencies]` entry for `flutter_rust_bridge_codegen` was removed from `rust/Cargo.toml`.
- `native_toolchain_rust`, which spawns rustup/cargo on consumer machines, is pinned exactly (1.0.6); the shared `hooks` protocol package stays a range (`^2.1.0`) so apps can combine this package with other native-assets packages.
- Removed the unused `path_provider`, `ffi`, and `plugin_platform_interface` dependencies. Apps that used one of them only through this package must now depend on it directly.

# 0.2.0

- Unified API with Genesix reference bindings post-hard-fork
- Added XSWD bindings
- Removed dangling dependence on xelis_dart_sdk