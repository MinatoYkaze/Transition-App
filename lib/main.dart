import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;

void main() {
  runApp(const TransitionApp());
}

// ==========================================
// DESIGN SYSTEM TOKENS
// A small, consistent palette + radii + shadows so the whole app reads as
// one cohesive product instead of a set of loosely styled screens.
// ==========================================
class AppColors {
  AppColors._();
  // Rebranded to a royal-blue "decoded data" palette to match the
  // reference product screens (bold blue accent, off-white surfaces,
  // near-black pill navigation, high-contrast big numerals).
  static const Color primary = Color(0xFF3557E8);
  static const Color primaryDark = Color(0xFF1F3FBE);
  static const Color primarySoft = Color(0xFFE8ECFD);
  static const Color accent = Color(0xFF5B8DEF);
  static const Color ink = Color(0xFF0B0B12);
  static const Color slate = Color(0xFF32343E);
  static const Color muted = Color(0xFF868B98);
  static const Color faint = Color(0xFFB7BAC5);
  static const Color border = Color(0xFFE9EAF1);
  static const Color surface = Colors.white;
  static const Color bg = Color(0xFFF3F4F9);
  static const Color chrome = Color(0xFF111114);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEF2F2);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFFF7ED);
  static const Color info = Color(0xFF2563EB);
  static const Color infoSoft = Color(0xFFEFF6FF);
}

class AppRadius {
  AppRadius._();
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
}

final List<BoxShadow> kCardShadow = [
  BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 16,
      offset: const Offset(0, 6)),
];

// ==========================================
// DATA MODELS & ENUMS
// ==========================================
enum UserRole { landing, roleSelect, citizen, student, industrialist }

enum AppView {
  landing,
  roleSelect,
  // Citizen Views
  citizenHome,
  citizenReportWizard,
  citizenGeofenceCheck,
  problemDetailView,
  // Student Views
  studentHome,
  studentApplication,
  studentWorkspace,
  studentEvidenceSubmit,
  // Industrialist Views
  industrialistHome,
  industrialistSquadSelect,
  industrialistLiveFeed,
  industrialistAuditVerdict,
}

class ProblemItem {
  final String id;
  final String title;
  final String category;
  final String location;
  final String priorityLabel;
  final int priorityScore;
  final String complexityLabel;
  final int complexityScore;
  final int commutersAffected;
  final String supportRequired;
  final String requiredSkills;
  final String currentStage;
  final String sponsorName;
  final double latitude;
  final double longitude;

  ProblemItem({
    required this.id,
    required this.title,
    required this.category,
    required this.location,
    required this.priorityLabel,
    required this.priorityScore,
    required this.complexityLabel,
    required this.complexityScore,
    required this.commutersAffected,
    required this.supportRequired,
    required this.requiredSkills,
    required this.currentStage,
    required this.sponsorName,
    this.latitude = 28.5355,
    this.longitude = 77.3910,
  });
}

// Small holder for a bottom-nav entry (used to compute the active/highlighted
// pill without repeating the same logic across items).
class _NavEntry {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  _NavEntry(this.icon, this.label, this.onTap, this.active);
}

// ==========================================
// MAP MARKER DATA MODEL
// ==========================================
class MapMarkerData {
  final ll.LatLng point;
  final IconData icon;
  final Color color;
  final String label;

  MapMarkerData({
    required this.point,
    required this.icon,
    required this.color,
    required this.label,
  });
}

// ==========================================
// MAIN APPLICATION ENTRY POINT
// ==========================================
class TransitionApp extends StatefulWidget {
  const TransitionApp({super.key});

  @override
  State<TransitionApp> createState() => _TransitionAppState();
}

class _TransitionAppState extends State<TransitionApp> {
  UserRole _currentRole = UserRole.landing;
  AppView _currentView = AppView.landing;
  final List<AppView> _viewHistory = [];

  // Global Mock State
  final List<ProblemItem> _problems = [
    ProblemItem(
      id: "TR-8812",
      title: "Sector 18 Road Infrastructure / Sinkhole",
      category: "Road / Infrastructure",
      location: "Ward 14 • 8th Cross Arterial Junction",
      priorityLabel: "High",
      priorityScore: 92,
      complexityLabel: "Medium",
      complexityScore: 58,
      commutersAffected: 1450,
      supportRequired: "\$420 Capital + Bitumen Compactor",
      requiredSkills: "Civil Engineering, Asphalt Testing",
      currentStage: "Under Execution",
      sponsorName: "Apex Infra Ventures",
      latitude: 28.5355,
      longitude: 77.3910,
    ),
    ProblemItem(
      id: "TR-7721",
      title: "Damaged Streetlight Cluster & Cabling",
      category: "Electricity & Safety",
      location: "Sector 14 Crossroad Grid Sub-station",
      priorityLabel: "Critical",
      priorityScore: 850,
      complexityLabel: "Feasible",
      complexityScore: 45,
      commutersAffected: 850,
      supportRequired: "\$350 Parts Budget + Testing Gear",
      requiredSkills: "Multimeter Diagnostics, IP67 Sealing",
      currentStage: "Industrialist Sponsored",
      sponsorName: "Apex Energy Labs",
      latitude: 28.5402,
      longitude: 77.3831,
    ),
  ];

  int _reportStep = 1;
  String _citizenSelectedCategory = "Road damage";
  bool _confirmCheck = false;
  String _auditVerdict = "Pending";

  // Camera / document / map state (report wizard)
  final List<XFile> _reportPhotos = [];
  final List<PlatformFile> _reportDocuments = [];
  ll.LatLng? _reportSelectedLocation;
  String _reportAddressPreview = "Detecting address...";

  // Camera state (student before/after evidence)
  XFile? _beforePhoto;
  XFile? _afterPhoto;

  void _navigateTo(AppView view) {
    if (view == _currentView) return;
    setState(() {
      _viewHistory.add(_currentView);
      _currentView = view;
    });
  }

  // Pops one screen off the in-app history. Returns false when there was
  // nowhere left to go (caller should then fall back to system behaviour,
  // e.g. exiting the app or asking for confirmation).
  bool _goBack() {
    if (_viewHistory.isNotEmpty) {
      setState(() => _currentView = _viewHistory.removeLast());
      return true;
    }
    if (_currentRole != UserRole.landing &&
        _currentRole != UserRole.roleSelect) {
      setState(() {
        _currentRole = UserRole.roleSelect;
        _currentView = AppView.roleSelect;
      });
      return true;
    }
    if (_currentView != AppView.landing) {
      setState(() {
        _currentRole = UserRole.landing;
        _currentView = AppView.landing;
      });
      return true;
    }
    return false;
  }

  // ==========================================
  // LOCATION HELPERS (device GPS via geolocator)
  // ==========================================
  Future<ll.LatLng?> _getCurrentDeviceLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Please enable Location Services to continue.")));
      }
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Location permission denied.")));
        }
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "Location permission permanently denied. Enable it from app settings.")));
      }
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high));
    return ll.LatLng(pos.latitude, pos.longitude);
  }

  // Reverse-geocode a point into a readable address using OpenStreetMap's
  // free Nominatim service.
  Future<String> _reverseGeocode(ll.LatLng point) async {
    try {
      final uri = Uri.parse(
          "https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=0");
      final res = await http.get(uri, headers: {
        "User-Agent": "TransitionCivicApp/1.0"
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final display = data["display_name"];
        if (display is String && display.isNotEmpty) return display;
      }
    } catch (_) {
      // Fall through to coordinate string on any network/geocoding failure.
    }
    return "${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}";
  }

  Future<void> _useCurrentLocationForReport() async {
    setState(() => _reportAddressPreview = "Locating you...");
    final loc = await _getCurrentDeviceLocation();
    if (loc == null) {
      setState(() => _reportAddressPreview = "Location unavailable");
      return;
    }
    final address = await _reverseGeocode(loc);
    setState(() {
      _reportSelectedLocation = loc;
      _reportAddressPreview = address;
    });
  }

  // Quick photo/document attach sheet used inside chat-style workspaces.
  void _showAttachmentSheet(BuildContext context) {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                title: const Text("Take Photo"),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final file = await picker.pickImage(
                      source: ImageSource.camera, imageQuality: 85);
                  if (file != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Photo attached.")));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.info),
                title: const Text("Choose from Gallery"),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final file = await picker.pickImage(
                      source: ImageSource.gallery, imageQuality: 85);
                  if (file != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Photo attached.")));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file, color: AppColors.muted),
                title: const Text("Upload Document"),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final result = await FilePicker.platform.pickFiles();
                  if (result != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text("${result.files.first.name} attached.")));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _switchRole(UserRole role) {
    setState(() {
      _viewHistory.clear();
      _currentRole = role;
      switch (role) {
        case UserRole.landing:
          _currentView = AppView.landing;
          break;
        case UserRole.roleSelect:
          _currentView = AppView.roleSelect;
          break;
        case UserRole.citizen:
          _currentView = AppView.citizenHome;
          break;
        case UserRole.student:
          _currentView = AppView.studentHome;
          break;
        case UserRole.industrialist:
          _currentView = AppView.industrialistHome;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TRANSITION Platform',
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(),
      home: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (didPop) return;
          final handled = _goBack();
          if (!handled) SystemNavigator.pop();
        },
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                _buildGlobalTopBar(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                                begin: const Offset(0, 0.02), end: Offset.zero)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_currentView),
                      child: _buildBody(),
                    ),
                  ),
                ),
                if (_currentRole != UserRole.landing &&
                    _currentRole != UserRole.roleSelect)
                  _buildRoleNavigationBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _buildAppTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.ink,
      error: AppColors.danger,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      primaryColor: AppColors.primary,
      colorScheme: colorScheme,
      fontFamily: 'Roboto',
      splashFactory: InkRipple.splashFactory,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: -0.4),
        titleLarge:
            TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
        titleMedium:
            TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
        bodyMedium: TextStyle(color: AppColors.slate, height: 1.4),
        bodySmall: TextStyle(color: AppColors.muted),
        labelLarge: TextStyle(fontWeight: FontWeight.w600),
      ),
      iconTheme: const IconThemeData(color: AppColors.slate),
      dividerTheme: const DividerThemeData(
          color: AppColors.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        color: AppColors.surface,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bg,
        selectedColor: AppColors.primarySoft,
        labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            side: const BorderSide(color: AppColors.border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.faint, fontSize: 13.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.slate,
          side: const BorderSide(color: AppColors.border, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : Colors.transparent),
      ),
    );
  }

  // Header switcher for rapid testing across all portals
  String _screenTitle() {
    switch (_currentView) {
      case AppView.landing:
        return "";
      case AppView.roleSelect:
        return "Choose Your Role";
      case AppView.citizenHome:
        return "Citizen Dashboard";
      case AppView.citizenReportWizard:
        return "Report a Problem";
      case AppView.citizenGeofenceCheck:
        return "Verify Nearby";
      case AppView.problemDetailView:
        return "Problem Details";
      case AppView.studentHome:
        return "Student Dashboard";
      case AppView.studentApplication:
        return "Apply to Solve";
      case AppView.studentWorkspace:
        return "My Workspace";
      case AppView.studentEvidenceSubmit:
        return "Submit Evidence";
      case AppView.industrialistHome:
        return "Industrialist Hub";
      case AppView.industrialistSquadSelect:
        return "Select a Squad";
      case AppView.industrialistLiveFeed:
        return "Live Feed";
      case AppView.industrialistAuditVerdict:
        return "Audit Verdict";
    }
  }

  void _openWorkspaceSwitcher() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        Widget tile(UserRole role, IconData icon, String label, String sub) {
          final selected = _currentRole == role;
          return ListTile(
            onTap: () {
              Navigator.pop(sheetContext);
              _switchRole(role);
            },
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: selected ? Colors.white : AppColors.slate, size: 20),
            ),
            title: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            trailing: selected
                ? const Icon(Icons.check_circle,
                    color: AppColors.primary, size: 20)
                : null,
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: const [
                      Text("Switch Workspace",
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                tile(UserRole.citizen, Icons.groups_2_rounded, "Citizen",
                    "Report & verify local problems"),
                tile(UserRole.student, Icons.school_rounded, "Student",
                    "Apply and execute fixes"),
                tile(UserRole.industrialist, Icons.apartment_rounded,
                    "Industrialist", "Sponsor & mentor squads"),
                const Divider(height: 20),
                tile(UserRole.landing, Icons.home_rounded, "Welcome Screen",
                    "Back to the start"),
              ],
            ),
          ),
        );
      },
    );
  }

  // Minimal, native-feeling top bar: no chrome at all on the welcome
  // screen (full-bleed onboarding), otherwise a light bar with a back
  // arrow, the current screen's title, and a tucked-away workspace
  // switcher instead of a permanent dev-style dropdown.
  Widget _buildGlobalTopBar() {
    if (_currentView == AppView.landing) return const SizedBox.shrink();

    final canGoBack = _viewHistory.isNotEmpty ||
        (_currentRole != UserRole.landing &&
            _currentRole != UserRole.roleSelect);

    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      child: Row(
        children: [
          if (canGoBack)
            IconButton(
              onPressed: () => _goBack(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.ink, size: 18),
              splashRadius: 20,
              tooltip: "Back",
            )
          else
            const SizedBox(width: 16),
          Expanded(
            child: Text(
              _screenTitle(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: -0.2),
            ),
          ),
          InkWell(
            onTap: _toggleTheme,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _openWorkspaceSwitcher,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(Icons.grid_view_rounded,
                  color: Theme.of(context).colorScheme.onSurface, size: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentView) {
      case AppView.landing:
        return _buildLandingView();
      case AppView.roleSelect:
        return _buildRoleSelectionView();
      // Citizen Views
      case AppView.citizenHome:
        return _buildCitizenDashboard();
      case AppView.citizenReportWizard:
        return _buildCitizenReportWizard();
      case AppView.citizenGeofenceCheck:
        return _buildCitizenGeofencePrompt();
      case AppView.problemDetailView:
        return _buildProblemDetailView();
      // Student Views
      case AppView.studentHome:
        return _buildStudentDashboard();
      case AppView.studentApplication:
        return _buildStudentApplicationView();
      case AppView.studentWorkspace:
        return _buildStudentWorkspaceView();
      case AppView.studentEvidenceSubmit:
        return _buildStudentEvidenceSubmissionView();
      // Industrialist Views
      case AppView.industrialistHome:
        return _buildIndustrialistDashboard();
      case AppView.industrialistSquadSelect:
        return _buildIndustrialistSquadSelectionView();
      case AppView.industrialistLiveFeed:
        return _buildIndustrialistLiveFeedView();
      case AppView.industrialistAuditVerdict:
        return _buildIndustrialistAuditVerdictView();
    }
  }

  // Nav bar mirroring role navigation
  Widget _buildRoleNavigationBar() {
    final items = <_NavEntry>[
      _NavEntry(Icons.home_rounded, "Home", () {
        if (_currentRole == UserRole.citizen) {
          _navigateTo(AppView.citizenHome);
        }
        if (_currentRole == UserRole.student) {
          _navigateTo(AppView.studentHome);
        }
        if (_currentRole == UserRole.industrialist) {
          _navigateTo(AppView.industrialistHome);
        }
      }, _homeViewFor(_currentRole) == _currentView),
      _NavEntry(
          Icons.map_rounded,
          "Map/Ops",
          () => _navigateTo(AppView.problemDetailView),
          _currentView == AppView.problemDetailView),
      if (_currentRole == UserRole.citizen)
        _NavEntry(
            Icons.add_circle_rounded,
            "Report",
            () => _navigateTo(AppView.citizenReportWizard),
            _currentView == AppView.citizenReportWizard),
      if (_currentRole == UserRole.student)
        _NavEntry(
            Icons.build_rounded,
            "Workspace",
            () => _navigateTo(AppView.studentWorkspace),
            _currentView == AppView.studentWorkspace),
      if (_currentRole == UserRole.industrialist)
        _NavEntry(
            Icons.groups_rounded,
            "Squads",
            () => _navigateTo(AppView.industrialistSquadSelect),
            _currentView == AppView.industrialistSquadSelect),
      _NavEntry(Icons.verified_rounded, "Audit", () {
        if (_currentRole == UserRole.industrialist) {
          _navigateTo(AppView.industrialistAuditVerdict);
        }
        if (_currentRole == UserRole.citizen) {
          _navigateTo(AppView.citizenGeofenceCheck);
        }
        if (_currentRole == UserRole.student) {
          _navigateTo(AppView.studentEvidenceSubmit);
        }
      },
          _currentView == AppView.industrialistAuditVerdict ||
              _currentView == AppView.citizenGeofenceCheck ||
              _currentView == AppView.studentEvidenceSubmit),
    ];

    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.chrome,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 24,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [for (final item in items) _navItem(item)],
        ),
      ),
    );
  }

  AppView _homeViewFor(UserRole role) {
    switch (role) {
      case UserRole.citizen:
        return AppView.citizenHome;
      case UserRole.student:
        return AppView.studentHome;
      case UserRole.industrialist:
        return AppView.industrialistHome;
      default:
        return AppView.landing;
    }
  }

  // Pill-shaped, floating dark navigation bar with circular icon buttons —
  // the active tab lights up in the brand blue, inactive tabs stay on the
  // dark chrome, matching the reference product's nav pattern.
  Widget _navItem(_NavEntry entry) {
    return InkWell(
      onTap: entry.onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: entry.active ? AppColors.primary : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(entry.icon,
            color: entry.active ? Colors.white : Colors.white54, size: 22),
      ),
    );
  }

  // ==========================================
  // SCREEN 1: WELCOME / LANDING PAGE
  // ==========================================
  Widget _buildLandingView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full-bleed gradient hero — the welcome screen has no chrome
          // bar above it, so this doubles as the app's masthead.
          Container(
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 40),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(36),
                bottomRight: Radius.circular(36),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.hub_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Text("TRANSITION",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 1.2)),
                  ],
                ),
                const SizedBox(height: 28),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "● CIVIC TECH MOVEMENT",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        letterSpacing: 0.4),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  "From civic reporting to\nreal-world action.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.5,
                      color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  "Report verified local problems, connect them with industrialist mentors, and let students execute practical fixes.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13.5,
                      height: 1.45),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              children: [
                // Interactive Action Engine Illustration Node
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: AppColors.border),
                    boxShadow: kCardShadow,
                  ),
                  child: Column(
                    children: [
                      const Text("The Civic Action Engine",
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _nodeChip("Citizen", "Reports & Verifies",
                              AppColors.primary),
                          const Icon(Icons.arrow_forward,
                              color: AppColors.faint),
                          _nodeChip("Industrialist", "Mentors & Funds",
                              AppColors.ink),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Icon(Icons.arrow_downward, color: AppColors.faint),
                      const SizedBox(height: 12),
                      _nodeChip(
                          "Student Unit", "Executes Work", AppColors.info),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const [
                    _StatBox(value: "8.4k", label: "ISSUES LOGGED"),
                    _StatBox(value: "94%", label: "RESOLVED RATE"),
                    _StatBox(value: "320+", label: "CAMPUS TEAMS"),
                  ],
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => _switchRole(UserRole.roleSelect),
                    child: const Text("Get Started →",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {},
                  child: const Text("How TRANSITION Works"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nodeChip(String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          Text(subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 2: ROLE SELECTION
  // ==========================================
  Widget _buildRoleSelectionView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("02 STEP 2 OF 3",
              style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          const SizedBox(height: 6),
          const Text(
              "The role selection customizes your civic dashboard and active toolsets.",
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 20),
          _roleCard(
            role: UserRole.citizen,
            title: "Citizen",
            badge: "Ground Team",
            description: "Community Watch & Local Verification",
            bullets: [
              "Report civic problems",
              "Verify nearby issues",
              "Track outcomes"
            ],
            buttonLabel: "Select Citizen",
          ),
          const SizedBox(height: 16),
          _roleCard(
            role: UserRole.student,
            title: "Student",
            badge: "Field Unit",
            description: "Hands-on Engineering & Civic Execution",
            bullets: [
              "Discover problems",
              "Join intervention teams",
              "Submit execution evidence"
            ],
            buttonLabel: "Select Student",
          ),
          const SizedBox(height: 16),
          _roleCard(
            role: UserRole.industrialist,
            title: "Industrialist",
            badge: "Sponsor & Mentor",
            description: "Mentorship, Capital & Resources",
            bullets: [
              "Take up prioritized problems",
              "Select and mentor students",
              "Support practical solutions"
            ],
            buttonLabel: "Select Industrialist",
          ),
        ],
      ),
    );
  }

  Widget _roleCard({
    required UserRole role,
    required String title,
    required String badge,
    required String description,
    required List<String> bullets,
    required String buttonLabel,
  }) {
    final bool isSelected = _currentRole == role;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.6 : 1),
        boxShadow: isSelected
            ? [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8))
              ]
            : kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(badge,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate)),
              ),
              if (isSelected) ...[
                const Spacer(),
                const Icon(Icons.check_circle,
                    color: AppColors.primary, size: 18),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(description,
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          ...bullets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(b,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.slate)),
                  ],
                ),
              )),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: isSelected
                ? ElevatedButton(
                    onPressed: () => _switchRole(role),
                    child: Text(buttonLabel),
                  )
                : OutlinedButton(
                    onPressed: () => _switchRole(role),
                    child: Text(buttonLabel,
                        style: const TextStyle(color: AppColors.ink)),
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 3: CITIZEN DASHBOARD
  // ==========================================
  Widget _buildCitizenDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Text("AS", style: TextStyle(color: Colors.white))),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Hello, Aarav Sharma",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("Sector 18, Metro Corridor ▾",
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
              const Spacer(),
              IconButton(
                  onPressed: () {}, icon: const Icon(Icons.notifications_none)),
            ],
          ),
          const SizedBox(height: 16),
          // Search & Filters
          TextField(
            decoration: InputDecoration(
              hintText: "Search nearby problems, roads, water...",
              prefixIcon: const Icon(Icons.search),
              fillColor: Colors.white,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip("Nearby (8)", true),
                _chip("High priority (3)", false),
                _chip("Unverified (4)", false),
                _chip("Still active", false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Live OpenStreetMap with reported-problem pins & current location
          OsmMapView(
            height: 200,
            initialCenter:
                ll.LatLng(_problems.first.latitude, _problems.first.longitude),
            markers: _problems
                .map((p) => MapMarkerData(
                      point: ll.LatLng(p.latitude, p.longitude),
                      icon: Icons.warning,
                      color: Colors.red,
                      label: p.title,
                    ))
                .toList(),
            onMarkerTap: (m) => _navigateTo(AppView.problemDetailView),
          ),
          const SizedBox(height: 16),
          // Primary Action Floating Trigger
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                setState(() {
                  _reportStep = 1;
                  _reportPhotos.clear();
                  _reportDocuments.clear();
                  _reportSelectedLocation = null;
                  _reportAddressPreview = "Detecting address...";
                });
                _navigateTo(AppView.citizenReportWizard);
              },
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text("Report a Problem",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),
          // Action Dashboard Cards
          const Text("Action Dashboard",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.assignment, color: AppColors.primary),
              title: const Text("Open drainage near block C"),
              subtitle: const Text("Under Review • Reported Yesterday"),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primarySoft),
                onPressed: () => _navigateTo(AppView.problemDetailView),
                child: const Text("Track",
                    style: TextStyle(color: AppColors.primary, fontSize: 12)),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.near_me, color: AppColors.info),
              title: const Text("Nearby problem to verify"),
              subtitle: const Text("300m away • Pothole on Sector 18 lane"),
              trailing: ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.info),
                onPressed: () => _navigateTo(AppView.citizenGeofenceCheck),
                child: const Text("Verify",
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.ink : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label,
          style: TextStyle(
              color: isSelected ? Colors.white : AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w500)),
    );
  }

  // ==========================================
  // SCREEN 4: CITIZEN REPORT FLOW (5 STEPS)
  // ==========================================
  Widget _buildCitizenReportWizard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("STEP $_reportStep OF 5",
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              IconButton(
                  onPressed: () => _goBack(), icon: const Icon(Icons.close)),
            ],
          ),
          LinearProgressIndicator(
              value: _reportStep / 5,
              backgroundColor: AppColors.border,
              color: AppColors.primary),
          const SizedBox(height: 20),

          // STEP 1: ADD EVIDENCE
          if (_reportStep == 1) ...[
            const Text("Step 1: Add Evidence",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            CameraUploadField(
              label: "Take Photo or Upload from Gallery",
              initialPhotos: _reportPhotos,
              onChanged: (photos) {
                setState(() {
                  _reportPhotos
                    ..clear()
                    ..addAll(photos);
                });
              },
            ),
            const SizedBox(height: 16),
            const Text("Supporting Documents (optional)",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            DocumentUploadField(
              initialFiles: _reportDocuments,
              onChanged: (files) {
                setState(() {
                  _reportDocuments
                    ..clear()
                    ..addAll(files);
                });
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 48)),
              onPressed: _reportPhotos.isEmpty
                  ? null
                  : () => setState(() => _reportStep = 2),
              child: const Text("Continue to Description",
                  style: TextStyle(color: Colors.white)),
            ),
            if (_reportPhotos.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text("Add at least one photo to continue.",
                    style: TextStyle(fontSize: 11, color: Colors.red)),
              ),
          ],

          // STEP 2: DESCRIBE THE PROBLEM
          if (_reportStep == 2) ...[
            const Text("Step 2: Describe the Problem",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const TextField(
              maxLength: 140,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "e.g., Large pothole near the college entrance",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text("Category Selection:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              isExpanded: true,
              value: _citizenSelectedCategory,
              items: [
                "Road damage",
                "Waste accumulation",
                "Water leakage",
                "Electricity/Lighting",
                "Public Safety"
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) =>
                  setState(() => _citizenSelectedCategory = val!),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 48)),
              onPressed: () => setState(() => _reportStep = 3),
              child: const Text("Confirm Location",
                  style: TextStyle(color: Colors.white)),
            ),
          ],

          // STEP 3: CONFIRM LOCATION
          if (_reportStep == 3) ...[
            const Text("Step 3: Confirm Location",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            OsmMapView(
              height: 220,
              allowAddMarker: true,
              initialCenter:
                  _reportSelectedLocation ?? const ll.LatLng(28.5355, 77.3910),
              onLocationSelected: (point) async {
                setState(() {
                  _reportSelectedLocation = point;
                  _reportAddressPreview = "Looking up address...";
                });
                final address = await _reverseGeocode(point);
                if (!mounted) return;
                setState(() => _reportAddressPreview = address);
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _useCurrentLocationForReport,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text("Use My Current Location"),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44)),
            ),
            const SizedBox(height: 12),
            Text("Address Preview: $_reportAddressPreview",
                style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 48)),
              onPressed: _reportSelectedLocation == null
                  ? null
                  : () => setState(() => _reportStep = 4),
              child: const Text("Run AI Understanding Check",
                  style: TextStyle(color: Colors.white)),
            ),
          ],

          // STEP 4: AI UNDERSTANDING & DEDUPLICATION (From Screenshot 1000100135)
          if (_reportStep == 4) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.infoSoft,
                  borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: AppColors.info),
                  SizedBox(width: 8),
                  Text("CIVICAI COPILOT • Reviewable Preview",
                      style: TextStyle(
                          color: AppColors.info, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Detected Category: Road damage (94% Confidence)",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                        "Estimated Severity: High (Structural asphalt failure)",
                        style: TextStyle(color: Colors.red)),
                    SizedBox(height: 12),
                    Divider(),
                    Text("SIMILAR NEARBY ISSUE DETECTED",
                        style: TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    SizedBox(height: 4),
                    Text(
                        "#TR-8812 - Deep pothole outside Metro Pillar 42 (120m away)"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  minimumSize: const Size(double.infinity, 48)),
              onPressed: () => setState(() => _reportStep = 5),
              child: const Text("+ Add Evidence to Existing Problem #TR-8812",
                  style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              onPressed: () => setState(() => _reportStep = 5),
              child: const Text("Continue as New Report"),
            ),
          ],

          // STEP 5: SUBMISSION CONFIRMATION
          if (_reportStep == 5) ...[
            const Center(
              child: Column(
                children: [
                  Icon(Icons.check_circle, size: 64, color: AppColors.accent),
                  SizedBox(height: 12),
                  Text("Report Submitted Successfully!",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text("Problem ID: #TR-4092",
                      style: TextStyle(fontSize: 16, color: AppColors.muted)),
                  Text("Status: Reported ➔ AI Review Pending"),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 48)),
              onPressed: () => _navigateTo(AppView.problemDetailView),
              child: const Text("View Problem Details",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 5: GEOFENCED VERIFICATION PROMPT (Screenshot 1000100117)
  // ==========================================
  Widget _buildCitizenGeofencePrompt() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.location_on, color: AppColors.primaryDark),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        "GEOFENCE TRIGGERED: You are within 60m of a reported civic problem",
                        style: TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text("Severe Asphalt Pothole near Pillar 42",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text("#TR-8812 • Priority Index: High (340 cars/h)",
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          OsmMapView(
            height: 140,
            interactive: false,
            showCurrentLocationButton: false,
            initialCenter:
                ll.LatLng(_problems.first.latitude, _problems.first.longitude),
            markers: [
              MapMarkerData(
                point: ll.LatLng(
                    _problems.first.latitude, _problems.first.longitude),
                icon: Icons.location_on,
                color: Colors.red,
                label: _problems.first.title,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text("Can you confirm whether this problem still exists?",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Verification recorded! +15 Civic Karma")));
              _goBack();
            },
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text("Yes, it still exists",
                style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48)),
            onPressed: () => _goBack(),
            icon: const Icon(Icons.close),
            label: const Text("No, it appears resolved"),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _goBack(),
            child: const Center(child: Text("Not sure / Can't see clearly")),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
            child: const Text(
              "ROLE PROTOCOL DISTINCTION:\nCitizens provide community verification evidence. Students submit official engineering completion evidence.",
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 6: PROBLEM DETAIL & LIFECYCLE (Screenshot 1000100123)
  // ==========================================
  Widget _buildProblemDetailView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () => _goBack(),
                  icon: const Icon(Icons.arrow_back)),
              const Text("Docket #TR-8812",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text("UNDER EXECUTION",
                    style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OsmMapView(
            height: 160,
            interactive: false,
            showCurrentLocationButton: false,
            initialCenter:
                ll.LatLng(_problems.first.latitude, _problems.first.longitude),
            markers: [
              MapMarkerData(
                point: ll.LatLng(
                    _problems.first.latitude, _problems.first.longitude),
                icon: Icons.location_on,
                color: Colors.red,
                label: _problems.first.title,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // STRICT SEPARATION OF PRIORITY AND COMPLEXITY CARDS
          const Row(
            children: [
              Expanded(
                child: Card(
                  color: AppColors.dangerSoft,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("CIVIC IMPACT VECTOR",
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                        Text("Priority: High",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.red)),
                        SizedBox(height: 4),
                        Text(
                            "• Severity: Critical Tier 1\n• 1,450 Commuters Daily\n• 24 Citizen Reports\n• Recency: 2h ago",
                            style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  color: AppColors.infoSoft,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("EXECUTION LOGISTICS",
                            style: TextStyle(
                                fontSize: 9,
                                color: AppColors.info,
                                fontWeight: FontWeight.bold)),
                        Text("Complexity: Med",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.info)),
                        SizedBox(height: 4),
                        Text(
                            "• 3 Days Turnaround\n• Asphalt Compacting\n• Bitumen & Barriers\n• Cost: \$420 USD",
                            style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Text("Lifecycle Milestone Audit",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _timelineStep("1. Reported", "Oct 12 via Citizen App", true),
          _timelineStep("2. AI Understood",
              "Vision model identified asphalt fissure", true),
          _timelineStep(
              "3. Community Verified", "Validated by 24 local residents", true),
          _timelineStep(
              "4. Prioritized", "Elevated to High Priority (#4 Ward 14)", true),
          _timelineStep("5. Taken up by Industrialist",
              "Apex Infra Corp (\$420 Capital)", true),
          _timelineStep(
              "6. Students Selected", "Team Apex Civic Lab (4 Students)", true),
          _timelineStep("7. Under Execution",
              "Civil asphalt compaction in progress", true),
          _timelineStep(
              "8. Evidence Submitted", "Pending student EXIF upload", false),
          _timelineStep("9. Outcome Verified",
              "Independent resident sign-off pending", false),
        ],
      ),
    );
  }

  Widget _timelineStep(String title, String subtitle, bool isDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isDone ? AppColors.primary : AppColors.border, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDone ? AppColors.ink : AppColors.faint)),
              Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 7: STUDENT DASHBOARD (Screenshot 1000100153)
  // ==========================================
  Widget _buildStudentDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                  backgroundColor: AppColors.info,
                  child: Text("RV", style: TextStyle(color: Colors.white))),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Rohan Verma ✓",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("Civil & Environmental Eng. (3rd Yr)",
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12)),
                child: const Text("• Available",
                    style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatBox(value: "12", label: "Recommended"),
              _StatBox(value: "2", label: "Applications"),
              _StatBox(value: "1", label: "Active Project"),
            ],
          ),
          const SizedBox(height: 20),
          const Text("Field Challenges Available",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ..._problems.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(p.category,
                              style: const TextStyle(
                                  color: AppColors.info,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                          Text(p.priorityLabel,
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(p.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("Skills Required: ${p.requiredSkills}",
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            const Icon(Icons.business,
                                size: 16, color: AppColors.ink),
                            const SizedBox(width: 6),
                            Text("Sponsor: ${p.sponsorName}",
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary),
                          onPressed: () =>
                              _navigateTo(AppView.studentApplication),
                          child: const Text("View Challenge & Submit Proposal",
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 8: STUDENT APPLICATION & PROPOSAL (Screenshot 1000100138)
  // ==========================================
  Widget _buildStudentApplicationView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () => _goBack(),
                  icon: const Icon(Icons.arrow_back)),
              const Text("Submit Engineering Approach",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Damaged Streetlight Cluster",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                      "Sponsor: Apex Energy Labs • Budget: \$350 Parts Allocated"),
                  Divider(height: 24),
                  Text("Proposed Technical Solution",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  TextField(
                    maxLines: 2,
                    decoration: InputDecoration(
                        hintText:
                            "Explain bypass, driver tests, grounding checks...",
                        border: OutlineInputBorder()),
                  ),
                  SizedBox(height: 12),
                  Text("Estimated Commitment: 8 Hours over weekend",
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      "Approach Submitted to Mentor! Status: Under Review")));
              _navigateTo(AppView.studentWorkspace);
            },
            child: const Text("Submit Proposal to Mentor",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 9: STUDENT EXECUTION WORKSPACE (Screenshot 1000100129)
  // ==========================================
  Widget _buildStudentWorkspaceView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("DOCKET #TR-7721",
              style: TextStyle(
                  color: AppColors.info,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          const Text("Reconstruction of Sector 14 Conduit",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text("Mentor: Dr. Arvind Swamy (Apex Energy)",
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.infoSoft,
                borderRadius: BorderRadius.circular(12)),
            child: const Text(
              "EXPLICIT STATUS: Your team reports that the planned intervention has been carried out.\nNotice: Not yet marked resolved. Requires objective outcome verification.",
              style: TextStyle(color: AppColors.primaryDark, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
          const Text("Field Intervention Checklist (75% Done)",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _checkItem(
              "Isolate circuit junction 4B", true, "Signed off by Vikram P."),
          _checkItem(
              "Rewire burnt copper traces", true, "Thermal bridge replaced"),
          _checkItem(
              "Install IP67 weatherproof seal", true, "Dual gasket seated"),
          _checkItem("Capture geolocated night illuminance photo", false,
              "Required for milestone completion"),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48)),
            onPressed: () => _navigateTo(AppView.studentEvidenceSubmit),
            child: const Text("Proceed to Evidence Submission →",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _checkItem(String title, bool done, String detail) {
    return Card(
      child: ListTile(
        leading: Icon(done ? Icons.check_box : Icons.check_box_outline_blank,
            color: done ? AppColors.primary : Colors.grey),
        title: Text(title,
            style: TextStyle(
                decoration: done ? TextDecoration.lineThrough : null,
                fontSize: 14)),
        subtitle: Text(detail, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  // ==========================================
  // SCREEN 10: COMPLETION EVIDENCE SUBMISSION (Screenshot 1000100141)
  // ==========================================
  Widget _buildStudentEvidenceSubmissionView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Photographic Audit • DUAL-PROOF MATCHED",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("BEFORE",
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    CameraUploadField(
                      label: "Original Incident",
                      multiple: false,
                      previewHeight: 120,
                      initialPhotos:
                          _beforePhoto == null ? [] : [_beforePhoto!],
                      onChanged: (photos) => setState(() =>
                          _beforePhoto = photos.isEmpty ? null : photos.last),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("RESOLVED: AFTER",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                    const SizedBox(height: 4),
                    CameraUploadField(
                      label: "Geo-Tagged Proof",
                      multiple: false,
                      previewHeight: 120,
                      initialPhotos: _afterPhoto == null ? [] : [_afterPhoto!],
                      onChanged: (photos) => setState(() =>
                          _afterPhoto = photos.isEmpty ? null : photos.last),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text("Work Performed Summary:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              "• Replaced 150W transformers\n• Re-crimped terminal leads\n• Sealed IP67 enclosure"),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                  value: _confirmCheck,
                  onChanged: (v) => setState(() => _confirmCheck = v!)),
              const Expanded(
                child: Text(
                    "I confirm that this evidence accurately represents work carried out by the team.",
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48)),
            onPressed:
                (_confirmCheck && _beforePhoto != null && _afterPhoto != null)
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                "Submitted! Status: Execution Evidence Submitted — Outcome Verification Pending")));
                        _navigateTo(AppView.industrialistAuditVerdict);
                      }
                    : null,
            child: const Text("Submit for Outcome Verification",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 11: INDUSTRIALIST DASHBOARD (Screenshot 1000100150)
  // ==========================================
  Widget _buildIndustrialistDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                  backgroundColor: AppColors.ink,
                  child: Text("SS", style: TextStyle(color: Colors.white))),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Siddharth Singhania",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("VP, Apex Infra Ventures • Tier Civic Patron",
                      style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatBoxSmall(value: "18", label: "Prioritized"),
              _StatBoxSmall(value: "4", label: "Taken Up"),
              _StatBoxSmall(value: "3", label: "Active Teams"),
              _StatBoxSmall(value: "7", label: "Pending Apps"),
              _StatBoxSmall(value: "2", label: "Evidence Review"),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Vetted Civic Interventions",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              TextButton(
                  onPressed: () =>
                      _navigateTo(AppView.industrialistSquadSelect),
                  child: const Text("Manage Squads")),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Ward 14, Sector 18 Junction",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Text("Critical crossroad sinkhole & bitumen collapse",
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  const Text(
                      "Required Patronage: \$420 Capital + Bitumen Compactor"),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary),
                          onPressed: () =>
                              _navigateTo(AppView.industrialistSquadSelect),
                          child: const Text("Take Up Problem",
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () =>
                            _navigateTo(AppView.industrialistLiveFeed),
                        child: const Text("Live Feed"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 12: INDUSTRIALIST SQUAD SELECTION (Screenshot 1000100144)
  // ==========================================
  Widget _buildIndustrialistSquadSelectionView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Sponsor Grant Commitment",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Text("Sector 18 Road Infrastructure • 4 Candidate Applicants",
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          _applicantCard(
              "Aarav Mehta (98% Match)",
              "Civil Engineering • Final Year",
              "Proposed: Cold-pour asphalt emulsion with gravel compaction layer"),
          const SizedBox(height: 8),
          _applicantCard(
              "Priya Das (91% Match)",
              "Urban Infrastructure • 3rd Year",
              "Proposed: Topographical survey & rapid drainage routing"),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("SQUAD AUTHORIZATION DOSSIER",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                SizedBox(height: 4),
                Text("Escrow Resources: \$420 Locked in Escrow ✓"),
                Text("Faculty Mentor: Prof. Siddharth Singhania"),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                minimumSize: const Size(double.infinity, 48)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      "Team Finalized! Escrow Smart Contract Activated.")));
              _navigateTo(AppView.industrialistLiveFeed);
            },
            child: const Text("Finalize Team & Authorize Work",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _applicantCard(String name, String dept, String proposal) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(dept,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 4),
            Text(proposal, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {},
              child: const Text("Add to Team",
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SCREEN 13: MENTORSHIP WORKSPACE & LIVE FEED (Screenshot 1000100132)
  // ==========================================
  Widget _buildIndustrialistLiveFeedView() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("LIVE WORKSPACE • Sector 18 Asphalt Repair",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text("Quality Index: 94/100 | Escrow Released: \$1,450 / \$2.2k",
                  style: TextStyle(color: AppColors.primaryDark, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _feedTile(
                  "Aarav Patel (Student Lead)",
                  "14:15 - Sub-base gravel leveled. Compactor machine received from depot.",
                  Icons.engineering),
              _feedTile(
                  "Siddharth Mehta (Mentor)",
                  "14:30 - Looks clean. Ensure ambient surface temperature is above 18°C.",
                  Icons.verified_user),
              _feedTile(
                  "Resource Allocation Bot",
                  "15:02 - Micro-grant draw: \$42.00 dispatched for safety cones.",
                  Icons.attach_money),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                  onPressed: () => _showAttachmentSheet(context),
                  icon: const Icon(Icons.attach_file, color: AppColors.muted)),
              const Expanded(
                child: TextField(
                  decoration: InputDecoration(
                      hintText: "Reply to team / send mentor guidance...",
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.send, color: AppColors.primary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _feedTile(String author, String msg, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(author,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(msg, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  // ==========================================
  // SCREEN 14: AUDIT VERDICT & REWORK DIRECTIVES (Screenshot 1000100120)
  // ==========================================
  Widget _buildIndustrialistAuditVerdictView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Docket #TR-7721 • INDEPENDENT AUDIT",
              style: TextStyle(
                  color: AppColors.info,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          const Text("Ground Evidence & Verdict Decision",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Card(
            color: AppColors.bg,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Student Report: Apex Civic Lab",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("Verified GPS: 28.5356° N, 77.3911° E"),
                  Text("Community Consensus: 93% (14 Citizens Confirmed)"),
                  Text("Current Audit Verdict Status: REWORK REQUIRED",
                      style: TextStyle(
                          color: Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text("Select Audit Verdict:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent),
                  onPressed: () => setState(() => _auditVerdict = "Resolved"),
                  child: const Text("Resolved",
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: () => setState(() => _auditVerdict = "Rework"),
                  child: const Text("Rework",
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => setState(() => _auditVerdict = "Disputed"),
                  child: const Text("Disputed",
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_auditVerdict == "Rework" || _auditVerdict == "Pending") ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("REWORK DIRECTIVE MANDATE (SLO: 48 Hrs)",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 11)),
                  SizedBox(height: 4),
                  Text(
                      "Required Correction: Inspect grounding wire connection on lower mast; clamp appears loose."),
                  SizedBox(height: 4),
                  Text(
                      "Additional Mandate: High-res macro photo of grounding bolt."),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  minimumSize: const Size(double.infinity, 48)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        "Rework Order Dispatched to Student Team (48h SLO).")));
                _navigateTo(AppView.industrialistHome);
              },
              child: const Text("Dispatch Rework Order (48hr SLO)",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }
}

// ==========================================
// REUSABLE OPENSTREETMAP WIDGET (flutter_map + OSM tiles)
// Supports: current-location detection & centering, tap-to-drop marker,
// showing a list of pre-supplied markers (problems/pins), and a
// "my location" floating action button.
// ==========================================
class OsmMapView extends StatefulWidget {
  final double height;
  final ll.LatLng initialCenter;
  final List<MapMarkerData> markers;
  final bool allowAddMarker;
  final bool showCurrentLocationButton;
  final bool interactive;
  final double initialZoom;
  final void Function(ll.LatLng point)? onLocationSelected;
  final void Function(MapMarkerData marker)? onMarkerTap;

  const OsmMapView({
    super.key,
    this.height = 220,
    this.initialCenter = const ll.LatLng(28.5355, 77.3910),
    this.markers = const [],
    this.allowAddMarker = false,
    this.showCurrentLocationButton = true,
    this.interactive = true,
    this.initialZoom = 15,
    this.onLocationSelected,
    this.onMarkerTap,
  });

  @override
  State<OsmMapView> createState() => _OsmMapViewState();
}

class _OsmMapViewState extends State<OsmMapView> {
  final MapController _mapController = MapController();
  ll.LatLng? _droppedPin;
  ll.LatLng? _myLocation;
  bool _locating = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _locating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _notify("Please enable Location Services.");
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _notify("Location permission is required to show your position.");
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      final point = ll.LatLng(pos.latitude, pos.longitude);
      setState(() {
        _myLocation = point;
        if (widget.allowAddMarker) _droppedPin = point;
      });
      _mapController.move(point, 16);
      widget.onLocationSelected?.call(point);
    } catch (_) {
      _notify("Couldn't fetch current location.");
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _notify(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final allMarkers = <Marker>[
      ...widget.markers.map((m) => Marker(
            point: m.point,
            width: 40,
            height: 46,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => widget.onMarkerTap?.call(m),
              child: _pin(m.icon, m.color),
            ),
          )),
      if (_myLocation != null)
        Marker(
          point: _myLocation!,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.info,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4)
              ],
            ),
          ),
        ),
      if (_droppedPin != null)
        Marker(
          point: _droppedPin!,
          width: 40,
          height: 46,
          alignment: Alignment.topCenter,
          child: _pin(Icons.location_on, AppColors.danger),
        ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.initialCenter,
                initialZoom: widget.initialZoom,
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
                onTap: widget.allowAddMarker
                    ? (tapPos, point) {
                        setState(() => _droppedPin = point);
                        widget.onLocationSelected?.call(point);
                      }
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.transition.civic_app',
                  subdomains: const [],
                ),
                MarkerLayer(markers: allMarkers),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            if (widget.showCurrentLocationButton)
              Positioned(
                right: 10,
                bottom: 10,
                child: FloatingActionButton.small(
                  heroTag: null,
                  backgroundColor: Colors.white,
                  onPressed: _locating ? null : _goToCurrentLocation,
                  child: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, color: AppColors.primary),
                ),
              ),
            if (widget.allowAddMarker)
              const Positioned(
                top: 8,
                left: 8,
                child: _MapHintChip(text: "Tap map to drop a pin"),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pin(IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 34),
      ],
    );
  }
}

class _MapHintChip extends StatelessWidget {
  final String text;
  const _MapHintChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child:
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}

// ==========================================
// REUSABLE CAMERA / GALLERY CAPTURE WIDGET
// ==========================================
class CameraUploadField extends StatefulWidget {
  final String label;
  final List<XFile> initialPhotos;
  final bool multiple;
  final void Function(List<XFile> photos) onChanged;
  final double previewHeight;

  const CameraUploadField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialPhotos = const [],
    this.multiple = true,
    this.previewHeight = 140,
  });

  @override
  State<CameraUploadField> createState() => _CameraUploadFieldState();
}

class _CameraUploadFieldState extends State<CameraUploadField> {
  late List<XFile> _photos;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _photos = [...widget.initialPhotos];
  }

  Future<void> _capture(ImageSource source) async {
    try {
      final XFile? file =
          await _picker.pickImage(source: source, imageQuality: 85);
      if (file == null) return;
      setState(() {
        if (!widget.multiple) _photos.clear();
        _photos.add(file);
      });
      widget.onChanged(_photos);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(source == ImageSource.camera
                ? "Couldn't access the camera."
                : "Couldn't open the gallery.")));
      }
    }
  }

  void _removeAt(int i) {
    setState(() => _photos.removeAt(i));
    widget.onChanged(_photos);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_photos.isEmpty)
          InkWell(
            onTap: () => _capture(ImageSource.camera),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: widget.previewHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt,
                      size: 48, color: AppColors.muted),
                  const SizedBox(height: 8),
                  Text(widget.label,
                      style: const TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: widget.previewHeight,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (int i = 0; i < _photos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: kIsWebSafeImage(_photos[i],
                              height: widget.previewHeight,
                              width: widget.previewHeight),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeAt(i),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.multiple || _photos.isEmpty)
                  InkWell(
                    onTap: () => _capture(ImageSource.camera),
                    child: Container(
                      height: widget.previewHeight,
                      width: widget.previewHeight,
                      decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border)),
                      child:
                          const Icon(Icons.add_a_photo, color: AppColors.muted),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _capture(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text("Take Photo"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text("Gallery"),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Renders an XFile as an Image using in-memory bytes, which works
// identically across mobile, desktop and web without extra dependencies.
Widget kIsWebSafeImage(XFile file, {double? height, double? width}) {
  return FutureBuilder<Uint8List>(
    future: file.readAsBytes(),
    builder: (context, snap) {
      if (!snap.hasData) {
        return SizedBox(
            height: height,
            width: width,
            child:
                const Center(child: CircularProgressIndicator(strokeWidth: 2)));
      }
      return Image.memory(snap.data!,
          height: height, width: width, fit: BoxFit.cover);
    },
  );
}

// ==========================================
// REUSABLE DOCUMENT UPLOAD WIDGET (file_picker)
// ==========================================
class DocumentUploadField extends StatefulWidget {
  final List<PlatformFile> initialFiles;
  final void Function(List<PlatformFile> files) onChanged;
  final List<String>? allowedExtensions;

  const DocumentUploadField({
    super.key,
    required this.onChanged,
    this.initialFiles = const [],
    this.allowedExtensions,
  });

  @override
  State<DocumentUploadField> createState() => _DocumentUploadFieldState();
}

class _DocumentUploadFieldState extends State<DocumentUploadField> {
  late List<PlatformFile> _files;

  @override
  void initState() {
    super.initState();
    _files = [...widget.initialFiles];
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: widget.allowedExtensions == null ? FileType.any : FileType.custom,
        allowedExtensions: widget.allowedExtensions,
      );
      if (result == null) return;
      setState(() => _files.addAll(result.files));
      widget.onChanged(_files);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't open the document picker.")));
      }
    }
  }

  void _removeAt(int i) {
    setState(() => _files.removeAt(i));
    widget.onChanged(_files);
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _pickFiles,
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text("Upload Document / PDF"),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44)),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._files.asMap().entries.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.description, color: AppColors.info),
                  title: Text(e.value.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(_sizeLabel(e.value.size),
                      style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeAt(e.key),
                  ),
                ),
              )),
        ],
      ],
    );
  }
}

// ==========================================
// REUSABLE HELPER STAT WIDGETS
// ==========================================
class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: kCardShadow,
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 9.5,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2)),
        ],
      ),
    );
  }
}

class _StatBoxSmall extends StatelessWidget {
  final String value;
  final String label;
  const _StatBoxSmall({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border),
          boxShadow: kCardShadow),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 9, color: AppColors.muted),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
