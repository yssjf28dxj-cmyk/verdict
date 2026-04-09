import 'package:get_it/get_it.dart';
import '../services/app_locale_controller.dart';
import '../services/sound_service.dart';
import '../services/pending_debate_service.dart';

final getIt = GetIt.instance;

void setupDI() {
  getIt.registerSingleton<AppLocaleController>(AppLocaleController.instance);
  getIt.registerSingleton<SoundService>(SoundService.instance);
  getIt.registerSingleton<PendingDebateService>(PendingDebateService.instance);
}
