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
