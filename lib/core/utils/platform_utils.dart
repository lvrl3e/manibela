import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether this build is running on a desktop OS (Windows/Linux/macOS).
///
/// `image_picker` has no built-in webcam capture there — `ImageSource
/// .camera` only works on desktop if a custom `cameraDelegate` is
/// registered, which this app doesn't do — so desktop UIs should only
/// offer gallery/file picking, not a "Take Photo" option. Web is
/// excluded: it gets camera access through the browser's own `<input
/// capture>` support, which `image_picker_for_web` already handles.
bool get isDesktopPlatform {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
