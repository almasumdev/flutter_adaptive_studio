import 'dart:io';

import 'package:flutter_adaptive_studio/src/platform/ios/pbxproj_editor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A representative slice of a Flutter `project.pbxproj`: three base configs
/// (Debug/Release/Profile) plus the standard per-flavor copies (`*-dev`). The
/// `-dev` configs vary on purpose — Debug-dev has no app-icon key (insert path),
/// Release-dev already sets it to `AppIcon` (replace path), Profile-dev quotes
/// its name and has no key.
const _pbxproj = '''
// !\$*UTF8*\$!
{
	objects = {
/* Begin XCBuildConfiguration section */
		97C1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CLANG_ENABLE_MODULES = YES;
			};
			name = Debug;
		};
		97C2 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
			};
			name = Release;
		};
		97C3 /* Profile */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
			};
			name = Profile;
		};
		A001 /* Debug-dev */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CLANG_ENABLE_MODULES = YES;
				INFOPLIST_FILE = Runner/Info.plist;
			};
			name = "Debug-dev";
		};
		A002 /* Release-dev */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				INFOPLIST_FILE = Runner/Info.plist;
			};
			name = "Release-dev";
		};
		A003 /* Profile-dev */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				INFOPLIST_FILE = Runner/Info.plist;
			};
			name = "Profile-dev";
		};
/* End XCBuildConfiguration section */
	};
}
''';

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fas_pbx_');
    path = p.join(dir.path, 'project.pbxproj');
    File(path).writeAsStringSync(_pbxproj);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  int braces(String s, String ch) => ch.allMatches(s).length;

  test('sets the app-icon name on every -dev config, inserting or replacing',
      () {
    final result = PbxprojEditor(path).setAppIcon('dev', 'AppIcon-dev');

    expect(result.changed, isTrue);
    expect(result.matched, isTrue);
    expect(result.configs,
        containsAll(['Debug-dev', 'Release-dev', 'Profile-dev']));
    expect(result.configs.length, 3);

    final out = File(path).readAsStringSync();
    // All three flavor configs now point at the flavor set (quoted).
    expect(
        'ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-dev";'
            .allMatches(out)
            .length,
        3);
    // Base configs are untouched (still the unquoted default).
    expect(
        'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'.allMatches(out).length,
        3);
    // Structure preserved.
    expect(braces(out, '{'), braces(_pbxproj, '{'));
    expect(braces(out, '}'), braces(_pbxproj, '}'));

    // The pristine original is backed up beside the file.
    expect(result.backupPath, '$path.bak');
    expect(File('$path.bak').readAsStringSync(), _pbxproj);
  });

  test('is idempotent — a second run rewrites nothing', () {
    PbxprojEditor(path).setAppIcon('dev', 'AppIcon-dev');
    final after1 = File(path).readAsStringSync();

    final second = PbxprojEditor(path).setAppIcon('dev', 'AppIcon-dev');
    expect(second.matched, isTrue); // still finds the configs
    expect(second.changed, isFalse); // but writes nothing
    expect(File(path).readAsStringSync(), after1);
  });

  test('onlyConfigs (from a scheme) overrides the naming convention', () {
    // Scheme says this flavor builds only Release-dev — so Debug-dev/Profile-dev
    // must be left alone even though they match the `-dev` suffix.
    final result = PbxprojEditor(path)
        .setAppIcon('dev', 'AppIcon-dev', onlyConfigs: {'Release-dev'});
    expect(result.configs, ['Release-dev']);
    final out = File(path).readAsStringSync();
    expect('= "AppIcon-dev";'.allMatches(out).length, 1);
  });

  test(
      'insertIfMissing: false (revert reset) only touches configs with the key',
      () {
    // Of the three -dev configs, only Release-dev carries the key in the
    // fixture, so a reset-style call changes exactly that one.
    final result = PbxprojEditor(path)
        .setAppIcon('dev', 'AppIcon', insertIfMissing: false);
    expect(result.configs, ['Release-dev']);
    final out = File(path).readAsStringSync();
    // Debug-dev / Profile-dev still have no app-icon key (none was inserted):
    // the only ASSETCATALOG lines are the 3 base + the reset Release-dev = 4.
    expect('ASSETCATALOG_COMPILER_APPICON_NAME'.allMatches(out).length, 4);
  });

  test('no matching flavor configs → no change, no backup, reports nothing',
      () {
    final result = PbxprojEditor(path).setAppIcon('prod', 'AppIcon-prod');
    expect(result.matched, isFalse);
    expect(result.changed, isFalse);
    expect(result.configs, isEmpty);
    expect(File(path).readAsStringSync(), _pbxproj); // untouched
    expect(File('$path.bak').existsSync(), isFalse);
  });

  test('missing pbxproj is handled gracefully', () {
    final result = PbxprojEditor(p.join(dir.path, 'nope.pbxproj'))
        .setAppIcon('dev', 'AppIcon-dev');
    expect(result.matched, isFalse);
    expect(result.changed, isFalse);
  });
}
