import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/legal_text.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_operations_log.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/utils/date_only.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/legal_document_dialog.dart';
import '../../driver/screens/driver_dashboard_screen.dart';
import 'forgot_password_screen.dart';
import 'role_selection_screen.dart';

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _phoneController = TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  bool _isPasswordObscured = true;
  bool _isLoading = false;
  bool _rememberMe = true;

  // Local PH mobile format: 09 followed by 9 digits (e.g. 09171234567) —
  // matches CommuterLoginScreen's own _phoneRegExp exactly.
  final RegExp _phoneRegExp = RegExp(r'^09\d{9}$');

  // Drivers never see a signup screen (accounts are admin-created) — this
  // is the closest equivalent to a commuter's signup-checkbox moment, so
  // it's a note under the login button instead of a gate before one.
  late final TapGestureRecognizer _termsTapRecognizer = TapGestureRecognizer()
    ..onTap = () => showLegalDocumentDialog(
          context,
          title: 'Terms & Conditions',
          updated: kTermsAndConditionsUpdated,
          body: kTermsAndConditionsText,
        );
  late final TapGestureRecognizer _privacyTapRecognizer = TapGestureRecognizer()
    ..onTap = () => showLegalDocumentDialog(
          context,
          title: 'Privacy Policy',
          updated: kPrivacyPolicyUpdated,
          body: kPrivacyPolicyText,
        );

  // =========================================================================
  // PHONE VALIDATION
  // =========================================================================

  String? _validatePhone(String? value) {
    final phone = value?.trim().replaceAll(' ', '') ?? '';

    if (phone.isEmpty) {
      return 'Please enter your mobile number';
    }

    if (!_phoneRegExp.hasMatch(phone)) {
      return 'Enter a valid number, e.g. 09171234567';
    }

    return null;
  }

  // =========================================================================
  // DISPOSE
  // =========================================================================

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _termsTapRecognizer.dispose();
    _privacyTapRecognizer.dispose();
    super.dispose();
  }

  // =========================================================================
  // LOGIN
  // =========================================================================

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    final normalizedPhone = PhoneUtils.toE164(_phoneController.text.trim());

    try {
      // ---------------------------------------------------------------------
      // LOG IN AGAINST THE BACKEND
      // ---------------------------------------------------------------------

      final response = await ApiClient.post('/api/driver/login', {
        'mobileNumber': normalizedPhone,
        'password': _passwordController.text,
      });

      final driver = response['driver'] as Map<String, dynamic>;
      final dobRaw = driver['dateOfBirth'] as String?;

      // ---------------------------------------------------------------------
      // SAVE DRIVER LOGIN
      // ---------------------------------------------------------------------

      await DriverSession.instance.logIn(
        mobileNumber: driver['mobileNumber'] as String,
        authToken: response['token'] as String,
        driverId: driver['driverId'] as String,
        fullName: driver['fullName'] as String,
        plateNumber: driver['plateNumber'] as String,
        dateOfBirth: DateOnly.tryParse(dobRaw),
        photoUrl: driver['photoUrl'] as String?,
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );

      // ---------------------------------------------------------------------
      // LOAD DRIVER DATA
      // ---------------------------------------------------------------------

      await DriverOperationsLog.loadFromPrefs();
      unawaited(DriverOperationsLog.syncFromBackend());

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // ---------------------------------------------------------------------
      // GO TO DRIVER DASHBOARD
      // ---------------------------------------------------------------------

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const DriverDashboardScreen(),
        ),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  // =========================================================================
  // FIELD DECORATION — matches CommuterLoginScreen's own _fieldDecoration
  // exactly, so both login screens read as the same design.
  // =========================================================================

  InputDecoration _fieldDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(prefixIcon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey.shade100,
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

  // =========================================================================
  // BUILD — same shape as CommuterLoginScreen: brand-colored top with the
  // jeepney logo, then a white rounded card holding the form.
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),

              Image.asset(
                AppAssets.jeepneyLogo,
                width: 140,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.directions_bus_rounded,
                    size: 90,
                    color: AppColors.logoBlue,
                  );
                },
              ),

              const SizedBox(height: 10),

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

              const SizedBox(height: 54),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 25,
                  vertical: 30,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Welcome Back!",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),

                      const SizedBox(height: 5),

                      const Text(
                        "Sign in as Driver",
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                        ),
                      ),

                      const SizedBox(height: 30),

                      const Text(
                        "Phone Number",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _fieldDecoration(
                          hintText: "09XXXXXXXXX",
                          prefixIcon: Icons.phone_outlined,
                        ),
                        validator: _validatePhone,
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        "Password",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: _isPasswordObscured,
                        decoration: _fieldDecoration(
                          hintText: "Enter your password",
                          prefixIcon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordObscured
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordObscured = !_isPasswordObscured;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          InkWell(
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(() => _rememberMe = v ?? true),
                                    activeColor: AppColors.logoBlue,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Remember Me',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(isDriver: true),
                                ),
                              );
                            },
                            child: const Text(
                              "Forgot Password?",
                              style: TextStyle(
                                color: AppColors.logoBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryButtonRed,
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
                                  "LOGIN",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Center(
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                            children: [
                              const TextSpan(text: 'By logging in, you agree to our '),
                              TextSpan(
                                text: 'Terms & Conditions',
                                style: const TextStyle(
                                  color: AppColors.logoBlue,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: _termsTapRecognizer,
                              ),
                              const TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: const TextStyle(
                                  color: AppColors.logoBlue,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: _privacyTapRecognizer,
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Drivers don't self-register (see this screen's own
                      // signup doc comment) — a demo account plus a way
                      // back to role selection replace commuter's "Sign Up"
                      // link here.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.qrTileBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Demo driver account\n09171234567 · Julie@123',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.qrIconColor,
                            height: 1.4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                              (route) => false,
                            );
                          },
                          child: const Text(
                            'Back to Welcome',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.logoBlue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}