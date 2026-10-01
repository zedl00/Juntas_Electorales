/* src/lib/constantes.js */
/* Etiquetas y catálogos fijos del dominio electoral */

export const rolLbl = {
  presidente: 'Presidente(a)', secretario_general: 'Secretario(a) General', enc_electoral: 'Encargado(a) Electoral',
  supervisor_provincial: 'Supervisor(a) Provincial', coordinador_regional: 'Coordinador(a) Regional',
  consulta_nacional: 'Consulta Nacional', admin_sne: 'Administrador SNE'
};

export const cargoLbl = {
  delegado_titular: 'Delegado(a) Titular', suplente_delegado: 'Suplente de Delegado(a)',
  observador_escrutinio: 'Observador(a) de Escrutinio', indistinto: 'Indistinto'
};

export const cargoCorto = { delegado_titular: 'Titular', suplente_delegado: 'Suplente', observador_escrutinio: 'Observador', indistinto: 'Indistinto' };

export const estadoLbl = {
  postulado: 'Postulado', validado: 'Validado', devuelto: 'Devuelto', rechazado: 'Rechazado',
  en_formacion: 'En formación', aprobado: 'Aprobado', no_aprobado: 'No aprobado', designado: 'Designado', acreditado: 'Acreditado'
};

/* Verificación de membresía con la Secretaría de Organización (fase 85) */
export const miembroLbl = { pendiente: 'Sin verificar', enviado: 'Enviado a Organización', miembro: 'Miembro', no_miembro: 'No miembro', no_localizado: 'No localizado', en_revision: 'En revisión' };
export const miembroCls = {
  pendiente: 'border-line bg-paper text-mut', enviado: 'border-sky-200 bg-sky-50 text-sky-800',
  miembro: 'border-fp-200 bg-fp-50 text-fp-800', no_miembro: 'border-red-200 bg-red-50 text-red-700',
  no_localizado: 'border-amber-200 bg-amber-50 text-amber-800', en_revision: 'border-line bg-paper text-ink'
};

export const estadoCls = {
  postulado: 'border-fp-200 bg-fp-50 text-fp-800', validado: 'border-fp-600 bg-fp-600 text-white',
  devuelto: 'border-amber-200 bg-amber-50 text-amber-800', rechazado: 'border-red-200 bg-red-50 text-red-700',
  en_formacion: 'border-sky-200 bg-sky-50 text-sky-800', aprobado: 'border-teal-200 bg-teal-50 text-teal-800',
  no_aprobado: 'border-red-200 bg-red-50 text-red-700', designado: 'border-ink bg-ink text-white',
  acreditado: 'border-fp-800 bg-fp-800 text-white'
};

export const estadoOrden = ['postulado','validado','devuelto','en_formacion','aprobado','no_aprobado','designado','acreditado','rechazado'];

export const reqLbl = {
  militante: 'Es miembro activo y militante del Partido.',
  derechos: 'Se encuentra en pleno ejercicio de sus derechos civiles y políticos.',
  inscrito: 'Está inscrito(a) en el Registro Electoral de la demarcación donde ejercerá sus funciones.',
  no_candidatura: 'No aspira ni ostenta candidatura a cargo de elección popular en este proceso.',
  sin_incompat: 'No presenta incompatibilidades legales para el ejercicio de las funciones.',
  disponibilidad: 'Cuenta con las aptitudes y actitudes idóneas para el cargo, y con disponibilidad para la formación y los simulacros electorales.',
  tecnologia: 'Posee habilidades básicas de comunicación y manejo de herramientas tecnológicas.'
};

/* Qué significa cada requisito, para que el Encargado(a) certifique con criterio */
export const reqDet = {
  militante: 'Inscrito en el padrón del partido y con participación reconocida por la dirigencia de su demarcación. No basta la simpatía.',
  derechos: 'Sin condena que le inhabilite ni interdicción vigente. Es condición legal para ejercer ante la mesa.',
  inscrito: 'Debe votar en la misma demarcación donde será delegado. El sistema lo verifica contra el padrón; si vota en otra, se advierte.',
  no_candidatura: 'Quien aspira a un cargo no puede ser delegado del partido en la mesa donde se cuenta su propia elección.',
  sin_incompat: 'Sin parentesco cercano con miembros de la mesa, ni función pública que comprometa su imparcialidad.',
  disponibilidad: 'Temple ante la presión, discreción y trato respetuoso; y podrá asistir a la capacitación, a los simulacros y permanecer en el colegio desde la apertura hasta el cierre del escrutinio. Las aptitudes y actitudes quedan sujetas a revisión con el Protocolo.',
  tecnologia: 'Sabe usar WhatsApp, recibir y enviar fotografías, y reportar por teléfono. Es el canal por el que se comunicará el día de la votación.'
};

/* Peso de cada requisito para el análisis de idoneidad */
export const reqPeso = {
  militante: 3, derechos: 3, inscrito: 3, no_candidatura: 2,
  sin_incompat: 2, disponibilidad: 3, tecnologia: 2
};

export const nivelOpts = ['Primaria','Secundaria','Técnico','Universitario','Postgrado'];

export const cronograma = [
  { a: 'Socialización, preselección y recepción de postulaciones', p: 'Sept. 2026 – Enero 2027' },
  { a: 'Validación de requisitos', p: 'Oct. 2026 – Feb. 2027' },
  { a: 'Programa de formación electoral y evaluación', p: 'Feb. – Sept. 2027' },
  { a: 'Selección, designación y acreditación', p: 'Oct. – Dic. 2027' },
  { a: 'Acreditación ante Juntas Electorales y OCLEE', p: 'Calendario JCE' },
  { a: 'Elecciones municipales', p: '20 de febrero de 2028' },
  { a: 'Elecciones presidenciales y congresuales', p: '21 de mayo de 2028' }
];


/* Experiencia electoral · redacción general que abarca cualquier función
   servida —titular, suplente u observador— sin obligar a precisar cuál */
export const expTitulo = 'Ha servido en procesos electorales anteriores';
export const expLbl = {
  experiencia_2020:  'Proceso 2020',
  experiencia_2024:  'Proceso 2024',
  experiencia_otros: 'Otros procesos'
};

/* Cómo se describe cada nivel de traslado */
export const trasladoLbl = {
  mismo_colegio:   'En su propio colegio',
  mismo_distrito:  'Otro colegio de su distrito',
  mismo_municipio: 'Otro colegio de su municipio',
  misma_provincia: 'Otro municipio de su provincia',
  otra_provincia:  'Otra provincia'
};

export const alcanceLbl = {
  colegio:   'Solo su propio colegio',
  municipio: 'Dentro de su distrito o municipio',
  provincia: 'Dentro de su provincia',
  libre:     'Cualquier territorio'
};
