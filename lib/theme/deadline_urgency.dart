import 'package:flutter/painting.dart';

import 'tp_colors.dart';

/// Shared deadline status for Home and the full Deadlines list.
enum DeadlineUrgency {
  scheduled,
  approaching,
  urgent;

  static DeadlineUrgency fromRemaining(
    Duration remaining, {
    bool needsAttention = false,
  }) {
    if (needsAttention || remaining < const Duration(days: 1)) {
      return DeadlineUrgency.urgent;
    }
    if (remaining < const Duration(days: 3)) {
      return DeadlineUrgency.approaching;
    }
    return DeadlineUrgency.scheduled;
  }

  Color color(TpColors colors) => switch (this) {
        scheduled => colors.infoBlue,
        approaching => colors.warningAmber,
        urgent => colors.dangerRed,
      };
}

/// The bar fills as the deadline approaches. The half-full point is two
/// days away. More distant dates stay distinguishable instead of sharing a
/// fixed fill across the following weeks.
double deadlineUrgencyProgress(Duration remaining) {
  if (remaining <= Duration.zero) return 1;
  final days = remaining.inMilliseconds / Duration.millisecondsPerDay;
  return 1 / (1 + days / 2);
}
