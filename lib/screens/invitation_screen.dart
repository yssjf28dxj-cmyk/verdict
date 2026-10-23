import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../firebase_session.dart';
import '../l10n/app_localizations.dart';
import '../utils/invitation_links.dart';
import 'lobby_screen.dart';

/// No debate query is issued until Firebase has restored the selected identity.
class InvitationScreen extends StatefulWidget {
  const InvitationScreen(
      {super.key, required this.debateId, this.authChanges, this.lobbyBuilder});
  final String debateId;
  final Stream<User?>? authChanges;
  final Widget Function(String)? lobbyBuilder;
  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  late Stream<User?> _authChanges;
  @override
  void initState() {
    super.initState();
    _authChanges = validInvitationId(widget.debateId)
        ? widget.authChanges ?? appAuth.authStateChanges()
        : const Stream.empty();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!validInvitationId(widget.debateId)) {
      return Scaffold(
          appBar: AppBar(title: Text(l10n.invitationTitle)),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.invitationUnavailable))));
    }
    return StreamBuilder<User?>(
        stream: _authChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(
                body: Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l10n.invitationLoadFailed))));
          }
          if (snapshot.data != null) {
            return widget.lobbyBuilder?.call(widget.debateId) ??
                LobbyScreen(debateId: widget.debateId);
          }
          return Scaffold(
              appBar: AppBar(title: Text(l10n.invitationTitle)),
              body: Center(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const Icon(Icons.forum_outlined,
                                            size: 40),
                                        const SizedBox(height: 16),
                                        Text(l10n.invitationTitle,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge),
                                        const SizedBox(height: 12),
                                        Text(l10n.invitationSignInHint),
                                        const SizedBox(height: 20),
                                        FilledButton(
                                            onPressed: () => context.go(
                                                invitationAuthRoute(
                                                    widget.debateId)),
                                            child:
                                                Text(l10n.invitationContinue)),
                                      ])))))));
        });
  }
}
