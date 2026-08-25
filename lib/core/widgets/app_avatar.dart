import 'package:flutter/material.dart';

import '../utils/avatar_image.dart';

/// A circular avatar backed by [avatarImageProvider], showing [fallback]
/// whenever there's no photo *or* the photo fails to load — a broken/
/// 404ing URL is common enough to design for deliberately, not just a
/// theoretical edge case: any account with a profile photo uploaded
/// before the backend's migration from local disk to Cloudinary storage
/// has a photoUrl pointing at a file that no longer exists (Render's
/// local disk doesn't survive a redeploy), and every future dead link —
/// deleted Cloudinary asset, brief network hiccup — hits the same path.
/// [Image.errorBuilder] is what makes that automatic: unlike
/// CircleAvatar's backgroundImage (which has no built-in load-failure
/// fallback — that has to be wired up by hand per call site with
/// onBackgroundImageError + setState) or DecorationImage (no error
/// callback at all), this repaints [fallback] the moment the image
/// fails, no per-screen state management needed.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.size,
    required this.fallback,
    this.photoUrl,
    this.photoPath,
    this.backgroundColor = const Color(0xFFD9D9D9),
    this.border,
    this.boxShadow,
  });

  final double size;
  final Widget fallback;
  final String? photoUrl;
  final String? photoPath;
  final Color backgroundColor;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final image = avatarImageProvider(photoUrl: photoUrl, photoPath: photoPath);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: border,
        boxShadow: boxShadow,
      ),
      child: image == null
          ? Center(child: fallback)
          : ClipOval(
              child: Image(
                image: image,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(child: fallback),
              ),
            ),
    );
  }
}
