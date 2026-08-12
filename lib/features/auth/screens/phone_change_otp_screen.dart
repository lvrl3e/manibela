import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';

/// Confirms a commuter/driver actually controls a new mobile number before
/// Settings applies it. The caller is expected to have already sent the
/// first code (via `POST /me/phone/send-otp`) before pushing this screen.
///
/// Pops `true` once `/me/phone/verify` succeeds — the account's
/// mobileNumber is already updated on the backend by that point. Pops
/// `null` (back button / swipe-back) if the user abandons the flow, in
/// which case the number is left untouched.
class PhoneChangeOtpScreen extends StatefulWidget {
  const PhoneChangeOtpScreen({
    super.key,
    required this.mobileNumber,
    required this.authToken,
    required this.isDriver,
  });

  /// Already normalized to `+63XXXXXXXXXX` — the new number being confirmed.
  final String mobileNumber;

  final String? authToken;

  /// Which role's `/me/phone/*` endpoints to call.
  final bool isDriver;

  @override
  State<PhoneChangeOtpScreen> createState() => _PhoneChangeOtpScreenState();
}

class _PhoneChangeOtpScreenState extends State<PhoneChangeOtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  bool _hasError = false;
  String? _errorText;

  String get _sendOtpPath =>
      widget.isDriver ? '/api/driver/me/phone/send-otp' : '/api/commuter/me/phone/send-otp';
  String get _verifyPath =>
      widget.isDriver ? '/api/driver/me/phone/verify' : '/api/commuter/me/phone/verify';

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

  Future<void> _handleVerify() async {
    if (_isLoading) return;

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

    setState(() {
      _hasError = false;
      _errorText = null;
      _isLoading = true;
    });

    try {
      await ApiClient.post(
        _verifyPath,
        {'mobileNumber': widget.mobileNumber, 'code': _code},
        token: widget.authToken,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
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
    if (_isResending) return;

    setState(() => _isResending = true);
    for (var controller in _controllers) {
      controller.clear();
    }
    setState(() {
      _hasError = false;
      _errorText = null;
    });
    FocusScope.of(context).requestFocus(_focusNodes[0]);

    try {
      await ApiClient.post(
        _sendOtpPath,
        {'mobileNumber': widget.mobileNumber},
        token: widget.authToken,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP code resent.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isResending = false);
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
              color: _hasError ? const Color(0xFFE23F3F) : AppColors.logoBlue,
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
                  Icons.phone_android_rounded,
                  size: 35,
                  color: AppColors.logoBlue,
                ),
              ),

              const SizedBox(height: 25),

              const Text(
                "Confirm New Number",
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
                  onPressed: _isLoading ? null : _handleVerify,
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
                          "VERIFY",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              TextButton(
                onPressed: _isResending ? null : _handleResend,
                child: Text(
                  _isResending ? "Resending..." : "Resend Code",
                  style: const TextStyle(
                    color: AppColors.logoBlue,
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
