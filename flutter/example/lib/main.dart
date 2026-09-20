import 'package:adreward_attribution/adreward_attribution.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Minimal integration example.
///
/// The recommended shape: let AdReward tell you a claim is available, then show
/// your own prompt and open the link on a user tap. Launching a browser on your
/// own at startup risks an App Store rejection and confuses customers.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AdReward.init(
    trackingId: 'ADR-XXXXXX', // from the AdReward advertiser dashboard
    debug: true,
    onClaimAvailable: (claimUrl) => pendingClaimUrl.value = claimUrl,
  );

  runApp(const ExampleApp());
}

/// Holds a claim link until the customer chooses to open it.
final pendingClaimUrl = ValueNotifier<String?>(null);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('AdReward example')),
        body: Center(
          child: ValueListenableBuilder<String?>(
            valueListenable: pendingClaimUrl,
            builder: (context, claimUrl, _) {
              if (claimUrl == null) {
                return const Text('No reward to claim.');
              }

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('You installed this app via AdReward.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => launchUrl(
                      Uri.parse(claimUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Claim your reward'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
