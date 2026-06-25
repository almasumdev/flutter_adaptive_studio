# Themed (light/dark) launcher icons

flutter_adaptive_studio generated two full-colour adaptive icons and wired
`activity-alias` entries (`FasIconLight`, `FasIconDark`) in your
AndroidManifest.xml. Exactly one alias is enabled at a time; switching is done
at runtime by your app.

> ⚠️ Android has **no** automatic "swap launcher icon by system theme". This is
> the only mechanism for two *different full-colour* icons, and it has costs:
> - Toggling an alias can **relaunch** your task — switch in the background
>   (`onStop`) to hide it (the Blinkit/Meesho approach).
> - Shipped aliases are **permanent** — never delete one a user might have
>   enabled, or their icon vanishes.
> - **OEM launchers vary** (Samsung/Xiaomi/OnePlus vs Pixel) and may cache the
>   old icon briefly.
> For a side-effect-free theme-reactive icon, prefer the **monochrome** themed
> icon (Android 13+) — already generated if you supplied `monochrome:`.

## Wiring (3 steps)

1. Move `FasIconSwitcher.kt` into `android/app/src/main/kotlin/<your/package>/`
   and set its `package` to your applicationId.

2. Register the channel in `MainActivity.kt`:

   ```kotlin
   import io.flutter.embedding.android.FlutterActivity
   import io.flutter.embedding.engine.FlutterEngine
   import io.flutter.plugin.common.MethodChannel

   class MainActivity : FlutterActivity() {
       override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
           super.configureFlutterEngine(flutterEngine)
           MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
               "flutter_adaptive_studio/icon").setMethodCallHandler { call, result ->
               if (call.method == "setIcon") {
                   FasIconSwitcher.setIcon(this, call.argument<String>("variant") ?: "Light")
                   result.success(null)
               } else result.notImplemented()
           }
       }
   }
   ```

3. Copy `icon_switcher.dart` into your `lib/` and call it — ideally when the app
   is backgrounded, after detecting the platform brightness:

   ```dart
   final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
   await AdaptiveIconSwitcher.setVariant(dark ? 'Dark' : 'Light');
   ```
