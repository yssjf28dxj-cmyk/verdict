import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('ru'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'VERDICT'**
  String get appTitle;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'HOME'**
  String get homeTitle;

  /// No description provided for @createDebates.
  ///
  /// In en, this message translates to:
  /// **'Create debates'**
  String get createDebates;

  /// No description provided for @searchDebates.
  ///
  /// In en, this message translates to:
  /// **'Search debate topics...'**
  String get searchDebates;

  /// No description provided for @languageAll.
  ///
  /// In en, this message translates to:
  /// **'Language: all'**
  String get languageAll;

  /// No description provided for @worldChatTab.
  ///
  /// In en, this message translates to:
  /// **'World Chat'**
  String get worldChatTab;

  /// No description provided for @profileTab.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTab;

  /// No description provided for @mainTab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get mainTab;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'PROFILE'**
  String get profileTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get settingsTitle;

  /// No description provided for @languageSetting.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get languageSetting;

  /// No description provided for @settings_section_general.
  ///
  /// In en, this message translates to:
  /// **'General Settings'**
  String get settings_section_general;

  /// No description provided for @settings_language_title.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get settings_language_title;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'SIGN OUT'**
  String get signOut;

  /// No description provided for @wins.
  ///
  /// In en, this message translates to:
  /// **'WINS'**
  String get wins;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'RATING'**
  String get rating;

  /// No description provided for @battles.
  ///
  /// In en, this message translates to:
  /// **'BATTLES'**
  String get battles;

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @worldChatTitle.
  ///
  /// In en, this message translates to:
  /// **'WORLD CHAT'**
  String get worldChatTitle;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message...'**
  String get messageHint;

  /// No description provided for @createBattleTitle.
  ///
  /// In en, this message translates to:
  /// **'CREATE BATTLE'**
  String get createBattleTitle;

  /// No description provided for @debateTopicLabel.
  ///
  /// In en, this message translates to:
  /// **'DEBATE TOPIC'**
  String get debateTopicLabel;

  /// No description provided for @enterTopic.
  ///
  /// In en, this message translates to:
  /// **'For example: iOS or Android?'**
  String get enterTopic;

  /// No description provided for @roundTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'ROUND TIME'**
  String get roundTimeLabel;

  /// No description provided for @roundsLabel.
  ///
  /// In en, this message translates to:
  /// **'ROUNDS'**
  String get roundsLabel;

  /// No description provided for @modesLabel.
  ///
  /// In en, this message translates to:
  /// **'MODES'**
  String get modesLabel;

  /// No description provided for @languageRegionLabel.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE & REGION'**
  String get languageRegionLabel;

  /// No description provided for @welcomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'WELCOME'**
  String get welcomeHeadline;

  /// No description provided for @publishChallenge.
  ///
  /// In en, this message translates to:
  /// **'PUBLISH CHALLENGE'**
  String get publishChallenge;

  /// No description provided for @publicFeed.
  ///
  /// In en, this message translates to:
  /// **'Public feed'**
  String get publicFeed;

  /// No description provided for @directInvite.
  ///
  /// In en, this message translates to:
  /// **'Direct invite'**
  String get directInvite;

  /// No description provided for @publicMode.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get publicMode;

  /// No description provided for @requestOnly.
  ///
  /// In en, this message translates to:
  /// **'Request only'**
  String get requestOnly;

  /// No description provided for @privateMode.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get privateMode;

  /// No description provided for @opponentId.
  ///
  /// In en, this message translates to:
  /// **'Opponent ID'**
  String get opponentId;

  /// No description provided for @enterOpponentId.
  ///
  /// In en, this message translates to:
  /// **'Enter opponent ID'**
  String get enterOpponentId;

  /// No description provided for @lobbyWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'WAITING'**
  String get lobbyWaitingTitle;

  /// No description provided for @waitingOpponent.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Opponent'**
  String get waitingOpponent;

  /// No description provided for @searchingOpponent.
  ///
  /// In en, this message translates to:
  /// **'Searching opponent...'**
  String get searchingOpponent;

  /// No description provided for @acceptChallenge.
  ///
  /// In en, this message translates to:
  /// **'ACCEPT CHALLENGE'**
  String get acceptChallenge;

  /// No description provided for @cancelChallenge.
  ///
  /// In en, this message translates to:
  /// **'CANCEL CHALLENGE'**
  String get cancelChallenge;

  /// No description provided for @accepting.
  ///
  /// In en, this message translates to:
  /// **'ACCEPTING...'**
  String get accepting;

  /// No description provided for @invitedToDebate.
  ///
  /// In en, this message translates to:
  /// **'You are invited to this debate'**
  String get invitedToDebate;

  /// No description provided for @battleAutoStart.
  ///
  /// In en, this message translates to:
  /// **'As soon as someone accepts, the battle starts automatically.'**
  String get battleAutoStart;

  /// No description provided for @accessRestricted.
  ///
  /// In en, this message translates to:
  /// **'Access to debate is restricted'**
  String get accessRestricted;

  /// No description provided for @requestAccess.
  ///
  /// In en, this message translates to:
  /// **'REQUEST ACCESS'**
  String get requestAccess;

  /// No description provided for @requestSent.
  ///
  /// In en, this message translates to:
  /// **'REQUEST SENT'**
  String get requestSent;

  /// No description provided for @errorLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading error'**
  String get errorLoading;

  /// No description provided for @noDebatesFound.
  ///
  /// In en, this message translates to:
  /// **'No debates found for your query'**
  String get noDebatesFound;

  /// No description provided for @themeLanguageRU.
  ///
  /// In en, this message translates to:
  /// **'RU'**
  String get themeLanguageRU;

  /// No description provided for @themeLanguageEN.
  ///
  /// In en, this message translates to:
  /// **'EN'**
  String get themeLanguageEN;

  /// No description provided for @themeLanguageAR.
  ///
  /// In en, this message translates to:
  /// **'AR'**
  String get themeLanguageAR;

  /// No description provided for @themeLanguageZH.
  ///
  /// In en, this message translates to:
  /// **'ZH'**
  String get themeLanguageZH;

  /// No description provided for @themeLanguageES.
  ///
  /// In en, this message translates to:
  /// **'ES'**
  String get themeLanguageES;

  /// No description provided for @themeLanguageFR.
  ///
  /// In en, this message translates to:
  /// **'FR'**
  String get themeLanguageFR;

  /// No description provided for @themeLanguageHI.
  ///
  /// In en, this message translates to:
  /// **'HI'**
  String get themeLanguageHI;

  /// No description provided for @regionGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get regionGlobal;

  /// No description provided for @regionCis.
  ///
  /// In en, this message translates to:
  /// **'CIS'**
  String get regionCis;

  /// No description provided for @regionMena.
  ///
  /// In en, this message translates to:
  /// **'MENA'**
  String get regionMena;

  /// No description provided for @regionEuAf.
  ///
  /// In en, this message translates to:
  /// **'EU/AF'**
  String get regionEuAf;

  /// No description provided for @accessApproved.
  ///
  /// In en, this message translates to:
  /// **'Access approved'**
  String get accessApproved;

  /// No description provided for @approveAccessFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to approve access'**
  String get approveAccessFailed;

  /// No description provided for @requestRejected.
  ///
  /// In en, this message translates to:
  /// **'Request rejected'**
  String get requestRejected;

  /// No description provided for @rejectRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to reject request'**
  String get rejectRequestFailed;

  /// No description provided for @accessRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Access requests'**
  String get accessRequestsTitle;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @loginToRequestAccess.
  ///
  /// In en, this message translates to:
  /// **'Sign in to request access'**
  String get loginToRequestAccess;

  /// No description provided for @requestAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'Request already sent'**
  String get requestAlreadySent;

  /// No description provided for @accessRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Access request sent'**
  String get accessRequestSent;

  /// No description provided for @sendRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send request'**
  String get sendRequestFailed;

  /// No description provided for @waitingStatus.
  ///
  /// In en, this message translates to:
  /// **'WAITING'**
  String get waitingStatus;

  /// No description provided for @finishedStatus.
  ///
  /// In en, this message translates to:
  /// **'FINISHED'**
  String get finishedStatus;

  /// No description provided for @topicNotSpecified.
  ///
  /// In en, this message translates to:
  /// **'Topic not specified'**
  String get topicNotSpecified;

  /// No description provided for @fighterOne.
  ///
  /// In en, this message translates to:
  /// **'Fighter 1'**
  String get fighterOne;

  /// No description provided for @fighterTwo.
  ///
  /// In en, this message translates to:
  /// **'Fighter 2'**
  String get fighterTwo;

  /// No description provided for @accessRequestsCountPrefix.
  ///
  /// In en, this message translates to:
  /// **'REQUESTS'**
  String get accessRequestsCountPrefix;

  /// No description provided for @authRequired.
  ///
  /// In en, this message translates to:
  /// **'Authorization required'**
  String get authRequired;

  /// No description provided for @directInviteNeedsOpponent.
  ///
  /// In en, this message translates to:
  /// **'Provide opponent ID for direct invite'**
  String get directInviteNeedsOpponent;

  /// No description provided for @privateNeedsOpponent.
  ///
  /// In en, this message translates to:
  /// **'Provide opponent ID for private debate'**
  String get privateNeedsOpponent;

  /// No description provided for @serverNoDebateId.
  ///
  /// In en, this message translates to:
  /// **'Server did not return debateId'**
  String get serverNoDebateId;

  /// No description provided for @serverErrorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get serverErrorPrefix;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorPrefix;

  /// No description provided for @enterTopicValidation.
  ///
  /// In en, this message translates to:
  /// **'Enter a topic'**
  String get enterTopicValidation;

  /// No description provided for @oneMinute.
  ///
  /// In en, this message translates to:
  /// **'1 min'**
  String get oneMinute;

  /// No description provided for @threeMinutes.
  ///
  /// In en, this message translates to:
  /// **'3 min'**
  String get threeMinutes;

  /// No description provided for @fiveMinutes.
  ///
  /// In en, this message translates to:
  /// **'5 min'**
  String get fiveMinutes;

  /// No description provided for @oneRound.
  ///
  /// In en, this message translates to:
  /// **'1 round'**
  String get oneRound;

  /// No description provided for @threeRounds.
  ///
  /// In en, this message translates to:
  /// **'3 rounds'**
  String get threeRounds;

  /// No description provided for @fiveRounds.
  ///
  /// In en, this message translates to:
  /// **'5 rounds'**
  String get fiveRounds;

  /// No description provided for @secondsShort.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get secondsShort;

  /// No description provided for @debateNotFound.
  ///
  /// In en, this message translates to:
  /// **'Debate not found'**
  String get debateNotFound;

  /// No description provided for @debateAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'Debate is already active'**
  String get debateAlreadyActive;

  /// No description provided for @noAccessToInviteAccept.
  ///
  /// In en, this message translates to:
  /// **'No access to accept invite'**
  String get noAccessToInviteAccept;

  /// No description provided for @cannotAcceptOwnChallenge.
  ///
  /// In en, this message translates to:
  /// **'You cannot accept your own challenge'**
  String get cannotAcceptOwnChallenge;

  /// No description provided for @cancelChallengeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel challenge'**
  String get cancelChallengeFailed;

  /// No description provided for @acceptChallengeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to accept challenge'**
  String get acceptChallengeFailed;

  /// No description provided for @loadingTopic.
  ///
  /// In en, this message translates to:
  /// **'Loading topic...'**
  String get loadingTopic;

  /// No description provided for @anonymous.
  ///
  /// In en, this message translates to:
  /// **'Anonymous'**
  String get anonymous;

  /// No description provided for @battleDataNotFound.
  ///
  /// In en, this message translates to:
  /// **'Battle data not found'**
  String get battleDataNotFound;

  /// No description provided for @unknownTopic.
  ///
  /// In en, this message translates to:
  /// **'Unknown topic'**
  String get unknownTopic;

  /// No description provided for @draw.
  ///
  /// In en, this message translates to:
  /// **'DRAW'**
  String get draw;

  /// No description provided for @victoryPrefix.
  ///
  /// In en, this message translates to:
  /// **'VICTORY'**
  String get victoryPrefix;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'BACK TO HOME'**
  String get backToHome;

  /// No description provided for @versusLabel.
  ///
  /// In en, this message translates to:
  /// **'VS'**
  String get versusLabel;

  /// No description provided for @votesLabel.
  ///
  /// In en, this message translates to:
  /// **'VOTES'**
  String get votesLabel;

  /// No description provided for @guestSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to sign in as guest'**
  String get guestSignInFailed;

  /// No description provided for @googleSignInUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in is not configured or was cancelled'**
  String get googleSignInUnavailable;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'SIGN IN WITH GOOGLE'**
  String get signInWithGoogle;

  /// No description provided for @browseWithoutRegistration.
  ///
  /// In en, this message translates to:
  /// **'BROWSE WITHOUT REGISTRATION'**
  String get browseWithoutRegistration;

  /// No description provided for @alreadyVoted.
  ///
  /// In en, this message translates to:
  /// **'You already voted'**
  String get alreadyVoted;

  /// No description provided for @notYourTurn.
  ///
  /// In en, this message translates to:
  /// **'It\'s not your turn right now'**
  String get notYourTurn;

  /// No description provided for @cannotDetectSender.
  ///
  /// In en, this message translates to:
  /// **'Could not identify the sender'**
  String get cannotDetectSender;

  /// No description provided for @penaltyAppliedPrefix.
  ///
  /// In en, this message translates to:
  /// **'Penalty applied'**
  String get penaltyAppliedPrefix;

  /// No description provided for @penaltyApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply penalty'**
  String get penaltyApplyFailed;

  /// No description provided for @closedDebates.
  ///
  /// In en, this message translates to:
  /// **'CLOSED DEBATES'**
  String get closedDebates;

  /// No description provided for @requestOnlyDebates.
  ///
  /// In en, this message translates to:
  /// **'BY REQUEST'**
  String get requestOnlyDebates;

  /// No description provided for @openDebates.
  ///
  /// In en, this message translates to:
  /// **'OPEN DEBATES'**
  String get openDebates;

  /// No description provided for @timeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeLabel;

  /// No description provided for @timeEnding.
  ///
  /// In en, this message translates to:
  /// **'TIME IS RUNNING OUT'**
  String get timeEnding;

  /// No description provided for @roundLabel.
  ///
  /// In en, this message translates to:
  /// **'Round'**
  String get roundLabel;

  /// No description provided for @yourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get yourTurn;

  /// No description provided for @opponentTurn.
  ///
  /// In en, this message translates to:
  /// **'Opponent\'s turn'**
  String get opponentTurn;

  /// No description provided for @nextTurnPenaltyPrefix.
  ///
  /// In en, this message translates to:
  /// **'Penalty on next turn'**
  String get nextTurnPenaltyPrefix;

  /// No description provided for @noNextTurnPenalty.
  ///
  /// In en, this message translates to:
  /// **'No penalties on the next turn'**
  String get noNextTurnPenalty;

  /// No description provided for @voteFor.
  ///
  /// In en, this message translates to:
  /// **'Vote for'**
  String get voteFor;

  /// No description provided for @alreadyVotedFor.
  ///
  /// In en, this message translates to:
  /// **'You already voted for'**
  String get alreadyVotedFor;

  /// No description provided for @alreadyVotedThisRound.
  ///
  /// In en, this message translates to:
  /// **'You already voted in this round'**
  String get alreadyVotedThisRound;

  /// No description provided for @votingOnlyForViewers.
  ///
  /// In en, this message translates to:
  /// **'Voting is available only for viewers'**
  String get votingOnlyForViewers;

  /// No description provided for @viewerModeHint.
  ///
  /// In en, this message translates to:
  /// **'Viewer mode: you can watch the debate and vote, but only the two fighters can write.'**
  String get viewerModeHint;

  /// No description provided for @yourTurnUpper.
  ///
  /// In en, this message translates to:
  /// **'YOUR TURN'**
  String get yourTurnUpper;

  /// No description provided for @opponentTurnUpper.
  ///
  /// In en, this message translates to:
  /// **'OPPONENT TURN'**
  String get opponentTurnUpper;

  /// No description provided for @viewerUpper.
  ///
  /// In en, this message translates to:
  /// **'VIEWER'**
  String get viewerUpper;

  /// No description provided for @waitingYourTurn.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your turn'**
  String get waitingYourTurn;

  /// No description provided for @yourTurnWriteArgument.
  ///
  /// In en, this message translates to:
  /// **'Your turn. Write your argument...'**
  String get yourTurnWriteArgument;

  /// No description provided for @waitForOpponentTurn.
  ///
  /// In en, this message translates to:
  /// **'Wait for your opponent\'s turn...'**
  String get waitForOpponentTurn;

  /// No description provided for @battleFinishedGoingToResult.
  ///
  /// In en, this message translates to:
  /// **'Battle finished. Moving to results...'**
  String get battleFinishedGoingToResult;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

  /// No description provided for @migrationToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Migration Tools'**
  String get migrationToolsTitle;

  /// No description provided for @migrationToolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Run cleanup for legacy placeholder names in Firestore.'**
  String get migrationToolsSubtitle;

  /// No description provided for @runDryMigration.
  ///
  /// In en, this message translates to:
  /// **'Run Dry Migration'**
  String get runDryMigration;

  /// No description provided for @applyMigration.
  ///
  /// In en, this message translates to:
  /// **'Apply Migration'**
  String get applyMigration;

  /// No description provided for @migrationDryRunDone.
  ///
  /// In en, this message translates to:
  /// **'Dry run complete'**
  String get migrationDryRunDone;

  /// No description provided for @migrationApplyDone.
  ///
  /// In en, this message translates to:
  /// **'Migration applied'**
  String get migrationApplyDone;

  /// No description provided for @migrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Migration failed'**
  String get migrationFailed;

  /// No description provided for @migrationUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get migrationUsers;

  /// No description provided for @migrationDebates.
  ///
  /// In en, this message translates to:
  /// **'Debates'**
  String get migrationDebates;

  /// No description provided for @migrationWorldMessages.
  ///
  /// In en, this message translates to:
  /// **'World messages'**
  String get migrationWorldMessages;

  /// No description provided for @migrationDebateMessages.
  ///
  /// In en, this message translates to:
  /// **'Debate messages'**
  String get migrationDebateMessages;

  /// No description provided for @migrationLastRunTitle.
  ///
  /// In en, this message translates to:
  /// **'Last migration run'**
  String get migrationLastRunTitle;

  /// No description provided for @migrationLastRunEmpty.
  ///
  /// In en, this message translates to:
  /// **'No migration runs yet.'**
  String get migrationLastRunEmpty;

  /// No description provided for @migrationModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get migrationModeLabel;

  /// No description provided for @migrationModeDryRun.
  ///
  /// In en, this message translates to:
  /// **'Dry run'**
  String get migrationModeDryRun;

  /// No description provided for @migrationModeApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get migrationModeApply;

  /// No description provided for @migrationActorLabel.
  ///
  /// In en, this message translates to:
  /// **'Actor'**
  String get migrationActorLabel;

  /// No description provided for @migrationLastRunAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Started at'**
  String get migrationLastRunAtLabel;

  /// No description provided for @migrationInProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Migration is currently running'**
  String get migrationInProgressTitle;

  /// No description provided for @migrationConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply migration?'**
  String get migrationConfirmTitle;

  /// No description provided for @migrationConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will write cleanup changes to Firestore for legacy placeholder data.'**
  String get migrationConfirmBody;

  /// No description provided for @migrationHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent runs'**
  String get migrationHistoryTitle;

  /// No description provided for @migrationHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recent migration history.'**
  String get migrationHistoryEmpty;

  /// No description provided for @migrationStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get migrationStatusCompleted;

  /// No description provided for @migrationStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get migrationStatusFailed;

  /// No description provided for @migrationStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get migrationStatusInProgress;

  /// No description provided for @viewFullReport.
  ///
  /// In en, this message translates to:
  /// **'View full report'**
  String get viewFullReport;

  /// No description provided for @migrationFullReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Migration report'**
  String get migrationFullReportTitle;

  /// No description provided for @migrationStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get migrationStatusLabel;

  /// No description provided for @migrationCompletedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Completed at'**
  String get migrationCompletedAtLabel;

  /// No description provided for @migrationErrorLabel.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get migrationErrorLabel;

  /// No description provided for @losses.
  ///
  /// In en, this message translates to:
  /// **'LOSSES'**
  String get losses;

  /// No description provided for @draws.
  ///
  /// In en, this message translates to:
  /// **'DRAWS'**
  String get draws;

  /// No description provided for @reputation.
  ///
  /// In en, this message translates to:
  /// **'REPUTATION'**
  String get reputation;

  /// No description provided for @winRate.
  ///
  /// In en, this message translates to:
  /// **'WIN RATE'**
  String get winRate;

  /// No description provided for @audience.
  ///
  /// In en, this message translates to:
  /// **'AUDIENCE'**
  String get audience;

  /// No description provided for @styleLabel.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get styleLabel;

  /// No description provided for @recentDebates.
  ///
  /// In en, this message translates to:
  /// **'RECENT DEBATES'**
  String get recentDebates;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'VIEW ALL'**
  String get viewAll;

  /// No description provided for @noDebatesYet.
  ///
  /// In en, this message translates to:
  /// **'No debates yet'**
  String get noDebatesYet;

  /// No description provided for @copyIdTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy ID'**
  String get copyIdTooltip;

  /// No description provided for @profileIdCopied.
  ///
  /// In en, this message translates to:
  /// **'ID copied'**
  String get profileIdCopied;

  /// No description provided for @findFighterById.
  ///
  /// In en, this message translates to:
  /// **'Find Fighter By ID'**
  String get findFighterById;

  /// No description provided for @searchByPublicIdHint.
  ///
  /// In en, this message translates to:
  /// **'Search by public ID (e.g. VERDICT-ABC123)'**
  String get searchByPublicIdHint;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get noUsersFound;

  /// No description provided for @viewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get viewProfile;

  /// No description provided for @userWithIdNotFound.
  ///
  /// In en, this message translates to:
  /// **'User with this ID not found'**
  String get userWithIdNotFound;

  /// No description provided for @balancedStyle.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get balancedStyle;

  /// No description provided for @joinAsFighter.
  ///
  /// In en, this message translates to:
  /// **'JOIN AS FIGHTER'**
  String get joinAsFighter;

  /// No description provided for @watchAndVote.
  ///
  /// In en, this message translates to:
  /// **'WATCH & VOTE'**
  String get watchAndVote;

  /// No description provided for @roundProgress.
  ///
  /// In en, this message translates to:
  /// **'Round {current}/{total}'**
  String roundProgress(Object current, Object total);

  /// No description provided for @viewersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} watching'**
  String viewersCount(Object count);

  /// No description provided for @waitingForOpponent.
  ///
  /// In en, this message translates to:
  /// **'Waiting for opponent...'**
  String get waitingForOpponent;

  /// No description provided for @cancelChallengeTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this challenge?'**
  String get cancelChallengeTitle;

  /// No description provided for @cancelChallengeConfirmation.
  ///
  /// In en, this message translates to:
  /// **'The waiting debate will be removed. A debate that has already started cannot be cancelled here.'**
  String get cancelChallengeConfirmation;

  /// No description provided for @guestSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave your guest account?'**
  String get guestSignOutTitle;

  /// No description provided for @guestSignOutWarning.
  ///
  /// In en, this message translates to:
  /// **'Signing in as a guest again may create a new account. You will not be able to recover control of your current fighter through guest sign-in. Close the app without signing out to keep this account.'**
  String get guestSignOutWarning;

  /// No description provided for @staySignedIn.
  ///
  /// In en, this message translates to:
  /// **'Stay signed in'**
  String get staySignedIn;

  /// No description provided for @testProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Test profiles'**
  String get testProfilesTitle;

  /// No description provided for @testProfileNumber.
  ///
  /// In en, this message translates to:
  /// **'Profile {number}'**
  String testProfileNumber(int number);

  /// No description provided for @testProfileSwitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not switch profile. Check the connection and try again.'**
  String get testProfileSwitchFailed;

  /// No description provided for @aiJudgeLoading.
  ///
  /// In en, this message translates to:
  /// **'AI judge is reviewing…'**
  String get aiJudgeLoading;

  /// No description provided for @messageSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Message could not be sent. Please retry.'**
  String get messageSendFailed;

  /// No description provided for @aiVerdictTitle.
  ///
  /// In en, this message translates to:
  /// **'AI verdict'**
  String get aiVerdictTitle;

  /// No description provided for @aiJudgeNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI judging is not configured yet.'**
  String get aiJudgeNotConfigured;

  /// No description provided for @aiJudgeInsufficientContent.
  ///
  /// In en, this message translates to:
  /// **'There is not enough content for an AI verdict.'**
  String get aiJudgeInsufficientContent;

  /// No description provided for @aiJudgeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'AI verdict is unavailable. Please try again later.'**
  String get aiJudgeUnavailable;

  /// No description provided for @publicIdPending.
  ///
  /// In en, this message translates to:
  /// **'Public ID is being prepared'**
  String get publicIdPending;

  /// No description provided for @voteTotalsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Live vote totals are temporarily unavailable.'**
  String get voteTotalsUnavailable;

  /// No description provided for @voteSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Your vote could not be confirmed. Please retry.'**
  String get voteSendFailed;

  /// No description provided for @timeBankLabel.
  ///
  /// In en, this message translates to:
  /// **'Time bank'**
  String get timeBankLabel;

  /// No description provided for @timeBankHint.
  ///
  /// In en, this message translates to:
  /// **'Unused time stays with you and is added to your next turn.'**
  String get timeBankHint;

  /// No description provided for @spectatorsLiveLabel.
  ///
  /// In en, this message translates to:
  /// **'watching'**
  String get spectatorsLiveLabel;

  /// No description provided for @mediaSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get mediaSending;

  /// No description provided for @retryMediaLabel.
  ///
  /// In en, this message translates to:
  /// **'Retry send'**
  String get retryMediaLabel;

  /// No description provided for @accountSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save account'**
  String get accountSaveTitle;

  /// No description provided for @accountSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Link Google or an email to keep your fighter, history and place in debates when signing in again.'**
  String get accountSaveHint;

  /// No description provided for @accountLinkGoogle.
  ///
  /// In en, this message translates to:
  /// **'Link Google'**
  String get accountLinkGoogle;

  /// No description provided for @accountLinkEmail.
  ///
  /// In en, this message translates to:
  /// **'Link email'**
  String get accountLinkEmail;

  /// No description provided for @accountEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountEmailLabel;

  /// No description provided for @accountPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get accountPasswordLabel;

  /// No description provided for @accountPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters.'**
  String get accountPasswordHint;

  /// No description provided for @accountPasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Repeat password'**
  String get accountPasswordConfirm;

  /// No description provided for @accountPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get accountPasswordMismatch;

  /// No description provided for @accountSaved.
  ///
  /// In en, this message translates to:
  /// **'Account saved'**
  String get accountSaved;

  /// No description provided for @accountConflict.
  ///
  /// In en, this message translates to:
  /// **'This login already belongs to another account. Your current guest is unchanged. Use a different login to save this guest.'**
  String get accountConflict;

  /// No description provided for @accountSessionChanged.
  ///
  /// In en, this message translates to:
  /// **'The session changed. Open the current profile and try again.'**
  String get accountSessionChanged;

  /// No description provided for @accountProviderDisabled.
  ///
  /// In en, this message translates to:
  /// **'This sign-in method is not available yet. Your current session is unchanged.'**
  String get accountProviderDisabled;

  /// No description provided for @accountEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get accountEmailInvalid;

  /// No description provided for @accountCredentialsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check your email and password.'**
  String get accountCredentialsInvalid;

  /// No description provided for @accountNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Try again when you are online.'**
  String get accountNetworkError;

  /// No description provided for @accountActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the action. Try again later.'**
  String get accountActionFailed;

  /// No description provided for @accountEmailSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with email'**
  String get accountEmailSignIn;

  /// No description provided for @accountResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get accountResetPassword;

  /// No description provided for @accountResetSent.
  ///
  /// In en, this message translates to:
  /// **'If this email has an account, a reset link will arrive. Check your inbox and spam.'**
  String get accountResetSent;

  /// No description provided for @accountVerificationHint.
  ///
  /// In en, this message translates to:
  /// **'Email linked. Send a verification link and confirm it in your inbox.'**
  String get accountVerificationHint;

  /// No description provided for @accountSendVerification.
  ///
  /// In en, this message translates to:
  /// **'Send verification link'**
  String get accountSendVerification;

  /// No description provided for @accountCheckVerification.
  ///
  /// In en, this message translates to:
  /// **'I verified my email'**
  String get accountCheckVerification;

  /// No description provided for @accountEmailVerified.
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get accountEmailVerified;

  /// No description provided for @accountVerificationSent.
  ///
  /// In en, this message translates to:
  /// **'Verification link sent. Check your inbox and spam.'**
  String get accountVerificationSent;

  /// No description provided for @accountCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accountCancel;

  /// No description provided for @accountGoogleUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Google is not available yet. You can use email.'**
  String get accountGoogleUnavailable;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en', 'es', 'fr', 'hi', 'ru', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'en': return AppLocalizationsEn();
    case 'es': return AppLocalizationsEs();
    case 'fr': return AppLocalizationsFr();
    case 'hi': return AppLocalizationsHi();
    case 'ru': return AppLocalizationsRu();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
