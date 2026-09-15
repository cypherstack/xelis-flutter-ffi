import 'dart:io';
to stdout is the intended UX.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as p;

/// The codegen version must match the `flutter_rust_bridge` runtime pinned in
/// pubspec.yaml (and rust/Cargo.toml), so read the exact pin from there.
String getFrbCodegenVersion(String pubspecPath) {
  final content = File(pubspecPath).readAsStringSync();
  final match = RegExp(
    r'^\s+flutter_rust_bridge:\s*["\x27]?(\d+\.\d+\.\d+[^\s"\x27#]*)',
    multiLine: true,
  ).firstMatch(content);
  if (match == null) {
    throw Exception(
      'pubspec.yaml must pin flutter_rust_bridge to an exact version '
      '(e.g. `flutter_rust_bridge: 2.13.0`); could not read it from $pubspecPath',
    );
  }
  return match.group(1)!;
}

String? findLlvmPath() {
  final configuredPath = Platform.environment['LLVM_PATH'];
  if (configuredPath != null && configuredPath.isNotEmpty) {
    return configuredPath;
  }

  try {
    final result = Process.runSync('llvm-config', ['--prefix']);
    if (result.exitCode != 0) return null;

    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  } on ProcessException {
    return null;
  }
}

/// Locates the package root (the directory containing `rust/Cargo.toml` and
/// `flutter_rust_bridge.yaml`). This script lives in `<root>/tool/` and is
/// normally run from that directory, so try the script location first and
/// fall back to the current directory and its parent.
Directory findPackageRoot() {
  final candidates = <Directory>[
    File.fromUri(Platform.script).parent.parent,
    Directory.current.parent,
    Directory.current,
  ];
  for (final dir in candidates) {
    if (File(p.join(dir.path, 'rust', 'Cargo.toml')).existsSync() &&
        File(p.join(dir.path, 'flutter_rust_bridge.yaml')).existsSync()) {
      return dir.absolute;
    }
  }
  throw Exception(
    'Could not find the package root (rust/Cargo.toml + '
    'flutter_rust_bridge.yaml). Run this from the tool/ directory.',
  );
}

Future<void> main() async {
  print('🔧 Starting Flutter Rust Bridge binding generation...');

  try {
    final root = findPackageRoot();
    print('📁 Package root: ${root.path}');
    final version = getFrbCodegenVersion(p.join(root.path, 'pubspec.yaml'));
    print('📦 flutter_rust_bridge_codegen version: $version');

    // Local binary path (inside the package's .dart_tool, which is gitignored)
    final binRoot = Directory(p.join(root.path, '.dart_tool', 'frb_bin'));
    final binPath = p.join(
      binRoot.path,
      'bin',
      'flutter_rust_bridge_codegen${Platform.isWindows ? '.exe' : ''}',
    );
    final bin = File(binPath);

    // Check if installed and version matches
    final alreadyInstalled =
        bin.existsSync() && await _checkFrbVersion(binPath, version);

    if (!alreadyInstalled) {
      print('📥 Installing flutter_rust_bridge_codegen...');
      await binRoot.create(recursive: true);

      final installProcess = await Process.start('cargo', [
        'install',
        'flutter_rust_bridge_codegen',
        '--version',
        version,
        // Build the generator with its published Cargo.lock for reproducibility.
        '--locked',
        '--root',
        binRoot.path,
        if (bin.existsSync()) '--force', // Only force if an old version exists
      ], mode: ProcessStartMode.inheritStdio);

      final exitCode = await installProcess.exitCode;
      if (exitCode != 0) {
        throw Exception('Failed to install flutter_rust_bridge_codegen');
      }
    } else {
      print('✅ flutter_rust_bridge_codegen $version already installed');
    }

    // Prepare Dart output dir
    final dartOutput = Directory(p.join(root.path, 'lib', 'src'));
    if (!dartOutput.existsSync()) {
      await dartOutput.create(recursive: true);
    }

    // Run the codegen from the package root so it picks up
    // flutter_rust_bridge.yaml.
    print('🚀 Running flutter_rust_bridge_codegen...');
    final llvmPath = findLlvmPath();
    if (llvmPath != null) {
      print('🔎 Using LLVM at $llvmPath');
    }
    final process = await Process.start(
      binPath,
      [
        'generate',
        '--rust-root',
        p.join(root.path, 'rust'),
        '--rust-input',
        'crate::api',
        '--dart-output',
        dartOutput.path,
        if (llvmPath != null) ...['--llvm-path', llvmPath],
      ],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );

    final code = await process.exitCode;
    if (code != 0) {
      throw Exception(
        'flutter_rust_bridge_codegen failed with exit code $code',
      );
    }

    print('🎉 Bindings generated successfully!');
  } catch (e, stack) {
    print('❌ Error: $e');
    print(stack);
    exit(1);
  }
}

/// Checks if the binary version matches what we want
Future<bool> _checkFrbVersion(String binPath, String expected) async {
  try {
    final result = await Process.run(binPath, ['--version']);
    final actual = (result.stdout as String).trim();
    return actual.contains(expected);
  } catch (_) {
    return false;
  }
}
