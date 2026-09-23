<script setup>
import { ref } from 'vue';
import { perfil, registrarAcuse } from '../stores/auth';
import { reqLbl, cronograma } from '../lib/constantes';
import { fecha } from '../lib/formato';

const acuseBusy = ref(false);
const acuse = async () => { acuseBusy.value = true; await registrarAcuse(); acuseBusy.value = false; };
</script>

<template>
  <section class="max-w-3xl space-y-4">
    <div class="flex items-start justify-between gap-3">
      <div>
        <h2 class="font-serif text-xl font-bold">Protocolo · Instructivo oficial</h2>
        <p class="text-[12.5px] text-mut mt-0.5">Preselección, formación y designación de delegados, suplentes y observadores de escrutinio ante los colegios electorales 2028.</p>
      </div>
    </div>
    <div class="card p-4 flex flex-wrap items-center gap-2">
      <a href="./instructivo.pdf" target="_blank" rel="noopener" class="btn-p btn-s">Abrir PDF oficial</a>
      <a href="./instructivo.pdf" download="Instructivo_Delegados_2028_SNE-FP.pdf" class="btn-o btn-s">Descargar</a>
      <span class="mx-auto"></span>
      <span v-if="perfil?.acuse_instructivo" class="chip">✓ Leído el {{ fecha(perfil.acuse_instructivo) }}</span>
      <button v-else class="btn-o btn-s" @click="acuse" :disabled="acuseBusy">Confirmo que he leído el Instructivo</button>
    </div>

    <details class="card acc" open>
      <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Presentación y objeto</summary>
      <div class="px-4 pb-4 text-[13.5px] leading-relaxed text-ink/90 space-y-2.5">
        <p>La adecuada y oportuna preselección, formación, certificación, designación e integración del cuerpo de delegados, suplentes de delegados y observadores de escrutinio es esencial para garantizar la representación del Partido ante los colegios electorales, fortalecer la defensa del voto y contribuir al desarrollo ordenado del proceso electoral.</p>
        <p>El Instructivo establece el procedimiento para los procesos electorales de <b>febrero y mayo de 2028</b>, con fundamento en la Constitución, la Ley 20-23 de Régimen Electoral, la Ley 33-18 de Partidos, los reglamentos de la JCE, el Estatuto del Partido y las disposiciones de la Secretaría Nacional Electoral.</p>
      </div>
    </details>

    <details class="card acc">
      <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Principios rectores</summary>
      <div class="px-4 pb-4 text-[13.5px] leading-relaxed space-y-1.5">
        <p><b>Legalidad</b>, con apego a la normativa electoral vigente. <b>Transparencia</b>, mediante procedimientos claros y verificables. <b>Idoneidad</b>, prefiriendo la capacidad, el compromiso, la militancia y la responsabilidad. <b>Representación territorial</b>, con compañeros(as) que conozcan la demarcación donde ejercerán. <b>Disciplina institucional</b>, promoviendo el respeto a las decisiones del Partido.</p>
      </div>
    </details>

    <details class="card acc">
      <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Perfil y requisitos mínimos</summary>
      <div class="px-4 pb-4 text-[13.5px] leading-relaxed">
        <ul class="space-y-1.5">
          <li v-for="(rq, k) in reqLbl" :key="k" class="flex gap-2"><span class="text-fp-600 font-bold">✓</span><span>{{ rq }}</span></li>
          <li class="flex gap-2"><span class="text-fp-600 font-bold">✓</span><span>Se tomará en cuenta la experiencia en procesos electorales previos, la trayectoria, la conducta ética y el compromiso partidario para la defensa del voto.</span></li>
        </ul>
      </div>
    </details>

    <details class="card acc">
      <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Procedimiento (4 etapas)</summary>
      <div class="px-4 pb-4 text-[13.5px] leading-relaxed space-y-3">
        <p><b>1 · Convocatoria y postulaciones.</b> Las estructuras ejecutivas territoriales identifican y postulan a los aspirantes en el formulario físico, firmado por el presidente, el secretario general y el encargado electoral de la Dirección Ejecutiva Municipal. El secretario electoral territorial lo integra o digitaliza en esta plataforma y lo remite a la Comisión de Juntas Electorales y OCLEE.</p>
        <p><b>2 · Validación de requisitos.</b> La Secretaría Nacional Electoral verifica el cumplimiento y conforma el banco inicial de aspirantes.</p>
        <p><b>3 · Formación y evaluación.</b> Los preseleccionados pasan a la Escuela de Formación Electoral, bajo la responsabilidad de la Secretaría de Formación Política y la Secretaría de Innovación.</p>
        <p><b>4 · Selección y designación.</b> La SNE designa delegados titulares, suplentes y observadores según resultados de evaluación, perfiles, necesidades electorales y distribución territorial. Solo la SNE puede autorizar, remitir o depositar los listados ante las Juntas Electorales y OCLEE.</p>
      </div>
    </details>

    <details class="card acc">
      <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Funciones ante el colegio electoral</summary>
      <div class="px-4 pb-4 grid sm:grid-cols-3 gap-3">
        <div class="rounded-xl border border-line bg-paper p-3.5">
          <div class="font-serif font-bold text-[13.5px] mb-1.5">Delegado(a) Titular</div>
          <p class="text-[12px] leading-relaxed text-ink/85">Representa oficialmente al Partido ante el colegio; vela por el cumplimiento normativo durante votación, cierre y escrutinio; formula observaciones y reclamaciones; coordina con el suplente y el observador; rinde informe de incidencias al coordinador del recinto.</p>
        </div>
        <div class="rounded-xl border border-line bg-paper p-3.5">
          <div class="font-serif font-bold text-[13.5px] mb-1.5">Suplente de Delegado(a)</div>
          <p class="text-[12px] leading-relaxed text-ink/85">Apoya al titular, lo sustituye cuando sea necesario y colabora en la documentación y comunicación de las incidencias de la jornada electoral.</p>
        </div>
        <div class="rounded-xl border border-line bg-paper p-3.5">
          <div class="font-serif font-bold text-[13.5px] mb-1.5">Observador(a) de Escrutinio</div>
          <p class="text-[12px] leading-relaxed text-ink/85">Presencia el escrutinio, verifica los procedimientos, observa el llenado de actas y la transmisión de resultados, registra incidencias e informa oportunamente al delegado.</p>
        </div>
        <p class="sm:col-span-3 text-[12px] text-ink/80 border-t border-line pt-3"><b>Reserva:</b> los delegados, suplentes y observadores actuarán con absoluta reserva respecto de la información, documentación y orientaciones recibidas, utilizándolas exclusivamente para el cumplimiento de sus funciones.</p>
      </div>
    </details>

    <details class="card acc">
      <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Cronograma de trabajo</summary>
      <div class="px-4 pb-4 overflow-x-auto">
        <table class="w-full text-[12.5px]">
          <tbody>
            <tr v-for="c in cronograma" :key="c.a" class="border-b border-line/70 last:border-0">
              <td class="py-2 pr-3 font-medium">{{ c.a }}</td>
              <td class="py-2 text-mut whitespace-nowrap text-right">{{ c.p }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </details>

    <p class="text-[11.5px] text-mut px-1">Aprobado por la Dirección Ejecutiva de la Secretaría Nacional Electoral, a unanimidad, el 11 de agosto de 2026 · <b>Dr. Henry Merán</b>, Secretario Nacional Electoral. Las situaciones no previstas serán resueltas por la SNE conforme a la legislación electoral vigente.</p>
  </section>
</template>
