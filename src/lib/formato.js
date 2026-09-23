/* src/lib/formato.js */
/* Utilidades de formato compartidas */

export const fmt = n => Number(n ?? 0).toLocaleString('es-DO');
export const soloDig = s => String(s ?? '').replace(/\D/g, '');
export const fmtCed = c => { const d = soloDig(c); return d.length === 11 ? d.slice(0,3)+'-'+d.slice(3,10)+'-'+d.slice(10) : (c || ''); };
export const edad = f => {
  if (!f) return '—';
  const d = new Date(f + 'T00:00:00'); if (isNaN(d)) return '—';
  const h = new Date(); let e = h.getFullYear() - d.getFullYear();
  const m = h.getMonth() - d.getMonth();
  if (m < 0 || (m === 0 && h.getDate() < d.getDate())) e--;
  return e;
};
export const fecha = d => d ? new Date(d).toLocaleDateString('es-DO', { day:'2-digit', month:'short', year:'numeric' }) : '';
export const fechaHora = d => d ? new Date(d).toLocaleDateString('es-DO', { day:'2-digit', month:'short' }) + ' ' + new Date(d).toLocaleTimeString('es-DO', { hour:'2-digit', minute:'2-digit' }) : '';
export const hoyLarga = () => new Date().toLocaleDateString('es-DO', { day:'numeric', month:'long', year:'numeric' });
export const genPin = () => String(Math.floor(100000 + Math.random() * 900000));

/** Teléfono RD listo para wa.me: 10 dígitos → antepone el 1. */
export const soloTel = t => { const d = soloDig(t || ''); return d.length === 10 ? '1' + d : d; };

/** Enlace de WhatsApp con mensaje precargado. */
export const waLink = (tel, msg) => {
  const d = soloTel(tel);
  return 'https://wa.me/' + (d.length >= 11 ? d : '') + '?text=' + encodeURIComponent(msg);
};

/**
 * Verifica una cédula dominicana: 11 dígitos y dígito verificador
 * calculado por módulo 10 con pesos alternos 1-2 (algoritmo de Luhn).
 */
export const cedulaValida = (ced) => {
  const d = soloDig(ced || '');
  if (d.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(d)) return false;          // 00000000000, 11111111111…
  let suma = 0;
  for (let i = 0; i < 10; i++) {
    let p = Number(d[i]) * ((i % 2 === 0) ? 1 : 2);
    if (p > 9) p -= 9;
    suma += p;
  }
  return ((10 - (suma % 10)) % 10) === Number(d[10]);
};

/** Motivo por el que una cédula no es válida, para mostrarlo al usuario. */
export const cedulaError = (ced) => {
  const d = soloDig(ced || '');
  if (!d) return 'Escribe la cédula.';
  if (d.length < 11) return `Faltan dígitos: la cédula tiene 11 y escribiste ${d.length}.`;
  if (d.length > 11) return `Sobran dígitos: la cédula tiene 11 y escribiste ${d.length}.`;
  if (!cedulaValida(d)) return 'El número no corresponde a una cédula válida. Verifica los dígitos.';
  return '';
};
