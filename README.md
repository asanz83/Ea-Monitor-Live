# ea-monitor-live — panel en vivo (Fase 0 / MVP)

Panel de solo lectura, en la nube (Cloudflare), que muestra en vivo el saldo,
posiciones abiertas y operaciones cerradas de una cuenta MT5 — alimentado por
un EA reportero (`EA_Reporter.mq5`) que corre en tu terminal y envía los datos,
sin depender de que tu PC esté encendido para poder VERLO (si tu PC se apaga,
el panel sigue accesible, solo deja de recibir datos nuevos).

Ver el plan completo con el porqué de cada decisión en
`C:\Users\antonio\.claude\plans\prancy-greeting-platypus.md`.

## Qué hay en esta carpeta

- `wrangler.toml` — configuración del Worker de Cloudflare.
- `src/index.js` — el servidor (recibe datos del EA, sirve el panel).
- `public/index.html` — el panel en sí.
- `migrations/0001_init.sql` — la base de datos (tablas).
- `EA_Reporter.mq5` — el EA que instalas en MT5, envía los datos.

## Pasos para ponerlo en marcha (Fase 0 — una sola cuenta de prueba)

### 1. Cuenta de Cloudflare
Si no tienes, crea una gratis en https://dash.cloudflare.com/sign-up (solo pide
email). No hace falta tarjeta para el nivel gratuito que usamos.

### 2. Repo de GitHub
Crea un repositorio nuevo y vacío en GitHub (por ejemplo `ea-monitor-live`,
privado). Dímelo cuando lo tengas creado y subo yo todo este contenido con el
mismo método que ya uso para `ea_monitor` (tu token de GitHub).

### 3. Conectar Cloudflare Workers con ese repo
En el dashboard de Cloudflare: **Workers & Pages → Create → Workers → Import
a repository** (o "Connect to Git"), elige el repo que acabas de crear. Deja
que Cloudflare detecte `wrangler.toml` automáticamente. Esto hace que cada vez
que se suba algo nuevo al repo, se despliegue solo — no hace falta que hagas
nada más después de este paso para futuras actualizaciones.

### 4. Crear la base de datos D1
En el dashboard: **Workers & Pages → D1 → Create database** — nombre libre,
por ejemplo `ea-monitor-live-db`. Al crearla te da un **Database ID**: cópialo
y pégalo en `wrangler.toml` (sustituye el texto `PENDIENTE-rellenar-...`),
donde dice `database_id`. Súbelo al repo (yo te ayudo con esto si quieres) y
en **Workers & Pages → tu Worker → Settings → Bindings** conecta esa base con
el binding `DB` si no queda ya conectado automáticamente por el `wrangler.toml`.

### 5. Crear las tablas
En el dashboard: **D1 → (tu base) → Console**. Pega el contenido completo de
`migrations/0001_init.sql` y ejecútalo. Solo se hace una vez.

### 6. Dar de alta tu primera cuenta (el token de prueba)
Para que el EA pueda enviar datos, tiene que existir una fila en la tabla
`accounts` con un token. Aquí tienes uno ya generado, listo para usar en tu
primera prueba — **guarda el TOKEN, lo necesitas en el paso 8**:

```
TOKEN (va en el EA_Reporter, input InpAuthToken):
a0e8926a84b8b77cda182f94c787fe44c973088d5bc05d239f07f9204e85e23c
```

En la consola D1 (mismo sitio que el paso 5), pega y ejecuta (cambia
`TU_LOGIN_MT5` por el número de tu cuenta MT5, y el `label` por lo que
quieras que aparezca en el panel):

```sql
INSERT INTO accounts (mt5_login, label, broker, currency, token_hash, created_at)
VALUES (
  'TU_LOGIN_MT5',
  'Mi cuenta de prueba',
  '', '',
  'cb80e08630d21deead40fafacf74c5912597224b9d70ad1262200560445e4b57',
  datetime('now')
);
```

(El hash de arriba corresponde exactamente al token de arriba — no lo cambies
a mano. Si en el futuro quieres dar de alta OTRA cuenta, dímelo y te genero un
token+hash nuevo para esa — nunca reutilices el mismo token en dos cuentas.)

### 7. Activar Cloudflare Access (para que el panel solo lo veas tú)
**Zero Trust → Access → Applications → Add an application → Self-hosted.**
Dominio: el que te haya dado el Worker (`ea-monitor-live.<algo>.workers.dev`).
Política: permitir solo tu email (`antoniosanz83@gmail.com`) por código de un
solo uso (One-time PIN) — no hace falta contraseña nueva, te llega un código
por correo cada vez que entras. **Importante:** añade una regla de bypass (o
un "Service Auth") para la ruta `/ingest`, para que el EA pueda seguir
mandando datos sin tener que hacer login (esa ruta ya tiene su propia
protección por token, no necesita Access).

### 8. Instalar el EA reportero en MT5
1. Copia `EA_Reporter.mq5` a la carpeta `MQL5/Experts` de tu terminal MT5
   (Archivo → Abrir carpeta de datos → MQL5 → Experts).
2. Ábrelo en MetaEditor y compílalo (F7) — no debería dar errores.
3. En el terminal: **Herramientas → Opciones → Asesores Expertos** → marca
   "Permitir WebRequest para las URL listadas" y añade la URL de tu Worker
   (la misma que usarás en `InpServerUrl`, terminada en `/ingest`).
4. Arrastra `EA_Reporter` a un gráfico cualquiera de esa cuenta (solo uno,
   no hace falta en cada gráfico). En sus inputs, rellena:
   - `InpServerUrl`: `https://ea-monitor-live.<tu-subdominio>.workers.dev/ingest`
   - `InpAuthToken`: el token del paso 6.
5. Revisa la pestaña "Expertos" del terminal — debería decir "EA_Reporter
   iniciado..." sin errores de WebRequest.

### 9. Verificar
- Abre la URL del Worker (sin `/ingest`) en el navegador — debería aparecer
  el panel, pidiéndote el login de Cloudflare Access la primera vez.
- Espera 1-2 minutos y confirma que el saldo/equity y las posiciones abiertas
  coinciden con lo que ves en MT5.
- Prueba a abrirlo desde el móvil con datos (no wifi de casa) para confirmar
  que no depende de tu red local.
- Apaga MT5/el PC un momento y comprueba que el panel sigue abriéndose (solo
  se marcará como "desactualizado", no desaparece).

## Si algo falla

- **Error 4014 en el log de Expertos** → la URL no está en la lista blanca
  del paso 8.3, revísala (tiene que ser exactamente igual, con `https://`).
- **El panel no carga ninguna cuenta** → revisa que el paso 6 (INSERT en
  `accounts`) se ejecutó sin errores, y que el token del EA coincide con el
  que diste de alta.
- **Cloudflare Access no deja pasar al EA** → revisa la regla de bypass del
  paso 7 para `/ingest`.

Cuando esto funcione con una cuenta, avísame y seguimos con el resto
(Fase 1 del plan).
