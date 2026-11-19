-- Productivity table indexes and multi-admin announcement maintenance.
create index if not exists announcements_created_by_idx on public.announcements (created_by);
create index if not exists study_tasks_paper_idx on public.study_tasks (paper_id);

drop policy if exists "admins update announcements" on public.announcements;
create policy "admins update announcements"
on public.announcements for update to authenticated
using ((select private.study_is_admin()))
with check ((select private.study_is_admin()));
