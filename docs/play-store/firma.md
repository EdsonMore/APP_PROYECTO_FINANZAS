# Firma de la app para Play Store

La firma se prepara una sola vez, cuando ya vas a publicar (Fase 2C). Nadie
más que tú debe tener el keystore ni sus contraseñas.

## 1. Crear el keystore de subida

En una terminal, fuera del repo (por ejemplo en `C:\Users\<tú>\keys\`):

```
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` viene con el JDK de Android Studio
(`C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`). Te pedirá una
contraseña para el keystore, otra para la clave (puede ser la misma) y unos
datos (nombre, país). Anota las contraseñas en tu gestor de contraseñas.

## 2. Decirle al build dónde está

Crea `android/key.properties` (está en `.gitignore`, nunca se sube):

```
storePassword=<contraseña del keystore>
keyPassword=<contraseña de la clave>
keyAlias=upload
storeFile=C:/Users/<tú>/keys/upload-keystore.jks
```

`android/app/build.gradle.kts` ya está preparado: si existe
`android/key.properties`, la release se firma con tu keystore; si no existe,
se firma con la clave de debug (así el build de release funciona para pruebas,
pero ese APK no sirve para Play).

## 3. Verificar

```
flutter build appbundle --release
```

El `.aab` queda en `build/app/outputs/bundle/release/`. Para comprobar con qué
clave se firmó:

```
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

Sin `key.properties`, `flutter build apk --release` también debe compilar
(firma de debug). Un test (`test/features/settings/legal_test.dart`) vigila que
`build.gradle.kts` mantenga ese respaldo.

## Dónde guardarlo

- Nunca en el repo, ni en una carpeta sincronizada pública.
- Dos copias: el disco de tu PC y un lugar seguro aparte (USB guardado o una
  bóveda cifrada en la nube), junto con las contraseñas.

## Qué pasa si se pierde

Play usa **Play App Signing**: Google guarda la clave con la que se firma la
app que reciben los usuarios, y tú solo usas la clave de **subida**. Si pierdes
el keystore de subida (o sus contraseñas), puedes pedir que la restablezcan
desde Play Console (Configuración → Integridad de la app → Firma de apps →
Solicitar restablecimiento de la clave de subida). Mientras tanto no podrás
subir versiones nuevas. Por eso conviene la segunda copia.
