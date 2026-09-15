import 'package:test/test.dart';

import '../../hook/cargo_dependencies.dart';

void main() {
  group('parseCargoDependencies', () {
    test('returns dependencies from each rule without tracking targets', () {
      const contents =
          '/build/libxelis_flutter.dylib: /source/src/lib.rs '
          '/source/src/api/wallet.rs\n'
          '/build/libxelis_flutter.a: /source/Cargo.toml\n'
          '/source/src/lib.rs:\n';

      expect(parseCargoDependencies(contents), [
        '/source/src/lib.rs',
        '/source/src/api/wallet.rs',
        '/source/Cargo.toml',
      ]);
    });

    test('decodes escaped spaces in Unix dependency paths', () {
      const contents =
          r'/build/my\ app/libxelis_flutter.dylib: '
          r'/source/my\ wallet/src/lib.rs /source/my\ wallet/Cargo.toml';

      expect(parseCargoDependencies(contents), [
        '/source/my wallet/src/lib.rs',
        '/source/my wallet/Cargo.toml',
      ]);
    });

    test('preserves Windows separators and ignores the target drive colon', () {
      const contents =
          r'C:\build\libxelis_flutter.dll: '
          r'C:\source\wallet\src\lib.rs C:\source\wallet\src\api\wallet.rs';

      expect(parseCargoDependencies(contents), [
        r'C:\source\wallet\src\lib.rs',
        r'C:\source\wallet\src\api\wallet.rs',
      ]);
    });

    test('decodes spaces while preserving Windows path separators', () {
      const contents =
          r'C:\my\ app\build\libxelis_flutter.dll: '
          r'C:\source\my\ wallet\src\lib.rs '
          r'C:\source\my\ wallet\Cargo.toml';

      expect(parseCargoDependencies(contents), [
        r'C:\source\my wallet\src\lib.rs',
        r'C:\source\my wallet\Cargo.toml',
      ]);
    });

    test('preserves a literal backslash adjacent to an escaped space', () {
      const contents =
          r'/build/libxelis_flutter.dylib: '
          r'/source/name\\ with\ space.rs /source/name\segment.rs';

      expect(parseCargoDependencies(contents), [
        r'/source/name\ with space.rs',
        r'/source/name\segment.rs',
      ]);
    });

    test('preserves literal hashes, dollar signs, and dependency colons', () {
      const contents =
          r'/build/libxelis_flutter.dylib: '
          r'/source/hash#dollar$/src/lib:generated.rs '
          r'/source/escaped\ #$\ name.rs';

      expect(parseCargoDependencies(contents), [
        r'/source/hash#dollar$/src/lib:generated.rs',
        r'/source/escaped #$ name.rs',
      ]);
    });

    test('preserves literal tabs inside dependency paths', () {
      const contents =
          '/build/libxelis_flutter.dylib: '
          '/source/name\twith-tab.rs /source/src/lib.rs';

      expect(parseCargoDependencies(contents), [
        '/source/name\twith-tab.rs',
        '/source/src/lib.rs',
      ]);
    });

    test('accepts CRLF rules and skips empty lines and target-only rules', () {
      const contents =
          '\r\n'
          r'C:\build\libxelis_flutter.dll: C:\source\src\lib.rs'
          '\r\n'
          r'C:\build\libxelis_flutter.lib: C:\source\Cargo.toml'
          '\r\n'
          r'C:\source\src\lib.rs:'
          '\r\n\r\n';

      expect(parseCargoDependencies(contents), [
        r'C:\source\src\lib.rs',
        r'C:\source\Cargo.toml',
      ]);
    });
  });
}
