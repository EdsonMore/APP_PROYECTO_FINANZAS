import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/legal/legal_content.dart';

/// Pantalla de documentos legales: "Términos y Condiciones" y "Política de
/// Privacidad" en pestañas. Se abre desde el registro, el perfil y la pantalla
/// de consentimiento.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Información legal'),
          bottom: const TabBar(
            tabs: [
              Tab(text: LegalContent.termsTitle),
              Tab(text: LegalContent.privacyTitle),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _LegalDocument(
              intro: 'Fecha de vigencia: ${LegalContent.effectiveDate}',
              sections: LegalContent.termsSections,
            ),
            _LegalDocument(
              intro: 'Fecha de vigencia: ${LegalContent.effectiveDate}',
              sections: LegalContent.privacySections,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalDocument extends StatelessWidget {
  const _LegalDocument({required this.intro, required this.sections});

  final String intro;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${AppConfig.appName} – Información legal',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(ColorConfig.textPrimary),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          intro,
          style: const TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Color(ColorConfig.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        for (final section in sections) ...[
          LegalSectionTile(section: section),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class LegalSectionTile extends StatelessWidget {
  const LegalSectionTile({super.key, required this.section});

  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(ColorConfig.surface),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.heading,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(ColorConfig.textPrimary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            section.body,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.5,
              color: const Color(ColorConfig.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
