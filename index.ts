import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return respond({ error: 'Method not allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anon || !service) return respond({ error: 'Server configuration is incomplete.' }, 500);
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return respond({ error: 'Authentication required.' }, 401);
  const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const { data: userData, error: authError } = await caller.auth.getUser();
  if (authError || !userData.user) return respond({ error: 'Invalid session.' }, 401);
  const { data: profile, error: profileError } = await caller.from('profiles').select('role,is_active').eq('id', userData.user.id).single();
  if (profileError || profile?.role !== 'admin' || !profile?.is_active) return respond({ error: 'Administrator access required.' }, 403);
  let body: { email?: string; full_name?: string; role?: string; department?: string; password?: string };
  try { body = await req.json(); } catch { return respond({ error: 'Invalid request body.' }, 400); }
  const email = String(body.email || '').trim().toLowerCase();
  const full_name = String(body.full_name || '').trim();
  const role = String(body.role || 'student');
  const department = String(body.department || '').trim();
  const password = String(body.password || '');
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !full_name) return respond({ error: 'Enter a valid email and full name.' }, 400);
  if (!['student', 'faculty', 'admin'].includes(role)) return respond({ error: 'Invalid role.' }, 400);
  if (password.length < 12) return respond({ error: 'Temporary password must be at least 12 characters.' }, 400);
  const admin = createClient(url, service, { auth: { persistSession: false } });
  const { data: created, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name } });
  if (createError || !created.user) return respond({ error: createError?.message || 'Unable to create account.' }, 400);
  const { error: updateError } = await admin.from('profiles').update({ full_name, email, role, department: department || null, is_active: true, updated_at: new Date().toISOString() }).eq('id', created.user.id);
  if (updateError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return respond({ error: `Profile creation failed: ${updateError.message}` }, 500);
  }
  await admin.from('audit_logs').insert({ actor_id: userData.user.id, action: 'created_account', entity_type: 'profile', entity_id: created.user.id, details: { email, role } });
  return respond({ user_id: created.user.id, email, role }, 201);
});
