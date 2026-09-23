# Portal de Delegados 2028 — Guía de trabajo en Mac y despliegue en cPanel

**Secretaría Nacional Electoral · Fuerza del Pueblo**
Proyecto Vue 3 + Vite, modular, con PWA instalable y backend Supabase.

Esta guía asume una **Mac limpia, recién sacada de la caja**, viniendo de Windows, sin nada instalado. Sigue los pasos en orden; solo se hacen una vez. A partir de ahí, tu día a día son 2 comandos.

---

## PARTE 1 · Preparar la Mac (se hace una sola vez)

### 1.1 Abrir la Terminal

La Terminal es el equivalente al "CMD" o "PowerShell" de Windows.

1. Presiona **Cmd (⌘) + Barra espaciadora** — se abre el buscador Spotlight.
2. Escribe `Terminal` y presiona **Enter**.
3. Se abre una ventana con un cursor esperando comandos. Consejo: clic derecho sobre el ícono de Terminal en el Dock → **Opciones → Mantener en el Dock**, para tenerla siempre a mano.

En la Terminal, **pegar** es **Cmd + V** (igual que en Windows con Ctrl + V).

### 1.2 Instalar Homebrew (el instalador de programas para desarrolladores)

Homebrew es como una "tienda de aplicaciones" por comandos: con él instalaremos Node y todo lo demás. Pega esta línea completa en la Terminal y presiona Enter:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

- Te pedirá tu **contraseña de la Mac** (al escribirla no se ven los caracteres — es normal, escribe y presiona Enter).
- Es posible que pida instalar las **Command Line Tools de Xcode**: acepta y espera (puede tardar varios minutos).
- **Importante:** al terminar, Homebrew muestra una sección llamada **"Next steps"** con 2 comandos que empiezan con `echo` y `eval`. **Cópialos y ejecútalos tal cual** — eso activa el comando `brew`. En Macs con chip Apple (M1/M2/M3/M4) suelen ser:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verifica que quedó bien:

```bash
brew --version
```

Debe responder con un número de versión (por ejemplo `Homebrew 4.x`).

### 1.3 Instalar Node.js y Git

```bash
brew install node git
```

Verifica:

```bash
node -v
npm -v
git --version
```

Deben responder versiones (Node 20 o superior es lo que necesita este proyecto).

### 1.4 Instalar Visual Studio Code (el editor)

```bash
brew install --cask visual-studio-code
```

Se instala en Aplicaciones. Ábrelo una vez (Cmd + Espacio → "Visual Studio Code"). Si macOS pregunta si confías en la app descargada, acepta.

> Con esto la Mac queda lista. Todo lo anterior no se vuelve a hacer.

---

## PARTE 2 · Poner el proyecto a funcionar

### 2.1 Ubicar el proyecto

1. Crea una carpeta de trabajo, por ejemplo `Proyectos`, dentro de tu carpeta personal (Finder → tu usuario → clic derecho → Nueva carpeta).
2. Descomprime **`portal-delegados-fuente.zip`** ahí (doble clic al zip). Te queda:
   `/Users/tu-usuario/Proyectos/portal-delegados/`

### 2.2 Entrar a la carpeta desde la Terminal

Truco de Mac: escribe `cd ` (con un espacio al final) en la Terminal y **arrastra la carpeta** `portal-delegados` desde el Finder hasta la ventana de la Terminal — la ruta se escribe sola. Presiona Enter.

```bash
cd ~/Proyectos/portal-delegados
```

### 2.3 Instalar las dependencias del proyecto (una vez por computadora)

```bash
npm install
```

Descarga Vue, Vite, Tailwind y el resto de librerías dentro de la carpeta `node_modules` (tarda 1–2 minutos la primera vez). Esa carpeta **nunca se sube al servidor**.

### 2.4 Trabajar en el proyecto (tu día a día)

```bash
npm run dev
```

Verás algo como `Local: http://localhost:5173/`. Ábrelo en el navegador: es el portal corriendo en tu Mac, conectado al Supabase real. **Cada cambio que guardes en el código se refleja al instante** en el navegador, sin recargar.

Para abrir el código: en VS Code → **File → Open Folder** → selecciona `portal-delegados`. Para detener el servidor de desarrollo: en la Terminal, **Ctrl + C**.

### 2.5 El archivo `.env` (credenciales)

Las claves de Supabase **no están regadas por el código**: viven en el archivo `.env` en la raíz:

```
VITE_SUPABASE_URL=…
VITE_SUPABASE_ANON_KEY=…
VITE_PORTAL_URL=https://electoral.strategosfp.com/delegados/
```

Ya viene configurado con los valores del proyecto. Si algún día cambian, se editan solo aquí.

---

## PARTE 3 · Compilar y subir a cPanel

### 3.1 Compilar

```bash
npm run empaquetar
```

Este comando hace dos cosas: compila la versión de producción (carpeta `dist/`, optimizada y minificada) y la comprime en **`portal-delegados-dist.zip`** en la raíz del proyecto. Ese zip es **lo único** que se sube al servidor.

### 3.2 Subir por el Administrador de Archivos de cPanel (recomendado)

1. Entra a tu **cPanel** → **Administrador de Archivos** (File Manager).
2. Navega a la **carpeta raíz del subdominio** `electoral.strategosfp.com` (su *document root*).
3. Si no existe, crea la carpeta **`delegados`** y entra en ella.
4. Botón **Subir** (Upload) → selecciona `portal-delegados-dist.zip` de tu Mac.
5. De vuelta en el Administrador, clic derecho sobre el zip → **Extract** → extraer ahí mismo.
6. Borra el zip del servidor (opcional, por orden).
7. Abre `https://electoral.strategosfp.com/delegados/` — el portal está en línea.

**No hace falta configurar nada más en el servidor** (ni `.htaccess` ni reglas de reescritura): el portal usa rutas con `#` y rutas relativas precisamente para que funcione en cualquier carpeta de cPanel tal cual se extrae.

### 3.3 Alternativa: FTP con FileZilla

Si prefieres FTP como en Windows: `brew install --cask filezilla`, conéctate con las credenciales FTP de cPanel y arrastra **el contenido de la carpeta `dist/`** (no la carpeta en sí) hacia `/delegados/` en el servidor.

### 3.4 Actualizaciones futuras

Cada vez que hagas cambios: `npm run empaquetar` → subir el zip → Extract (sobrescribe) → listo. La PWA detecta la nueva versión y se actualiza sola en los teléfonos de los usuarios.

---

## PARTE 4 · Requisitos en Supabase (antes del primer uso)

1. **Ejecutar en orden** en Supabase → SQL Editor: `sql/fase1_setup.sql`, luego `sql/fase2_seguimiento_y_auditoria.sql`, luego `sql/fase4_distritos_y_regiones.sql`, luego `sql/fase5_consulta_bot_y_ajustes.sql` (completos, cada uno una vez, en ese orden). La fase 4 incluye y supera a la fase 3. Crea **todo el portal dentro de su propio esquema `delegados`** (tablas, vista de metas, RPC y políticas). **No crea ni modifica nada en `public`**: el sistema SNE queda intacto, y revertir el portal completo es una sola orden (`drop schema delegados cascade;`).
2. **Exponer el esquema a la API** (obligatorio): Supabase → **Settings → API → "Exposed schemas"** → agrega `delegados` a la lista y guarda. Sin este paso la aplicación no puede consultar el esquema (error PGRST106).
3. **Authentication → Providers → Email → desactivar "Confirm email"**. Sin esto, los accesos creados desde el portal quedarían esperando un correo de confirmación que nunca llega (los usuarios entran con cédula, no con correo real).
4. **Crearte como administrador:** al final de `fase1_setup.sql` hay un bloque comentado — colócale tu email del SNE y tu cédula, y ejecútalo. Con eso entras al portal con tu email y contraseña actuales del sistema, y desde **Usuarios** creas a los demás.

---

## Estructura del proyecto

```
portal-delegados/
├── index.html                  Página raíz (fuentes, metadatos)
├── package.json                Dependencias y comandos (dev, build, empaquetar)
├── vite.config.js              Configuración de Vite + PWA (manifest, service worker)
├── tailwind.config.js          Paleta FP y tipografías
├── .env                        Credenciales de Supabase (URL, clave anon, URL del portal)
├── public/
│   ├── icons/                  Íconos de la app (192, 512, maskable, Apple)
│   └── instructivo.pdf         Instructivo oficial (se sirve tal cual)
├── sql/
│   ├── fase1_setup.sql         Base de datos del portal (ejecutar en Supabase)
│   ├── fase2_seguimiento_y_auditoria.sql  Cobertura por colegio + bitácora total
│   ├── fase3_regiones_y_vista.sql         (superada por fase4; se conserva por historial)
│   └── fase4_distritos_y_regiones.sql     Regiones como el sistema SNE + distritos JCE
├── docs/
│   ├── ESQUEMA_BD.md           Esquema y mapa completo de tablas del proyecto
│   └── USUARIOS_Y_PIN.md       Manual operativo: accesos, PIN, seguridad y despliegue
└── src/
    ├── main.js                 Arranque: PWA + sesión + montaje
    ├── App.vue                 Estructura general (barra, cinta, navegación, modales)
    ├── style.css               Tokens de diseño, clases de componentes, CSS de impresión
    ├── lib/
    │   ├── supabase.js         Clientes Supabase (principal y auxiliar)
    │   ├── constantes.js       Etiquetas: roles, cargos, etapas, requisitos, cronograma
    │   └── formato.js          Formatos: cédulas, fechas, números, PIN
    ├── stores/                 Estado compartido entre pantallas
    │   ├── auth.js             Sesión, perfil, roles, PIN, acuse
    │   ├── catalogo.js         Territorios y metas (vista portal_metas_municipio)
    │   ├── kpi.js              Indicadores y avance por territorio
    │   ├── print.js            Impresión de formularios y relaciones
    │   ├── pwa.js              Instalación de la app en el teléfono
    │   └── toasts.js           Avisos flotantes y portapapeles
    ├── router/index.js         Rutas y control de acceso por rol
    ├── components/             Piezas reutilizables (barra superior, tabs, hojas de impresión…)
    └── views/                  Una pantalla = un archivo
        ├── AccesoView.vue      Inicio de sesión
        ├── InicioView.vue      Seguimiento (KPI + avance por territorio)
        ├── RegistrarView.vue   Asistente de postulación en 4 pasos
        ├── PostulantesView.vue Listado, filtros, CSV, detalle y gestión de etapas
        ├── ProtocoloView.vue   Instructivo oficial con acuse de lectura
        ├── UsuariosView.vue    Gestión de usuarios territoriales (admin)
        ├── ActividadView.vue   Bitácora total del sistema (admin)
        ├── AyudaView.vue       Centro de ayuda didáctico (todos, incluso sin sesión)
        └── CuentaView.vue      Perfil, cambio de PIN, cierre de sesión
```

## Comandos de referencia

| Comando | Qué hace |
|---|---|
| `npm install` | Instala dependencias (una vez por computadora) |
| `npm run dev` | Servidor de desarrollo en `http://localhost:5173` con recarga en vivo |
| `npm run build` | Compila producción en `dist/` |
| `npm run empaquetar` | Compila **y** genera `portal-delegados-dist.zip` listo para cPanel |

## Problemas comunes

- **`command not found: brew`** → faltó ejecutar los 2 comandos de "Next steps" del paso 1.2.
- **`command not found: npm`** → falta `brew install node`, o abre una Terminal nueva.
- **`npm install` da error de red** → verifica la conexión y reintenta; npm continúa donde quedó.
- **La página abre en blanco en cPanel** → confirma que extrajiste el **contenido** del zip dentro de `/delegados/` (debe verse `index.html` directamente en esa carpeta, no una subcarpeta extra).
- **Cambié algo y no se ve en producción** → recuerda el ciclo: `npm run empaquetar` → subir → Extract.
