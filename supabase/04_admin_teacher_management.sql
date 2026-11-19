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
alter table public.admin_activity enable row level security;
revoke all on public.admin_activity from anon, authenticated;
grant select on public.admin_activity to authenticated;

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
