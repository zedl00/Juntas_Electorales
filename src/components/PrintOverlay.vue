<!-- src/components/PrintOverlay.vue -->
<script setup>
import { computed } from 'vue';
import { printJob, cerrarPrint, doPrint, printSello, selloOmitido } from '../stores/print';
import { fmtCed, fecha, hoyLarga } from '../lib/formato';
import { reqLbl, cargoCorto, trasladoLbl } from '../lib/constantes';
import { catMap } from '../stores/catalogo';

/* ── Ubicación electoral ──
   Con datos se rellena; en blanco queda vacío, con línea para escribir a mano. */
const votaRecinto = computed(() => printJob.value?.p?.recinto_nombre || '');

const votaColegio = computed(() => {
  const p = printJob.value?.p;
  return p ? [p.codigo_colegio, p.colegio_desc].filter(Boolean).join(' — ') : '';
});

const votaMunicipio = computed(() => {
  const p = printJob.value?.p;
  if (!p) return '';
  if (p.municipio_padron_id) return catMap.value.get(p.municipio_padron_id)?.nombre || '';
  return printJob.value?.mun?.nombre || '';
});

const votaCirc = computed(() => printJob.value?.p?.circunscripcion || '');

/* Cuando trabaja donde vota, el bloque B repite los datos del padrón.
   Cuando hay traslado, solo consta el territorio: la mesa concreta se
   asigna después, y esas líneas quedan en blanco para completarlas. */
const hayTraslado = computed(() => !!printJob.value?.p?.fuera_de_colegio);

const trabajaRecinto   = computed(() => hayTraslado.value ? '' : votaRecinto.value);
const trabajaColegio   = computed(() => hayTraslado.value ? '' : votaColegio.value);
const trabajaCirc      = computed(() => hayTraslado.value ? '' : votaCirc.value);
const trabajaMunicipio = computed(() => printJob.value?.p ? (printJob.value?.mun?.nombre || '') : '');

const etiquetaB = computed(() => {
  if (!printJob.value?.p) return '· a completar';
  return hayTraslado.value ? '· otra demarcación' : '· el mismo lugar';
});
</script>

<template>
  <div class="print-overlay fixed inset-0 z-[80] bg-ink/50 p-3 sm:p-6 overflow-y-auto">

    <div class="print-controls sticky top-0 z-10 flex items-center justify-end gap-2 max-w-[840px] mx-auto mb-3">
      <span v-if="printSello" class="mr-auto text-[11.5px] text-white/85 bg-black/25 rounded-lg px-2.5 py-1.5 backdrop-blur">
        Sellado a nombre de <b>{{ printSello.nombre }}</b> · {{ printSello.momento.toLocaleString('es-DO') }}
      </span>
      <span v-else-if="selloOmitido" class="mr-auto text-[11.5px] text-white/75 bg-black/25 rounded-lg px-2.5 py-1.5 backdrop-blur">
        Sin marca de agua · pensado para fotocopiarse
        <span class="block text-white/60">La emisión queda registrada igualmente</span>
      </span>
      <button class="btn-p btn-s" @click="doPrint">⎙ Imprimir</button>
      <button class="btn-o btn-s" @click="cerrarPrint">Cerrar</button>
    </div>
    <div class="print-card bg-white rounded-xl shadow-2xl max-w-[840px] mx-auto p-6 sm:p-10">

      <!-- Hoja: formulario individual / en blanco -->
      <div v-if="printJob.tipo === 'individual' || printJob.tipo === 'blanco'" class="sheet sh-ind">
        <div v-if="printSello" class="marca-agua" aria-hidden="true">
          <span class="m-tit">Emitido</span>
          <span class="m-nom">{{ printSello.nombre }}</span>
          <span class="m-fec">{{ printSello.momento.toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) }}</span>
        </div>
        <div v-if="printSello" class="pie-traza">
          Documento emitido por <b>{{ printSello.nombre }}</b> · {{ printSello.momento.toLocaleString('es-DO') }}
          · Portal de Delegados 2028 · Secretaría Nacional Electoral · Fuerza del Pueblo.
          Su emisión queda registrada en la bitácora del sistema.
        </div>

        <div style="height:2.5px;background:#1D8A55"></div>
        <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-top:7px">
          <div style="display:flex;align-items:center;gap:7px">
            <div style="width:34px;height:34px;background:#1D8A55;color:#fff;display:grid;place-items:center;font-weight:700;font-size:13px;border-radius:7px">FP</div>
            <div>
              <div class="s-serif" style="font-weight:700;font-size:14px">FUERZA DEL PUEBLO</div>
              <div style="font-size:9.5px;color:#444">Secretaría Nacional Electoral · Comisión de Juntas Electorales y OCLEE</div>
            </div>
          </div>
          <div style="border:1.6px solid #20241F;border-radius:6px;padding:3px 10px;text-align:center">
            <div style="font-size:8.5px;font-weight:700;letter-spacing:.08em">FORMULARIO No.</div>
            <div class="s-serif" style="font-size:14px;font-weight:700">{{ printJob.p?.numero_formulario || '____-_____' }}</div>
          </div>
        </div>
        <div class="s-serif" style="text-align:center;font-weight:700;font-size:12px;letter-spacing:.04em;margin:13px 0 3px;text-transform:uppercase">Postulación de Delegados, Suplentes de Delegados y Observadores de Escrutinio</div>
        <div style="text-align:center;font-size:10px;color:#444;margin-bottom:5px">Colegios Electorales · Procesos de Febrero y Mayo 2028</div>
        <div style="display:flex;gap:12px;flex-wrap:wrap;font-size:10px;border-top:.8px solid #bbb;border-bottom:.8px solid #bbb;padding:5px 2px">
          <span><b>Región:</b> {{ printJob.mun?.macroregion || '__________' }}</span>
          <span><b>Provincia:</b> {{ printJob.mun?.provincia_nombre || '__________' }}</span>
          <span><b>Municipio / DM:</b> {{ printJob.mun?.nombre || '________________' }}</span>
          <span><b>Circunscripción:</b> {{ printJob.p?.circunscripcion || '______' }}</span>
          <span style="margin-left:auto"><b>Fecha:</b> {{ printJob.p ? fecha(printJob.p.created_at) : '____ /____ /______' }}</span>
        </div>

        <div class="sh-sec">I · Datos del postulante</div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:0 16px">
          <div class="frow"><span class="flab">Nombres</span><span class="fval">{{ printJob.p?.nombres || '' }}</span></div>
          <div class="frow"><span class="flab">Apellidos</span><span class="fval">{{ printJob.p ? (printJob.p.apellido1 + ' ' + (printJob.p.apellido2 || '')) : '' }}</span></div>
          <div class="frow"><span class="flab">Cédula</span><span class="fval">{{ printJob.p ? fmtCed(printJob.p.cedula) : '' }}</span></div>
          <div class="frow"><span class="flab">Sexo / F. nac.</span><span class="fval">{{ printJob.p ? (printJob.p.sexo + ' · ' + (printJob.p.fecha_nacimiento || '')) : '' }}</span></div>
          <div class="frow"><span class="flab">Teléfono</span><span class="fval">{{ printJob.p?.telefono || '' }}</span></div>
          <div class="frow"><span class="flab">WhatsApp</span><span class="fval">{{ printJob.p?.whatsapp || '' }}</span></div>
          <div class="frow" style="grid-column:1/-1"><span class="flab">Dirección</span><span class="fval">{{ printJob.p?.direccion || '' }}</span></div>
          <div class="frow"><span class="flab">Nivel académico</span><span class="fval">{{ printJob.p?.nivel_academico || '' }}</span></div>
          <div class="frow"><span class="flab">Ocupación</span><span class="fval">{{ printJob.p?.ocupacion || '' }}</span></div>
          <div class="frow"><span class="flab">Correo</span><span class="fval">{{ printJob.p?.email || '' }}</span></div>
          <div class="frow"><span class="flab">Vínculo con el partido</span><span class="fval">{{ printJob.p?.militancia || '' }}</span></div>
        </div>

        <div class="sh-sec">II · UBICACIÓN ELECTORAL</div>
        <div class="ubic" style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:4px">

          <div style="border:1px solid #b9b9b9;border-radius:4px;padding:5px 8px 4px">
            <div style="font-size:8.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:#444;border-bottom:1px solid #d5d5d5;padding-bottom:2px;margin-bottom:3px">
              A · Vota en <span style="font-weight:600;letter-spacing:0;text-transform:none;color:#777">· según el padrón</span>
            </div>
            <div class="frow"><span class="flab">Recinto</span><span class="fval">{{ votaRecinto }}</span></div>
            <div class="frow"><span class="flab">Colegio</span><span class="fval">{{ votaColegio }}</span></div>
            <div class="frow"><span class="flab">Municipio / DM</span><span class="fval">{{ votaMunicipio }}</span></div>
            <div class="frow"><span class="flab">Circunscripción</span><span class="fval">{{ votaCirc }}</span></div>
          </div>

          <div style="border-radius:4px;padding:5px 8px 4px"
               :style="hayTraslado ? 'border:1.6px solid #B4720E;background:#FDF6E7' : 'border:1px solid #b9b9b9'">
            <div style="font-size:8.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;border-bottom:1px solid #d5d5d5;padding-bottom:2px;margin-bottom:3px"
                 :style="hayTraslado ? 'color:#B4720E' : 'color:#444'">
              B · Trabajará en
              <span style="font-weight:600;letter-spacing:0;text-transform:none"
                    :style="hayTraslado ? 'color:#B4720E' : 'color:#777'">{{ etiquetaB }}</span>
            </div>
            <div class="frow"><span class="flab">Recinto</span><span class="fval">{{ trabajaRecinto }}</span></div>
            <div class="frow"><span class="flab">Colegio</span><span class="fval">{{ trabajaColegio }}</span></div>
            <div class="frow"><span class="flab">Municipio / DM</span><span class="fval">{{ trabajaMunicipio }}</span></div>
            <div class="frow"><span class="flab">Circunscripción</span><span class="fval">{{ trabajaCirc }}</span></div>
          </div>
        </div>

        <div v-if="hayTraslado"
             style="font-size:9px;border:1px solid #E0C89A;background:#FDF6E7;border-radius:4px;padding:4px 8px;margin-bottom:4px;line-height:1.3">
          <b style="color:#B4720E">Traslado:</b> {{ trasladoLbl[printJob.p.traslado_nivel] || 'Otra demarcación' }}.
          <span v-if="printJob.p.autorizado_por">Autorizado por <b>{{ printJob.p.autorizado_por }}</b>.</span>
          <b v-if="printJob.p.traslado_estado === 'pendiente'" style="color:#B4720E">PENDIENTE DE AUTORIZACIÓN DE LA SNE.</b>
        </div>

        <div class="sh-sec">III · Cargo al que se postula</div>
        <div style="display:flex;gap:14px;flex-wrap:wrap;font-size:11px;padding:2px 0">
          <span><span class="cbx" :class="{ on: printJob.p?.cargo_postulado === 'delegado_titular' }"></span>Delegado(a) Titular</span>
          <span><span class="cbx" :class="{ on: printJob.p?.cargo_postulado === 'suplente_delegado' }"></span>Suplente de Delegado(a)</span>
          <span><span class="cbx" :class="{ on: printJob.p?.cargo_postulado === 'observador_escrutinio' }"></span>Observador(a) de Escrutinio</span>
          <span><span class="cbx" :class="{ on: printJob.p?.cargo_postulado === 'indistinto' }"></span>Indistinto</span>
        </div>

        <div class="sh-sec">IV · Requisitos (Instructivo, Sección III)</div>
        <div style="font-size:10.5px;line-height:1.35">
          <div v-for="(rq, k) in reqLbl" :key="k" style="padding:2.5px 0"><span class="cbx" :class="{ on: !printJob.p || !!printJob.p.requisitos?.[k] }"></span>{{ rq }}</div>
        </div>

        <div class="sh-sec">V · Ha servido en procesos electorales anteriores electoral previa</div>
        <div style="display:flex;gap:14px;align-items:flex-end;font-size:11px">
        <span><span class="cbx" :class="{ on: printJob.p?.experiencia_2020 === true }"></span>Proceso 2020</span>
          <span><span class="cbx" :class="{ on: printJob.p?.experiencia_2024 === true }"></span>Proceso 2024</span>
          <span><span class="cbx" :class="{ on: printJob.p?.experiencia_otros === true }"></span>Otros procesos</span>
          <span class="fval" style="min-height:15px">{{ printJob.p?.experiencia_detalle || '' }}</span>
        </div>

        <div style="margin:22px 0 5px;display:flex;justify-content:center">
          <div class="sigline" style="width:58%">
            <div style="font-size:10px;min-height:15px">&nbsp;</div>
            <div style="font-size:9px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;margin-top:2px">Firma del postulante</div>
          </div>
        </div>

        <div class="sh-sec">VI · Certificación de la Dirección Ejecutiva</div>
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:18px">
          <div class="sigline"><div style="font-size:10px;min-height:15px">{{ printJob.off?.presidente || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;margin-top:2px">Presidente(a)</div><div style="font-size:8.5px;color:#555">Dirección Ejecutiva</div></div>
          <div class="sigline"><div style="font-size:10px;min-height:15px">{{ printJob.off?.secretario_general || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;margin-top:2px">Secretario(a) General</div><div style="font-size:8.5px;color:#555">Dirección Ejecutiva</div></div>
          <div class="sigline"><div style="font-size:10px;min-height:15px">{{ printJob.off?.enc_electoral || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;margin-top:2px">Encargado(a) Electoral</div><div style="font-size:8.5px;color:#555">Dirección Ejecutiva</div></div>
        </div>
        <div style="font-size:8.5px;color:#666;border-top:.8px solid #bbb;margin-top:16px;padding-top:5px;display:flex;justify-content:space-between">
          <span>Remitir el original firmado a la Comisión de Juntas Electorales y OCLEE · SNE-FP.</span>
          <span>{{ hoyLarga() }}</span>
        </div>
      </div>

      <!-- Hoja: relación de postulantes -->
      <div v-else-if="printJob.tipo === 'relacion'" class="sheet">
        <div v-if="printSello" class="marca-agua" aria-hidden="true">
          <span class="m-tit">Emitido</span>
          <span class="m-nom">{{ printSello.nombre }}</span>
          <span class="m-fec">{{ printSello.momento.toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) }}</span>
        </div>
        <div v-if="printSello" class="pie-traza">
          Documento emitido por <b>{{ printSello.nombre }}</b> · {{ printSello.momento.toLocaleString('es-DO') }}
          · Portal de Delegados 2028 · Secretaría Nacional Electoral · Fuerza del Pueblo.
          Su emisión queda registrada en la bitácora del sistema.
        </div>

        <div style="height:3px;background:#1D8A55"></div>
        <div style="display:flex;align-items:center;justify-content:space-between;margin-top:10px">
          <div style="display:flex;align-items:center;gap:8px">
            <div style="width:28px;height:28px;background:#1D8A55;color:#fff;display:grid;place-items:center;font-weight:700;font-size:11px;border-radius:6px">FP</div>
            <div><div class="s-serif" style="font-weight:700;font-size:13px">FUERZA DEL PUEBLO · Secretaría Nacional Electoral</div><div style="font-size:9px;color:#444">Comisión de Juntas Electorales y OCLEE</div></div>
          </div>
          <div style="font-size:9.5px;color:#444;text-align:right">{{ hoyLarga() }}</div>
        </div>
        <div class="s-serif" style="text-align:center;font-weight:700;font-size:12.5px;letter-spacing:.04em;margin:12px 0 2px;text-transform:uppercase">Relación de Postulantes · Colegios Electorales 2028</div>
        <div style="text-align:center;font-size:10.5px;color:#333;margin-bottom:9px"><b>{{ printJob.mun ? (printJob.mun.nombre + ' · ' + (printJob.mun.provincia_nombre || '') + (printJob.mun.macroregion ? ' · Región ' + printJob.mun.macroregion : '')) : 'Varios territorios' }}</b> · {{ printJob.rows.length }} postulantes</div>
        <table class="rel">
          <thead><tr><th style="width:22px">#</th><th>Folio</th><th>Cédula</th><th>Nombre</th><th>Cargo</th><th>Colegio</th><th>Teléfono</th></tr></thead>
          <tbody>
            <tr v-for="(r, i) in printJob.rows" :key="r.id">
              <td>{{ i + 1 }}</td>
              <td style="font-weight:600">{{ r.numero_formulario }}</td>
              <td>{{ fmtCed(r.cedula) }}</td>
              <td>{{ r.nombres }} {{ r.apellido1 }} {{ r.apellido2 || '' }}</td>
              <td>{{ cargoCorto[r.cargo_postulado] }}</td>
              <td>{{ r.codigo_colegio || r.id_colegio_padron || '' }}</td>
              <td>{{ r.telefono || '' }}</td>
            </tr>
          </tbody>
        </table>
        <div v-if="printJob.mun" style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:18px;margin-top:8px">
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.presidente || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Presidente(a)</div></div>
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.secretario_general || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Secretario(a) General</div></div>
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.enc_electoral || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Encargado(a) Electoral</div></div>
        </div>
        <div style="font-size:8.5px;color:#666;border-top:.8px solid #bbb;margin-top:14px;padding-top:5px">Secretaría Nacional Electoral · Fuerza del Pueblo · Uso institucional.</div>
      </div>


      <!-- Hoja: reporte de validación por recinto y colegio -->
      <div v-else-if="printJob.tipo === 'colegios'" class="sheet">
        <div v-if="printSello" class="marca-agua" aria-hidden="true">
          <span class="m-tit">Emitido</span>
          <span class="m-nom">{{ printSello.nombre }}</span>
          <span class="m-fec">{{ printSello.momento.toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) }}</span>
        </div>
        <div v-if="printSello" class="pie-traza">
          Documento emitido por <b>{{ printSello.nombre }}</b> · {{ printSello.momento.toLocaleString('es-DO') }}
          · Portal de Delegados 2028 · Secretaría Nacional Electoral · Fuerza del Pueblo.
          Su emisión queda registrada en la bitácora del sistema.
        </div>

        <div style="height:3px;background:#1D8A55"></div>
        <div style="display:flex;align-items:center;justify-content:space-between;margin-top:10px">
          <div style="display:flex;align-items:center;gap:8px">
            <div style="width:28px;height:28px;background:#1D8A55;color:#fff;display:grid;place-items:center;font-weight:700;font-size:11px;border-radius:6px">FP</div>
            <div><div class="s-serif" style="font-weight:700;font-size:13px">FUERZA DEL PUEBLO · Secretaría Nacional Electoral</div><div style="font-size:9px;color:#444">Comisión de Juntas Electorales y OCLEE</div></div>
          </div>
          <div style="font-size:9.5px;color:#444;text-align:right">{{ hoyLarga() }}</div>
        </div>
        <div class="s-serif" style="text-align:center;font-weight:700;font-size:12.5px;letter-spacing:.04em;margin:12px 0 2px;text-transform:uppercase">Relación de Postulantes por Recinto y Colegio Electoral</div>
        <div v-if="printJob.alcance" style="text-align:center;font-size:10.5px;font-weight:700;color:#1D8A55;margin-bottom:3px">{{ printJob.alcance }}</div>
          <div style="text-align:center;font-size:10px;color:#444;margin-bottom:4px">Documento de revisión y validación de la Dirección Ejecutiva Territorial · Colegios Electorales 2028</div>
        <div style="text-align:center;font-size:10.5px;color:#333;margin-bottom:8px">
          <b>{{ printJob.mun ? (printJob.mun.nombre + (printJob.mun.provincia_nombre ? ' · ' + printJob.mun.provincia_nombre : '')) : '' }}</b>
          · {{ printJob.cob.length }} colegios
          · Completos: {{ printJob.cob.filter(c => c.personas >= 3).length }}
          · Incompletos: {{ printJob.cob.filter(c => c.personas > 0 && c.personas < 3).length }}
          · Sin registro: {{ printJob.cob.filter(c => !c.personas).length }}
        </div>

        <template v-for="(c, ci) in printJob.cob" :key="c.id_colegio">
          <div v-if="ci === 0 || printJob.cob[ci-1].recinto !== c.recinto"
               style="background:#EAF6EF;border:1px solid #B4DFC6;border-radius:4px;padding:3px 8px;margin:10px 0 5px;font-weight:700;font-size:10.5px">
            RECINTO: {{ c.recinto }}<span v-if="c.recinto_dir" style="font-weight:400;color:#444"> · {{ c.recinto_dir }}</span>
          </div>
          <div style="page-break-inside:avoid;border:1px solid #cfcfcf;border-radius:4px;padding:5px 8px;margin-bottom:6px">
            <div style="display:flex;justify-content:space-between;align-items:baseline;border-bottom:.8px solid #ddd;padding-bottom:3px;margin-bottom:4px">
              <span style="font-weight:700;font-size:10.5px">{{ c.colegio }} <span style="font-weight:400;color:#555">· {{ c.inscritos }} inscritos</span></span>
              <span style="font-size:9px;font-weight:700;letter-spacing:.04em"
                    :style="{ color: c.personas >= 3 ? '#177347' : (c.personas ? '#b45309' : '#b91c1c') }">
                {{ c.personas >= 3 ? '✔ COMPLETO' : (c.personas ? 'FALTAN ' + (3 - c.personas) : 'SIN REGISTRO') }} · {{ c.personas }}/3
              </span>
            </div>
            <table style="width:100%;font-size:9.5px;border-collapse:collapse">
              <tr v-for="(p, pi) in (printJob.porColegio.get(c.id_colegio) || [])" :key="p.numero_formulario">
                <td style="width:14px;padding:2px 3px;color:#555">{{ pi + 1 }}.</td>
                <td style="width:62px;padding:2px 3px;font-weight:600">{{ p.numero_formulario }}</td>
                <td style="width:88px;padding:2px 3px">{{ fmtCed(p.cedula) }}</td>
                <td style="padding:2px 3px;font-weight:600">{{ p.nombres }} {{ p.apellido1 }} {{ p.apellido2 || '' }}</td>
                <td style="width:70px;padding:2px 3px">{{ cargoCorto[p.cargo_postulado] }}</td>
                <td style="width:82px;padding:2px 3px">{{ p.telefono || '' }}</td>
                <td style="width:64px;padding:2px 3px;color:#555">☐ Conforme</td>
              </tr>
              <tr v-for="n in Math.max(0, 3 - (printJob.porColegio.get(c.id_colegio) || []).length)" :key="'v' + n">
                <td style="width:14px;padding:2px 3px;color:#999">{{ (printJob.porColegio.get(c.id_colegio) || []).length + n }}.</td>
                <td colspan="5" style="padding:2px 3px;color:#999;border-bottom:.6px dotted #bbb">— pendiente de postulación —</td>
                <td style="width:64px;padding:2px 3px"></td>
              </tr>
            </table>
          </div>
        
</template>

        <div style="font-size:9.5px;margin-top:12px;border-top:.8px solid #bbb;padding-top:6px">
          Certificamos que hemos revisado la presente relación y que las personas aquí postuladas cumplen los requisitos
          establecidos en el Instructivo de la Secretaría Nacional Electoral, y validamos su remisión a la Comisión de
          Juntas Electorales y OCLEE.
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:18px;margin-top:4px">
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.presidente || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Presidente(a)</div></div>
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.secretario_general || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Secretario(a) General</div></div>
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.enc_electoral || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Encargado(a) Electoral</div></div>
        </div>
        <div style="font-size:8.5px;color:#666;border-top:.8px solid #bbb;margin-top:12px;padding-top:5px">Secretaría Nacional Electoral · Fuerza del Pueblo · Uso institucional.</div>
      </div>

      <!-- Hoja: Formulario General del Territorio -->
      <div v-else class="sheet">
        <div v-if="printSello" class="marca-agua" aria-hidden="true">
          <span class="m-tit">Emitido</span>
          <span class="m-nom">{{ printSello.nombre }}</span>
          <span class="m-fec">{{ printSello.momento.toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) }}</span>
        </div>
        <div v-if="printSello" class="pie-traza">
          Documento emitido por <b>{{ printSello.nombre }}</b> · {{ printSello.momento.toLocaleString('es-DO') }}
          · Portal de Delegados 2028 · Secretaría Nacional Electoral · Fuerza del Pueblo.
          Su emisión queda registrada en la bitácora del sistema.
        </div>

        <div style="height:3px;background:#1D8A55"></div>
        <div style="display:flex;align-items:center;justify-content:space-between;margin-top:10px">
          <div style="display:flex;align-items:center;gap:8px">
            <div style="width:28px;height:28px;background:#1D8A55;color:#fff;display:grid;place-items:center;font-weight:700;font-size:11px;border-radius:6px">FP</div>
            <div><div class="s-serif" style="font-weight:700;font-size:13px">FUERZA DEL PUEBLO · Secretaría Nacional Electoral</div><div style="font-size:9px;color:#444">Comisión de Juntas Electorales y OCLEE</div></div>
          </div>
          <div style="font-size:9.5px;color:#444;text-align:right">{{ hoyLarga() }}</div>
        </div>
        <div class="s-serif" style="text-align:center;font-weight:700;font-size:12.5px;letter-spacing:.04em;margin:12px 0 2px;text-transform:uppercase">Formulario General del Territorio</div>
        <div v-if="printJob.alcance" style="text-align:center;font-size:11px;font-weight:700;color:#1D8A55;margin-bottom:3px">{{ printJob.alcance }}</div>
        <div style="text-align:center;font-size:10px;color:#444;margin-bottom:7px">Resumen y relación de postulantes a delegados(as), suplentes y observadores(as) · Colegios Electorales 2028</div>
        <div style="display:flex;gap:12px;flex-wrap:wrap;font-size:10px;border-top:.8px solid #bbb;border-bottom:.8px solid #bbb;padding:5px 2px;margin-bottom:8px">
          <span><b>Región:</b> {{ printJob.mun?.macroregion || '__________' }}</span>
          <span><b>Provincia:</b> {{ printJob.mun?.provincia_nombre || '__________' }}</span>
          <span><b>Municipio / DM / OCLEE:</b> {{ printJob.mun?.nombre || '________________' }}</span>
        </div>

        <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin-bottom:8px">
          <div style="border:1px solid #cfcfcf;border-radius:4px;padding:5px 7px"><div style="font-size:8px;color:#555;text-transform:uppercase;letter-spacing:.05em">Meta del territorio</div><div style="font-size:15px;font-weight:700">{{ printJob.mun?.meta ?? '—' }}</div></div>
          <div style="border:1px solid #cfcfcf;border-radius:4px;padding:5px 7px"><div style="font-size:8px;color:#555;text-transform:uppercase;letter-spacing:.05em">Registrados</div><div style="font-size:15px;font-weight:700">{{ printJob.pers.length }}</div></div>
          <div style="border:1px solid #cfcfcf;border-radius:4px;padding:5px 7px"><div style="font-size:8px;color:#555;text-transform:uppercase;letter-spacing:.05em">Avance</div><div style="font-size:15px;font-weight:700">{{ printJob.mun?.meta ? Math.round(printJob.pers.length * 100 / printJob.mun.meta) : 0 }}%</div></div>
          <div style="border:1px solid #cfcfcf;border-radius:4px;padding:5px 7px"><div style="font-size:8px;color:#555;text-transform:uppercase;letter-spacing:.05em">Colegios completos</div><div style="font-size:15px;font-weight:700">{{ printJob.colOk }}<span style="font-size:10px;font-weight:400;color:#555"> / {{ printJob.colTot }}</span></div></div>
        </div>
        <div style="display:flex;gap:14px;font-size:9.5px;margin-bottom:9px;color:#333">
          <span><b>Titulares:</b> {{ printJob.tot.t }}</span>
          <span><b>Suplentes:</b> {{ printJob.tot.s }}</span>
          <span><b>Observadores:</b> {{ printJob.tot.o }}</span>
          <span v-if="printJob.tot.i"><b>Indistintos:</b> {{ printJob.tot.i }}</span>
          <span style="margin-left:auto"><b>Colegios incompletos:</b> {{ printJob.colPar }} · <b>Sin registro:</b> {{ printJob.colVac }}</span>
        </div>

        <table style="width:100%;font-size:8.8px;border-collapse:collapse">
          <thead>
            <tr style="border-top:1px solid #999;border-bottom:1px solid #999;background:#EAF6EF">
              <th style="text-align:left;padding:3px 3px;width:16px">No.</th>
              <th style="text-align:left;padding:3px 3px;width:58px">Formulario</th>
              <th style="text-align:left;padding:3px 3px;width:84px">Cédula</th>
              <th style="text-align:left;padding:3px 3px">Nombre completo</th>
              <th style="text-align:left;padding:3px 3px;width:64px">Cargo</th>
              <th style="text-align:left;padding:3px 3px;width:56px">Colegio</th>
              <th style="text-align:left;padding:3px 3px;width:92px">Distrito</th>
              <th style="text-align:left;padding:3px 3px;width:74px">Teléfono</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(p, i) in printJob.pers" :key="p.numero_formulario" style="border-bottom:.6px solid #ddd">
              <td style="padding:2.5px 3px;color:#555">{{ i + 1 }}</td>
              <td style="padding:2.5px 3px;font-weight:600">{{ p.numero_formulario }}</td>
              <td style="padding:2.5px 3px">{{ fmtCed(p.cedula) }}</td>
              <td style="padding:2.5px 3px;font-weight:600">{{ p.nombres }} {{ p.apellido1 }} {{ p.apellido2 || '' }}</td>
              <td style="padding:2.5px 3px">{{ cargoCorto[p.cargo_postulado] }}</td>
              <td style="padding:2.5px 3px">{{ p.codigo_colegio || '—' }}</td>
              <td style="padding:2.5px 3px">{{ printJob.distDe.get(p.id_colegio_padron) || '—' }}</td>
              <td style="padding:2.5px 3px">{{ p.telefono || '' }}</td>
            </tr>
            <tr v-if="!printJob.pers.length"><td colspan="8" style="padding:8px;text-align:center;color:#777">Sin postulantes registrados a la fecha.</td></tr>
          </tbody>
        </table>

        <div style="font-size:9.5px;margin-top:12px;border-top:.8px solid #bbb;padding-top:6px">
          Certificamos que la presente relación corresponde a las postulaciones registradas por este territorio para los
          Colegios Electorales 2028, que sus datos fueron verificados y que se remite a la Comisión de Juntas Electorales
          y OCLEE para los fines de validación correspondientes.
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:18px;margin-top:4px">
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.presidente || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Presidente(a)</div></div>
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.secretario_general || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Secretario(a) General</div></div>
          <div class="sigline"><div style="font-size:10px;min-height:13px">{{ printJob.off?.enc_electoral || '' }}</div><div style="font-size:9px;font-weight:700;text-transform:uppercase;margin-top:2px">Encargado(a) Electoral</div></div>
        </div>
        <div style="display:flex;justify-content:space-between;font-size:9px;color:#333;margin-top:10px;border-top:.8px solid #bbb;padding-top:5px">
          <span>Recibido por la Comisión: ______________________________</span>
          <span>Fecha: ______ / ______ / __________</span>
        </div>
        <div style="font-size:8.5px;color:#666;margin-top:8px">Secretaría Nacional Electoral · Fuerza del Pueblo · Uso institucional.</div>
      </div>

    </div>
  </div>
</template>
