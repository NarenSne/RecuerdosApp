# Auditoría técnica y de seguridad — Recuerditos

Fecha: 19 de noviembre de 2026 · Alcance: todo el código de la app (`lib/`), las pruebas (`test/`), el esquema de Supabase (`supabase/schema.sql`) y la configuración de Android e iOS.

## Resumen ejecutivo

**Antes:** el análisis estático no mostraba avisos y las 14 pruebas pasaban, pero:
- La app **no compilaba para Android**.
- Cualquier persona con la llave pública podía crear cuentas por correo y usar el almacenamiento de Supabase.
- Un solo mensaje dañado dejaba el buzón bloqueado para siempre.
- Un dato recibido podía borrar o escribir archivos fuera de la carpeta de fotos.
- El identificador de las invitaciones permitía, a quien tuviera acceso al servidor, descubrir el código por fuerza bruta.

**Después:**
- Las dos plataformas compilan en modo release.
- El esquema solo acepta cuentas de Google y limita tamaños y cantidades.
- Los mensajes inválidos se descartan sin bloquear los demás, y los nombres de archivo recibidos se validan.
- La invitación usa una derivación lenta (PBKDF2) también para el identificador.
- El cifrado pesado corre fuera del hilo de la pantalla.
- Hay **43 pruebas** (antes 14) y la cobertura de la lógica es del **88 %**.

Esto **no** significa que la app esté libre de vulnerabilidades. Los riesgos que siguen abiertos están al final.

## Inventario de problemas (fase 1)

| # | Severidad | Problema | Dónde |
|---|---|---|---|
| 1 | CRÍTICO | La app no compila para Android: `cryptography_flutter 2.3.2` no declara *namespace* y usa la API `Registrar`, que esta versión de Flutter eliminó. En iOS el plugin nunca estaba activo (solo se registra en Android). | `pubspec.yaml` |
| 2 | ALTO | Registro por correo abierto en Supabase (`email: true`, `disable_signup: false`). Con la llave pública, que va dentro de la app, cualquiera crea una cuenta y puede subir archivos a su propio "buzón" hasta agotar el plan gratuito. | Proyecto Supabase, `schema.sql` |
| 3 | ALTO | *Path traversal*: el `id` o la `ext` de una foto recibida se usaban sin validar para construir rutas. Un `id` como `../../x` borraba o escribía archivos fuera de `media/`. | `repository.dart` (`applyRecord`, `fileFor`) |
| 4 | ALTO | Mensaje "veneno": un registro con tipos inesperados (TypeError), un JSON que no es un mapa o un archivo que ya no existe en el buzón detenía la sincronización, nunca se confirmaba y bloqueaba todos los mensajes siguientes. | `sync_service.dart` |
| 5 | MEDIO | El identificador de la invitación era SHA‑256 directo del código (unos 44 bits). Con acceso al servidor se prueban todos los códigos en minutos y se abre el secreto de la pareja: eso rompe la promesa de que "el servidor nunca puede leer". | `couple_crypto.dart` |
| 6 | MEDIO | Las funciones `security definer` usaban `search_path = public`, no validaban formato ni tamaño de los parámetros y no tenían límites (invitaciones, buzones, tamaño de mensajes). `object_path` podía apuntar fuera del buzón. | `schema.sql` |
| 7 | MEDIO | Una fecha de aniversario recibida fuera de rango hacía fallar `DateTime` en cada arranque, y la app no volvía a abrir. | `repository.dart` |
| 8 | MEDIO | El cifrado de fotos y videos y el PBKDF2 corrían en el hilo de la pantalla: con un video de 45 MB son 7 a 10 s de pantalla congelada (medido). | `couple_crypto.dart` |
| 9 | BAJO | Se mostraban al usuario textos de excepción crudos (`$e`, mensajes del servidor) en 5 lugares. | `partner_screen`, `memory_edit_screen`, `sync_service`, `supabase_transport`, `auth` |
| 10 | BAJO | `setState` después de cerrar la pantalla al volver del selector de fotos (excepción). | `memory_edit_screen.dart` |
| 11 | BAJO | Si la programación de recordatorios fallaba a mitad, se marcaba como hecha y no se reintentaba. | `reminders.dart` |
| 12 | BAJO | Nombre de la pareja sin límite de largo ni limpieza de caracteres de control. | `sync_service.dart`, campos de nombre |
| 13 | BAJO | Código muerto (`appointmentById`, `devBypass`), dependencia sin uso (`cupertino_icons`), comentario obsoleto (WhatsApp) y descripción de plantilla en `pubspec.yaml`. | varios |
| 14 | BAJO | 29 de 32 archivos no seguían `dart format`; un aviso de llaves en `milestones.dart`. | varios |
| 15 | INFO | Ninguna de las 171 dependencias resueltas tiene vulnerabilidades conocidas en OSV (osv.dev, ecosistema Pub). | `pubspec.lock` |

## Cambios realizados (fases 2 a 4)

### Seguridad del servidor — `supabase/schema.sql`

- Función nueva `is_allowed_user()`: solo cuentas cuyo `app_metadata` incluya `google`. La exigen `join_couple`, `is_couple_member` (y con ella todas las políticas de tabla y de archivos), `create_invite` y `claim_invite`.
- Todas las funciones `security definer` usan `search_path = ''` y nombres completos (`public.tabla`).
- `join_couple`:
  - Valida el formato del buzón.
  - Admite como máximo 5 buzones por cuenta y 4 miembros por buzón.
  - Si la cuenta ya es miembro, no hace nada.
- `create_invite`:
  - Valida el hash (64 hex), el tamaño del paquete (≤ 200) y la duración.
  - Deja como máximo 3 invitaciones vigentes por cuenta.
- `claim_invite` valida el formato antes de buscar.
- `mailbox`:
  - Límite de 256 KB por mensaje (`mailbox_payload_size`).
  - El archivo de un mensaje tiene que estar en la carpeta de su buzón (`mailbox_object_in_couple`).
- El bucket se reafirma como privado con límite de 50 MB.
- Índices nuevos por `user_id` y `created_by`.
- El archivo sigue siendo idempotente: se puede ejecutar varias veces.

### Seguridad y robustez de la app

| Archivo | Cambio |
|---|---|
| `lib/data/repository.dart` | `isSafeMediaName()`; `fileFor()` nunca sale de `media/` (`basename`); `mediaExtensionFor()` limpia extensiones locales; `applyRecord` valida tipos (los convierte en `FormatException`), descarta fotos con nombres peligrosos, de otro recuerdo o de tipo desconocido, rechaza fechas fuera de rango e ignora tipos desconocidos; `storeIncomingFile` rechaza nombres inválidos en vez de "arreglarlos" con otro nombre. |
| `lib/sync/sync_service.dart` | `_receive` dividido en `_openEnvelope`, `_receiveRecord` y `_receiveFile`. Los datos inválidos se descartan y se confirman; los errores de red se propagan y el mensaje espera al próximo intento. `cleanPartnerName()` limpia el nombre y lo recorta a 60 caracteres. Errores genéricos para la persona y detalle en `debugPrint`. |
| `lib/sync/mailbox_transport.dart`, `supabase_transport.dart` | `download()` devuelve `null` si el archivo ya no existe (404). Mensajes de error sin texto crudo del servidor; los mensajes propios del esquema (`P0001`) sí se muestran porque están escritos para eso. |
| `lib/sync/couple_crypto.dart` | Invitación v2: un solo PBKDF2 (60 000 iteraciones, 512 bits) da la llave y el identificador. Archivos de 64 KB o más y el PBKDF2 se procesan con `Isolate.run`. `open()` también tolera paquetes demasiado cortos (`ArgumentError`). |
| `lib/data/auth.dart` | Sin mensaje crudo de Supabase al fallar el inicio de sesión. |
| `lib/data/reminders.dart` | La clave de "ya programado" se guarda al final, así un fallo se reintenta. |
| `lib/ui/memory_edit_screen.dart` | Comprueba `mounted` antes de `setState` al volver del selector; error de guardado sin `$e`. |
| `lib/ui/partner_screen.dart` | `_errorText` ya no muestra la excepción cruda. |
| `lib/ui/auth_screen.dart`, `partner_screen.dart`, `widgets/couple_title.dart` | Nombre y apodo limitados a 60 caracteres. |

### Dependencias y compilación

- **Se quitó `cryptography_flutter`.**
  - En iOS nunca se activaba, porque solo declara `dartPluginClass` para Android, así que el cifrado ya era Dart puro.
  - En Android rompía la compilación, y su versión nueva (2.3.4) no compila con este Flutter (usa `@internal` desde `foundation.dart`).
  - Los algoritmos y formatos son los mismos (AES‑GCM de `package:cryptography`), así que los mensajes siguen siendo compatibles.
  - La lentitud del cifrado en Dart puro se compensó moviéndolo a otro hilo.
- Se quitó `cupertino_icons`, que nada usaba.
- Se probó un ajuste de Gradle para asignarle *namespace* al plugin viejo. Se descartó porque el plugin tampoco compila por la API `Registrar`, y se revirtió.

### Código eliminado

- `Repository.appointmentById()` (sin referencias).
- `AuthService.devBypass` (getter sin uso; se usan `canUseDevBypass` y `_devBypass`).
- `cryptography_flutter` y `cupertino_icons` de `pubspec.yaml`.
- Comentario obsoleto sobre WhatsApp en `auth_screen.dart` y descripción de plantilla en `pubspec.yaml`.

### Refactorizaciones

- `applyRecord` pasó de un bloque `if/else` dentro de una transacción a un `switch` con `_applyMemory`. Primero se valida fuera de la transacción y después se escribe.
- La recepción de mensajes se dividió en tres funciones con una sola responsabilidad cada una.
- `maxNameLength` es una constante compartida entre la interfaz y la sincronización.
- `pairCode` quedó marcado `@visibleForTesting`.
- `dart format` se aplicó a todo `lib/` y `test/`.

## Pruebas

| Archivo | Pruebas | Qué cubre |
|---|---|---|
| `test/repository_test.dart` (nuevo) | 17 | Nombres seguros, *path traversal* (no borra fuera de la carpeta), tipos inválidos, fechas fuera de rango, tipos desconocidos, gana el más reciente, archivos recibidos, guardar/quitar/borrar fotos, cola sin duplicados, ajustes, nombre. |
| `test/crypto_test.dart` (nuevo) | 9 | Lectura de códigos, letras confusas y largos, `seal`/`open` y código equivocado, paquetes dañados, identificador estable y distinto del SHA‑256 directo, nonce aleatorio, alteración detectada, archivos grandes en otro hilo. |
| `test/sync_test.dart` | 10 (+3) | Mensajes dañados de 7 formas sin bloquear el buzón, falla de red en la descarga (el mensaje espera), limpieza del nombre; además de los flujos que ya había. |
| `test/milestones_test.dart`, `test/auth_test.dart` | 7 | Sin cambios de lógica. |

**Prueba de mutación:** se desactivó a mano la protección de rutas y la prueba de *path traversal* falló (el archivo de fuera se borraba). Después se restauró.

**Prueba de punta a punta con Supabase real**, en dos simuladores de iPhone con cuentas de Google distintas:
- Se creó un recuerdo con una foto de más de 64 KB, que pasa por el cifrado en otro hilo.
- Llegó al otro teléfono con su foto.
- Al borrarlo, el borrado también llegó.

**Cobertura** (`flutter test --coverage`, solo archivos que importan las pruebas):

| Archivo | Cobertura |
|---|---|
| `couple_crypto.dart` | 100 % |
| `repository.dart` | 97 % |
| `models` | 94 % |
| `milestones.dart` | 88 % |
| `sync_service.dart` | 84 % |
| `auth.dart` | 41 % (el flujo con Google necesita Supabase y el SDK nativo) |
| **Lógica en total** | **88 %** |

Las pantallas no tienen pruebas de widgets.

## Validaciones (resultados reales)

| Verificación | Resultado |
|---|---|
| `flutter analyze` | No issues found |
| `dart format --set-exit-if-changed lib test` | Sin cambios pendientes |
| `flutter test` | 43 de 43 pasan |
| `flutter build ios --release --no-codesign` | ✓ Runner.app 26,2 MB |
| `flutter build apk --release` | ✓ app-release.apk 30,1 MB (antes fallaba) |
| Vulnerabilidades en dependencias (OSV, 171 paquetes) | Ninguna conocida |
| Sintaxis de `schema.sql` (parser de PostgreSQL `pglast`) | 43 sentencias y 5 funciones válidas. **No se ejecutó contra una base**: no hay Postgres en este equipo y no se usó la contraseña de la base de datos. |
| Esquema nuevo en Supabase (después de que lo ejecutaste) | `is_allowed_user` existe; sin sesión, `join_couple`, `is_couple_member`, `create_invite` y `claim_invite` responden 42501 (permiso denegado) y la inserción en `mailbox` la rechaza RLS. |
| Proveedores de Auth (`/auth/v1/settings`) | Solo Google activo; Email, teléfono y anónimo desactivados. |
| Cuenta de Google con las reglas nuevas (iPhone 16) | Al abrir la app, `join_couple` y la lectura del buzón funcionan ("Al día"); un cambio enviado salió sin error. |
| `flutter pub outdated` | Hay versiones nuevas, pero ninguna se puede instalar sin cambiar la versión principal o la de Flutter. No se actualizaron. |

## Lo que tienes que hacer tú

1. ~~Ejecutar de nuevo `supabase/schema.sql`~~ y ~~desactivar Email~~: hecho y verificado (ver Validaciones).
2. Actualizar la app en los dos teléfonos. Una invitación creada con la versión anterior no se puede usar con la nueva (cambió el identificador); basta con crear otro código.

## Riesgos pendientes

- **Abuso de almacenamiento por cuentas de Google.** Alguien con una cuenta de Google puede crear hasta 5 buzones y subir archivos de 50 MB hasta llenar el GB gratuito. No hay cobro (el plan gratis solo deja de aceptar subidas), pero el buzón de la pareja dejaría de funcionar. Se puede mitigar con un límite de archivos por buzón (contando `storage.objects`) o con una tarea que borre lo viejo.
- **Sin límite de intentos en `claim_invite`.** Con 31⁹ ≈ 2,6·10¹³ códigos y 15 minutos de vigencia, la probabilidad de acertar es despreciable, pero no hay *rate limiting* propio.
- **Mensajes que nunca se reciben** se quedan en el servidor (cifrados) para siempre.
- **La llave de la pareja y la sesión de Supabase** se guardan en el almacenamiento de la app (SQLite y SharedPreferences), no en Keychain/Keystore. Están dentro del sandbox, pero entran en las copias de seguridad del teléfono, igual que los recuerdos.
- **La pareja es de confianza:** su teléfono puede enviar muchos archivos (llenar disco) o fechas de edición futuras (gana siempre por "última escritura"). Los nombres y rutas sí se validan.
- **Android release firmado con la llave de depuración** (configuración por defecto de Flutter). Sirve para instalar el APK a mano; para Play Store hace falta una llave propia, registrar su SHA‑1 en Google Cloud y también la de Play App Signing.
- **Cifrado en Dart puro:** en otro hilo ya no congela la pantalla, pero un video de 45 MB tarda varios segundos más en enviarse que con cifrado nativo.
- **No verificado:** la subida de fotos y videos con el esquema nuevo (solo se probó un mensaje sin archivo), el rechazo de una cuenta que no sea de Google (ya no se pueden crear cuentas por correo para probarlo), el inicio de sesión con Google en Android (no hay emulador ni dispositivo en esta auditoría), y las pantallas con pruebas de widgets.

## Recomendaciones para llegar a producción

1. Enviar un recuerdo con foto entre los dos teléfonos para confirmar la subida con el esquema nuevo.
2. Agregar una cuota de archivos por buzón y una limpieza programada (`pg_cron`) de mensajes de más de 60 días, avisando en la app.
3. Mover la llave de la pareja a Keychain/Keystore (`flutter_secure_storage`) y excluir la sesión de las copias de seguridad.
4. Crear la llave de firma de Android y su ID de OAuth; probar el inicio de sesión en un Android real.
5. Agregar pruebas de widgets para los flujos de Pareja (crear y usar código) y de guardar recuerdo.
6. Cuando se actualice Flutter, revisar `flutter pub outdated`. Hay versiones mayores de `share_plus`, `flutter_local_notifications`, `gal`, `geocoding` y `flutter_lints` que conviene evaluar una por una.
7. Poner el proyecto en git, con `coverage/` y `build/` ignorados.
