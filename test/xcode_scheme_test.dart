import 'dart:io';

import 'package:flutter_adaptive_studio/src/platform/ios/xcode_scheme.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _scheme = '''
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1510" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForRunning="YES">
            <BuildableReference BlueprintName="Runner" BuildableName="Runner.app"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug-dev" selectedDebuggerIdentifier="Xcode.Debugger.LLDB"/>
   <LaunchAction buildConfiguration="Debug-dev" selectedDebuggerIdentifier="Xcode.Debugger.LLDB"/>
   <ProfileAction buildConfiguration="Release-dev"/>
   <AnalyzeAction buildConfiguration="Debug-dev"/>
   <ArchiveAction buildConfiguration="Release-dev" revealArchiveInOrganizer="YES"/>
</Scheme>
''';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fas_scheme_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('collects the distinct build configurations a scheme references', () {
    final path = p.join(dir.path, 'dev.xcscheme');
    File(path).writeAsStringSync(_scheme);
    expect(XcodeScheme.buildConfigs(path), {'Debug-dev', 'Release-dev'});
  });

  test('missing or malformed scheme → empty (caller falls back to convention)',
      () {
    expect(
        XcodeScheme.buildConfigs(p.join(dir.path, 'nope.xcscheme')), isEmpty);
    final bad = p.join(dir.path, 'bad.xcscheme');
    File(bad).writeAsStringSync('<Scheme><not closed');
    expect(XcodeScheme.buildConfigs(bad), isEmpty);
  });
}
