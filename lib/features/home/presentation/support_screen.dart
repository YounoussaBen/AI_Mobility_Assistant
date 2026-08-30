import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
          children: [
            Text('Support', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 9),
            const Text(
              'Help with planning, voice guidance, location, and Look Ahead.',
            ),
            const SizedBox(height: 28),
            const _HelpTile(
              title: 'I cannot find a destination',
              body:
                  'Check location access, include the area or landmark name, and always choose the exact result before starting.',
            ),
            const _HelpTile(
              title: 'Voice input is not responding',
              body:
                  'Use the Type button, then check microphone permission in system settings. Basic typed planning remains available.',
            ),
            const _HelpTile(
              title: 'A route or transport option looks wrong',
              body:
                  'Do not start it. Ask for another route. Simulated provider options are always labelled and never dispatch a real vehicle.',
            ),
            const _HelpTile(
              title: 'Look Ahead limitations',
              body:
                  'It cannot prove the path is clear or replace a cane, guide dog, sighted guide, or normal orientation skills.',
            ),
            const SizedBox(height: 20),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Mobility AI is not an emergency service. If you are in immediate danger, stop moving and contact local emergency help or a trusted person.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  const _HelpTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(body)],
      ),
    );
  }
}
