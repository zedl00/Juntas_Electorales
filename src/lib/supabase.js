import { createClient } from '@supabase/supabase-js';

const URL  = import.meta.env.VITE_SUPABASE_URL;
const ANON = import.meta.env.VITE_SUPABASE_ANON_KEY;
if (!URL || !ANON) throw new Error('Faltan VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY en el archivo .env');

export const PORTAL_URL = import.meta.env.VITE_PORTAL_URL || './';
export const EMAIL_DOM  = import.meta.env.VITE_EMAIL_DOM || '@strategosfp.com';

/** Cliente principal (sesión del usuario conectado).
 *  db.schema = 'delegados': TODAS las consultas .from() y .rpc() del portal
 *  van al esquema propio «delegados» (requiere exponerlo en Supabase →
 *  Settings → API → Exposed schemas). */
export const sb = createClient(URL, ANON, { db: { schema: 'delegados' } });

/** Cliente auxiliar SIN persistencia: crea cuentas de terceros sin tocar la sesión del admin. */
export const sbAux = createClient(URL, ANON, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: 'sb-aux' }
});
