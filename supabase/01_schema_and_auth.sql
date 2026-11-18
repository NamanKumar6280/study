-- STUDY: secure database and private file storage setup
-- Run this entire script in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  registration_number text,
  class_or_title text not null default '',
  role text not null default 'student' check (role in ('student','teacher','admin')),
  approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.papers (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subject text not null,
  description text not null default '',
  due_at timestamptz,
  pdf_path text not null,
  teacher_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  image_paths text[] not null default '{}',
  status text not null default 'submitted' check (status in ('submitted','reviewed','returned')),
  remarks text not null default '',
  submitted_at timestamptz not null default now(),
  unique (paper_id, student_id)
);

alter table public.profiles add column if not exists registration_number text;
create unique index if not exists profiles_registration_number_unique on public.profiles (lower(registration_number)) where registration_number is not null;

create index if not exists papers_teacher_idx on public.papers(teacher_id);
create index if not exists submissions_paper_idx on public.submissions(paper_id);
create index if not exists submissions_student_idx on public.submissions(student_id);

create or replace function public.handle_new_study_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, registration_number, role, approval_status)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), nullif(trim(new.raw_user_meta_data->>'registration_number'), ''), 'student', 'approved')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_study on auth.users;
create trigger on_auth_user_created_study after insert on auth.users
for each row execute procedure public.handle_new_study_user();
