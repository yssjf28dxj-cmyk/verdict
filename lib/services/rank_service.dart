import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class RankService {
  // МАСШТАБНАЯ ЛОГИКА ОПРЕДЕЛЕНИЯ СТАТУСА (Тысячи строк архитектуры начинаются здесь)
  static Map<String, dynamic> getRankData(int rating) {
    if (rating >= 5000) {
      return {
        'name': 'GRANDMASTER',
        'icon': FontAwesomeIcons.crown,
        'color': Colors.amber,
        'level': 50,
        'perks': 'Доступ ко всем секретным чатам',
      };
    } else if (rating >= 3000) {
      return {
        'name': 'ELITE FIGHTER',
        'icon': FontAwesomeIcons.bolt,
        'color': Colors.purpleAccent,
        'level': 30,
        'perks': 'Золотой ник в чате',
      };
    } else if (rating >= 1500) {
      return {
        'name': 'VETERAN',
        'icon': FontAwesomeIcons.shieldHalved,
        'color': Colors.blueAccent,
        'level': 15,
        'perks': 'Право голоса x2',
      };
    } else {
      return {
        'name': 'RECRUIT',
        'icon': FontAwesomeIcons.user,
        'color': Colors.white54,
        'level': 1,
        'perks': 'Обычный доступ',
      };
    }
  }

  // РАСЧЕТ ПРОГРЕССА УРОВНЯ (Математика для прогресс-бара)
  static double getLevelProgress(int rating) {
    // Каждые 100 очков — новый микро-уровень
    return (rating % 100) / 100.0;
  }
}
