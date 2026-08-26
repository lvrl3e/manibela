import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/utils/phone_utils.dart';
import 'otp_verification_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.isDriver = false});

  /// Whether this flow is resetting a driver account (checked against
  /// [DriverSession]) instead of a commuter account (checked against
  /// [UserSession]).
  final bool isDriver;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();

  bool _isLoading = false;
  bool _isSubmitted = false;

  // See CommuterLoginScreen's matching field for why.
  bool _hasAttemptedSubmit = false;

  // The 10-digit national number typed after the field's own fixed "+63"
  // prefix (e.g. 9171234567) — matches CommuterLoginScreen's own
  // _phoneRegExp exactly.
  final RegExp _phoneRegExp = RegExp(r'^9\d{9}$');

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim().replaceAll(' ', '') ?? '';

    // Empty never shows a red "required" message while just typing — see
    // CommuterLoginScreen's matching field for why.
    if (phone.isEmpty) {
      return _hasAttemptedSubmit ? 'Please enter your mobile number' : null;
    }
    if (!_phoneRegExp.hasMatch(phone)) {
      return 'Enter a valid number, e.g. 9171234567';
    }
    return null;
  }

  void _handleSendResetLink() async {
    _hasAttemptedSubmit = true;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    final normalizedPhone = PhoneUtils.toE164(_phoneController.text.trim());
    final path = widget.isDriver
        ? '/api/driver/forgot-password'
        : '/api/commuter/forgot-password';

    try {
      await ApiClient.post(path, {'mobileNumber': normalizedPhone});

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OtpVerificationScreen(
            mobileNumber: normalizedPhone,
            isDriver: widget.isDriver,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // prefixText goes through prefixIcon, not InputDecoration's own
  // prefixText/prefixStyle — see CommuterLoginScreen's matching field for
  // why (prefixText silently doesn't render on this app's TextFormFields).
  InputDecoration _fieldDecoration({String? hintText, String? prefixText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Colors.black26,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: prefixText != null
          ? Padding(
              padding: const EdgeInsets.only(left: 20, right: 4),
              child: Text(
                prefixText,
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700),
              ),
            )
          : null,
      // See CommuterLoginScreen's matching field for why.
      prefixIconConstraints: prefixText != null ? const BoxConstraints(minWidth: 0, minHeight: 0) : null,
      filled: true,
      fillColor: const Color(0xFFF2F2F2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Form(
              key: _formKey,
              // Deliberately not set here — see CommuterLoginScreen's
              // matching Form for why. Only one field on this screen, but
              // consistent with every other auth screen regardless.
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Title Logo
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                      children: [
                        TextSpan(
                          text: 'Manibel',
                          style: TextStyle(color: AppColors.logoBlue),
                        ),
                        TextSpan(
                          text: 'App',
                          style: TextStyle(color: AppColors.logoRed),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Icon Badge
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: AppColors.logoBlue,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header Titles
                  const Text(
                    'Forgot Password',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isSubmitted
                        ? 'A reset link has been sent to your registered mobile number.'
                        : 'Enter your registered mobile number and we\'ll send you a code to reset your password.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),

                  if (!_isSubmitted) ...[
                    // Phone Number Input
                    TextFormField(
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                      decoration: _fieldDecoration(hintText: '', prefixText: '+63 '),
                      validator: _validatePhone,
                    ),
                    const SizedBox(height: 24),

                    // Yellow Send Reset Link Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSendResetLink,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE5A800),
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
                                'Send Code',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ] else ...[
                    // Success State
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _isSubmitted = false;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.logoBlue, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Resend Link',
                          style: TextStyle(
                            color: AppColors.logoBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Back to Login Action
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.logoBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}