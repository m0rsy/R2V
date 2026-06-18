import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'; // ✅ added (mouse drag)

// Screens
import 'screens/welcome.dart';
import 'screens/signup.dart';
import 'screens/signin.dart';
import 'screens/verify_code.dart';
import 'screens/forgot_password.dart';
import 'screens/otp_verification.dart';
import 'screens/set_new_password.dart';
import 'screens/oauth_callback.dart';
import 'screens/complete_profile.dart';
import 'screens/home_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/photo_scan_guided.dart';
import 'screens/photogrammetry_job_status_screen.dart';
import 'screens/photogrammetry_output_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'payments/payment_screen.dart';
import 'api/marketplace_service.dart';
import 'screens/freelance_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/widgets/global_chat_overlay.dart';

import 'screens/spline_scan_hero.dart';

import 'theme/app_theme.dart';
import 'widgets/ui/app_states.dart';

// ✅ GLOBAL THEME NOTIFIER
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Transparent status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp(const R2VApp());
}

/// ✅ Enables dragging scroll with mouse/trackpad on web/desktop
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

class R2VApp extends StatelessWidget {
  const R2VApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'R2V',

          // ✅ IMPORTANT: allows PageView/ListView drag by mouse on web
          scrollBehavior: const AppScrollBehavior(),

          // ✅ THEME MODE CONFIGURATION
          themeMode: currentMode,

          // ✅ Centralized design system (lib/theme/app_theme.dart)
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),

          initialRoute: '/signin',

          // -------------------------------------------------------------
          // STATIC ROUTES (all routed through onGenerateRoute)
          // -------------------------------------------------------------
          onGenerateRoute: (settings) {
            Widget page;
            final routeName = settings.name ?? '';

            // ── Talent (freelance) dynamic detail routes ──
            // The TalentScreen navigates with the `/talent/...` prefix; these
            // handlers must run before the static switch below.
            if (routeName.startsWith('/talent/talents/')) {
              page = TalentScreen(
                mode: TalentPageMode.talentDetail,
                id: routeName.substring('/talent/talents/'.length),
              );
              return _animatedRoute(GlobalChatOverlay(showButton: true, child: page), settings);
            }
            if (routeName.startsWith('/talent/services/')) {
              page = TalentScreen(
                mode: TalentPageMode.serviceDetail,
                id: routeName.substring('/talent/services/'.length),
              );
              return _animatedRoute(GlobalChatOverlay(showButton: true, child: page), settings);
            }
            if (routeName.startsWith('/talent/orders/')) {
              page = TalentScreen(
                mode: TalentPageMode.orderDetail,
                id: routeName.substring('/talent/orders/'.length),
              );
              return _animatedRoute(GlobalChatOverlay(showButton: true, child: page), settings);
            }
            if (routeName.startsWith('/talent/chat/')) {
              page = TalentScreen(
                mode: TalentPageMode.chat,
                id: routeName.substring('/talent/chat/'.length),
              );
              return _animatedRoute(GlobalChatOverlay(showButton: true, child: page), settings);
            }

            // ── OAuth callback ──
            // On Flutter web (hash strategy) the route name arrives with the
            // token query string attached, e.g.
            //   /oauth/callback?provider=google&access_token=...&refresh_token=...
            // The exact-match switch below would miss that and fall through to a
            // blank route, so match on the path part only here. The screen reads
            // the tokens from Uri.base, not from settings. It is auth-exempt, so
            // it intentionally skips the GlobalChatOverlay wrapper.
            if (routeName.split('?').first == '/oauth/callback') {
              return _animatedRoute(const OAuthCallbackScreen(), settings);
            }

            // ── Marketplace asset deep link ──
            // Shared links look like `/explore?asset=<asset_id>` (hash route).
            // The exact-match switch below would miss the query string, so parse
            // the asset id here and let Explore auto-open that asset's detail.
            if (routeName.split('?').first == '/explore' && routeName.contains('?')) {
              final assetId =
                  Uri.splitQueryString(routeName.split('?').last)['asset'];
              return _animatedRoute(
                GlobalChatOverlay(
                  showButton: true,
                  child: ExploreScreen(
                    initialAssetId:
                        (assetId != null && assetId.isNotEmpty) ? assetId : null,
                  ),
                ),
                settings,
              );
            }

            switch (settings.name) {
              case '/welcome':
                page = Welcome();
                break;
              case '/signup':
                page = SignUp();
                break;
              case '/signin':
                page = SignIn();
                break;
              case '/forgot':
                page = ForgotPassword();
                break;
              case '/setnewpass':
                page = SetNewPasswordPage(
                  resetToken: settings.arguments is String
                      ? settings.arguments as String
                      : null,
                );
                break;
              case '/completeprofile':
                page = CompleteProfile();
                break;
              case '/oauth/callback':
                page = const OAuthCallbackScreen();
                break;
              case '/home':
                page = const HomeScreen();
                break;
              case '/aichat':
                page = const AIChatScreen();
                break;
              case '/photo_scan':
                page = const PhotoScanGuidedScreen();
                break;
              case '/photogrammetry/status':
                final args = settings.arguments;
                final jobId = args is Map ? args['jobId']?.toString() : null;
                if (jobId == null || jobId.isEmpty) {
                  page = const AppErrorScaffold(
                    message: 'This scan job could not be opened because no '
                        'job reference was provided.',
                  );
                } else {
                  page = PhotogrammetryJobStatusScreen(jobId: jobId);
                }
                break;
              case '/photogrammetry/output':
                final outputArgs = settings.arguments;
                final outputJobId = outputArgs is Map
                    ? outputArgs['jobId']?.toString()
                    : null;
                if (outputJobId == null || outputJobId.isEmpty) {
                  page = const AppErrorScaffold(
                    message: 'This scan result could not be opened because no '
                        'job reference was provided.',
                  );
                } else {
                  page = PhotogrammetryOutputScreen(jobId: outputJobId);
                }
                break;
              case '/settings':
                page = const SettingsScreen();
                break;
              case '/explore':
                page = const ExploreScreen();
                break;
              case '/analysis':
                page = const AnalysisScreen();
                break;
              case '/admin':
                page = const AdminDashboardScreen();
                break;

              // ✅ TALENT (FREELANCE) ROUTES
              // Canonical `/talent/...` paths used by TalentScreen. Legacy
              // `/freelance` and `/freelance_hub` entry points are aliased so
              // any not-yet-migrated callers keep working.
              case '/talent':
              case '/freelance':
              case '/freelance_hub':
                page = const TalentScreen(mode: TalentPageMode.home);
                break;
              case '/talent/talents':
              case '/freelance/freelancers':
                page = const TalentScreen(mode: TalentPageMode.talents);
                break;
              case '/talent/services':
              case '/freelance/services':
                final serviceArgs = settings.arguments is Map
                    ? (settings.arguments as Map)
                    : const {};
                page = TalentScreen(
                  mode: TalentPageMode.services,
                  search: serviceArgs['search']?.toString(),
                  category: serviceArgs['category']?.toString(),
                );
                break;
              case '/talent/post-project':
              case '/freelance/post-project':
                page = TalentScreen(
                  mode: TalentPageMode.postProject,
                  prefill: settings.arguments is Map
                      ? (settings.arguments as Map).cast<String, dynamic>()
                      : null,
                );
                break;
              case '/talent/my-orders':
              case '/freelance/my-orders':
                page = const TalentScreen(mode: TalentPageMode.orders);
                break;
              case '/talent/become-talent':
              case '/freelance/become-freelancer':
                page = const TalentScreen(mode: TalentPageMode.apply);
                break;
              case '/talent/dashboard':
              case '/freelance/dashboard':
                page = const TalentScreen(mode: TalentPageMode.dashboard);
                break;
              case '/chat':
                final args = settings.arguments;
                page = ChatScreen(
                  initialUserId:
                      args is Map ? args['userId']?.toString() : null,
                );
                break;
              case '/profile':
                final args = settings.arguments;
                String? userId;
                String? username;
                String? initialTab;
                if (args is Map) {
                  userId = args['userId']?.toString();
                  username = args['username']?.toString();
                  initialTab = args['tab']?.toString();
                }
                page = ProfileScreen(
                  userId: userId,
                  username: username ?? 'User',
                  initialTab: initialTab,
                );
                break;
              case '/editprofile':
                page = const ProfileScreen();
                break;

              // ---------------------- Dynamic routes ----------------------
              case '/verifycode':
                page = VerifyCode(email: settings.arguments as String);
                break;

              case '/verifyotp':
                page = OTPVerification(email: settings.arguments as String);
                break;

              case '/payment':
                final args = settings.arguments;

                if (args is MarketplaceAsset) {
                  page = PaymentScreen(asset: args);
                } else {
                  page = const AppErrorScaffold(
                    message: 'No item was selected for checkout.',
                  );
                }
                break;

              case '/spline_test':
                page = SplineScanHeroScreen();
                break;

              default:
                return null;
            }

            // Global chat: overlay a floating Messages button on every
            // authenticated page (hidden on the auth flow and on /chat itself).
            const authExempt = {
              '/welcome',
              '/signup',
              '/signin',
              '/forgot',
              '/setnewpass',
              '/completeprofile',
              '/oauth/callback',
              '/verifycode',
              '/verifyotp',
            };
            if (!authExempt.contains(routeName)) {
              page = GlobalChatOverlay(
                showButton: routeName != '/chat',
                child: page,
              );
            }

            return _animatedRoute(page, settings);
          },

          // Safety net: any route onGenerateRoute can't resolve (the `default`
          // case above returns null) — e.g. a stale browser-history entry or a
          // deep link to a removed path — lands on Home instead of a blank/
          // white screen.
          onUnknownRoute: (settings) => _animatedRoute(
            GlobalChatOverlay(showButton: true, child: const HomeScreen()),
            const RouteSettings(name: '/home'),
          ),
        );
      },
    );
  }
}

// --------------------------------------------------------------------
// 🔥 GLOBAL PAGE TRANSITION (Fade + Slide Up)
// --------------------------------------------------------------------
Route _animatedRoute(Widget page, RouteSettings settings) {
  if (kIsWeb) {
    return PageRouteBuilder(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 230),
      pageBuilder: (_, animation, __) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutQuad,
          ),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        );
      },
    );
  }

  return PageRouteBuilder(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, animation, __) => page,
    transitionsBuilder: (_, animation, __, child) {
      final slideUp = Tween<Offset>(
        begin: const Offset(0, 0.18),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutQuad));

      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

      final scaleBackground = Tween<double>(
        begin: 1.0,
        end: 0.95,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      return Stack(
        children: [
          Transform.scale(
            scale: scaleBackground.value,
            child: IgnorePointer(ignoring: true),
          ),
          FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slideUp, child: child),
          ),
        ],
      );
    },
  );
}
