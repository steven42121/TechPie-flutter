import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/pages/elrc_player_page.dart';
import 'package:techpie/pages/elrc_recordings_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/elrc_client.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewWidget;
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const _portal = 'https://elrc.shanghaitech.edu.cn/learn/videoreview?type=1';

void main() {
  testWidgets(
    'macOS opens the recordings portal in an attached WebView',
    (tester) async {
      final browser = _Browser();
      WebViewPlatform.instance = browser;
      await _pumpRecordingsPage(tester);
      await tester.pump();

      expect(find.text('正在连接课程录播…'), findsOneWidget);
      expect(browser.controller.loads.single.uri.toString(), _portal);
      expect(find.byType(WebViewWidget), findsOneWidget);

      browser.delegate.pageStarted!('https://ids.shanghaitech.edu.cn/authserver/login');
      await tester.pump();
      expect(find.text('登录课程录播'), findsOneWidget);
      expect(find.byType(WebViewWidget), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'macOS shows playback when WebKit hands off the video document',
    (tester) async {
      final browser = _Browser();
      WebViewPlatform.instance = browser;
      const mediaUrl = 'https://elrc.shanghaitech.edu.cn/recording.mp4';
      await tester.pumpWidget(
        MaterialApp(
          home: ElrcPlayerPage(
            courseName: 'Computer Networks',
            lessonTitle: 'Week 1',
            referer: Uri.parse(_portal),
            sources: [ElrcSource('讲台', Uri.parse(mediaUrl))],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('正在加载视频'), findsOneWidget);
      final request = browser.controller.loads.single;
      expect(request.uri.toString(), mediaUrl);
      expect(request.headers['Referer'], _portal);

      browser.delegate.resourceError!(
        const WebResourceError(
          errorCode: 204,
          description: 'WebKit media document handoff',
          isForMainFrame: true,
          url: mediaUrl,
        ),
      );
      await tester.pump();

      expect(find.text('正在加载视频'), findsNothing);
      expect(find.text('视频加载失败'), findsNothing);
      expect(find.byType(WebViewWidget), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Windows and Linux launch the official recordings site externally',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final launches = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        launches.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _pumpRecordingsPage(tester);
      await tester.pumpAndSettle();

      expect(find.byType(TpCard), findsOneWidget);
      expect(find.byType(TpPageBody), findsOneWidget);
      final button = find.text('前往课程录播网站');
      expect(button, findsOneWidget);
      expect(launches, isEmpty);
      await tester.tap(button);
      await tester.pumpAndSettle();

      final launch = launches.single;
      expect(launch.method, 'launch');
      expect(launch.arguments['url'], _portal);
      expect(launch.arguments['useWebView'], isFalse);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );
}

Future<void> _pumpRecordingsPage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = _SignedInAuth(storage, http, uniAuth);
  final tpAuth = ThirdPartyAuthService(storage, http);
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
  final campusCard = CampusCardService();
  final allowance = StudentAllowanceService(auth, tpAuth);
  addTearDown(campusCard.dispose);
  addTearDown(allowance.dispose);
  addTearDown(http.close);

  await tester.pumpWidget(
    ServiceProvider(
      authService: auth,
      debugLogger: logger,
      storageService: storage,
      themeService: themeService,
      scheduleService: schedule,
      assignmentService: assignments,
      thirdPartyAuthService: tpAuth,
      oaGymService: OaGymService(auth, storage, tpAuth),
      egateAppService: EgateAppService(auth, storage, tpAuth),
      studentAllowanceService: allowance,
      uniAuthService: uniAuth,
      syncService: SyncService(auth, tpAuth, storage),
      updateService: UpdateService(),
      campusCardService: campusCard,
      ecardBindService: EcardBindService(),
      child: MaterialApp(
        theme: themeService.lightTheme,
        home: const ElrcRecordingsPage(),
      ),
    ),
  );
}

class _SignedInAuth extends AuthService {
  _SignedInAuth(super.storage, super.http, super.uniAuth);

  @override
  bool get isLoggedIn => true;
}

class _Browser extends WebViewPlatform {
  late _Controller controller;
  late _Delegate delegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      controller = _Controller(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      delegate = _Delegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _View(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) =>
      _Cookies(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();

  final loads = <LoadRequestParams>[];

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {}
  @override
  Future<void> clearLocalStorage() async {}
  @override
  Future<void> runJavaScript(String javaScript) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async => loads.add(params);
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();

  PageEventCallback? pageStarted;
  WebResourceErrorCallback? resourceError;

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback callback) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async => pageStarted = callback;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async =>
      resourceError = callback;
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Cookies extends PlatformWebViewCookieManager {
  _Cookies(super.params) : super.implementation();

  @override
  Future<bool> clearCookies() async => true;
}
