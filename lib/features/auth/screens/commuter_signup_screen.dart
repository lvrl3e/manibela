import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/legal_text.dart';
import '../../../core/services/api_client.dart';
import '../../../core/utils/date_only.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/legal_document_dialog.dart';
import 'commuter_login_screen.dart';
import 'commuter_otp_verification_screen.dart';
import 'role_selection_screen.dart';

class CommuterSignUpScreen extends StatefulWidget {
  const CommuterSignUpScreen({super.key});

  @override
  State<CommuterSignUpScreen> createState() => _CommuterSignUpScreenState();
}

class _CommuterSignUpScreenState extends State<CommuterSignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  // Date of birth is set via the picker below, not typed — assigning
  // _dobController.text directly doesn't trigger the field's own
  // didChange/autovalidate the way typing does, so _pickDateOfBirth calls
  // this field's own validate() afterward. A dedicated key instead of the
  // whole form's _formKey keeps that scoped to just this field, not every
  // field in the form (see the other TextFormFields' own autovalidateMode
  // for why that matters).
  final _dobFieldKey = GlobalKey<FormFieldState<String>>();

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();

  bool _isPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;

  DateTime? _dateOfBirth;

  bool _agreedToTerms = false;
  bool _showTermsError = false;
  bool _isLoading = false;

  // See CommuterLoginScreen's matching field for why.
  bool _hasAttemptedSubmit = false;

  // Matches the Terms & Conditions' eligibility clause (legal_text.dart)
  // and the age-confirmation checkbox on the ID-verification step right
  // after this screen — also enforced server-side in
  // verifySignupOtpSchema (backend/src/routes/commuter.ts), since a
  // client-side check alone doesn't stop a direct API call.
  static const int _minAge = 18;

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

  // Only letters, spaces, hyphens, apostrophes and periods (e.g. "Jr.")
  final RegExp _nameRegExp = RegExp(r"^[a-zA-Z\u00C0-\u017F' .-]+$");

  // The 10-digit national number typed after the field's own fixed "+63"
  // prefix (e.g. 9171234567) \u2014 matches CommuterLoginScreen's own
  // _phoneRegExp exactly.
  final RegExp _phoneRegExp = RegExp(r'^9\d{9}$');

  final RegExp _hasUppercase = RegExp(r'[A-Z]');
  final RegExp _hasLowercase = RegExp(r'[a-z]');
  final RegExp _hasDigit = RegExp(r'\d');
  final RegExp _hasSpecialChar = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\];]');

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _dobController.dispose();
    _termsTapRecognizer.dispose();
    _privacyTapRecognizer.dispose();
    super.dispose();
  }

  String? _validateFullName(String? value) {
    final name = value?.trim() ?? '';

    // Empty never shows a red "required" message while just typing — see
    // CommuterLoginScreen's matching field for why.
    if (name.isEmpty) {
      return _hasAttemptedSubmit ? 'Please enter your full name' : null;
    }
    if (name.length < 2) {
      return 'Full name must be at least 2 characters';
    }
    if (!_nameRegExp.hasMatch(name)) {
      return 'Full name can only contain letters';
    }
    if (!name.contains(' ')) {
      return 'Please enter your first and last name';
    }
    return null;
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

  String? _validatePassword(String? value) {
    final password = value ?? '';

    // Empty never shows a red "required" message while just typing — see
    // CommuterLoginScreen's matching field for why.
    if (password.isEmpty) {
      return _hasAttemptedSubmit ? 'Please enter a password' : null;
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

    // Empty never shows a red "required" message while just typing — see
    // CommuterLoginScreen's matching field for why.
    if (confirm.isEmpty) {
      return _hasAttemptedSubmit ? 'Please confirm your password' : null;
    }
    // Distinct from a genuine mismatch below — "Passwords do not match"
    // reads as wrong/confusing when there's nothing in Password yet to
    // compare against.
    if (_passwordController.text.isEmpty) {
      return 'Enter your password above first';
    }
    if (confirm != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  String? _validateDateOfBirth(String? _) {
    final value = _dateOfBirth;
    // Empty never shows a red "required" message while just typing — see
    // CommuterLoginScreen's matching field for why.
    if (value == null) {
      return _hasAttemptedSubmit ? 'Date of birth is required' : null;
    }
    final now = DateTime.now();
    if (value.isAfter(now)) {
      return 'Date of birth cannot be in the future';
    }
    final age = _calculateAge(value, now);
    if (age < _minAge) {
      return 'You must be at least $_minAge years old';
    }
    if (age > 120) {
      return 'Please enter a valid date of birth';
    }
    return null;
  }

  int _calculateAge(DateTime dob, DateTime now) {
    int age = now.year - dob.year;
    final hasHadBirthdayThisYear =
        (now.month > dob.month) || (now.month == dob.month && now.day >= dob.day);
    if (!hasHadBirthdayThisYear) age--;
    return age;
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dobController.text = DateOnly.displayDDMMYYYY(picked);
      });
      _dobFieldKey.currentState?.validate();
    }
  }

  void _handleSignUp() async {
    _hasAttemptedSubmit = true;
    final isFormValid = _formKey.currentState?.validate() ?? false;

    setState(() {
      _showTermsError = !_agreedToTerms;
    });

    if (!isFormValid || !_agreedToTerms) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final normalizedPhone = PhoneUtils.toE164(_phoneController.text.trim());

    try {
      // No account gets created yet — this only requests a code against
      // the number itself. The account is only actually created once
      // that code is verified, on CommuterOtpVerificationScreen, so
      // abandoning the flow here never leaves a "registered" account
      // behind.
      await ApiClient.post('/api/commuter/send-signup-otp', {
        'mobileNumber': normalizedPhone,
      });

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CommuterOtpVerificationScreen(
            fullName: _fullNameController.text.trim(),
            mobileNumber: normalizedPhone,
            password: _passwordController.text,
            dateOfBirth: _dateOfBirth!,
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

  InputDecoration _fieldDecoration({
    String? hintText,
    Widget? suffixIcon,
    // See CommuterLoginScreen's matching field for why this goes through
    // prefixIcon rather than InputDecoration's own prefixText (which
    // silently doesn't render on this app's TextFormFields).
    String? prefixText,
  }) {
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
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              // Deliberately not set here — see CommuterLoginScreen's
              // matching Form for why (Form-wide autovalidation triggers
              // every field, not just the one being typed in). Each
              // TextFormField below sets its own instead.
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),

                  // App Logo
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

                  // Title
                  const Text(
                    'Sign Up',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sign Up as Commuter',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Full Name Input
                  TextFormField(
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    controller: _fullNameController,
                    keyboardType: TextInputType.name,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    decoration: _fieldDecoration(hintText: 'Full Name'),
                    validator: _validateFullName,
                  ),
                  const SizedBox(height: 16),

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
                  const SizedBox(height: 16),

                  // Password Input
                  TextFormField(
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    controller: _passwordController,
                    obscureText: _isPasswordObscured,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    decoration: _fieldDecoration(
                      hintText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordObscured
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.logoBlue,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordObscured = !_isPasswordObscured;
                          });
                        },
                      ),
                    ),
                    validator: _validatePassword,
                    onChanged: (_) {
                      // Re-validate confirm password as the user edits password
                      if (_confirmPasswordController.text.isNotEmpty) {
                        _formKey.currentState?.validate();
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password Input
                  TextFormField(
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    controller: _confirmPasswordController,
                    obscureText: _isConfirmPasswordObscured,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    decoration: _fieldDecoration(
                      hintText: 'Confirm Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isConfirmPasswordObscured
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.logoBlue,
                        ),
                        onPressed: () {
                          setState(() {
                            _isConfirmPasswordObscured = !_isConfirmPasswordObscured;
                          });
                        },
                      ),
                    ),
                    validator: _validateConfirmPassword,
                  ),
                  const SizedBox(height: 16),

                  // Date of Birth Input
                  TextFormField(
                    key: _dobFieldKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    controller: _dobController,
                    readOnly: true,
                    onTap: _pickDateOfBirth,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    decoration: _fieldDecoration(
                      hintText: 'Date of Birth (DD/MM/YYYY)',
                      suffixIcon: const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.logoBlue,
                        size: 20,
                      ),
                    ),
                    validator: _validateDateOfBirth,
                  ),
                  const SizedBox(height: 16),

                  // Terms & Conditions Checkbox
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _agreedToTerms,
                          activeColor: AppColors.logoBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _agreedToTerms = value ?? false;
                              if (_agreedToTerms) _showTermsError = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _agreedToTerms = !_agreedToTerms;
                              if (_agreedToTerms) _showTermsError = false;
                            });
                          },
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                              children: [
                                const TextSpan(text: 'I agree to the '),
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_showTermsError) ...[
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'You must agree to the Terms & Conditions to continue',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE23F3F),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Sign Up Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignUp,
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
                              'Sign Up',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Already have an account
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Already have an account? ",
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CommuterLoginScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Log In",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.logoBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

// Back to Welcome Action
GestureDetector(
  onTap: () {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const RoleSelectionScreen(),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}