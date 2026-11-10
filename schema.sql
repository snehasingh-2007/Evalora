-- Evalora database schema (Supabase / PostgreSQL)
-- Run this in Supabase SQL Editor. No demo rows or seed data are created.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null unique,
  role text not null default 'student' check (role in ('student','faculty','admin')),
  department text,
  student_number text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  department text not null default '',
  faculty_id uuid references public.profiles(id) on delete set null,
  term text not null default '',
  description text not null default '',
  is_published boolean not null default false,
  feedback_open boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), unique(course_id,student_id)
);
create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete restrict,
  student_id uuid not null references public.profiles(id) on delete restrict,
  teaching_quality integer not null check (teaching_quality between 1 and 5),
  course_content integer not null check (course_content between 1 and 5),
  engagement integer not null check (engagement between 1 and 5),
  assessment integer not null check (assessment between 1 and 5),
  comments text not null default '',
  is_anonymous boolean not null default true,
  status text not null default 'submitted' check (status in ('submitted','reviewed','archived')),
  created_at timestamptz not null default now(), unique(course_id,student_id)
);
create table if not exists public.portal_settings (
  id boolean primary key default true check (id = true),
  institution_name text not null default 'Your Institution',
  portal_title text not null default 'Faculty Feedback & Course Evaluation',
  welcome_message text not null default 'Your voice helps improve learning.',
  feedback_guidelines text not null default 'Please keep feedback constructive, respectful, and specific.',
  allow_anonymous boolean not null default true,
  maintenance_mode boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null default 'all' check (audience in ('all','student','faculty','admin')),
  is_published boolean not null default false,
  publish_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_role() returns text language sql stable security definer set search_path=public as $$
  select role from public.profiles where id = auth.uid() and is_active = true limit 1;
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(public.current_role()='admin',false); $$;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id, full_name, email, role)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email, 'student')
  on conflict(id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.enrollments enable row level security;
alter table public.feedback enable row level security;
alter table public.portal_settings enable row level security;
alter table public.announcements enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists "profiles read self or admin" on public.profiles;
create policy "profiles read self or admin" on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
drop policy if exists "profiles admin manage" on public.profiles;
create policy "profiles admin manage" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "courses visible when published or admin" on public.courses;
create policy "courses visible when published or admin" on public.courses for select to authenticated using (is_published or public.is_admin() or faculty_id=auth.uid());
drop policy if exists "courses admin manage" on public.courses;
create policy "courses admin manage" on public.courses for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "enrollments student or admin read" on public.enrollments;
create policy "enrollments student or admin read" on public.enrollments for select to authenticated using (student_id=auth.uid() or public.is_admin());
drop policy if exists "enrollments admin manage" on public.enrollments;
create policy "enrollments admin manage" on public.enrollments for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "feedback student read own admin read all" on public.feedback;
create policy "feedback student read own admin read all" on public.feedback for select to authenticated using (student_id=auth.uid() or public.is_admin() or public.current_role()='faculty' and exists(select 1 from public.courses c where c.id=course_id and c.faculty_id=auth.uid()));
drop policy if exists "students submit feedback for enrolled course" on public.feedback;
create policy "students submit feedback for enrolled course" on public.feedback for insert to authenticated with check (student_id=auth.uid() and public.current_role()='student' and exists(select 1 from public.courses c join public.enrollments e on e.course_id=c.id where c.id=course_id and e.student_id=auth.uid() and c.feedback_open=true));
drop policy if exists "feedback admin update" on public.feedback;
create policy "feedback admin update" on public.feedback for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "settings read authenticated" on public.portal_settings;
create policy "settings read authenticated" on public.portal_settings for select to authenticated using (true);
drop policy if exists "settings admin manage" on public.portal_settings;
create policy "settings admin manage" on public.portal_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "published announcements read" on public.announcements;
create policy "published announcements read" on public.announcements for select to authenticated using (is_published or public.is_admin());
drop policy if exists "announcements admin manage" on public.announcements;
create policy "announcements admin manage" on public.announcements for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "audit admin read" on public.audit_logs;
create policy "audit admin read" on public.audit_logs for select to authenticated using (public.is_admin());
drop policy if exists "audit authenticated insert own" on public.audit_logs;
create policy "audit authenticated insert own" on public.audit_logs for insert to authenticated with check (actor_id=auth.uid());

-- Create the initial settings row only; it contains configuration, not fake student/course data.
insert into public.portal_settings(id) values(true) on conflict(id) do nothing;
