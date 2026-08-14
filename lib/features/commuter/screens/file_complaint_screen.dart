import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/utils/platform_utils.dart';

const List<String> _complaintTypes = [
  'Reckless Driving',
  'Overcharging',
  'Rude Behavior',
  'Route Deviation',
  'Other',
];

/// Files a complaint against a driver, identified by plate number since
/// there's no per-trip passenger record to pick a driver from (a jeepney
/// doesn't track individual riders anywhere in this app). Reviewed by an
/// admin on the Incident Report page.
class FileComplaintScreen extends StatefulWidget {
  const FileComplaintScreen({super.key});

  @override
  State<FileComplaintScreen> createState() => _FileComplaintScreenState();
}

class _FileComplaintScreenState extends State<FileComplaintScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _complaintType;
  File? _attachment;
  bool _isSubmitting = false;
  bool _isPickingImage = false;
  String? _error;

  @override
  void dispose() {
    _plateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    if (_isPickingImage) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (!isDesktopPlatform)
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded, color: AppColors.logoBlue),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.logoBlue),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            if (_attachment != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD32F2F)),
                title: const Text('Remove Photo', style: TextStyle(color: Color(0xFFD32F2F))),
                onTap: () => Navigator.pop(sheetContext),
              ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (source == null) {
      setState(() => _attachment = null);
      return;
    }

    setState(() => _isPickingImage = true);
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (picked != null && mounted) setState(() => _attachment = File(picked.path));
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid || _complaintType == null) {
      setState(() => _error = _complaintType == null ? 'Please choose a complaint type.' : null);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ApiClient.uploadFiles(
        '/api/commuter/complaints',
        files: _attachment != null ? {'attachment': _attachment!.path} : {},
        fields: {
          'plateNumber': _plateController.text.trim(),
          'complaintType': _complaintType!,
          'description': _descriptionController.text.trim(),
        },
        token: UserSession.instance.authToken,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complaint submitted. Our team will review it.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6F8),
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          'File a Complaint',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.settingsTileBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.settingsIconColor, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Report an issue with a driver by their plate number. An admin will review this before any action is taken.",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.settingsIconColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text('Driver Plate Number', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _plateController,
                textCapitalization: TextCapitalization.characters,
                decoration: _fieldDecoration('e.g. ABC123'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Plate number is required' : null,
              ),

              const SizedBox(height: 20),
              const Text('Complaint Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _complaintType,
                onChanged: (v) => setState(() => _complaintType = v),
                decoration: _fieldDecoration('Select a type'),
                items: _complaintTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              ),

              const SizedBox(height: 20),
              const Text('Description', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: _fieldDecoration('What happened?'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please describe what happened' : null,
              ),

              const SizedBox(height: 20),
              const Text('Photo Evidence (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
              const SizedBox(height: 10),
              InkWell(
                onTap: _isPickingImage ? null : _pickAttachment,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEDEDED)),
                    color: Colors.white,
                  ),
                  child: _attachment != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(_attachment!, fit: BoxFit.cover, width: double.infinity),
                        )
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined, color: Colors.black38, size: 28),
                              SizedBox(height: 6),
                              Text('Tap to add a photo', style: TextStyle(fontSize: 12, color: Colors.black45)),
                            ],
                          ),
                        ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F))),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary),
                        )
                      : const Text(
                          'Submit Complaint',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.black38, fontWeight: FontWeight.w600, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEDEDED)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEDEDED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.logoBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE23F3F)),
      ),
      errorStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F)),
    );
  }
}
