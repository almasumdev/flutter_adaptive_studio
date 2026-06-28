/// Reads the Android API level (`Build.VERSION.SDK_INT`) with **no plugin and no
/// third-party dependency** — by calling libc's `__system_property_get` over
/// `dart:ffi`. This is what lets [AdaptiveSplash] gate itself to "where there's
/// no native animated splash" (API < 31) without turning the package into a
/// Flutter plugin (which would drag in Gradle/Kotlin + an iOS podspec and risk
/// build-tooling conflicts in every host app).
///
/// Returns null off Android, or if the property can't be read.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _PropGetNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _PropGetDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

/// Android's `PROP_VALUE_MAX` — the system-property value buffer size.
const int _propValueMax = 92;

int? _cached;
bool _resolved = false;

/// The device's Android API level, or null on non-Android / on failure. Cached
/// after the first successful read.
int? androidSdkInt() {
  if (_resolved) return _cached;
  _resolved = true;
  if (!Platform.isAndroid) return _cached = null;
  try {
    final libc = DynamicLibrary.open('libc.so');
    final getProp = libc
        .lookupFunction<_PropGetNative, _PropGetDart>('__system_property_get');
    final keyPtr = 'ro.build.version.sdk'.toNativeUtf8();
    final valPtr = calloc<Uint8>(_propValueMax).cast<Utf8>();
    try {
      final len = getProp(keyPtr, valPtr);
      if (len <= 0) return _cached = null;
      return _cached = int.tryParse(valPtr.toDartString());
    } finally {
      calloc
        ..free(keyPtr)
        ..free(valPtr);
    }
  } on Object {
    return _cached = null;
  }
}
