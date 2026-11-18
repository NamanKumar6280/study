# STUDY — Exam workspace

A dark, responsive assessment portal: teachers publish PDF question papers and students submit photos of handwritten answer sheets.

## Live app

- [Student portal](https://namankumar6280.github.io/study/)
- [Teacher portal](https://namankumar6280.github.io/study/)

Both roles sign in through the same secure login screen. The role is assigned in the database, never through a URL parameter.

## Current workflow

### Students
- Register and sign in using email and password.
- View published question papers and open their private PDF links.
- Upload 1–10 answer-sheet images per paper (JPG, PNG or WEBP).
- View their own submission history and profile.

### Teachers
- Teacher accounts must be explicitly approved by an administrator.
- Upload and publish PDF question papers with subject, instructions and optional deadline.
- View submissions for papers they own and open submitted answer-sheet images.

### Accounts and privacy
- Student, teacher and administrator roles are database-controlled.
- New signups receive student access only.
- Teacher approval and role changes are protected by database triggers and row-level security.
- Question PDFs and answer-sheet images live in private storage buckets and are opened with short-lived signed URLs.
- Users can edit their profile name and class/designation, but cannot edit their own role.

## Required one-time backend setup

The GitHub Pages site is the front end. Real authentication, role enforcement and shared file storage require a Supabase project.

1. Create a Supabase project.
2. Open **SQL Editor** and run the complete script in [supabase/setup.sql](supabase/setup.sql).
3. In **Authentication → URL Configuration**, add:
   - Site URL: `https://namankumar6280.github.io`
   - Redirect URL: `https://namankumar6280.github.io/study/**`
4. In **Project Settings → API**, copy the Project URL and the public anon/publishable key.
5. Edit [site/config.js](site/config.js) and replace the two placeholders:
   - `YOUR_SUPABASE_PROJECT_URL`
   - `YOUR_SUPABASE_ANON_PUBLIC_KEY`
6. Commit the change. GitHub Actions will publish the updated site.

Only the public anon/publishable key belongs in `site/config.js`. **Never put a Supabase service-role key, database password, or other secret in GitHub Pages/browser code.**

## Make your account the administrator

After you register your own account and confirm your email, run this in Supabase SQL Editor, replacing the email:

```sql
update public.profiles
set role = 'admin', approval_status = 'approved'
where id = (select id from auth.users where email = 'YOUR_ADMIN_EMAIL');
```

To authorize a teacher after verifying their identity:

```sql
update public.profiles
set role = 'teacher', approval_status = 'approved'
where id = (select id from auth.users where email = 'TEACHER_EMAIL');
```

To revoke teacher access:

```sql
update public.profiles
set role = 'student', approval_status = 'approved'
where id = (select id from auth.users where email = 'TEACHER_EMAIL');
```

## Repository and deployment

- App: `site/index.html`
- Public Supabase config placeholder: `site/config.js`
- Database, RLS and private storage setup: `supabase/setup.sql`
- GitHub Pages workflow: `.github/workflows/deploy.yml`

GitHub Pages deploys the `site` directory on pushes to `main`.
