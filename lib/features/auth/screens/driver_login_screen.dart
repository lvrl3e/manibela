import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/driver_operations_log.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/utils/phone_utils.dart';
import '../../driver/screens/driver_dashboard_screen.dart';
import '../../driver/screens/driver_history_screen.dart';
import '../../driver/screens/driver_notifications_screen.dart';
import 'forgot_password_screen.dart';
import 'role_selection_screen.dart';

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _phoneController =
      TextEditingController(text: '+63');

  final TextEditingController _passwordController =
      TextEditingController();

  bool _isPasswordObscured = true;
  bool _isLoading = false;

  final RegExp _phoneRegExp = RegExp(r'^\+63\d{10}$');

  // =========================================================================
  // PHONE VALIDATION
  // =========================================================================

  String? _validatePhone(String? value) {
    final phone = value?.trim().replaceAll(' ', '') ?? '';

    if (phone.isEmpty) {
      return 'Please enter your mobile number';
    }

    if (!phone.startsWith('+63')) {
      return 'Mobile number must start with +63';
    }

    if (!_phoneRegExp.hasMatch(phone)) {
      return 'Enter a valid 10-digit mobile number';
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

    try {
      // ---------------------------------------------------------------------
      // LOAD SAVED DRIVER SESSION
      // ---------------------------------------------------------------------

      await DriverSession.instance.loadFromPrefs();

      // ---------------------------------------------------------------------
      // DEMO ACCOUNT
      // ---------------------------------------------------------------------

      await DriverSession.instance.ensureDemoAccountSeeded();

      // ---------------------------------------------------------------------
      // NORMALIZE PHONE NUMBER
      // ---------------------------------------------------------------------

      final normalizedPhone = PhoneUtils.toE164(
        _phoneController.text.trim(),
      );

      // ---------------------------------------------------------------------
      // CHECK REGISTERED DRIVER
      // ---------------------------------------------------------------------

      if (!DriverSession.instance.isRegistered(normalizedPhone)) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "This number isn't registered. "
              "Contact your operator to get a driver account.",
            ),
          ),
        );

        return;
      }

      // ---------------------------------------------------------------------
      // VERIFY PASSWORD
      // ---------------------------------------------------------------------

      final credentialsValid =
          DriverSession.instance.verifyCredentials(
        mobileNumber: normalizedPhone,
        password: _passwordController.text,
      );

      if (!credentialsValid) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Incorrect mobile number or password.',
            ),
          ),
        );

        return;
      }

      // ---------------------------------------------------------------------
      // SAVE DRIVER LOGIN
      // ---------------------------------------------------------------------

      await DriverSession.instance.logIn(
        mobileNumber: normalizedPhone,
      );

      // ---------------------------------------------------------------------
      // LOAD DRIVER DATA
      // ---------------------------------------------------------------------

      await DriverHistoryScreen.loadFromPrefs();
      await DriverNotificationsScreen.loadFromPrefs();
      await DriverOperationsLog.loadFromPrefs();

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
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Login failed. Please try again.\n$e',
          ),
        ),
      );
    }
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
            ),

            child: Form(
              key: _formKey,

              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,

                children: [
                  // =========================================================
                  // LOGO
                  // =========================================================

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
                          style: TextStyle(
                            color: AppColors.logoBlue,
                          ),
                        ),

                        TextSpan(
                          text: 'App',
                          style: TextStyle(
                            color: AppColors.logoRed,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // =========================================================
                  // TITLE
                  // =========================================================

                  const Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(height: 4),

                  const Text(
                    'Log In as Driver',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // =========================================================
                  // PHONE NUMBER
                  // =========================================================

                  TextFormField(
                    controller: _phoneController,

                    keyboardType: TextInputType.phone,

                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),

                    decoration: InputDecoration(
                      hintText: '+63XXXXXXXXXX',

                      hintStyle: const TextStyle(
                        color: Colors.black26,
                        fontWeight: FontWeight.w600,
                      ),

                      prefixIcon: const Icon(
                        Icons.phone_outlined,
                        color: AppColors.logoBlue,
                      ),

                      filled: true,

                      fillColor: AppColors.inputFieldFill,

                      contentPadding:
                          const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),

                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),

                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.logoBlue,
                          width: 1.5,
                        ),
                      ),

                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),

                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),

                    validator: _validatePhone,
                  ),

                  const SizedBox(height: 16),

                  // =========================================================
                  // PASSWORD
                  // =========================================================

                  TextFormField(
                    controller: _passwordController,

                    obscureText: _isPasswordObscured,

                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),

                    decoration: InputDecoration(
                      hintText: 'Password',

                      hintStyle: const TextStyle(
                        color: Colors.black26,
                        fontWeight: FontWeight.w700,
                      ),

                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.logoBlue,
                      ),

                      filled: true,

                      fillColor: AppColors.inputFieldFill,

                      contentPadding:
                          const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),

                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),

                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.logoBlue,
                          width: 1.5,
                        ),
                      ),

                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),

                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),

                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordObscured
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.logoBlue,
                        ),

                        onPressed: () {
                          setState(() {
                            _isPasswordObscured =
                                !_isPasswordObscured;
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

                  const SizedBox(height: 8),

                  // =========================================================
                  // FORGOT PASSWORD
                  // =========================================================

                  Align(
                    alignment: Alignment.centerRight,

                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(
                              isDriver: true,
                            ),
                          ),
                        );
                      },

                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.logoBlue,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // =========================================================
                  // LOGIN BUTTON
                  // =========================================================

                  SizedBox(
                    width: double.infinity,
                    height: 52,

                    child: ElevatedButton(
                      onPressed:
                          _isLoading ? null : _handleLogin,

                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.splashBackground,

                        disabledBackgroundColor:
                            AppColors.splashBackground
                                .withOpacity(0.7),

                        elevation: 0,

                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(16),
                        ),
                      ),

                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,

                              child:
                                  CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Log In',

                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // =========================================================
                  // DEMO ACCOUNT
                  // =========================================================

                  Container(
                    width: double.infinity,

                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),

                    decoration: BoxDecoration(
                      color: AppColors.qrTileBg,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),

                    child: const Text(
                      'Demo driver account\n'
                      '09171234567 · Driver@123',

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

                  // =========================================================
                  // BACK TO WELCOME
                  // =========================================================

                  GestureDetector(
                    onTap: () {
                      Navigator.pushAndRemoveUntil(
                        context,

                        MaterialPageRoute(
                          builder: (_) =>
                              const RoleSelectionScreen(),
                        ),

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

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}