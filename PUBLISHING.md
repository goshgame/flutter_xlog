# Publishing checklist

Run all commands from this directory:

```bash
dart pub get
dart analyze
dart pub publish --dry-run
```

Before running `dart pub publish`, confirm:

- Confirm that you own `flutter_xlog_ffi` on pub.dev and that the version in
  `pubspec.yaml` is higher than the latest published version.
- `pubspec.yaml` points to the final public repository, homepage, and issue tracker.
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
