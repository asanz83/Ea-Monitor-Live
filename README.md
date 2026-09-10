# ea-monitor-live — panel en vivo (Fase 0 / MVP)

Panel de solo lectura, en la nube (Supabase), que muestra en vivo el saldo,
posiciones abiertas y operaciones cerradas de una cuenta MT5 — alimentado por
un EA reportero (`EA_Reporter.mq5`) que corre en tu terminal y envía los datos,
sin depender de que tu PC esté encendido para poder VERLO (si tu PC se apaga,
el panel sigue accesible, solo deja de recibir datos nuevos). Se actualiza
en tiempo real: en cuanto llega un dato nuevo, el panel lo pinta solo, sin
que tengas que refrescar.

Ver el plan completo con el porqué de cada decisión en
`C:\Users\antonio\.claude\plans\prancy-greeting-platypus.md`.

## Qué hay en esta carpeta

- `migrations/0001_init.sql` — la base de datos (tablas + permisos).
- `supabase/functions/ingest/index.ts` — recibe los datos que manda el EA.
- `supabase/config.toml` — configuración de esa función.
- `.github/workflows/deploy-functions.yml` — despliega la función sola al hacer push.
- `docs/index.html` — el panel en sí (con login y tiempo real).
- `EA_Reporter.mq5` — el EA que instalas en MT5, envía los datos.

## Pasos para ponerlo en marcha (Fase 0 — una sola cuenta de prueba)

### 1. Cuenta y proyecto de Supabase
Crea una cuenta gratis en https://supabase.com (no pide tarjeta). Luego
**New project** — dale un nombre, elige una contraseña de base de datos
(guárdala, no hace falta usarla a mano normalmente) y la región más cercana.
Espera 1-2 minutos a que se cree.

### 2. Crear las tablas
En el proyecto: **SQL Editor → New query**. Pega el contenido completo de
`migrations/0001_init.sql` y ejecútalo (Run). Solo se hace una vez.

### 3. Crear tu usuario de acceso al panel
**Authentication → Providers → Email** → desactiva "Allow new users to sign
up" (así nadie más puede crear una cuenta). Luego **Authentication → Users →
Add user → Create new user**, con tu email (`antoniosanz83@gmail.com`) —
marca "Auto Confirm User" para no tener que verificarlo. Este es el único
usuario que podrá entrar al panel.

Para entrar de verdad usarás un enlace mágico por correo (no hace falta
contraseña) — eso lo pide el propio panel, sigue en el paso 6.

### 4. Coger la URL y la clave del proyecto
**Project Settings → API**. Copia:
- **Project URL** (algo como `https://xxxxx.supabase.co`)
- **anon public key** (una clave larga — esta SÍ va en el navegador, no es
  secreta, el control de acceso real lo hacen el login + los permisos que ya
  creamos en el paso 2)

Pégalas en `docs/index.html`, al principio del `<script>`, sustituyendo
`TU-PROYECTO` y `TU-ANON-KEY`. Dímelo cuando lo tengas y lo hago yo si
prefieres.

### 5. Repo de GitHub + subirlo todo
Crea un repositorio nuevo y vacío en GitHub (por ejemplo `ea-monitor-live`,
privado). Dímelo cuando lo tengas creado y subo yo todo este contenido con el
mismo método que ya uso para `ea_monitor` (tu token de GitHub).

### 6. Activar GitHub Pages (para ver el panel desde cualquier sitio)
En el repo: **Settings → Pages → Source: Deploy from a branch → Branch: main,
carpeta `/docs`** → Save. GitHub te da una URL tipo
`https://tu-usuario.github.io/ea-monitor-live/` — esa es la dirección del
panel. Tarda 1-2 minutos en publicarse la primera vez.

### 7. Conectar el despliegue automático de la función (`/ingest`)
Esto hace que cada vez que se actualice `supabase/functions/ingest`, se
despliegue solo, sin que tengas que hacer nada a mano.
1. En Supabase: **Account → Access Tokens → Generate new token** — cópialo
   (solo se ve una vez).
2. En Supabase: **Project Settings → General** — copia el **Reference ID**
   del proyecto (unas letras/números cortos).
3. En GitHub: **Settings → Secrets and variables → Actions → New repository
   secret** — crea dos:
   - `SUPABASE_ACCESS_TOKEN` → el token del paso 1
   - `SUPABASE_PROJECT_REF` → el Reference ID del paso 2

Con esto ya subido, el primer push desplegará la función automáticamente
(lo puedo hacer yo cuando subamos todo).

### 8. Dar de alta tu primera cuenta MT5 (el token de prueba)
Para que el EA pueda enviar datos, tiene que existir una fila en la tabla
`accounts` con un token. Aquí tienes uno ya generado, listo para tu primera
prueba — **guarda el TOKEN, lo necesitas en el paso 9**:

```
TOKEN (va en el EA_Reporter, input InpAuthToken):
a0e8926a84b8b77cda182f94c787fe44c973088d5bc05d239f07f9204e85e23c
```

En **SQL Editor** (mismo sitio que el paso 2), pega y ejecuta (cambia
`TU_LOGIN_MT5` por el número de tu cuenta MT5, y el `label` por lo que
quieras que aparezca en el panel):

```sql
insert into accounts (mt5_login, label, broker, currency, token_hash)
values (
  'TU_LOGIN_MT5',
  'Mi cuenta de prueba',
  '', '',
  'cb80e08630d21deead40fafacf74c5912597224b9d70ad1262200560445e4b57'
);
```

(El hash de arriba corresponde exactamente al token de arriba — no lo cambies
a mano. Si en el futuro quieres dar de alta OTRA cuenta, dímelo y te genero un
token+hash nuevo para esa — nunca reutilices el mismo token en dos cuentas.)

### 9. Instalar el EA reportero en MT5
1. Copia `EA_Reporter.mq5` a la carpeta `MQL5/Experts` de tu terminal MT5
   (Archivo → Abrir carpeta de datos → MQL5 → Experts).
2. Ábrelo en MetaEditor y compílalo (F7) — no debería dar errores.
3. En el terminal: **Herramientas → Opciones → Asesores Expertos** → marca
   "Permitir WebRequest para las URL listadas" y añade tu Project URL de
   Supabase (la misma que usarás en `InpServerUrl`, terminada en
   `/functions/v1/ingest`).
4. Arrastra `EA_Reporter` a un gráfico cualquiera de esa cuenta (solo uno,
   no hace falta en cada gráfico). En sus inputs, rellena:
   - `InpServerUrl`: `https://TU-PROYECTO.supabase.co/functions/v1/ingest`
   - `InpAuthToken`: el token del paso 8.
5. Revisa la pestaña "Expertos" del terminal — debería decir "EA_Reporter
   iniciado..." sin errores de WebRequest.

### 10. Verificar
- Abre la URL de GitHub Pages del paso 6. Escribe tu email y pulsa "Enviarme
  un enlace de acceso" — te llega un correo de Supabase, pulsa el enlace y
  vuelves al panel ya conectado.
- Espera 1-2 minutos y confirma que el saldo/equity y las posiciones abiertas
  coinciden con lo que ves en MT5 — deberían aparecer solas, sin refrescar.
- Prueba a abrirlo desde el móvil con datos (no wifi de casa) para confirmar
  que no depende de tu red local.
- Apaga MT5/el PC un momento y comprueba que el panel sigue abriéndose (solo
  se marcará como "desactualizado", no desaparece).

## Si algo falla

- **Error 4014 en el log de Expertos** → la URL no está en la lista blanca
  del paso 9.3, revísala (tiene que ser exactamente igual, con `https://`).
- **El panel no carga ninguna cuenta** → revisa que el paso 8 (insert en
  `accounts`) se ejecutó sin errores, y que el token del EA coincide con el
  que diste de alta.
- **No llega el correo de acceso** → revisa spam, y que el email coincide
  exactamente con el usuario creado en el paso 3.
- **La función no se despliega sola tras un push** → revisa que los dos
  secretos de GitHub Actions (paso 7) están bien puestos, y mira la pestaña
  "Actions" del repo para ver el error exacto.

Cuando esto funcione con una cuenta, avísame y seguimos con el resto
(Fase 1 del plan).
