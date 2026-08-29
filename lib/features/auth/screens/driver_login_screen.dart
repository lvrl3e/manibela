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
  bool _rememberMe = false;

  // See CommuterLoginScreen's matching field for why.
  bool _hasAttemptedSubmit = false;

  // The 10-digit national number typed after the field's own fixed "+63"
  // prefix (e.g. 9171234567) — matches CommuterLoginScreen's own
  // _phoneRegExp exactly.
  final RegExp _phoneRegExp = RegExp(r'^9\d{9}$');

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

  String? _validatePassword(String? value) {
    final password = value ?? '';
    // Empty never shows a red "required" message while just typing — see
    // CommuterLoginScreen's matching field for why.
    if (password.isEmpty) {
      return _hasAttemptedSubmit ? 'Please enter your password' : null;
    }
    return null;
  }

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();
    _suggestLastAccount();
  }

  // DriverSession.lastSuggestedMobileNumber stays on disk even after an
  // explicit logout, but only when Remember Me was checked at that login
  // (see DriverSession.logIn's doc comment) — reload it here so the phone
  // field starts pre-filled with a suggestion instead of making a
  // returning driver retype a number the device already knows, same idea
  // as a browser's remembered-username autofill, without also suggesting
  // an account back after a login that deliberately opted out.
  Future<void> _suggestLastAccount() async {
    await DriverSession.instance.loadFromPrefs();
    final lastNumber = DriverSession.instance.lastSuggestedMobileNumber;
    if (!mounted || lastNumber == null || _phoneController.text.isNotEmpty) return;
    setState(() {
      _phoneController.text = PhoneUtils.national(lastNumber);
    });
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
    setState(() => _hasAttemptedSubmit = true);
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
    IconData? prefixIcon,
    Widget? suffixIcon,
    // See CommuterLoginScreen's matching field for why this goes through
    // prefixIcon rather than InputDecoration's own prefixText.
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixText != null
          ? Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Text(
                prefixText,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            )
          : (prefixIcon != null ? Icon(prefixIcon) : null),
      // See CommuterLoginScreen's matching field for why.
      prefixIconConstraints: prefixText != null ? const BoxConstraints(minWidth: 0, minHeight: 0) : null,
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
                      text: 'Manibela',
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
                  // Deliberately not set here — see CommuterLoginScreen's
                  // matching Form for why (Form-wide autovalidation
                  // triggers every field, not just the one being typed
                  // in). Each TextFormField below sets its own instead.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Welcome!",
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
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _fieldDecoration(
                          hintText: "",
                          prefixIcon: Icons.phone_outlined,
                          prefixText: "+63 ",
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
                        autovalidateMode: AutovalidateMode.onUserInteraction,
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
                        validator: _validatePassword,
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
                      // signup doc comment) — a way back to role selection
                      // replaces commuter's "Sign Up" link here.
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