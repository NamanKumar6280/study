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
