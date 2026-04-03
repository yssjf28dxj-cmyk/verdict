import 'package:get_it/get_it.dart';
import '../services/app_locale_controller.dart';
import '../services/sound_service.dart';

final getIt = GetIt.instance;

void setupDI() {
  // Регистрируем существующие сервисы.
  // Это первый шаг ухода от хардкод-синглтонов.
  getIt.registerSingleton<AppLocaleController>(AppLocaleController.instance);
  getIt.registerSingleton<SoundService>(SoundService.instance);
  
  // TODO: По мере рефакторинга переносить остальные сервисы сюда
  // Пример: getIt.registerLazySingleton<AuthService>(() => AuthService());
}
