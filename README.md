# STUDY — Student and Teacher Exam Portals

## Separate websites
- Student portal: https://namankumar6280.github.io/study/
- Teacher portal: https://namankumar6280.github.io/study/teacher/

The student site contains student features only. Teacher sign-in and tools are on the separate teacher URL.

## Registration-number login
Users enter a registration number and password; no email address is requested. The app maps each registration number to an internal synthetic Supabase Auth email. This is not shown to users. Disable email confirmation in Supabase Authentication settings because these accounts do not use real email addresses. Email-based password recovery will not work; use an administrator-assisted reset process.

Registration numbers must be 3–32 characters using letters, numbers, underscore or hyphen. New accounts are students by default. Teacher access must be granted by an administrator.

## Supabase setup
1. Create a Supabase project.
2. Run [supabase/setup.sql](supabase/setup.sql) in SQL Editor. It adds the registration number field and unique index to an existing STUDY database too.
3. Disable email confirmation in Authentication settings.
4. Add Site URL `https://namankumar6280.github.io` and Redirect URL `https://namankumar6280.github.io/study/**`.
5. Add the Project URL and public anon/publishable key to [site/config.js](site/config.js). Both portals use this config.
6. Commit; GitHub Actions deploys both sites.

Never put a service-role key or database password in browser code.

## Administrator and teacher approval
After creating the intended account, run SQL as the project owner:

```sql
update public.profiles set role='admin', approval_status='approved'
where registration_number='ADMIN_REGISTRATION_NUMBER';

update public.profiles set role='teacher', approval_status='approved'
where registration_number='TEACHER_REGISTRATION_NUMBER';
```

## Features
- Students: browse published PDF papers, open private PDFs, upload 1–10 answer-sheet images, view submission history and edit profile.
- Teachers: publish PDFs with subject/instructions/deadline, view and open student submissions.
- Private storage buckets, short-lived signed URLs and database row-level security.

## Repository layout
- `site/index.html`: student portal
- `site/teacher/index.html`: teacher portal
- `site/config.js`: shared public Supabase configuration
- `supabase/setup.sql`: database and storage setup
