# STUDY — Student, Teacher and Admin Portals

## Portals
- Student portal: https://namankumar6280.github.io/study/
- Teacher portal: https://namankumar6280.github.io/study/teacher/
- Admin portal: https://namankumar6280.github.io/study/admin/

The student site is for learners, the teacher site is for approved teachers, and the admin console manages teacher accounts and platform oversight.

## Authentication
- Students sign in with their registration number and password.
- Teachers sign in with the unique teacher name/login issued by an administrator and their password.
- Administrators sign in with their administrator registration number and password.
- There is no public teacher or admin registration.
- Student login continues to use the existing registration-number mapping. Teacher logins use a separate internal Auth identifier ending in `@swatiog.com`; this address is never shown to the teacher and the admin tool creates already-confirmed accounts without sending email.

## First administrator setup
A platform owner must promote one trusted account to admin once, using Supabase SQL Editor:

```sql
update public.profiles
set role = 'admin', approval_status = 'approved'
where registration_number = 'YOUR_ADMIN_REGISTRATION_NUMBER';
```

Then open the Admin portal and sign in using that account's existing registration number and password. Never promote an untrusted account.

## Supabase setup
1. Create a Supabase project.
2. Run [supabase/setup.sql](supabase/setup.sql) in SQL Editor for a fresh setup, or run the existing setup and then [supabase/04_admin_teacher_management.sql](supabase/04_admin_teacher_management.sql) for an existing STUDY database.
3. Deploy the `admin-manage-teachers` Edge Function (the project copy is in `supabase/functions/admin-manage-teachers/index.ts`). It uses Supabase's server-side Auth Admin API and the Edge Function's server-side service-role environment variable. Never put a service-role/secret key in browser code.
4. Disable email confirmation in Supabase Authentication settings because the portal uses internal login identifiers, not user-managed email addresses.
5. Set Site URL to `https://namankumar6280.github.io` and Redirect URL to `https://namankumar6280.github.io/study/**`.
6. Keep [site/config.js](site/config.js) set to the project's URL and publishable key only.
7. Push to `main`; GitHub Actions deploys all portals.

## Admin features
- Create teacher accounts with full name, unique teacher login name, designation and temporary password.
- Reset teacher passwords and suspend/reactivate teacher access.
- Browse the student directory, review platform counts and inspect administrator activity.
- Teacher account creation, password resets and access changes are recorded in an admin-only activity table.

## Teacher features
- Publish PDF papers with subject, description and optional deadline.
- See named students who submitted to the teacher's papers.
- Open answer-sheet images through short-lived signed URLs.
- Mark submissions as reviewed or returned, award marks and leave remarks.

## Student features
- Browse published papers and open private PDF papers.
- Upload 1–10 answer-sheet photos (JPG, PNG or WEBP; 8 MB each).
- Track submission status and view teacher marks and remarks.
- Manage profile details.

## Security
- Private storage buckets, short-lived signed URLs and row-level security remain enabled.
- Teacher account creation and password changes run in a server-side Edge Function. The caller is verified as an active admin before any Auth Admin action.
- Service-role/secret keys must stay in server-side function environment variables and must never be committed to Git or sent to the browser.
- The Admin portal is not self-bootstrapping: the first admin is provisioned once by a trusted project owner.
