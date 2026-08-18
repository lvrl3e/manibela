import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Shows [body] (see legal_text.dart) as a scrollable in-app popup —
/// deliberately not a link out to a browser, so a commuter never has to
/// leave the sign-up flow to read it.
Future<void> showLegalDocumentDialog(
  BuildContext context, {
  required String title,
  required String updated,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                updated,
                style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    body,
                    style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.logoBlue),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
