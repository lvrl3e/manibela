import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/utils/date_only.dart';
import '../../../core/utils/phone_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'commuter_signup_screen.dart';
import 'commuter_verification_status_screen.dart';
import 'forgot_password_screen.dart';
import '../../commuter/screens/commuter_dashboard_screen.dart';
import '../../commuter/screens/commuter_history_screen.dart';
import '../../commuter/screens/notifications_screen.dart';

class CommuterLoginScreen extends StatefulWidget {
  const CommuterLoginScreen({super.key});

  @override
  State<CommuterLoginScreen> createState() => _CommuterLoginScreenState();
}

class _CommuterLoginScreenState extends State<CommuterLoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;

  // False until the first Login tap — an empty field never shows a red
  // "required" message before that (see each _validate*'s own empty
  // check), but the tap itself needs to actually surface what's missing,
  // not just silently no-op. Set true synchronously before that same
  // tap's validate() call, so it takes effect for the very press that
  // set it, not just subsequent ones.
  bool _hasAttemptedSubmit = false;

  // The 10-digit national number typed after the field's own fixed "+63"
  // prefix (e.g. 9171234567) — always starts with 9 for a PH mobile.
  final RegExp _phoneRegExp = RegExp(r'^9\d{9}$');

  @override
  void initState() {
    super.initState();
    _suggestLastAccount();
  }

  // UserSession.lastSuggestedMobileNumber stays on disk even after an
  // explicit logout, but only when Remember Me was checked at that login
  // (see UserSession.logIn's doc comment) — reload it here so the phone
  // field starts pre-filled with a suggestion instead of making a
  // returning commuter retype a number the device already knows, same
  // idea as a browser's remembered-username autofill, without also
  // suggesting an account back after a login that deliberately opted out.
  Future<void> _suggestLastAccount() async {
    await UserSession.instance.loadFromPrefs();
    final lastNumber = UserSession.instance.lastSuggestedMobileNumber;
    if (!mounted || lastNumber == null || phoneController.text.isNotEmpty) return;
    setState(() {
      phoneController.text = PhoneUtils.national(lastNumber);
    });
  }

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim().replaceAll(' ', '') ?? '';

    // Empty never shows a red "required" message while just typing — an
    // emptied field reads as "still editing," not "wrong" — but a Login
    // tap with it still empty needs to actually say so.
    if (phone.isEmpty) {
      return _hasAttemptedSubmit ? 'Please enter your phone number' : null;
    }
    if (!_phoneRegExp.hasMatch(phone)) {
      return 'Enter a valid number, e.g. 9171234567';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';

    // Empty never shows a red "required" message while just typing — see
    // _validatePhone's matching check above.
    if (password.isEmpty) {
      return _hasAttemptedSubmit ? 'Please enter your password' : null;
    }
    if (password.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  void _handleLogin() async {
    setState(() => _hasAttemptedSubmit = true);
    final isFormValid = _formKey.currentState?.validate() ?? false;
    if (!isFormValid) return;

    setState(() {
      _isLoading = true;
    });

    final enteredPhoneE164 = PhoneUtils.toE164(phoneController.text.trim());

    try {
      final response = await ApiClient.post('/api/commuter/login', {
        'mobileNumber': enteredPhoneE164,
        'password': passwordController.text,
      });

      final commuter = response['commuter'] as Map<String, dynamic>;
      final dobRaw = commuter['dateOfBirth'] as String?;

      await UserSession.instance.logIn(
        mobileNumber: commuter['mobileNumber'] as String,
        authToken: response['token'] as String,
        commuterId: commuter['commuterId'] as String,
        fullName: commuter['fullName'] as String,
        dateOfBirth: DateOnly.tryParse(dobRaw),
        photoUrl: commuter['photoUrl'] as String?,
        password: passwordController.text,
        rememberMe: _rememberMe,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('commuterLoggedIn', true);

      // Load this commuter's persisted trip history and notifications
      // before the dashboard ever builds — otherwise they'd briefly render
      // as empty.
      await CommuterHistoryScreen.loadFromPrefs();
      await NotificationsScreen.loadFromPrefs();
      unawaited(CommuterHistoryScreen.syncFromBackend());

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // Clears the whole stack (not just a pushReplacement) so
      // RoleSelectionScreen isn't still sitting underneath — otherwise the
      // phone's back button on the dashboard would pop straight back to
      // it, which looks exactly like getting logged out.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const CommuterDashboardScreen(),
        ),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      // Correct credentials, but the account isn't APPROVED yet — the
      // backend withholds the token entirely in that case (see
      // POST /api/commuter/login) rather than a generic error, so route
      // to the status screen instead of just showing the message. This
      // doubles as the "check again" flow: closing that screen comes
      // back here, and trying to log in again re-runs this same check.
      if (e.statusCode == 403 && e.body?.containsKey('verificationStatus') == true) {
        await UserSession.instance.setPendingVerification(enteredPhoneE164);
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CommuterVerificationStatusScreen(
              status: e.body!['verificationStatus'] as String?,
              mobileNumber: enteredPhoneE164,
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
    // A country-code prefix (e.g. "+63 ") deliberately goes through the
    // prefixIcon slot, not InputDecoration's own prefixText/prefixStyle —
    // verified empirically that prefixText silently doesn't render on
    // this app's TextFormFields (prefixIcon renders fine on the same
    // decoration), so this is the reliable path, not a style choice.
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
      // Prevents Material's default 48px-minimum prefixIcon tap target
      // from padding out a short "+63" into a taller/emptier-looking box
      // than sibling fields that don't have anything in this slot.
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

              const SizedBox(height: 30),

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
                  // Deliberately not set here — Form's own autovalidateMode
                  // validates every descendant field the moment ANY one of
                  // them is touched, not just the field you're actually
                  // typing in. Each TextFormField below sets its own
                  // instead, which Flutter scopes per-field correctly.
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
                        "Sign in as Commuter",
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
                        controller: phoneController,
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
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: _fieldDecoration(
                          hintText: "Enter your password",
                          prefixIcon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                obscurePassword = !obscurePassword;
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
                                  builder: (_) => const ForgotPasswordScreen(),
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

                      const SizedBox(height: 25),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CommuterSignUpScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              "Sign Up",
                              style: TextStyle(
                                color: AppColors.logoBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
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