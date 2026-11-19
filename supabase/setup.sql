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
  if (new.role is distinct from old.role or new.approval_status is distinct from old.approval_status or new.registration_number is distinct from old.registration_number)
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
-- where registration_number = 'YOUR_ADMIN_REGISTRATION_NUMBER';
-- Approve a teacher after verifying their identity:
-- update public.profiles set role='teacher', approval_status='approved'
-- where registration_number = 'TEACHER_REGISTRATION_NUMBER';


-- Apply the admin, teacher login, grading and audit-log additions for fresh setups.
-- STUDY admin portal, managed teacher accounts, teacher login names and marking.
-- Safe to run on the existing STUDY database; all additions are idempotent.

create schema if not exists private;

alter table public.profiles
  add column if not exists teacher_login text;

create unique index if not exists profiles_teacher_login_lower_unique
  on public.profiles (lower(teacher_login))
  where teacher_login is not null;

alter table public.submissions
  add column if not exists marks_awarded numeric(8,2),
  add column if not exists max_marks numeric(8,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'submissions_marks_nonnegative' and conrelid = 'public.submissions'::regclass) then
    alter table public.submissions add constraint submissions_marks_nonnegative
      check ((marks_awarded is null or marks_awarded >= 0) and (max_marks is null or max_marks > 0));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'submissions_marks_within_max' and conrelid = 'public.submissions'::regclass) then
    alter table public.submissions add constraint submissions_marks_within_max
      check (marks_awarded is null or max_marks is null or marks_awarded <= max_marks);
  end if;
end $$;

create table if not exists public.admin_activity (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_user_id uuid references auth.users(id) on delete set null,
  target_label text not null default '',
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_activity_created_at_idx on public.admin_activity (created_at desc);
create index if not exists admin_activity_actor_idx on public.admin_activity (actor_id);
create index if not exists admin_activity_target_idx on public.admin_activity (target_user_id);
alter table public.admin_activity enable row level security;
revoke all on public.admin_activity from anon, authenticated;
grant select on public.admin_activity to authenticated;
grant all on public.admin_activity to service_role;

create or replace function private.study_is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin' and approval_status = 'approved'
  );
$$;

create or replace function private.study_can_publish()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and (role = 'admin' or (role = 'teacher' and approval_status = 'approved'))
  );
$$;

revoke all on function private.study_is_admin() from public, anon;
revoke all on function private.study_can_publish() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.study_is_admin() to authenticated;
grant execute on function private.study_can_publish() to authenticated;

create or replace function public.protect_study_role()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if (
       new.role is distinct from old.role
       or new.approval_status is distinct from old.approval_status
       or new.registration_number is distinct from old.registration_number
       or new.teacher_login is distinct from old.teacher_login
     )
     and coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and (select auth.uid()) is not null
     and not private.study_is_admin() then
    raise exception 'Only a platform administrator can change account roles, approval status or teacher login names';
  end if;
  return new;
end;
$$;
revoke all on function public.protect_study_role() from public, anon, authenticated;

drop policy if exists "profile read self" on public.profiles;
create policy "profile read self" on public.profiles for select to authenticated
using (
  id = (select auth.uid())
  or (select private.study_is_admin())
  or exists (
    select 1 from public.submissions s
    join public.papers p on p.id = s.paper_id
    where s.student_id = profiles.id and p.teacher_id = (select auth.uid())
  )
);
drop policy if exists "profile update self" on public.profiles;
create policy "profile update self" on public.profiles for update to authenticated
using (id = (select auth.uid()) or (select private.study_is_admin()))
with check (id = (select auth.uid()) or (select private.study_is_admin()));

drop policy if exists "approved teachers publish papers" on public.papers;
create policy "approved teachers publish papers" on public.papers for insert to authenticated
with check (teacher_id = (select auth.uid()) and (select private.study_can_publish()));
drop policy if exists "paper owner or admin updates" on public.papers;
create policy "paper owner or admin updates" on public.papers for update to authenticated
using (teacher_id = (select auth.uid()) or (select private.study_is_admin()))
with check (teacher_id = (select auth.uid()) or (select private.study_is_admin()));
drop policy if exists "paper owner or admin deletes" on public.papers;
create policy "paper owner or admin deletes" on public.papers for delete to authenticated
using (teacher_id = (select auth.uid()) or (select private.study_is_admin()));

drop policy if exists "students and paper teachers read submissions" on public.submissions;
create policy "students and paper teachers read submissions" on public.submissions for select to authenticated
using (
  student_id = (select auth.uid())
  or exists (select 1 from public.papers p where p.id = paper_id and p.teacher_id = (select auth.uid()))
  or (select private.study_is_admin())
);
drop policy if exists "paper teacher reviews submissions" on public.submissions;
create policy "paper teacher reviews submissions" on public.submissions for update to authenticated
using (
  exists (select 1 from public.papers p where p.id = paper_id and p.teacher_id = (select auth.uid()))
  or (select private.study_is_admin())
)
with check (
  exists (select 1 from public.papers p where p.id = paper_id and p.teacher_id = (select auth.uid()))
  or (select private.study_is_admin())
);

drop policy if exists "approved teachers upload paper files" on storage.objects;
create policy "approved teachers upload paper files" on storage.objects for insert to authenticated
with check (
  bucket_id = 'paper-pdfs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (select private.study_can_publish())
);

drop policy if exists "student or assigned teacher reads answer images" on storage.objects;
create policy "student or assigned teacher reads answer images" on storage.objects for select to authenticated
using (
  bucket_id = 'answer-sheets'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1 from public.submissions s join public.papers p on p.id = s.paper_id
      where p.teacher_id = (select auth.uid()) and name = any(s.image_paths)
    )
    or (select private.study_is_admin())
  )
);

drop policy if exists "admins read activity" on public.admin_activity;
create policy "admins read activity" on public.admin_activity for select to authenticated
using ((select private.study_is_admin()));

-- The profile, paper and storage policies above no longer depend on the old
-- public helper functions. Keep authorization helpers in the private schema.
drop function if exists public.study_is_admin();
drop function if exists public.study_can_publish();


-- STUDY role-isolation hardening.
-- Only a trusted database owner using Supabase SQL Editor may grant/change roles.
-- Authenticated application sessions (including admins) cannot promote accounts.
-- The server-side service_role is allowed to provision teacher profiles only.

create or replace function private.study_is_active_teacher()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role = 'teacher'
      and approval_status = 'approved'
  );
$$;
revoke all on function private.study_is_active_teacher() from public, anon;
grant execute on function private.study_is_active_teacher() to authenticated;

create or replace function private.study_can_publish()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and approval_status = 'approved'
      and role in ('admin', 'teacher')
  );
$$;
revoke all on function private.study_can_publish() from public, anon;
grant execute on function private.study_can_publish() to authenticated;

create or replace function public.protect_study_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (
       new.role is distinct from old.role
       or new.approval_status is distinct from old.approval_status
       or new.registration_number is distinct from old.registration_number
       or new.teacher_login is distinct from old.teacher_login
     )
     and coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and (select auth.uid()) is not null then
    raise exception 'Role, approval and login identity changes are restricted to the Supabase project owner. Use Supabase SQL Editor.';
  end if;
  return new;
end;
$$;
revoke all on function public.protect_study_role() from public, anon, authenticated;

-- A teacher must be approved and assigned to the paper to see student identity.
drop policy if exists "profile read self" on public.profiles;
create policy "profile read self" on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or (select private.study_is_admin())
  or (
    (select private.study_is_active_teacher())
    and exists (
      select 1
      from public.submissions s
      join public.papers p on p.id = s.paper_id
      where s.student_id = profiles.id
        and p.teacher_id = (select auth.uid())
    )
  )
);

-- Only active teachers may change their own papers; admins may also manage papers.
drop policy if exists "paper owner or admin updates" on public.papers;
create policy "paper owner or admin updates" on public.papers
for update to authenticated
using (
  (teacher_id = (select auth.uid()) and (select private.study_is_active_teacher()))
  or (select private.study_is_admin())
)
with check (
  (teacher_id = (select auth.uid()) and (select private.study_is_active_teacher()))
  or (select private.study_is_admin())
);

drop policy if exists "paper owner or admin deletes" on public.papers;
create policy "paper owner or admin deletes" on public.papers
for delete to authenticated
using (
  (teacher_id = (select auth.uid()) and (select private.study_is_active_teacher()))
  or (select private.study_is_admin())
);

-- Suspended teachers cannot read or grade submissions, even with an old session.
drop policy if exists "students and paper teachers read submissions" on public.submissions;
create policy "students and paper teachers read submissions" on public.submissions
for select to authenticated
using (
  student_id = (select auth.uid())
  or (
    (select private.study_is_active_teacher())
    and exists (
      select 1 from public.papers p
      where p.id = paper_id and p.teacher_id = (select auth.uid())
    )
  )
  or (select private.study_is_admin())
);

drop policy if exists "paper teacher reviews submissions" on public.submissions;
create policy "paper teacher reviews submissions" on public.submissions
for update to authenticated
using (
  (
    (select private.study_is_active_teacher())
    and exists (
      select 1 from public.papers p
      where p.id = paper_id and p.teacher_id = (select auth.uid())
    )
  )
  or (select private.study_is_admin())
)
with check (
  (
    (select private.study_is_active_teacher())
    and exists (
      select 1 from public.papers p
      where p.id = paper_id and p.teacher_id = (select auth.uid())
    )
  )
  or (select private.study_is_admin())
);

-- Students must have an active student profile to submit answer sheets.
drop policy if exists "students submit their own work" on public.submissions;
create policy "students submit their own work" on public.submissions
for insert to authenticated
with check (
  student_id = (select auth.uid())
  and exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid())
      and me.role = 'student'
      and me.approval_status = 'approved'
  )
  and exists (select 1 from public.papers p where p.id = paper_id)
);

-- An already-open teacher session cannot bypass a later suspension to view answer images.
drop policy if exists "student or assigned teacher reads answer images" on storage.objects;
create policy "student or assigned teacher reads answer images" on storage.objects
for select to authenticated
using (
  bucket_id = 'answer-sheets'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or (
      (select private.study_is_active_teacher())
      and exists (
        select 1 from public.submissions s
        join public.papers p on p.id = s.paper_id
        where p.teacher_id = (select auth.uid())
          and name = any(s.image_paths)
      )
    )
    or (select private.study_is_admin())
  )
);

drop policy if exists "approved teachers upload paper files" on storage.objects;
create policy "approved teachers upload paper files" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'paper-pdfs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (select private.study_can_publish())
);


-- STUDY richer exam metadata, scheduling, publishing states and student-safe visibility.
-- Existing papers remain published and immediately available through defaults.

alter table public.papers
  add column if not exists target_class text not null default '',
  add column if not exists max_marks numeric(8,2),
  add column if not exists duration_minutes integer,
  add column if not exists available_from timestamptz,
  add column if not exists status text not null default 'published',
  add column if not exists allow_late_submissions boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='papers_max_marks_positive'
      and conrelid='public.papers'::regclass
  ) then
    alter table public.papers
      add constraint papers_max_marks_positive
      check (max_marks is null or max_marks > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='papers_duration_range'
      and conrelid='public.papers'::regclass
  ) then
    alter table public.papers
      add constraint papers_duration_range
      check (duration_minutes is null or duration_minutes between 1 and 600);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='papers_status_valid'
      and conrelid='public.papers'::regclass
  ) then
    alter table public.papers
      add constraint papers_status_valid
      check (status in ('draft','published','archived'));
  end if;
end $$;

create index if not exists papers_status_available_idx
  on public.papers (status, available_from, created_at desc);
create index if not exists papers_subject_idx
  on public.papers (subject);
create index if not exists papers_target_class_idx
  on public.papers (target_class);

-- Students can only discover published papers after their scheduled release.
-- Owners can see their own drafts/archives; admins can see every paper.
drop policy if exists "papers visible to signed in users" on public.papers;
create policy "papers visible to signed in users"
on public.papers for select to authenticated
using (
  (
    status = 'published'
    and (available_from is null or available_from <= now())
  )
  or (
    teacher_id = (select auth.uid())
    and (select private.study_is_active_teacher())
  )
  or (select private.study_is_admin())
);

-- Drafts can be created by active teachers too. Existing insert policy already
-- calls private.study_can_publish(), which permits approved teachers/admins.
-- Publishing, archiving and editing are covered by the active-owner update policy.

-- Submission rows are accepted only when the exam is published and released.
-- Overdue submissions are allowed only when the teacher enabled that option.
drop policy if exists "students submit their own work" on public.submissions;
create policy "students submit their own work"
on public.submissions for insert to authenticated
with check (
  student_id = (select auth.uid())
  and exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid())
      and me.role = 'student'
      and me.approval_status = 'approved'
  )
  and exists (
    select 1 from public.papers p
    where p.id = paper_id
      and p.status = 'published'
      and (p.available_from is null or p.available_from <= now())
      and (p.due_at is null or p.due_at >= now() or p.allow_late_submissions)
  )
);


-- STUDY productivity layer: announcements, read receipts, saved papers and student planner.
-- All records are protected by row-level security and scoped to the signed-in user/role.

create or replace function private.study_is_active_student()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role = 'student'
      and approval_status = 'approved'
  );
$$;
revoke all on function private.study_is_active_student() from public, anon;
grant execute on function private.study_is_active_student() to authenticated;

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 2 and 120),
  message text not null check (char_length(trim(message)) between 2 and 3000),
  audience text not null default 'all' check (audience in ('all','student','teacher')),
  target_class text,
  is_pinned boolean not null default false,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint announcements_expiry_after_start check (expires_at is null or expires_at > starts_at)
);
create index if not exists announcements_start_expiry_idx
  on public.announcements (starts_at, expires_at);
create index if not exists announcements_audience_idx
  on public.announcements (audience, target_class, is_pinned);

alter table public.announcements enable row level security;
grant select, insert, update, delete on public.announcements to authenticated;

drop policy if exists "users read active announcements for their audience" on public.announcements;
create policy "users read active announcements for their audience"
on public.announcements for select to authenticated
using (
  (select private.study_is_admin())
  or (
    starts_at <= now()
    and (expires_at is null or expires_at > now())
    and audience in (
      'all',
      (select p.role from public.profiles p where p.id = (select auth.uid()))
    )
    and (
      target_class is null
      or target_class = (select p.class_or_title from public.profiles p where p.id = (select auth.uid()))
    )
  )
);

drop policy if exists "admins create announcements" on public.announcements;
create policy "admins create announcements"
on public.announcements for insert to authenticated
with check (
  created_by = (select auth.uid())
  and (select private.study_is_admin())
);

drop policy if exists "admins update announcements" on public.announcements;
create policy "admins update announcements"
on public.announcements for update to authenticated
using ((select private.study_is_admin()))
with check (
  created_by = (select auth.uid())
  and (select private.study_is_admin())
);

drop policy if exists "admins delete announcements" on public.announcements;
create policy "admins delete announcements"
on public.announcements for delete to authenticated
using ((select private.study_is_admin()));

create table if not exists public.announcement_reads (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
create index if not exists announcement_reads_user_idx
  on public.announcement_reads (user_id, read_at desc);

alter table public.announcement_reads enable row level security;
grant select, insert, delete on public.announcement_reads to authenticated;

drop policy if exists "users read their own announcement receipts" on public.announcement_reads;
create policy "users read their own announcement receipts"
on public.announcement_reads for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "users mark visible announcements read" on public.announcement_reads;
create policy "users mark visible announcements read"
on public.announcement_reads for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.announcements a
    where a.id = announcement_id
  )
);

drop policy if exists "users remove their own announcement receipts" on public.announcement_reads;
create policy "users remove their own announcement receipts"
on public.announcement_reads for delete to authenticated
using (user_id = (select auth.uid()));

create table if not exists public.paper_bookmarks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  paper_id uuid not null references public.papers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, paper_id)
);
create index if not exists paper_bookmarks_paper_idx
  on public.paper_bookmarks (paper_id);

alter table public.paper_bookmarks enable row level security;
grant select, insert, delete on public.paper_bookmarks to authenticated;

drop policy if exists "students read their own bookmarks" on public.paper_bookmarks;
create policy "students read their own bookmarks"
on public.paper_bookmarks for select to authenticated
using (user_id = (select auth.uid()) and (select private.study_is_active_student()));

drop policy if exists "students save available papers" on public.paper_bookmarks;
create policy "students save available papers"
on public.paper_bookmarks for insert to authenticated
with check (
  user_id = (select auth.uid())
  and (select private.study_is_active_student())
  and exists (
    select 1 from public.papers p
    where p.id = paper_id
      and p.status = 'published'
      and (p.available_from is null or p.available_from <= now())
  )
);

drop policy if exists "students remove their own bookmarks" on public.paper_bookmarks;
create policy "students remove their own bookmarks"
on public.paper_bookmarks for delete to authenticated
using (user_id = (select auth.uid()) and (select private.study_is_active_student()));

create table if not exists public.study_tasks (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  paper_id uuid references public.papers(id) on delete set null,
  title text not null check (char_length(trim(title)) between 2 and 160),
  details text not null default '' check (char_length(details) <= 1000),
  due_at timestamptz,
  is_completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint study_tasks_completion_time check (
    (is_completed = false and completed_at is null)
    or (is_completed = true and completed_at is not null)
  )
);
create index if not exists study_tasks_student_due_idx
  on public.study_tasks (student_id, is_completed, due_at);

alter table public.study_tasks enable row level security;
grant select, insert, update, delete on public.study_tasks to authenticated;

drop policy if exists "students manage their own planner tasks" on public.study_tasks;
create policy "students manage their own planner tasks"
on public.study_tasks for all to authenticated
using (
  student_id = (select auth.uid())
  and (select private.study_is_active_student())
)
with check (
  student_id = (select auth.uid())
  and (select private.study_is_active_student())
);


-- Productivity table indexes and multi-admin announcement maintenance.
create index if not exists announcements_created_by_idx on public.announcements (created_by);
create index if not exists study_tasks_paper_idx on public.study_tasks (paper_id);

drop policy if exists "admins update announcements" on public.announcements;
create policy "admins update announcements"
on public.announcements for update to authenticated
using ((select private.study_is_admin()))
with check ((select private.study_is_admin()));
