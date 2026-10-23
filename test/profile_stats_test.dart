import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/utils/profile_stats.dart';

void main() {
  test('server statistics replace legacy values including a zero reset', () {
    final profile = <String, dynamic>{
      'rating': 0,
      'wins': 3,
      'stats': {'rating': 900, 'wins': 12},
    };
    expect(profileStatistic(profile, 'rating'), 0);
    expect(profileStatistic(profile, 'wins'), 3);
  });

  test('partially migrated profiles retain legacy fields', () {
    final profile = <String, dynamic>{
      'reputation': -2,
      'viewerScore': 1.5,
      'stats': {'wins': 2},
      'debateStyle': 'Analytical',
    };
    expect(profileStatistic(profile, 'reputation'), -2);
    expect(profileStatistic(profile, 'viewerScore'), 1.5);
    expect(profileDebateStyle(profile), 'Analytical');
  });

  test('malformed profile values cannot poison rank calculations', () {
    final profile = <String, dynamic>{
      'rating': double.infinity,
      'wins': '10',
      'stats': {'rating': double.nan, 'wins': null},
    };
    expect(profileStatistic(profile, 'rating'), 0);
    expect(profileStatistic(profile, 'wins'), 0);
    expect(profileStatistic(profile, 'losses'), 0);
    expect(profileDebateStyle(profile), 'Balanced');
  });

  test('current server style wins while empty values preserve legacy style', () {
    expect(
        profileDebateStyle({
          'debateStyle': ' Strategic ',
          'stats': {'debateStyle': 'Balanced'},
        }),
        'Strategic');
    expect(
        profileDebateStyle({
          'debateStyle': 'Analytical',
          'stats': {'debateStyle': ''},
        }),
        'Analytical');
  });
}
