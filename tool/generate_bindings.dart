import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

/// Get the pinned flutter_rust_bridge_codegen version from Cargo.toml
String getFrbCodegenVersion(String cargoTomlPath) {
  final content = File(cargoTomlPath).readAsStringSync();
  final toml = TomlDocument.parse(content).toMap();
  final section = toml['build-dependencies'] as Map?;
  final frb = section?['flutter_rust_bridge_codegen'];

  if (frb is String) return frb;
  if (frb is Map && frb['version'] != null) return frb['version'] as String;
  return '2.7.1'; // fallback
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

Future<void> main() async {
  print('🔧 Starting Flutter Rust Bridge binding generation...');

  try {
    final root = Directory.current;
    final cargoToml = File(p.join(root.path, 'rust', 'Cargo.toml'));
    if (!cargoToml.existsSync()) {
      throw Exception('Could not find rust/Cargo.toml at project root.');
    }

    final version = getFrbCodegenVersion(cargoToml.path);
    print('📦 flutter_rust_bridge_codegen version: $version');

    // Local binary path
    final binRoot = Directory(p.join('.dart_tool', 'frb_bin'));
    final binPath = p.join(binRoot.path, 'bin', 'flutter_rust_bridge_codegen');
    final bin = File(binPath);

    // Check if installed and version matches
    final alreadyInstalled =
        bin.existsSync() && await _checkFrbVersion(binPath, version);

    if (!alreadyInstalled) {
      print('📥 Installing flutter_rust_bridge_codegen...');
      await binRoot.create(recursive: true);

      final installProcess = await Process.start(
        'cargo',
        [
          'install',
          'flutter_rust_bridge_codegen',
          '--version', version,
          '--root', binRoot.path,
          if (bin.existsSync())
            '--force', // Only force if an old version exists
        ],
        mode: ProcessStartMode.inheritStdio,
      );

      final exitCode = await installProcess.exitCode;
      if (exitCode != 0) {
        throw Exception('Failed to install flutter_rust_bridge_codegen');
      }
    } else {
      print('✅ flutter_rust_bridge_codegen $version already installed');
    }

    // Prepare Dart output dir
    final dartOutput = Directory(p.join('lib', 'src'));
    if (!dartOutput.existsSync()) {
      await dartOutput.create(recursive: true);
    }

    // Run the codegen
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
        'rust',
        '--rust-input',
        'crate::api',
        '--dart-output',
        dartOutput.path,
        if (llvmPath != null) ...['--llvm-path', llvmPath],
      ],
      mode: ProcessStartMode.inheritStdio,
    );

    final code = await process.exitCode;
    if (code != 0) {
      throw Exception(
          'flutter_rust_bridge_codegen failed with exit code $code');
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
