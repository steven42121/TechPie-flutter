import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/assignment_service.dart';
import 'services/auth_service.dart';
import 'services/debug_logger.dart';
import 'services/http_client.dart';
import 'services/island_service.dart';
import 'services/schedule_service.dart';
import 'services/storage_service.dart';
import 'services/third_party_auth_service.dart';
import 'services/uni_auth_service.dart';

/// Rebuilds the absolute Android alarms from locally cached schedule data.
/// This entrypoint deliberately avoids network requests and account refreshes.
Future<void> runIslandTimelineRebuild() async {
  WidgetsFlutterBinding.ensureInitialized();
  var success = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService(logger: logger);
    final auth = AuthService(storage, http, uniAuth, logger: logger);
    final thirdParty = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, thirdParty);
    final assignments = AssignmentService(
      storage,
      http,
      auth,
      thirdParty,
      schedule,
    );
    final island = IslandService(storage, schedule, assignments);

    await schedule.loadCachedData();
    assignments.loadCached();
    await island.scheduleTimeline();
    await island.refreshNow(force: true);
    success = true;
  } catch (_) {
    // The next app launch or clock change can rebuild the timeline again.
  } finally {
    try {
      await const MethodChannel(
        'techpie/background',
      ).invokeMethod<bool>('done', {'success': success});
    } on PlatformException {
      // The host worker may have timed out or been cancelled.
    } on MissingPluginException {
      // No background Android host.
    }
  }
}
