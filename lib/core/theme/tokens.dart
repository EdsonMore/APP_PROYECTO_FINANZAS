import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tokens del sistema visual "Cuaderno" (SPEC.md §Sistema visual).
/// Cálido, editorial, sobrio: el color solo comunica significado.

/// Colores. Se registra como ThemeExtension para que los widgets lean los
/// semánticos (ingreso/gasto/ámbar) con `context.palette`.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.canvas,
    required this.surface,
    required this.border,
    required this.track,
    required this.ink,
    required this.inkMuted,
    required this.incomeBg,
    required this.incomeFg,
    required this.expenseBg,
    required this.expenseFg,
    required this.amberBg,
    required this.amberFg,
  });

  final Color canvas;
  final Color surface;
  final Color border;

  /// Carril de medidores (barra de presupuesto): ≥ 3:1 sobre surface y canvas.
  /// [border] es demasiado sutil para eso (≈ 1.2:1).
  final Color track;
  final Color ink;

  /// Texto secundario. Oscurecido vs #787774 para cumplir AA sobre [canvas].
  final Color inkMuted;
  final Color incomeBg;
  final Color incomeFg;
  final Color expenseBg;
  final Color expenseFg;
  final Color amberBg;
  final Color amberFg;

  static const light = Palette(
    canvas: Color(0xFFF7F6F3),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFEAE8E3),
    track: Color(0xFF8F8D88),
    ink: Color(0xFF2B2A27),
    inkMuted: Color(0xFF6F6E69),
    incomeBg: Color(0xFFEDF3EC),
    incomeFg: Color(0xFF346538),
    expenseBg: Color(0xFFFDEBEC),
    expenseFg: Color(0xFF9F2F2D),
    amberBg: Color(0xFFFBF3DB),
    amberFg: Color(0xFF8A5D00),
  );

  static const dark = Palette(
    canvas: Color(0xFF191918),
    surface: Color(0xFF222220),
    border: Color(0xFF34332F),
    track: Color(0xFF73716C),
    ink: Color(0xFFECEAE5),
    inkMuted: Color(0xFFA3A19B),
    incomeBg: Color(0xFF1F2B20),
    incomeFg: Color(0xFF8FC493),
    expenseBg: Color(0xFF35201F),
    expenseFg: Color(0xFFEFA29E),
    amberBg: Color(0xFF332A12),
    amberFg: Color(0xFFE3B85C),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      border: l(border, other.border),
      track: l(track, other.track),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      incomeBg: l(incomeBg, other.incomeBg),
      incomeFg: l(incomeFg, other.incomeFg),
      expenseBg: l(expenseBg, other.expenseBg),
      expenseFg: l(expenseFg, other.expenseFg),
      amberBg: l(amberBg, other.amberBg),
      amberFg: l(amberFg, other.amberFg),
    );
  }
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

/// Paleta categórica (1c, validada con dataviz; SPEC.md §Paleta categórica).
/// Índice = slot − 1: terracota, lago, mostaza, uva, salvia, piedra, ciruela,
/// añil, petróleo. La piedra (slot 6, "Otros") es gris a propósito.
const categoryLight = [
  Color(0xFFCA653C), Color(0xFF2266A4), Color(0xFFA08318), Color(0xFF634590), Color(0xFF8A943A),
  Color(0xFF56524B), Color(0xFFB5689D), Color(0xFF424B9C), Color(0xFF09919D),
];
const categoryDark = [
  Color(0xFFD87248), Color(0xFF4E90D2), Color(0xFFB0922E), Color(0xFF8C6EBD), Color(0xFF909A40),
  Color(0xFF726E67), Color(0xFFC274A9), Color(0xFF5A66B9), Color(0xFF029FAB),
];

/// Color de una categoría a partir de su `color_hex` ('cat:1'…'cat:9').
/// Cualquier otro valor cae en piedra.
Color categoryColor(String colorHex, Brightness brightness) {
  final slot = colorHex.startsWith('cat:') ? int.tryParse(colorHex.substring(4)) : null;
  final i = slot != null && slot >= 1 && slot <= 9 ? slot - 1 : 5;
  return (brightness == Brightness.dark ? categoryDark : categoryLight)[i];
}

/// Tipografía. Newsreader (serif, solo 500) para el número principal y
/// títulos ≥ 22 sp; Geist (400/500/600) para todo lo demás, incluidos montos
/// de listas y chips. Nunca pedir w700: no está empaquetado y Flutter lo
/// sintetizaría.
abstract final class AppType {
  static const serif = 'Newsreader';
  static const sans = 'Geist';

  /// Geist trae cifras proporcionales por defecto; los montos usan tabulares
  /// para que no "bailen". Newsreader ya es tabular por defecto.
  static const tabular = [FontFeature.tabularFigures()];

  /// Número principal del Home ("Te alcanza para ~23 días").
  static const display = TextStyle(
      fontFamily: serif, fontSize: 52, height: 1.05, letterSpacing: -1.04, fontWeight: FontWeight.w500);

  /// Título de pantalla.
  static const title = TextStyle(
      fontFamily: serif, fontSize: 26, height: 1.15, letterSpacing: -0.26, fontWeight: FontWeight.w500);

  /// Encabezado de sección ("En qué se va").
  static const heading = TextStyle(fontFamily: sans, fontSize: 17, height: 1.3, fontWeight: FontWeight.w600);

  static const body = TextStyle(fontFamily: sans, fontSize: 16, height: 1.5, fontWeight: FontWeight.w400);

  static const label = TextStyle(fontFamily: sans, fontSize: 14, height: 1.3, fontWeight: FontWeight.w500);

  /// Enlaces de texto secundarios ("Omitir").
  static const link = TextStyle(fontFamily: sans, fontSize: 15, height: 1.3, fontWeight: FontWeight.w500);

  /// Meta-datos (fechas, ayudas). Tracking positivo leve: tamaño chico.
  static const caption =
      TextStyle(fontFamily: sans, fontSize: 13, height: 1.4, letterSpacing: 0.1, fontWeight: FontWeight.w400);

  /// Montos en listas, chips y totales.
  static const amount =
      TextStyle(fontFamily: sans, fontSize: 16, height: 1.3, fontWeight: FontWeight.w600, fontFeatures: tabular);

  /// Monto que se escribe en el teclado de registro.
  static const amountInput = TextStyle(
      fontFamily: sans, fontSize: 44, height: 1.1, letterSpacing: -0.88, fontWeight: FontWeight.w500, fontFeatures: tabular);

  /// Teclas del teclado numérico propio.
  static const keypad = TextStyle(
      fontFamily: sans, fontSize: 26, height: 1.1, fontWeight: FontWeight.w500, fontFeatures: tabular);

  static const button = TextStyle(fontFamily: sans, fontSize: 16, height: 1.2, fontWeight: FontWeight.w600);
}

/// Espaciado, base 4.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Margen lateral de pantalla.
  static const gutter = 20.0;

  /// Alto mínimo de los CTAs "+ Gasto" / "+ Ingreso" (objetivo táctil holgado).
  static const ctaHeight = 56.0;

  /// Pantallas por debajo de esto (p. ej. 720p ≈ 640 dp) usan la variante compacta.
  static const compactBelowHeight = 700.0;

  /// Alto de tecla del teclado numérico: 56, o 48 en pantallas compactas.
  static double keyHeight(double screenHeight) => screenHeight >= compactBelowHeight ? 56 : 48;

  /// Alto del botón principal de una hoja: 56, o 52 en pantallas compactas.
  static double sheetCtaHeight(double screenHeight) => screenHeight >= compactBelowHeight ? ctaHeight : 52;
}

abstract final class Radii {
  static const chip = 8.0;
  static const button = 10.0;
  static const card = 12.0;
  static const sheet = 20.0;
}

/// Movimiento. Springs críticamente amortiguados por defecto; el sheet es lo
/// único con leve overshoot (se arrastra con el dedo). Con "reducir
/// movimiento" todo cae a [Motion.reducedFade].
abstract final class Motion {
  static const press = Duration(milliseconds: 100);
  static const pressScale = 0.97;
  static const numberChange = Duration(milliseconds: 250);
  static const lightChange = Duration(milliseconds: 200);
  static const reducedFade = Duration(milliseconds: 150);

  static const easeOut = Curves.easeOutCubic;

  /// Entrada enfática (cubic-bezier(0.16, 1, 0.3, 1)).
  static const emphasized = Cubic(0.16, 1, 0.3, 1);

  /// Default UI: damping 1.0, response 0.35 s.
  static final spring = appleSpring(damping: 1.0, response: 0.35);

  /// Bottom sheet: damping 0.85, response 0.30 s.
  static final sheetSpring = appleSpring(damping: 0.85, response: 0.30);
}

/// Traduce (damping, response) estilo Apple a SpringDescription de Flutter.
/// Con masa 1: stiffness = (2π / response)².
SpringDescription appleSpring({required double damping, required double response}) =>
    SpringDescription.withDampingRatio(mass: 1, stiffness: math.pow(2 * math.pi / response, 2).toDouble(), ratio: damping);
