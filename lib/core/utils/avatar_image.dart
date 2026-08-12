import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/api_client.dart';

/// Picks the right image source for an avatar: a locally-staged
/// [photoPath] (freshly picked on a settings screen, not saved yet) wins
/// if present, since it's the most recent thing the user did; otherwise
/// the uploaded [photoUrl] (resolved to a full URL); otherwise null —
/// callers should fall back to a placeholder icon. Screens outside of
/// settings never have a [photoPath] to pass, so they always just get
/// [photoUrl].
ImageProvider? avatarImageProvider({String? photoUrl, String? photoPath}) {
  if (photoPath != null && photoPath.isNotEmpty) {
    return FileImage(File(photoPath));
  }
  if (photoUrl != null && photoUrl.isNotEmpty) {
    return NetworkImage(ApiClient.resolveUrl(photoUrl));
  }
  return null;
}
