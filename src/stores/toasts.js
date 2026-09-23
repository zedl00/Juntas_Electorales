import { ref } from 'vue';

export const toasts = ref([]);
let tid = 0;

/** Muestra un aviso flotante: t('Mensaje', 'ok' | 'err' | 'info') */
export const t = (msg, tipo = 'info') => {
  const id = ++tid;
  toasts.value.push({ id, msg, tipo });
  setTimeout(() => { toasts.value = toasts.value.filter(x => x.id !== id); }, 4000);
};

/** Copiar al portapapeles con aviso */
export const copiar = async txt => {
  try { await navigator.clipboard.writeText(txt); t('Copiado al portapapeles', 'ok'); }
  catch (e) {
    const ta = document.createElement('textarea');
    ta.value = txt; document.body.appendChild(ta); ta.select();
    document.execCommand('copy'); ta.remove(); t('Copiado', 'ok');
  }
};
