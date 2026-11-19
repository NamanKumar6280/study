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
