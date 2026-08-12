import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/utils/phone_utils.dart';
import 'driver_change_password_screen.dart';

/// Value returned by [DriverSettingsScreen] via `Navigator.pop` when the
/// driver successfully saves their changes, so the caller can update its
/// own state (e.g. the name shown on the dashboard) without a refetch.
class DriverSettingsResult {
  const DriverSettingsResult({
    required this.fullName,
    required this.mobileNumber,
    required this.photoPath,
  });

  final String fullName;
  final String mobileNumber;
  final String? photoPath;
}

class DriverSettingsScreen extends StatefulWidget {
  const DriverSettingsScreen({
    super.key,
    this.initialFullName,
    this.initialMobileNumber,
  });

  /// Seed values from the caller (e.g. the dashboard's currently-held
  /// driver name) so this screen always reflects the latest saved state,
  /// not a hard-coded default.
  final String? initialFullName;
  final String? initialMobileNumber;

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameController;
  late final TextEditingController _mobileNumberController;

  /// Local filesystem path to the currently selected profile photo, or
  /// null if none has been set. Seeded from whatever was persisted in
  /// [DriverSession], same as the name/mobile fields.
  String? _photoPath;

  // Snapshot of every field's value as of screen-open (or last successful
  // save), used purely to detect whether anything has actually changed —
  // the Save button stays disabled until it has.
  late String _initialFullName;
  late String _initialMobileNumber;
  String? _initialPhotoPath;
  bool _isSaving = false;

  // Avatar / header sizing: the avatar is always centered on the banner's
  // bottom edge — half overlapping the banner, half overlapping the
  // scrollable white content beneath it — regardless of how tall the
  // banner itself is.
  static const double _avatarSize = 130;
  static const double _headerHeight = 170;

  // Matches 09XXXXXXXXX (11 digits) or +63XXXXXXXXXX (10 digits after +63).
  static final RegExp _phMobileRegex = RegExp(r'^(?:\+63\d{10}|09\d{9})$');

  // Only letters, spaces, and a few common name characters.
  static final RegExp _fullNameRegex = RegExp(r"^[A-Za-zÀ-ÿ.'\- ]+$");

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.initialFullName ??
          DriverSession.instance.fullName ??
          'Driver',
    );
    _mobileNumberController = TextEditingController(
      text: widget.initialMobileNumber ??
          DriverSession.instance.mobileNumber ??
          '',
    );
    _photoPath = DriverSession.instance.photoPath;

    _initialFullName = _fullNameController.text;
    _initialMobileNumber = _mobileNumberController.text;
    _initialPhotoPath = _photoPath;

    _fullNameController.addListener(_onFieldChanged);
    _mobileNumberController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _fullNameController.removeListener(_onFieldChanged);
    _mobileNumberController.removeListener(_onFieldChanged);
    _fullNameController.dispose();
    _mobileNumberController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    setState(() {});
  }

  bool get _hasChanges {
    return _fullNameController.text != _initialFullName ||
        _mobileNumberController.text != _initialMobileNumber ||
        _photoPath != _initialPhotoPath;
  }

  String? _validateFullName(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return 'Full name is required';
    }
    if (trimmed.length < 2) {
      return 'Full name is too short';
    }
    if (trimmed.length > 60) {
      return 'Full name is too long';
    }
    if (!_fullNameRegex.hasMatch(trimmed)) {
      return 'Full name can only contain letters, spaces, hyphens, and apostrophes';
    }
    if (!trimmed.contains(' ')) {
      return 'Please enter your first and last name';
    }
    return null;
  }

  String? _validateMobileNumber(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return 'Mobile number is required';
    }
    final normalized = trimmed.replaceAll(RegExp(r'[\s-]'), '');
    if (!_phMobileRegex.hasMatch(normalized)) {
      return 'Enter a valid PH mobile number (e.g. 09XXXXXXXXX or +63XXXXXXXXXX)';
    }
    return null;
  }

  Future<void> _handleChangePhoto() async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.gallery),
            ),
            if (_photoPath != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFD32F2F),
                ),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Color(0xFFD32F2F)),
                ),
                onTap: () => Navigator.pop(sheetContext, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (action == null) return;

    if (action == _PhotoAction.remove) {
      setState(() => _photoPath = null);
      return;
    }

    final source = action == _PhotoAction.camera
        ? ImageSource.camera
        : ImageSource.gallery;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );

    if (picked == null || !mounted) return;

    setState(() => _photoPath = picked.path);
  }

  Future<void> _handleChangePassword() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const DriverChangePasswordScreen()),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
    }
  }

  Future<void> _handleSave() async {
    final formValid = _formKey.currentState?.validate() ?? false;

    if (!formValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the highlighted fields.')),
      );
      return;
    }

    final updatedName = _fullNameController.text.trim();
    final updatedMobile = PhoneUtils.toE164(_mobileNumberController.text.trim());

    setState(() => _isSaving = true);

    try {
      // The backend is the source of truth for name/mobile — without this,
      // a changed number only ever updated the local copy, so the next
      // login (which checks the backend) would still expect the old one.
      final response = await ApiClient.patch(
        '/api/driver/me',
        {'fullName': updatedName, 'mobileNumber': updatedMobile},
        token: DriverSession.instance.authToken,
      );
      final driver = response['driver'] as Map<String, dynamic>;

      await DriverSession.instance.updateProfile(
        fullName: driver['fullName'] as String,
        mobileNumber: driver['mobileNumber'] as String,
      );
      // No backend upload support yet — this stays local-only.
      await DriverSession.instance.updatePhoto(_photoPath);

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _initialFullName = updatedName;
        _initialMobileNumber = updatedMobile;
        _initialPhotoPath = _photoPath;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );

      Navigator.of(context).pop(
        DriverSettingsResult(
          fullName: updatedName,
          mobileNumber: updatedMobile,
          photoPath: _photoPath,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              top: _headerHeight + (_avatarSize / 2) + 20,
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    const _SectionTitle(title: 'Account Settings'),
                    const SizedBox(height: 16),
                    _SettingsField(
                      label: 'Full Name',
                      controller: _fullNameController,
                      hintText: 'Enter your full name',
                      validator: _validateFullName,
                    ),
                    const SizedBox(height: 12),
                    _SettingsField(
                      label: 'Mobile Number',
                      controller: _mobileNumberController,
                      hintText: '+63 XXX XXX XXXX',
                      keyboardType: TextInputType.phone,
                      validator: _validateMobileNumber,
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle(title: 'Security'),
                    const SizedBox(height: 12),
                    _SecurityItem(
                      icon: Icons.lock_outline_rounded,
                      label: 'Change Password',
                      onTap: _handleChangePassword,
                    ),
                    const SizedBox(height: 24),
                    _SaveButton(
                      enabled: _hasChanges && !_isSaving,
                      onTap: _handleSave,
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _headerHeight,
              child: Container(
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
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    (_avatarSize / 2) + 12,
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
                            padding: EdgeInsets.all(13),
                            child: Icon(Icons.arrow_back, size: 22, color: Colors.black87),
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
                              'Settings',
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
                ),
              ),
            ),

            Positioned(
              top: _headerHeight - (_avatarSize / 2),
              left: 0,
              right: 0,
              child: Center(
                child: _ProfilePhoto(
                  photoPath: _photoPath,
                  size: _avatarSize,
                  onEditTap: _handleChangePhoto,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhotoAction { camera, gallery, remove }

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Colors.black,
      ),
    );
  }
}

class _ProfilePhoto extends StatelessWidget {
  const _ProfilePhoto({
    required this.onEditTap,
    required this.size,
    this.photoPath,
  });

  final VoidCallback onEditTap;
  final double size;
  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9D9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              image: photoPath != null
                  ? DecorationImage(
                      image: FileImage(File(photoPath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: photoPath == null
                ? Icon(
                    Icons.person_rounded,
                    size: size * 0.54,
                    color: AppColors.textSecondary,
                  )
                : null,
          ),
          Positioned(
            right: -6,
            bottom: 8,
            child: GestureDetector(
              onTap: onEditTap,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.secondary, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 20,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

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
            keyboardType: keyboardType,
            validator: validator,
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
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityItem extends StatelessWidget {
  const _SecurityItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E6E7)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.secondary),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onTap, required this.enabled});

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary : const Color(0xFFE6E6E7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_rounded,
              size: 20,
              color: enabled ? AppColors.onPrimary : Colors.grey.shade500,
            ),
            const SizedBox(width: 10),
            Text(
              'Save Changes',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: enabled ? AppColors.onPrimary : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
