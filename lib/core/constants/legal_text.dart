/// Plain-text content for the Terms & Conditions and Privacy Policy
/// popups shown from the sign-up screen's agreement checkbox (see
/// TODO.md — shown as an in-app dialog, not a link out to a browser).
/// Mirrors admin/public/terms-and-conditions.html and
/// admin/public/privacy-policy.html; keep both in sync if either changes.
library;

const String kTermsAndConditionsUpdated = 'Effective date: August 18, 2026 · Last updated: August 18, 2026';

const String kTermsAndConditionsText = '''
These Terms & Conditions ("Terms") govern your use of the ManibelApp mobile application and admin platform (together, the "Service"), which facilitates jeepney commuting on the Pasig–Quiapo route in Metro Manila. By creating an account or using the Service, you agree to these Terms and to our Privacy Policy.

1. Eligibility
You must be at least 13 years old to create a commuter account. If you are a minor, you may only use the Service with the consent and supervision of a parent or guardian. Driver accounts are created by an admin after license verification, not through self-registration.

2. What the Service Is
ManibelApp helps commuters find, track, and board nearby jeepneys on the Pasig–Quiapo route, and helps drivers log trips and report daily operations. The Service is a facilitation tool — it does not itself operate any jeepney, employ any driver, or guarantee the availability, timing, safety, or fare of any ride. Fares shown in the app are flat-rate estimates; jeepney fares are collected in cash by the driver, not processed through the app.

3. Account Responsibilities
You are responsible for keeping your password confidential and for all activity under your account. Information you provide (name, mobile number, date of birth, identity documents) must be accurate and belong to you. Commuter accounts require identity verification (government ID + selfie) before activation; driver accounts require license verification by an admin. ManibelApp may reject a submission or deactivate an account that fails verification or is later found to be fraudulent.

4. User Conduct
You agree not to: provide false identity documents or impersonate another person; use the Service to harass, threaten, or endanger a driver or commuter; submit false or malicious complaints or ratings; or interfere with or attempt to circumvent the Service's verification, boarding, or trip-tracking systems.

5. Driver Conduct & Trip Review
Drivers are expected to operate safely and honestly report trip and daily operations data. Unusually short trips are automatically flagged for admin review; a driver may submit an explanation for a flagged trip. ManibelApp's admin team reviews flagged trips and commuter complaints and may take action on a driver's account, including deactivation, based on that review.

6. Ratings & Complaints
Commuters may rate a driver after a completed ride and file complaints against a driver by plate number. Complaints are reviewed by admin staff; filing a knowingly false complaint is a violation of these Terms.

7. Disclaimer of Warranties
The Service is provided "as is." ManibelApp does not guarantee uninterrupted or error-free operation, the accuracy of live jeepney location data, or that a jeepney will be available when requested. Identity and license verification reduce but do not eliminate risk — use the Service at your own discretion, the same as any in-person transaction with a public transport driver.

8. Limitation of Liability
To the extent permitted by Philippine law, ManibelApp is not liable for any injury, loss, or damage arising from an actual jeepney ride, which is a transaction between commuter and driver — the Service only facilitates finding and tracking that ride.

9. Account Suspension & Termination
ManibelApp may suspend or deactivate an account that violates these Terms, fails identity/license verification, or is inactive, with or without prior notice where reasonably warranted (e.g. suspected fraud or safety risk). You may stop using the Service at any time.

10. Changes to These Terms
We may update these Terms from time to time. Material changes will be reflected by updating the "Last updated" date above, and where required, we will seek your renewed consent.

11. Governing Law
These Terms are governed by the laws of the Republic of the Philippines.

12. Contact Us
Email: manibelaapp@gmail.com
''';

const String kPrivacyPolicyUpdated = 'Effective date: August 18, 2026 · Last updated: August 18, 2026';

const String kPrivacyPolicyText = '''
This Privacy Policy explains how ManibelApp ("we", "us") collects, uses, stores, and protects personal information through the ManibelApp mobile application and admin platform (together, the "Service"), in compliance with the Data Privacy Act of 2012 (Republic Act No. 10173) and its Implementing Rules and Regulations.

By creating an account or using the Service, you consent to the collection and use of your information as described in this Policy.

1. Information We Collect

Commuters: full name, mobile number, date of birth (account creation); password, stored as a hash, never in plain text (account security); profile photo (personalization); government ID (type, front/back photo) and a selfie (identity verification before your account is activated); trip boarding/alighting records, fare, rider count, ratings, complaints filed (operating and improving the jeepney tracking and fare system); approximate location when requesting a ride ("demand signal") — processed as anonymized location clusters, never exposed with your identity attached.

Drivers: full name, mobile number, date of birth, plate number (account identification); profile photo (shown to commuters for driver recognition); driver's license front/back photo (verifying you are a licensed driver before your account is enabled; submitted through an admin, not self-uploaded); live GPS location while a trip is active (real-time jeepney tracking, and trip-integrity review such as flagging abnormally short trips); daily operations log — odometer readings, earnings, expenses (your own self-reported records, visible to admins for operational review).

Automatically collected: device/app identifiers used for push notifications; timestamps of account, trip, and verification activity.

2. How We Use Your Information
To create, verify, and secure your account; to operate core features — live jeepney tracking, boarding/fare records, ratings, and complaints; to review flagged trips and investigate complaints; to send you service notifications (e.g. trip status, account status); and to comply with legal obligations and respond to lawful government requests.

3. Legal Basis
We process your personal information based on your consent given at sign-up, and where necessary to perform our contract with you (providing the Service) or to comply with legal obligations. Government ID, license photos, and selfies are treated as sensitive personal information under RA 10173 and are collected only with your explicit consent, solely for identity and driver-eligibility verification.

4. Who We Share Information With
Admin staff — for identity verification, trip review, and complaint handling; access is restricted to authorized personnel. Service providers — hosting/cloud storage providers that store data on our behalf under confidentiality obligations. Legal authorities — only when required by law, court order, or to protect the rights and safety of users. We do not sell your personal information to third parties.

5. Data Storage and Security
We apply organizational, physical, and technical security measures appropriate to the sensitivity of the data, including restricted admin-only access to identity documents, encrypted password storage, and access logging. No method of transmission or storage is 100% secure, but we take reasonable steps consistent with RA 10173 to protect your data.

6. Data Retention
We retain personal information for as long as your account is active and as needed to fulfill the purposes described above, resolve disputes, and comply with legal obligations. Rejected identity/license submissions and inactive accounts are retained for 12 months before deletion, unless a longer period is required by law.

7. Your Rights
Under the Data Privacy Act of 2012, you have the right to: be informed that your personal data is being processed; access your personal data we hold; correct inaccurate or outdated data; object to processing, and withdraw consent; request erasure or blocking of your data, subject to legal retention requirements; data portability; and file a complaint with the National Privacy Commission (privacy.gov.ph). To exercise any of these rights, contact us using the details in Section 10.

8. Children's Privacy
The Service is not directed at children. If you are a minor, you may only use the Service with the consent and supervision of a parent or guardian.

9. Changes to This Policy
We may update this Privacy Policy from time to time. Material changes will be reflected by updating the "Last updated" date above, and where required, we will seek your renewed consent.

10. Contact Us
Data Protection Officer: ManibelApp Project Team
Email: manibelaapp@gmail.com
''';
