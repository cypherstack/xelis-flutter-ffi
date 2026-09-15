import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:logging/logging.dart';

import 'cargo_dependencies.dart';

/// Flutter native assets build hook.
///
/// Flutter runs this for every target platform/architecture during
/// `flutter run` / `flutter build` (and `flutter test`). It compiles the Rust
/// crate in `rust/` with Cargo (via rustup, using the toolchain and targets
/// pinned in `rust/rust-toolchain.toml`) and registers the resulting dynamic
/// library as a code asset so Flutter bundles it with the app.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // Keep the builder's assets, but replace its dependency list: version 1.0.6
    // splits Cargo's escaped paths on spaces and registers nonexistent files.
    final rustOutput = BuildOutputBuilder();
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      // Dart library (relative to lib/) that owns the generated FFI bindings.
      assetName: 'src/frb_generated.io.dart',
      // Fail loudly if Cargo.toml and Cargo.lock disagree instead of silently
      // re-resolving dependencies on the consumer's machine.
      extraCargoBuildArgs: const ['--locked'],
      // `input.config.code` throws when a hook run has no code assets (e.g. a
      // data-assets-only invocation), so check `buildCodeAssets` first, exactly
      // like native_toolchain_rust does before it touches the code config.
      extraCargoEnvironmentVariables: input.config.buildCodeAssets
          ? {
              ..._androidMinSdkToolchain(input.config.code),
              ..._androidPageSizeFlags(input.config.code),
            }
          : const <String, String>{},
    ).run(input: input, output: rustOutput, logger: _logger());

    for (final asset in rustOutput.build().assets.code) {
      output.assets.code.add(asset);
      final library = File.fromUri(asset.file!);
      final filename = library.uri.pathSegments.last;
      final depInfo = File.fromUri(
        library.parent.uri.resolve(
          '${filename.substring(0, filename.lastIndexOf('.'))}.d',
        ),
      );
      output.dependencies.addAll([
        for (final path in parseCargoDependencies(await depInfo.readAsString()))
          input.packageRoot.resolveUri(Uri.file(path)),
      ]);
    }

    // Cargo's dep-info does not list the crate configuration. Register it
    // too, so dependency/feature/toolchain changes invalidate the cached build.
    output.dependencies.addAll([
      for (final file in ['Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'])
        input.packageRoot.resolve('rust/$file'),
    ]);
  });
}

/// native_toolchain_rust's default logger runs at CONFIG level and dumps the
/// complete process environment (including any proxy URLs) into the build
/// output, which Flutter keeps under `.dart_tool/hooks_runner/**/stdout.txt`.
/// Log at INFO and above only: the cargo invocation and its outcome.
Logger _logger() {
  return Logger.detached('xelis_flutter.rust')
    ..level = Level.INFO
    ..onRecord.listen((record) {
      final sink = record.level >= Level.WARNING ? stderr : stdout;
      sink.writeln('[${record.level.name}] ${record.message}');
      if (record.error != null) sink.writeln(record.error);
      if (record.stackTrace != null) sink.writeln(record.stackTrace);
    });
}

/// native_toolchain_rust compiles and links Android targets with the NDK's
/// `<triple>35-clang` wrappers, i.e. against API level 35, regardless of the
/// app's `minSdk`. That lets the linker accept libc symbols that do not exist
/// on older devices, where `dlopen` would then fail at runtime. Cargokit (the
/// previous build system) linked against `minSdk`; restore that behaviour by
/// pointing CC/CXX/linker at the wrappers for the API level Flutter passes in.
/// Falls back to native_toolchain_rust's defaults if the wrappers are missing.
Map<String, String> _androidMinSdkToolchain(CodeConfig code) {
  if (code.targetOS != OS.android) return const {};
  final cCompiler = code.cCompiler;
  if (cCompiler == null) return const {};

  final rustTriple = switch (code.targetArchitecture) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.arm => 'armv7-linux-androideabi',
    Architecture.x64 => 'x86_64-linux-android',
    _ => null,
  };
  if (rustTriple == null) return const {};
  // The NDK names its armv7 wrappers differently from the Rust target triple.
  final ndkTriple = rustTriple == 'armv7-linux-androideabi'
      ? 'armv7a-linux-androideabi'
      : rustTriple;

  final api = code.android.targetNdkApi;
  final binDir = File.fromUri(cCompiler.compiler).parent.path;
  final suffix = Platform.isWindows ? '.cmd' : '';
  final prefix = '$binDir${Platform.pathSeparator}$ndkTriple$api';
  final clang = '$prefix-clang$suffix';
  final clangxx = '$prefix-clang++$suffix';
  if (!File(clang).existsSync() || !File(clangxx).existsSync()) {
    return const {};
  }

  final envTriple = rustTriple.replaceAll('-', '_');
  return {
    'CC_$envTriple': clang,
    'CXX_$envTriple': clangxx,
    'CARGO_TARGET_${envTriple.toUpperCase()}_LINKER': clang,
  };
}

/// 64-bit Android libraries must be 16 KB page aligned (Google Play requires it
/// for apps targeting Android 15+). rustc adds no linker flag for this and the
/// NDK linker only defaults to 16 KB from r28 on, so force it regardless of
/// which NDK Flutter picked. Hooks strip RUSTFLAGS from the environment, so the
/// per-target cargo variable is the only one that applies here.
Map<String, String> _androidPageSizeFlags(CodeConfig code) {
  if (code.targetOS != OS.android) return const {};
  final envTriple = switch (code.targetArchitecture) {
    Architecture.arm64 => 'AARCH64_LINUX_ANDROID',
    Architecture.x64 => 'X86_64_LINUX_ANDROID',
    _ => null,
  };
  if (envTriple == null) return const {};
  return {
    'CARGO_TARGET_${envTriple}_RUSTFLAGS':
        '-C link-arg=-Wl,-z,max-page-size=16384',
  };
}
