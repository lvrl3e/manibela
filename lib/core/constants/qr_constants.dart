/// Prefix encoded into every driver QR code, ahead of the backend-issued
/// token (see DriverQrCodeScreen / backend's `/api/driver/*/qr-token`).
/// Namespacing it lets the scanner (QrScannerScreen callers) tell a
/// ManibelApp driver code apart from some unrelated QR code at a glance,
/// without needing to hit the backend first.
const String kDriverQrPrefix = 'MNBL-DRV:';
