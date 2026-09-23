# Usuarios, PIN y Seguridad — Manual Operativo

**Portal de Delegados 2028 · Secretaría Nacional Electoral · Fuerza del Pueblo**

Este documento explica cómo funcionan los accesos, qué seguridad los protege, el procedimiento exacto para entregar usuarios a presidentes, secretarios generales y encargados electorales a escala nacional, y cómo crear los usuarios de prueba de cada rol.

---

## 1 · Cómo funciona el acceso (el concepto)

Cada dirigente entra con **dos datos que ya conoce o recibe por WhatsApp**:

- **Usuario = su cédula** (con o sin guiones, da igual).
- **PIN = una clave numérica de 6 dígitos** que el sistema genera al crearle el acceso.

No se usan correos: internamente el sistema convierte la cédula en una cuenta técnica (`cedula@delegadosfp.com`), pero el dirigente nunca ve eso — para él es simplemente *cédula + PIN*. La excepción son los administradores de la SNE, que entran con su email y contraseña del sistema SNE de siempre.

**Primer ingreso obligatorio:** la primera vez que la persona entra con el PIN que recibió, el sistema **la obliga a crear su PIN personal** (mínimo 6 caracteres) antes de poder hacer nada. Desde ese momento, el PIN inicial del WhatsApp deja de servir y **solo esa persona conoce su clave**. Ni el administrador ni la Comisión pueden verla: queda cifrada de forma irreversible.

### Quién ve qué (los alcances)

| Rol | Ve | Puede hacer |
|---|---|---|
| **Encargado(a) Electoral** | Solo su municipio/DM/OCLEE | **Registrar** postulantes, editarlos mientras estén en *Postulado* o *Devuelto*, imprimir formularios y reportes |
| **Presidente(a)** | Solo su territorio | Consultar, ver cobertura por colegio, **imprimir el reporte de validación** para revisar y firmar |
| **Secretario(a) General** | Solo su territorio | Igual que el presidente: consulta e impresión |
| **Supervisor(a) Provincial** | Toda su provincia | Consulta y seguimiento (no registra) |
| **Coordinador(a) Regional** | Toda su macroregión | Consulta y seguimiento (no registra) |
| **Administrador SNE** | Todo el país | Todo: validar/devolver/rechazar, crear usuarios, ver la bitácora de actividad |

Estos límites **no son de pantalla: son de base de datos** (Row Level Security). Aunque alguien manipulara la aplicación, el servidor solo le entrega las filas de su territorio.

---

## 2 · La seguridad, explicada sin tecnicismos

1. **Nadie puede leer un PIN.** Se guarda con cifrado de un solo sentido (bcrypt, el estándar bancario). Ni siquiera con acceso total a la base de datos se puede recuperar una clave — solo restablecerla.
2. **Cada quien en su territorio.** Las reglas de seguridad viven en el servidor de datos, no en la aplicación. Un encargado de Los Alcarrizos jamás recibirá un registro de Santiago, pida lo que pida.
3. **El esquema `delegados` está cerrado al público.** Sin sesión iniciada, la base de datos niega hasta la entrada al esquema (ya lo comprobaste con el `permission denied` del rol anónimo — esa es la puerta funcionando).
4. **Todo deja huella.** Desde la Fase 2, el sistema registra cada acceso, cada consulta de cédula al padrón, cada registro, cada edición (con el **antes y el después campo por campo**), cada cambio de etapa, cada alta/edición/activación/desactivación de usuarios. El administrador lo ve todo en la sección **Actividad**.
5. **Acceso revocable al instante.** En **Usuarios**, el botón Activo/Inactivo corta el acceso de cualquier persona de inmediato (por ejemplo, si cesa en sus funciones o pierde el teléfono).
6. **El padrón nunca se expone.** La búsqueda por cédula es de coincidencia exacta y pasa por una función controlada: no existe forma de listar ni navegar el padrón desde el portal.
7. **Un solo perfil por persona.** La cédula es única tanto en usuarios como en postulantes: no puede haber cuentas duplicadas ni doble postulación.

---

## 3 · Procedimiento de entrega de accesos (el operativo)

Diseñado para personas que no manejan tecnología: **el dirigente solo necesita abrir un enlace y escribir dos datos.**

### Lo que hace la Comisión (2 minutos por usuario)

1. Entra al portal como administrador → **Usuarios → + Nuevo usuario**.
2. Escribe la **cédula** del dirigente → **Verificar** (el sistema trae su nombre del padrón y avisa dónde vota).
3. Elige el **rol** y el **territorio** (municipio/DM/OCLEE para los tres roles municipales; provincia para supervisores; región para coordinadores).
4. El **PIN de 6 dígitos ya viene generado** (el botón ↻ genera otro si se desea) → **Crear acceso**.
5. El sistema muestra el **mensaje de WhatsApp listo** con: enlace del portal, cédula, PIN inicial y las instrucciones. Botón **Copiar mensaje** → pegarlo en WhatsApp y enviarlo al dirigente. Listo.

> Si el mensaje se pierde, en la tabla de Usuarios el botón **"Copiar acceso"** regenera el mensaje (sin el PIN, por seguridad — el PIN solo se muestra al crear).

### Lo que hace el dirigente (una sola vez, 2 minutos)

1. Toca el **enlace** del WhatsApp → se abre el portal.
2. (Recomendado) Toca **"Instalar la aplicación en este teléfono"** — queda el ícono FP en su pantalla, como cualquier app.
3. Escribe su **cédula** y el **PIN del mensaje** → Entrar.
4. El sistema le pide **crear su PIN personal** → lo escribe dos veces → adentro.
5. En **Protocolo**, lee el Instructivo y toca **"Confirmo que he leído el Instructivo"** (queda el acuse con fecha).

A partir de ahí entra siempre con cédula + su PIN personal, desde el ícono de su teléfono.

### Recomendaciones para el despliegue nacional

- **Orden sugerido por territorio:** primero el **Encargado Electoral** (es quien registra), después presidente y secretario (consultan y validan en papel).
- **Por lotes:** provincia por provincia, verificando en **Usuarios** el chip **"Sin primer acceso"** — ahí se ve quién todavía no ha entrado, para darle seguimiento telefónico.
- **Regla de oro a comunicar:** *el acceso es personal e intransferible; el PIN no se comparte con nadie, ni con la Comisión.* Todo lo que se haga con un usuario queda registrado a su nombre en la bitácora.

### Si alguien olvida su PIN

El administrador lo restablece **desde el propio portal, en un clic**: **Usuarios → botón ↺** en la fila de la persona → el sistema genera un PIN provisional, muestra el mensaje de WhatsApp listo (con el botón de envío directo) y obliga a crear un PIN personal en el siguiente ingreso. Cada restablecimiento queda en la bitácora de Actividad, y las cuentas de administración están protegidas (su clave se gestiona en el sistema SNE, nunca aquí).

Receta SQL de respaldo, por si alguna vez se necesita hacerlo directo en la base:

```sql
update auth.users
   set encrypted_password = extensions.crypt('NUEVO_PIN_6_DIGITOS', extensions.gen_salt('bf'))
 where email = 'CEDULA_SIN_GUIONES@delegadosfp.com';

update delegados.usuarios_territoriales
   set primer_acceso = true
 where cedula = 'CEDULA_SIN_GUIONES';
```

Se le envía el nuevo PIN por WhatsApp y el flujo de primer ingreso se repite.

---

## 4 · Usuarios de prueba (uno por rol)

Para probar el sistema completo sin tocar datos reales, crea los 5 desde el propio portal (**Usuarios → + Nuevo usuario**). Usa cédulas ficticias de 11 dígitos que empiecen en ceros — el botón Verificar dirá "no encontrada en el padrón", es normal y **no impide crearlos**; escribe el nombre a mano:

| Cédula | Nombre | Rol | Territorio |
|---|---|---|---|
| 00000000001 | PRUEBA ENCARGADO | Encargado(a) Electoral | un municipio tuyo de referencia |
| 00000000002 | PRUEBA PRESIDENTE | Presidente(a) | el mismo municipio |
| 00000000003 | PRUEBA SECRETARIO | Secretario(a) General | el mismo municipio |
| 00000000004 | PRUEBA SUPERVISOR | Supervisor(a) Provincial | la provincia de ese municipio |
| 00000000005 | PRUEBA COORDINADOR | Coordinador(a) Regional | la región correspondiente |

Anota el PIN de cada uno al crearlo. Luego entra con cada cuenta (en una ventana privada del navegador para no cerrar tu sesión de admin: **Archivo → Nueva ventana privada**) y verifica: el encargado registra y edita; presidente y secretario ven su cobertura por colegio e imprimen el reporte de validación pero **no** pueden registrar; supervisor y coordinador ven su provincia/región completa; y todos los movimientos aparecen en tu sección **Actividad**.

**Limpieza al terminar las pruebas** (elimina los 5 usuarios de prueba y sus cuentas):

```sql
delete from delegados.usuarios_territoriales where cedula like '0000000000%';
delete from auth.users where email like '0000000000%@delegadosfp.com';
```

(Si registraste postulantes de prueba, elimínalos antes desde el portal o con: `delete from delegados.postulantes_2028 where cedula = '...';` — la eliminación queda en la bitácora con el registro completo, como todo.)
