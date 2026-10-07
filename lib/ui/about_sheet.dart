import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

final privacyPolicyUrl = Uri.parse(
  'https://twodesktech.com/pomee/privacy-policy',
);
final supportEmail = Uri.parse('mailto:support@twodesktech.com?subject=Pomee');
final websiteUrl = Uri.parse('https://twodesktech.com');

/// Who made Pomee, with links to the privacy policy and support. Play
/// requires the privacy policy to be reachable from inside the app.
void showAboutSheet(BuildContext context) {
  final c = PomeeColors.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.background,
    showDragHandle: true,
    builder: (context) => const _AboutSheet(),
  );
}

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Pomee',
                style: TextStyle(
                  fontFamily: displayFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: c.ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              child: Text(
                'Made by Twodesk',
                style: TextStyle(fontSize: 14, color: c.dim),
              ),
            ),
            _Link(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy policy',
              uri: privacyPolicyUrl,
            ),
            _Link(
              icon: Icons.mail_outline_rounded,
              label: 'Contact support',
              uri: supportEmail,
            ),
            _Link(
              icon: Icons.public_rounded,
              label: 'twodesktech.com',
              uri: websiteUrl,
            ),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.uri});

  final IconData icon;
  final String label;
  final Uri uri;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(icon, color: c.ink),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: c.ink,
        ),
      ),
      trailing: Icon(Icons.open_in_new_rounded, size: 18, color: c.dim),
      onTap: () => _open(context),
    );
  }
}
