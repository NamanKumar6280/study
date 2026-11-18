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
