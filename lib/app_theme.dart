import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════
// AJOOMI WORKER — URBAN COMPANY STYLE THEME
// Clean White + Cyan — Light Professional UI
// ══════════════════════════════════════════════════════════════

// ─── Brand Colors ────────────────────────────────────────────
const Color kCyan = Color(0xFF1AC8DB);
const Color kCyanDark = Color(0xFF0EA5B8);
const Color kCyanDeep = Color(0xFF0891B2);
const Color kCyanLight = Color(0xFF22D3EE);
const Color kCyanBg = Color(0xFFE0F9FC);

// ─── Semantic Colors ─────────────────────────────────────────
const Color kSuccess = Color(0xFF22C55E);
const Color kSuccessLight = Color(0xFFDCFCE7);
const Color kWarning = Color(0xFFF59E0B);
const Color kWarningLight = Color(0xFFFEF3C7);
const Color kError = Color(0xFFEF4444);
const Color kErrorLight = Color(0xFFFEE2E2);
const Color kOrange = Color(0xFFF97316);

// ─── Backgrounds ─────────────────────────────────────────────
const Color kBgPage = Color(0xFFF7F9FA);
const Color kBgLight = Color(0xFFF0F4F7);
const Color kWhite = Color(0xFFFFFFFF);

// Legacy dark aliases (kept for screens that still use them)
const Color kBgDark = Color(0xFF0F172A);
const Color kBgCard = Color(0xFF1E293B);
const Color kBgSurface = Color(0xFF334155);

// ─── Text Colors ─────────────────────────────────────────────
const Color kTextDark = Color(0xFF0F172A);
const Color kTextMid = Color(0xFF475569);
const Color kTextMuted = Color(0xFF94A3B8);
const Color kTextLight = Color(0xFFCBD5E1);

// ─── Border / Divider ────────────────────────────────────────
const Color kDivider = Color(0xFFE2E8F0);
const Color kStroke = Color(0xFFCBD5E1);

// ─── Primary (legacy alias) ──────────────────────────────────
const Color kPrimary = kCyan;

// ─── Accent aliases ──────────────────────────────────────────
const Color kAccent = kCyan;
const Color kAccentLight = kCyanBg;
const Color kGreen = kSuccess;
const Color kGreenLight = kSuccessLight;
const Color kRed = kError;
const Color kRedLight = kErrorLight;

// ══════════════════════════════════════════════════════════════
// TEXT STYLES
// ══════════════════════════════════════════════════════════════

const TextStyle kDisplayLarge = TextStyle(
  color: kTextDark,
  fontSize: 28,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.5,
  height: 1.2,
);

const TextStyle kHeading = TextStyle(
  color: kTextDark,
  fontSize: 20,
  fontWeight: FontWeight.w700,
);

const TextStyle kTitle = TextStyle(
  color: kTextDark,
  fontSize: 16,
  fontWeight: FontWeight.w700,
);

const TextStyle kBody = TextStyle(
  color: kTextDark,
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 1.5,
);

const TextStyle kBodyMed = TextStyle(
  color: kTextDark,
  fontSize: 14,
  fontWeight: FontWeight.w500,
);

const TextStyle kSubhead = TextStyle(
  color: kTextMid,
  fontSize: 13,
  fontWeight: FontWeight.w400,
  height: 1.5,
);

const TextStyle kCaption = TextStyle(
  color: kTextMuted,
  fontSize: 11,
  fontWeight: FontWeight.w400,
);

const TextStyle kLabel = TextStyle(
  color: kCyanDeep,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.8,
);

const TextStyle kMuted = TextStyle(
  color: kTextMuted,
  fontSize: 12,
  fontWeight: FontWeight.w500,
);

// ══════════════════════════════════════════════════════════════
// DECORATIONS
// ══════════════════════════════════════════════════════════════

BoxDecoration kCardDecoration({
  double radius = 16,
  Color? borderColor,
  Color? color,
}) {
  return BoxDecoration(
    color: color ?? kWhite,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? kDivider, width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

BoxDecoration kSurface({double radius = 12}) {
  return BoxDecoration(
    color: kBgLight,
    borderRadius: BorderRadius.circular(radius),
  );
}

// ══════════════════════════════════════════════════════════════
// INPUT DECORATION
// ══════════════════════════════════════════════════════════════

InputDecoration kInputDecoration({
  required String hint,
  required IconData icon,
  Widget? suffix,
  bool readOnly = false,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: kCaption.copyWith(color: kTextMuted, fontSize: 13),
    prefixIcon: Icon(icon, color: kCyan, size: 18),
    suffixIcon: suffix,
    filled: true,
    fillColor: readOnly ? kBgLight : kWhite,
    contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kDivider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kDivider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kCyan, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kError),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kError, width: 1.5),
    ),
    errorStyle: const TextStyle(color: kError, fontSize: 11),
  );
}

// ══════════════════════════════════════════════════════════════
// BUTTON STYLES
// ══════════════════════════════════════════════════════════════

ButtonStyle kPrimaryButton({double radius = 14}) {
  return ElevatedButton.styleFrom(
    backgroundColor: kCyan,
    foregroundColor: kWhite,
    disabledBackgroundColor: kCyan.withOpacity(0.4),
    elevation: 0,
    shadowColor: Colors.transparent,
    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    textStyle: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
  );
}

ButtonStyle kOutlineButton({double radius = 14}) {
  return OutlinedButton.styleFrom(
    foregroundColor: kCyan,
    side: const BorderSide(color: kCyan, width: 1.3),
    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  );
}

// ══════════════════════════════════════════════════════════════
// APP THEME — Light / Urban Company style
// ══════════════════════════════════════════════════════════════

ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: kBgPage,
  primaryColor: kCyan,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kCyan,
    primary: kCyan,
    secondary: kCyanDark,
    surface: kWhite,
    background: kBgPage,
    error: kError,
    brightness: Brightness.light,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kWhite,
    elevation: 0,
    centerTitle: false,
    surfaceTintColor: Colors.transparent,
    iconTheme: IconThemeData(color: kTextDark),
    titleTextStyle: TextStyle(
      color: kTextDark,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  cardColor: kWhite,
  dividerColor: kDivider,
  splashColor: kCyan.withOpacity(0.08),
  highlightColor: Colors.transparent,
  fontFamily: 'Roboto',
  elevatedButtonTheme: ElevatedButtonThemeData(style: kPrimaryButton()),
  outlinedButtonTheme: OutlinedButtonThemeData(style: kOutlineButton()),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kWhite,
    contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
    hintStyle: kCaption.copyWith(color: kTextMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kDivider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kDivider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kCyan, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kError),
    ),
  ),
);
