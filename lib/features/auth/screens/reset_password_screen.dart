import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/user_session.dart';
import '../../../core/services/driver_session.dart';
import 'password_reset_success_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.mobileNumber,
    this.isDriver = false,
  });

  /// Already normalized to `+63XXXXXXXXXX` — identifies which account's
  /// password gets updated. Passed down from ForgotPasswordScreen through
  /// OtpVerificationScreen.
  final String mobileNumber;

  /// Whether this flow is resetting a driver account (updates
  /// [DriverSession]) instead of a commuter account (updates
  /// [UserSession]).
  final bool isDriver;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  final RegExp _hasUppercase = RegExp(r'[A-Z]');
  final RegExp _hasLowercase = RegExp(r'[a-z]');
  final RegExp _hasDigit = RegExp(r'\d');
  final RegExp _hasSpecialChar = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\];]');

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'Enter your new password';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (password.contains(' ')) {
      return 'Password cannot contain spaces';
    }
    if (!_hasUppercase.hasMatch(password)) {
      return 'Password must include an uppercase letter';
    }
    if (!_hasLowercase.hasMatch(password)) {
      return 'Password must include a lowercase letter';
    }
    if (!_hasDigit.hasMatch(password)) {
      return 'Password must include a number';
    }
    if (!_hasSpecialChar.hasMatch(password)) {
      return 'Password must include a special character';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final confirm = value ?? '';

    if (confirm.isEmpty) {
      return 'Confirm your password';
    }
    if (confirm != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  void _resetPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    // TODO: Replace with your API call once a backend exists.
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    // Make sure we're updating whatever's actually persisted, not stale
    // in-memory fields from earlier in the app's lifetime.
    if (widget.isDriver) {
      await DriverSession.instance.loadFromPrefs();
    } else {
      await UserSession.instance.loadFromPrefs();
    }

    final success = widget.isDriver
        ? await DriverSession.instance.resetPassword(
            mobileNumber: widget.mobileNumber,
            newPassword: _passwordController.text,
          )
        : await UserSession.instance.resetPassword(
            mobileNumber: widget.mobileNumber,
            newPassword: _passwordController.text,
          );

    if (!mounted) return;

    if (!success) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong updating your password. Please try again.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = false;
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PasswordResetSuccessScreen(isDriver: widget.isDriver),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF2F2F2),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE23F3F), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE23F3F), width: 1.5),
      ),
      errorStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE23F3F),
      ),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: AppColors.logoBlue,
        ),
        onPressed: onToggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 20,
          ),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppColors.settingsTileBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.lock_reset,
                    color: AppColors.logoBlue,
                    size: 36,
                  ),
                ),

                const SizedBox(height: 24),

                const Text(
                  "Reset Password",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  "Create a new password for your account.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 32),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _inputDecoration(
                    hint: "New Password",
                    obscure: _obscurePassword,
                    onToggle: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  validator: _validatePassword,
                  onChanged: (_) {
                    // Re-validate confirm password as the user edits password
                    if (_confirmPasswordController.text.isNotEmpty) {
                      _formKey.currentState?.validate();
                    }
                  },
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: _inputDecoration(
                    hint: "Confirm Password",
                    obscure: _obscureConfirmPassword,
                    onToggle: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                  validator: _validateConfirmPassword,
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.splashBackground,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            "RESET PASSWORD",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
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
}