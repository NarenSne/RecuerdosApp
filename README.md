# Recuerditos

App para iPhone y Android (Flutter) para guardar recuerdos de pareja —qué pasó, fecha, lugar, fotos y videos— y agendar citas en un calendario compartido.

- **Todo se guarda en el teléfono** (SQLite + carpeta de fotos/videos). No hay nube.
- **Compartir por internet** con un buzón temporal cifrado: cada cambio viaja cifrado (AES‑256‑GCM) a Supabase y se borra en cuanto la pareja lo descarga. El servidor nunca puede leer el contenido.
- Las dos personas pueden crear, editar y borrar recuerdos y citas; gana la edición más reciente.
- **Lugar en el mapa**: cada recuerdo o cita se marca con un girasol. En Recuerdos, el ícono de mapa muestra todos los girasoles juntos.
- **Mes y aniversario**: la fecha en que empezaron (se comparte entre los dos). Cada mes, ese mismo día a las 9:00, llega un recordatorio y cada año el de aniversario. Si el día no existe en un mes (ej. 31), se usa el último día.
- **3 favoritos** compartidos, arriba de la lista de recuerdos.
- **Inicio de sesión con Google** (gratis). Las cuentas las maneja Supabase Auth; los recuerdos siguen solo en el teléfono.
- **"RECUERDOS con:"** y el apodo que cada uno le pone a su pareja (solo se ve en su teléfono). Se toca el encabezado para cambiarlo.
- **Tipografía**: Nunito para el texto, Playfair Display para títulos y Dancing Script para nombres. Van incluidas en `assets/fonts` (licencia OFL), así que funcionan sin internet.
- La app se usa solo en **vertical**.
- **Post para Instagram**: al guardar un recuerdo con fotos o videos nuevos, la app arma el carrusel (portada = primera foto, fotos recortadas a 4:5 de 1080 × 1350, hasta 20 elementos, con el texto listo). Se puede reordenar, compartir directo o guardar en Fotos.

## Estructura

| Carpeta | Qué hay |
| --- | --- |
| `lib/models/` | Recuerdo, foto/video y cita |
| `lib/data/repository.dart` | Base de datos local, archivos, favoritos y cola de envío |
| `lib/data/milestones.dart`, `reminders.dart` | Cálculo de "meses" y recordatorios programados |
| `lib/sync/` | Código de pareja, cifrado, buzón Supabase y sincronización |
| `lib/ui/` | Pantallas: Recuerdos, mapa, Calendario, Pareja, post de Instagram |
| `supabase/schema.sql` | Tablas y reglas de seguridad del buzón |
| `test/sync_test.dart` | Dos teléfonos compartiendo con un buzón simulado: invitaciones, favoritos, fecha, mensajes dañados y fallas de red |
| `test/repository_test.dart` | Base local, archivos y validación de lo que llega de la pareja |
| `test/crypto_test.dart` | Códigos de invitación y cifrado |
| `test/milestones_test.dart` | Fechas de mes y aniversario, orden y recorte del post |
| `test/auth_test.dart` | Modo de prueba sin cuenta, apodo |
| `AUDITORIA.md` | Auditoría técnica y de seguridad |

## Probarla

```bash
flutter pub get
flutter test
flutter run
```

Sin configurar Supabase no se puede iniciar sesión. Mientras desarrollas, la pantalla de entrada muestra **Entrar sin cuenta (solo pruebas)**; ese botón no aparece en la versión final.

## Activar el buzón (una sola vez)

1. Crea un proyecto gratis en [supabase.com](https://supabase.com).
2. En **SQL Editor**, pega y ejecuta todo `supabase/schema.sql`. Se puede ejecutar varias veces; cada vez que cambie este archivo hay que volver a hacerlo.
3. En **Project Settings → API Keys** copia la *Project URL* y la *publishable key* (`sb_publishable_…`). Nunca pongas en la app la *secret key* ni la contraseña de la base de datos.
4. Activa Google (sección siguiente) y **desactiva Email** en **Authentication → Sign In / Providers**: la llave pública va dentro de la app, y con Email activo cualquiera podría crear cuentas. El buzón ya rechaza cuentas que no sean de Google, pero es mejor cerrarlo también ahí.
5. Compila la app con esos datos:

   ```bash
   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
   ```

   o ponlos como `defaultValue` en `lib/config.dart`.

## Inicio de sesión con Google (gratis)

1. En [Google Cloud Console](https://console.cloud.google.com/) → APIs y servicios → Credenciales, crea tres IDs de cliente OAuth: *Aplicación web*, *iOS* (bundle `com.recuerditos.recuerditos`) y *Android* (paquete `com.recuerditos.recuerditos` + huella SHA‑1 de tu firma). No pide tarjeta.
2. En Supabase → **Authentication → Sign In / Providers → Google**: actívalo, pega el ID y el secreto del cliente *web*, agrega el ID de *iOS* en "Client IDs" y marca **Skip nonce check** (necesario en iPhone).
3. En `ios/Runner/Info.plist` reemplaza `com.googleusercontent.apps.REEMPLAZAR-CON-TU-IOS-CLIENT-ID` por el "iOS URL scheme" que muestra Google (es el ID de iOS al revés).
4. Compila con `--dart-define=GOOGLE_WEB_CLIENT_ID=… --dart-define=GOOGLE_IOS_CLIENT_ID=…`.

## Costos

La app está pensada para no costar nada:

| Pieza | Costo |
| --- | --- |
| Supabase (cuentas y buzón) | Plan gratuito: 500 MB de base de datos, 1 GB de archivos, 50.000 usuarios. Como el buzón se vacía al entregar, sobra para una pareja. El proyecto se pausa si pasa 1 semana sin uso; se reactiva gratis desde el panel. |
| Inicio con Google | Gratis. |
| Mapas (OpenStreetMap) | Gratis para uso personal. |
| Recordatorios, fotos, Instagram, WhatsApp para enviar el código de pareja | Gratis: todo pasa en el teléfono o abre la app correspondiente. |

Lo único que podría costar es **publicar** la app en las tiendas: Google Play cobra 25 USD una sola vez y la App Store 99 USD al año. Para uso propio no hace falta:

- **Android**: se instala el APK directamente (`flutter build apk`), gratis.
- **iPhone**: se instala desde Xcode con un Apple ID gratuito; la instalación dura 7 días y luego hay que volver a instalarla desde el Mac.

Se quitaron a propósito el inicio con Apple (exige la cuenta de pago de Apple Developer) y el código por WhatsApp (cada mensaje se paga en Twilio).

## Conectar a la pareja

1. Cada persona escribe su nombre en **Pareja**.
2. Una toca **Crear código de invitación** y lo envía con **Enviar por WhatsApp** o **Por correo**. El código (ej. `K7M-2QX-9TB`) sirve una sola vez y vence en 15 minutos.
3. La otra lo escribe en **o si te enviaron uno** y toca **Conectarme**. Lo que cada una ya tenía guardado se envía a la otra.
4. Si alguien cambia de teléfono: **Invitar de nuevo** genera otro código para el mismo buzón.

El servidor nunca ve el código: guarda la llave de la pareja cifrada con él y la identifica por un hash.

La app revisa el buzón al abrirse y cada minuto mientras está abierta; también al deslizar hacia abajo en Recuerdos o con **Sincronizar ahora**.

## Seguridad

- Todo lo que pasa por Supabase va cifrado con AES‑256‑GCM con una llave que solo tienen los dos teléfonos. El servidor ve tamaños y horas, no el contenido.
- El código de invitación (9 caracteres, 15 minutos, un solo uso) se convierte en llave e identificador con PBKDF2: quien tenga acceso al servidor no puede probar códigos rápido.
- Las reglas de `schema.sql` solo dejan entrar a cuentas de Google, a buzones de los que la cuenta es miembro, y limitan tamaños, buzones por cuenta e invitaciones activas.
- Lo que llega de la pareja se valida antes de guardarse: un mensaje dañado se descarta sin bloquear los demás y ningún nombre de archivo puede salir de la carpeta de fotos.
- Detalle completo y riesgos pendientes en `AUDITORIA.md`.

## Límites que hay que conocer

- El mapa usa los mapas de OpenStreetMap (gratis, sin clave) y necesita internet para verse. Para publicar la app con muchos usuarios conviene un proveedor con clave (MapTiler, Stadia…); se cambia en `lib/ui/widgets/place_map.dart`.
- Los recordatorios son locales de cada teléfono: cada persona decide si los recibe.
- En el post de Instagram las fotos se recortan a 4:5; los videos se envían tal cual y Instagram los recorta al subirlos. Instagram no permite precargar el texto: la app lo copia para que lo pegues.
- Videos de más de 45 MB se guardan en el teléfono pero no se envían (el plan gratis de Supabase acepta archivos de hasta 50 MB).
- Si alguien desinstala la app, pierde sus datos locales. Al volver a conectarse con **Invitar de nuevo** recibe solo lo que la pareja cambie después, no el historial completo.
- Si alguien nunca recibe un mensaje, este se queda en el buzón. Puedes borrar mensajes viejos desde Supabase si hace falta.
