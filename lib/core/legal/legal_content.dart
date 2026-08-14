/// Textos legales de SaldoClaro (Términos y Condiciones + Política de
/// Privacidad).
///
/// Están redactados para:
///  1. Cumplir la normativa peruana de protección de datos (Ley N.º 29733 y su
///     Reglamento) y los requisitos de Google Play sobre transparencia del
///     acceso a notificaciones (Notification Listener Service).
///  2. Que el usuario entienda, con claridad, qué datos se leen, cómo se
///     procesan y qué NO se hace con ellos.
class LegalContent {
  const LegalContent._();

  static const String effectiveDate = '13 de agosto de 2026';
  static const String company = 'SaldoClaro';

  static const String termsTitle = 'Términos y Condiciones';
  static const String privacyTitle = 'Política de Privacidad';

  /// Referencias usadas en el texto de privacidad.
  static const String storageProvider = 'Supabase (supabase.com)';

  // ---------------------------------------------------------------------
  // TÉRMINOS Y CONDICIONES
  // ---------------------------------------------------------------------

  static const List<LegalSection> termsSections = [
    LegalSection(
      '1. Aceptación',
      'Al instalar y usar la aplicación SaldoClaro declaras ser mayor de edad '
          'en tu país y aceptas estos Términos y Condiciones y la Política de '
          'Privacidad. Si no estás de acuerdo, no uses la aplicación y elimínala.',
    ),
    LegalSection(
      '2. Descripción del servicio',
      'SaldoClaro es una herramienta personal de organización financiera. Con tu '
          'consentimiento explícito, lee las notificaciones de las aplicaciones '
          'financieras que elijas (Yape, BCP, Agora/Sip, Lemon Cash, Plin, '
          'Interbank, BBVA y otras), extrae el movimiento (monto, contraparte, '
          'tipo de ingreso o gasto) y lo registra en tu cuenta para llevar el '
          'control de tus finanzas.',
    ),
    LegalSection(
      '3. Acceso a notificaciones',
      'El acceso a notificaciones (Notification Listener Service) se concede y '
          'se retira únicamente por ti desde los Ajustes del sistema. SaldoClaro '
          'NO procesa notificaciones de aplicaciones ajenas a la lista de apps '
          'financieras configuradas. Puedes revocar el permiso en cualquier '
          'momento desde Ajustes del sistema o desinstalando la app.',
    ),
    LegalSection(
      '4. Lo que se procesa localmente',
      'Las notificaciones se interpretan en tu dispositivo. De cada notificación '
          'solo se conserva el movimiento financiero (monto, contraparte, fecha, '
          'tipo y app de origen). Los códigos de seguridad de un solo uso (OTP), '
          'números de tarjeta, claves y cualquier credencial se descartan y NUNCA '
          'se guardan ni se envían a servidores externos.',
    ),
    LegalSection(
      '5. Datos que se envían a la nube',
      'Para sincronizar tus dispositivos, los movimientos ya clasificados se '
          'almacenan en tu cuenta de ' '$company' ' (proveedor de base de datos '
          '$storageProvider' '). Los datos se asocian a tu cuenta con medidas de '
          'seguridad y controles de acceso por usuario.',
    ),
    LegalSection(
      '6. Uso permitido',
      'SaldoClaro es para uso personal y legítimo. Queda prohibido usar la '
          'aplicación para cometer fraude, estafar, suplantar a otras personas, '
          'revelar códigos de seguridad, o realizar cualquier actividad ilícita. '
          'El usuario es el único responsable del uso que haga de la información '
          'que registre.',
    ),
    LegalSection(
      '7. No es asesoría financiera',
      'La información que muestra SaldoClaro es de carácter informativo y de '
          'organización personal. SaldoClaro no es una entidad financiera ni '
          'brinda asesoría de inversión, crédito o tributación. Las decisiones '
          'financieras son responsabilidad exclusiva del usuario.',
    ),
    LegalSection(
      '8. Seguridad',
      'La aplicación incluye medidas como bloqueo biométrico opcional, modo '
          'incógnito y cifrado en tránsito hacia la nube. Ningún sistema es '
          'infalible: protege tu teléfono y no compartas tu sesión.',
    ),
    LegalSection(
      '9. Disponibilidad y cambios',
      'Podemos actualizar la aplicación y estos términos. Cuando los documentos '
          'legales cambien, se te pedirá aceptarlos nuevamente antes de continuar.',
    ),
    LegalSection(
      '10. Limitación de responsabilidad',
      'SaldoClaro se proporciona "tal cual". En la medida máxima permitida por '
          'la ley, no respondemos por daños indirectos derivados del uso de la '
          'app ni por errores en el reconocimiento de notificaciones, que pueden '
          'variar según la versión de cada app financiera y del sistema operativo.',
    ),
    LegalSection(
      '11. Terminación',
      'Puedes dejar de usar y eliminar la aplicación en cualquier momento. '
          'También puedes solicitar la eliminación de tus datos personales '
          'contactándonos conforme a la Política de Privacidad.',
    ),
    LegalSection(
      '12. Contacto y legislación aplicable',
      'Toda controversia se rige por las leyes de la República del Perú, sin '
          'perjuicio de la normativa del país donde viva el usuario. Para '
          'consultas escribe al correo disponible en la tienda de aplicaciones.',
    ),
  ];

  // ---------------------------------------------------------------------
  // POLÍTICA DE PRIVACIDAD
  // ---------------------------------------------------------------------

  static const List<LegalSection> privacySections = [
    LegalSection(
      '1. Responsable del tratamiento',
      'El responsable del tratamiento de los datos personales es ' '$company' '. '
          'Esta política describe qué datos se recopilan, para qué se usan y '
          'los derechos que tienes como titular.',
    ),
    LegalSection(
      '2. Datos que recopilamos',
      '• Datos de la cuenta: correo electrónico y nombre que registras al crear '
          'tu cuenta.\n'
          '• Movimientos financieros: el resumen (monto, contraparte, fecha, '
          'tipo y app de origen) que tú autorizas a leer de las notificaciones '
          'de las apps financieras configuradas.\n'
          '• Datos de uso: métricas técnicas anónimas necesarias para corregir '
          'errores.',
    ),
    LegalSection(
      '3. Datos que NO recopilamos',
      'Jamás almacenamos ni transmitimos: contraseñas de apps financieras, '
          'códigos de seguridad de un solo uso (OTP), PIN, números completos de '
          'tarjeta, huellas dactilares u otros datos biométricos, ni el contenido '
          'íntegro de tus notificaciones.',
    ),
    LegalSection(
      '4. Finalidades',
      'Las finalidades son: llevar tu registro de gastos e ingresos, sincronizar '
          'tus datos entre tus dispositivos y mejorar la precisión del servicio. '
          'El registro médico, comercial, académico y las decisiones de crédito '
          'quedan expresamente excluidos del tratamiento.',
    ),
    LegalSection(
      '5. Base legal y consentimiento',
      'El tratamiento se basa en tu consentimiento libre, previo, expreso e '
          'informado (art. 5 y 13 de la Ley N.º 29733). El consentimiento para '
          'la lectura de notificaciones y para el uso de los términos se registra '
          'y puedes revocarlo en cualquier momento: al revocar el permiso de '
          'notificaciones o dejar de usar la aplicación.',
    ),
    LegalSection(
      '6. Almacenamiento y seguridad',
      'Los datos se guardan en servicios de base de datos con cifrado en tránsito '
          'y controles de acceso por cuenta (' '$storageProvider' '). Cada usuario '
          'solo pueda acceder a sus propios datos. La app añade capas locales '
          'opcionales: bloqueo biométrico y ocultamiento de saldos.',
    ),
    LegalSection(
      '7. Intenteligencia artificial',
      'Cuando lo habilites, un proveedor de IA puede recibir el texto del '
          'movimiento (sin códigos de seguridad, sin credenciales) únicamente '
          'para clasificar la categoría del gasto o ingreso. Puedes desactivar '
          'la clasificación con IA en los ajustes.',
    ),
    LegalSection(
      '8. Derechos del titular',
      'Tienes derecho al acceso, rectificación, actualización, cancelación '
          '(supresión), oposición y portabilidad de tus datos personales. Para '
          'ejercerlos, o para solicitar la eliminación de tu cuenta y datos, '
          'escríbenos al correo indicado en la tienda. Atenderemos tu solicitud '
          'en los plazos legales.',
    ),
    LegalSection(
      '9. Retención de los datos',
      'Conservamos tus datos mientras mantengas tu cuenta activa. Al eliminar tu '
          'cuenta, los datos asociados se suprimen conforme a la normativa '
          'aplicable.',
    ),
    LegalSection(
      '10. Transferencia internacional y terceros',
      'Para brindar el servicio, la información puede residir en servidores '
          'ubicados fuera del Perú bajo estándares de protección equivalentes. '
          'No vendemos, alquilamos ni compartimos tus datos con terceros para '
          'publicidad.',
    ),
    LegalSection(
      '11. Menores de edad',
      'La aplicación está dirigida a mayores de 18 años. Si una persona menor '
          'de edad usó la app sin autorización, solicita la eliminación de sus '
          'datos a través del canal de contacto.',
    ),
    LegalSection(
      '12. Cambios y contacto',
      'Toda modificación de esta política será notificada dentro de la aplicación '
          'y requerirá tu aceptación. Vigencia: ' '$effectiveDate' '. Para '
          'ejercer tus derechos o resolver dudas, contacta al soporte de la '
          'aplicación.',
    ),
  ];
}

/// Una sección numerada de un documento legal.
class LegalSection {
  const LegalSection(this.heading, this.body);

  final String heading;
  final String body;
}