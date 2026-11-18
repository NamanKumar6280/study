-- STUDY: secure database and private file storage setup
-- Run this entire script in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
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

create index if not exists papers_teacher_idx on public.papers(teacher_id);
create index if not exists submissions_paper_idx on public.submissions(paper_id);
create index if not exists submissions_student_idx on public.submissions(student_id);

create or replace function public.handle_new_study_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role, approval_status)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), 'student', 'approved')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_study on auth.users;
create trigger on_auth_user_created_study after insert on auth.users
for each row execute procedure public.handle_new_study_user();

-- Prevent users from changing their own role or approval state.
create or replace function public.study_is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'); $$;

create or replace function public.study_can_publish()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and (role = 'admin' or (role = 'teacher' and approval_status = 'approved'))); $$;

create or replace function public.protect_study_role()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if (new.role is distinct from old.role or new.approval_status is distinct from old.approval_status)
     and auth.uid() is not null
     and not public.study_is_admin() then
    raise exception 'Only a platform administrator can change account roles or approval status';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_study_role_trigger on public.profiles;
create trigger protect_study_role_trigger before update on public.profiles
for each row execute procedure public.protect_study_role();

alter table public.profiles enable row level security;
alter table public.papers enable row level security;
alter table public.submissions enable row level security;

drop policy if exists "profile read self" on public.profiles;
create policy "profile read self" on public.profiles for select to authenticated
using (id = auth.uid() or public.study_is_admin());
drop policy if exists "profile update self" on public.profiles;
create policy "profile update self" on public.profiles for update to authenticated
using (id = auth.uid() or public.study_is_admin())
with check (id = auth.uid() or public.study_is_admin());

drop policy if exists "papers visible to signed in users" on public.papers;
create policy "papers visible to signed in users" on public.papers for select to authenticated using (true);
drop policy if exists "approved teachers publish papers" on public.papers;
create policy "approved teachers publish papers" on public.papers for insert to authenticated
with check (teacher_id = auth.uid() and public.study_can_publish());
drop policy if exists "paper owner or admin updates" on public.papers;
create policy "paper owner or admin updates" on public.papers for update to authenticated
using (teacher_id = auth.uid() or public.study_is_admin())
with check (teacher_id = auth.uid() or public.study_is_admin());
drop policy if exists "paper owner or admin deletes" on public.papers;
create policy "paper owner or admin deletes" on public.papers for delete to authenticated
using (teacher_id = auth.uid() or public.study_is_admin());

drop policy if exists "students and paper teachers read submissions" on public.submissions;
create policy "students and paper teachers read submissions" on public.submissions for select to authenticated
using (student_id = auth.uid() or exists (select 1 from public.papers p where p.id = paper_id and p.teacher_id = auth.uid()) or public.study_is_admin());
drop policy if exists "students submit their own work" on public.submissions;
create policy "students submit their own work" on public.submissions for insert to authenticated
with check (student_id = auth.uid() and exists (select 1 from public.profiles me where me.id = auth.uid() and me.role = 'student') and exists (select 1 from public.papers p where p.id = paper_id));
drop policy if exists "paper teacher reviews submissions" on public.submissions;
create policy "paper teacher reviews submissions" on public.submissions for update to authenticated
using (exists (select 1 from public.papers p where p.id = paper_id and p.teacher_id = auth.uid()) or public.study_is_admin())
with check (exists (select 1 from public.papers p where p.id = paper_id and p.teacher_id = auth.uid()) or public.study_is_admin());

-- Private buckets. Files are served through short-lived signed URLs after RLS checks.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('paper-pdfs','paper-pdfs',false,20971520,array['application/pdf'])
on conflict (id) do update set public=false, file_size_limit=20971520, allowed_mime_types=array['application/pdf'];
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('answer-sheets','answer-sheets',false,8388608,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false, file_size_limit=8388608, allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "signed in users read published paper files" on storage.objects;
create policy "signed in users read published paper files" on storage.objects for select to authenticated
using (bucket_id = 'paper-pdfs' and exists (select 1 from public.papers p where p.pdf_path = name));
drop policy if exists "approved teachers upload paper files" on storage.objects;
create policy "approved teachers upload paper files" on storage.objects for insert to authenticated
with check (bucket_id = 'paper-pdfs' and (storage.foldername(name))[1] = auth.uid()::text and public.study_can_publish());
drop policy if exists "paper owner deletes paper files" on storage.objects;
create policy "paper owner deletes paper files" on storage.objects for delete to authenticated
using (bucket_id = 'paper-pdfs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "student or assigned teacher reads answer images" on storage.objects;
create policy "student or assigned teacher reads answer images" on storage.objects for select to authenticated
using (bucket_id = 'answer-sheets' and (
  (storage.foldername(name))[1] = auth.uid()::text
  or exists (select 1 from public.submissions s join public.papers p on p.id=s.paper_id where p.teacher_id=auth.uid() and name = any(s.image_paths))
  or exists (select 1 from public.profiles me where me.id=auth.uid() and me.role='admin')
));
drop policy if exists "students upload own answer images" on storage.objects;
create policy "students upload own answer images" on storage.objects for insert to authenticated
with check (bucket_id = 'answer-sheets' and (storage.foldername(name))[1] = auth.uid()::text and exists (select 1 from public.profiles p where p.id=auth.uid() and p.role='student'));

-- ADMIN SETUP (run manually after creating your own account):
-- update public.profiles set role='admin', approval_status='approved'
-- where id = (select id from auth.users where email='YOUR_ADMIN_EMAIL');
-- Approve a teacher after verifying their identity:
-- update public.profiles set role='teacher', approval_status='approved'
-- where id = (select id from auth.users where email='TEACHER_EMAIL');
