# Publishing checklist

Run all commands from this directory:

```bash
dart pub get
dart analyze
dart pub publish --dry-run
```

Before running `dart pub publish`, confirm:

- `flutter_xlog` already exists on pub.dev and dry-run reported the latest
  published version as `0.1.1`. Publish only if you own that package and bump
  this package above the published version; otherwise rename the package before
  publishing.
- `pubspec.yaml` points to the final public repository, homepage, and issue tracker.
- Replace the placeholder `https://github.com/your-org/flutter_xlog` URLs before publishing.
- `LICENSE` contains the final copyright holder.
- `NOTICE` has been reviewed against the license terms of all bundled native binaries.
- `README.md` describes supported platforms, bundled artifacts, setup, and lifecycle usage.
- `dart pub publish --dry-run` does not include local caches such as `.gradle`, `.cxx`, `.dart_tool`, or `build_tools/.cache`.
- Android `arm64-v8a` native libraries were built with 16 KB page-size compatibility.
- The example app runs on at least one Android device/emulator and one iOS simulator/device.

Publish:

```bash
dart pub publish
```

Pub versions are long-lived. Prefer publishing a new patch version if a release
needs correction after upload.
