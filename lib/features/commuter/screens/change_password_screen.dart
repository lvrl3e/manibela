import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  static const int _minLength = 8;
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');
  static final RegExp _hasSpecialChar = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]\\/;+=~`]');

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateCurrentPassword(String? value) {
    // Trimmed defensively — a stored password can never legitimately
    // contain a space (new passwords are rejected if they do, see
    // _validateNewPassword), so a stray leading/trailing space here can
    // only be an artifact of the on-screen keyboard, not an intentional
    // part of the password.
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'Enter your current password';
    }
    // If there's no password on file yet (e.g. this screen was opened
    // without a signed-up session), skip the match check rather than
    // block the user — the backend is the real source of truth on submit.
    if (UserSession.instance.password != null &&
        v != UserSession.instance.password) {
      return 'Current password is incorrect';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) {
      return 'Enter a new password';
    }
    if (v.length < _minLength) {
      return 'Must be at least $_minLength characters';
    }
    if (v.length > 128) {
      return 'Password is too long';
    }
    if (!_hasUppercase.hasMatch(v)) {
      return 'Must include at least one uppercase letter';
    }
    if (!_hasLowercase.hasMatch(v)) {
      return 'Must include at least one lowercase letter';
    }
    if (!_hasDigit.hasMatch(v)) {
      return 'Must include at least one number';
    }
    if (!_hasSpecialChar.hasMatch(v)) {
      return 'Must include at least one special character';
    }
    if (v.contains(' ')) {
      return 'Password cannot contain spaces';
    }
    if (_currentPasswordController.text.isNotEmpty &&
        v == _currentPasswordController.text) {
      return 'New password must be different from your current password';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) {
      return 'Confirm your new password';
    }
    if (v != _newPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the highlighted fields.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiClient.patch(
        '/api/commuter/me/password',
        {
          'currentPassword': _currentPasswordController.text.trim(),
          'newPassword': _newPasswordController.text,
        },
        token: UserSession.instance.authToken,
      );

      // Keeps the local copy in sync so this screen's own "current
      // password" check (and re-opening it later) still works without
      // needing a fresh login first.
      await UserSession.instance.updatePassword(
        currentPassword: _currentPasswordController.text.trim(),
        newPassword: _newPasswordController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildHeader(),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  children: [
                    _PasswordField(
                      label: 'Current Password',
                      controller: _currentPasswordController,
                      obscureText: _obscureCurrent,
                      hintText: 'Enter your current password',
                      onToggleObscure: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                      validator: _validateCurrentPassword,
                    ),
                    const SizedBox(height: 12),
                    _PasswordField(
                      label: 'New Password',
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      hintText: 'Enter a new password',
                      onToggleObscure: () =>
                          setState(() => _obscureNew = !_obscureNew),
                      validator: _validateNewPassword,
                      onChanged: (_) {
                        // Re-validate confirm field live so a stale "match" state
                        // doesn't linger after the user edits the new password.
                        _formKey.currentState?.validate();
                      },
                    ),
                    const SizedBox(height: 6),
                    const _PasswordRequirementsHint(),
                    const SizedBox(height: 18),
                    _PasswordField(
                      label: 'Confirm New Password',
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      hintText: 'Re-enter your new password',
                      onToggleObscure: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      validator: _validateConfirmPassword,
                    ),
                    const SizedBox(height: 28),
                    _SubmitButton(onTap: _handleSubmit),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===============================================================
  // HEADER
  // ===============================================================
  // Scrolls away with the rest of the content — the back button and the
  // title/subtitle both live inside the yellow banner now.

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, Color(0xFFFFDE7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back, size: 18, color: Colors.black87),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Change Password',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// PASSWORD FIELD
/// -----------------------------------------------------------------------

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.label,
    required this.controller,
    required this.obscureText,
    required this.hintText,
    required this.onToggleObscure,
    required this.validator,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final String hintText;
  final VoidCallback onToggleObscure;
  final String? Function(String?) validator;
  final void Function(String)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E6E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          TextFormField(
            controller: controller,
            obscureText: obscureText,
            validator: validator,
            onChanged: onChanged,
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [],
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.only(top: 6),
              border: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.grey.shade400),
              errorStyle: const TextStyle(
                fontSize: 11,
                color: Color(0xFFD32F2F),
                height: 1.4,
              ),
              suffixIcon: IconButton(
                splashRadius: 18,
                icon: Icon(
                  obscureText
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
                onPressed: onToggleObscure,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// PASSWORD REQUIREMENTS HINT
/// -----------------------------------------------------------------------

class _PasswordRequirementsHint extends StatelessWidget {
  const _PasswordRequirementsHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        'At least 8 characters, with uppercase, lowercase, a number, and a special character.',
        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, height: 1.4),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// SUBMIT BUTTON
/// -----------------------------------------------------------------------

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_reset_rounded, size: 20, color: AppColors.onPrimary),
            SizedBox(width: 10),
            Text(
              'Update Password',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}