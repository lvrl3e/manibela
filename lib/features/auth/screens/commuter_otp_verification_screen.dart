import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import 'commuter_verification_screen.dart';

/// Verifies the mobile number entered during commuter sign up. No account
/// exists yet at this point — [fullName]/[mobileNumber]/[password] are
/// just what was typed into the sign-up form, carried here in memory. The
/// account only actually gets created once the code checks out (see
/// _verifyCode, which calls /api/commuter/signup with the code attached),
/// so abandoning the flow before this screen succeeds never leaves a
/// "registered" account behind. Continues into [CommuterVerificationScreen]
/// (ID upload) on success.
class CommuterOtpVerificationScreen extends StatefulWidget {
  const CommuterOtpVerificationScreen({
    super.key,
    required this.fullName,
    required this.mobileNumber,
    required this.password,
  });

  final String fullName;

  /// Already normalized to `+63XXXXXXXXXX`.
  final String mobileNumber;

  final String password;

  @override
  State<CommuterOtpVerificationScreen> createState() => _CommuterOtpVerificationScreenState();
}

class _CommuterOtpVerificationScreenState extends State<CommuterOtpVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _hasError = false;
  String? _errorText;

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _clearError() {
    if (_hasError) {
      setState(() {
        _hasError = false;
        _errorText = null;
      });
    }
  }

  void _verifyCode() async {
    // Make sure every box has a single digit and nothing was skipped
    final incompleteIndex = _controllers.indexWhere((c) => c.text.trim().isEmpty);

    if (incompleteIndex != -1 || _code.length != 6) {
      setState(() {
        _hasError = true;
        _errorText = 'Please enter the full 6-digit verification code';
      });
      FocusScope.of(context).requestFocus(
        _focusNodes[incompleteIndex == -1 ? 0 : incompleteIndex],
      );
      return;
    }

    if (!RegExp(r'^\d{6}$').hasMatch(_code)) {
      setState(() {
        _hasError = true;
        _errorText = 'Code must contain numbers only';
      });
      return;
    }

    setState(() {
      _hasError = false;
      _errorText = null;
      _isLoading = true;
    });

    try {
      // This is the actual account-creation call — the code is only
      // accepted here, atomically with creating the row, so there's no
      // window where "verified" and "registered" can disagree.
      final response = await ApiClient.post('/api/commuter/signup', {
        'fullName': widget.fullName,
        'mobileNumber': widget.mobileNumber,
        'password': widget.password,
        'code': _code,
      });

      final commuter = response['commuter'] as Map<String, dynamic>;

      await UserSession.instance.signUp(
        fullName: commuter['fullName'] as String,
        mobileNumber: commuter['mobileNumber'] as String,
        password: widget.password,
        commuterId: commuter['commuterId'] as String,
        authToken: response['token'] as String,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const CommuterVerificationScreen(),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorText = e.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleResend() async {
    for (var controller in _controllers) {
      controller.clear();
    }
    setState(() {
      _hasError = false;
      _errorText = null;
    });
    FocusScope.of(context).requestFocus(_focusNodes[0]);

    try {
      await ApiClient.post('/api/commuter/send-signup-otp', {
        'mobileNumber': widget.mobileNumber,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP code resent.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 48,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          counterText: "",
          filled: true,
          fillColor: const Color(0xFFF2F2F2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: _hasError ? const Color(0xFFE23F3F) : Colors.transparent,
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: _hasError ? const Color(0xFFE23F3F) : AppColors.secondary,
              width: 1.5,
            ),
          ),
        ),
        onChanged: (value) {
          _clearError();

          if (value.isNotEmpty && index < 5) {
            FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
          }

          if (value.isEmpty && index > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
          }
        },
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
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 20),

              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: 35,
                  color: AppColors.secondary,
                ),
              ),

              const SizedBox(height: 25),

              const Text(
                "Verify Your Number",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                "Enter the 6-digit code sent to ${widget.mobileNumber}.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 35),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) => _otpBox(index)),
              ),

              if (_hasError && _errorText != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorText!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE23F3F),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
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
                            color: AppColors.onPrimary,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          "VERIFY",
                          style: TextStyle(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              TextButton(
                onPressed: _handleResend,
                child: const Text(
                  "Resend Code",
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.bold,
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
