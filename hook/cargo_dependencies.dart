import 'dart:convert';

/// Reads the top-level `.d` files written by the pinned Cargo toolchain.
///
/// Cargo escapes spaces as `\ `, but leaves backslashes, `#`, and `$` literal.
/// These files are not fully Make-escaped, so unescaping other characters
/// would corrupt paths, particularly on Windows.
Iterable<String> parseCargoDependencies(String contents) {
  final paths = <String>{};
  for (final line in const LineSplitter().convert(contents)) {
    if (line.isEmpty || line.startsWith('#')) continue;

    // A drive letter contains a colon, but only the rule separator is followed
    // by an unescaped space. An empty (phony) rule has no dependencies.
    final separator = line.indexOf(': ');
    if (separator < 0) {
      if (line.trim().isEmpty || line.endsWith(':')) continue;
      throw FormatException('Invalid Cargo dependency rule', line);
    }

    final dependencies = line.substring(separator + 2);
    final path = StringBuffer();
    void addPath() {
      if (path.isNotEmpty) {
        paths.add(path.toString());
        path.clear();
      }
    }

    for (var i = 0; i < dependencies.length; i++) {
      final character = dependencies.codeUnitAt(i);
      if (character == 0x5c &&
          i + 1 < dependencies.length &&
          dependencies.codeUnitAt(i + 1) == 0x20) {
        path.write(' ');
        i++;
      } else if (character == 0x20) {
        addPath();
      } else {
        path.writeCharCode(character);
      }
    }
    addPath();
  }
  return paths;
}
