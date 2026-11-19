# STUDY — Student, Teacher and Admin Portals

## Portals
- Student portal: https://namankumar6280.github.io/study/
- Teacher portal: https://namankumar6280.github.io/study/teacher/
- Admin portal: https://namankumar6280.github.io/study/admin/

Each portal has its own browser session and strict role gate. A student account cannot enter the teacher or admin portal; a teacher account cannot enter the student or admin portal; an admin account can enter only the admin portal.

## Authentication
- Students sign in with their registration number and password.
- Teachers sign in with the unique teacher login name assigned by an administrator and their password.
- Administrators sign in with their administrator registration number and password.
- There is no public teacher registration and no public admin registration.
- Student login uses the existing internal registration-number identity.
- Teacher logins use an internal Auth identifier ending in `@swatiog.com`; this address is never shown to teachers. The server-side admin function creates confirmed teacher accounts without sending confirmation email.

## Administrator provisioning — Supabase only
**Admin roles must be assigned manually in Supabase. There is intentionally no website feature or Edge Function that can create another admin.** Even a signed-in admin cannot promote an account through the browser/API; the database trigger blocks role, approval and login-identity changes from authenticated sessions.

To provision the first admin:
1. Register the trusted person's account through the Student portal so the Auth user and profile are created.
2. Open Supabase Dashboard → SQL Editor.
3. Run [supabase/05_manual_admin_provisioning.sql](supabase/05_manual_admin_provisioning.sql), replacing the placeholder with that person's registration number.
4. Confirm the returned row shows exactly the intended name and registration number with `role = admin` and `approval_status = approved`.
5. They can then sign in to the Admin portal using their existing registration number and password. That account is no longer a student account.

The first administrator on the current project is already provisioned manually in Supabase. Do not promote anyone you have not personally verified.

## Supabase setup
1. Create a Supabase project.
2. Run [supabase/setup.sql](supabase/setup.sql) in SQL Editor for a fresh setup. For an existing STUDY database, apply migrations `study_admin_teacher_management` and `study_strict_role_isolation` (and keep the corresponding SQL files in this repository).
3. Deploy the `admin-manage-teachers` Edge Function from [supabase/functions/admin-manage-teachers/index.ts](supabase/functions/admin-manage-teachers/index.ts). It uses the Auth Admin API server-side and verifies the caller is an active admin before taking action.
4. Disable email confirmation in Supabase Authentication settings because STUDY uses internal login identifiers rather than user-managed email addresses.
5. Set Site URL to `https://namankumar6280.github.io` and Redirect URL to `https://namankumar6280.github.io/study/**`.
6. Keep [site/config.js](site/config.js) limited to the project URL and publishable key. Never add a service-role or secret key to browser code.
7. Push to `main`; GitHub Actions deploys all portals.

## Admin features
- Create teacher accounts with a full name, unique sign-in name, designation and temporary password.
- Reset teacher passwords and suspend/reactivate teacher access.
- Browse student accounts, platform counts and an admin-only activity log.
- Teacher creation, password resets and access changes are recorded in the admin activity table.
- Admin creation/promotion is deliberately excluded from the website and the teacher-management Edge Function.

## Teacher features
- Publish PDF papers with a subject, description and optional deadline.
- See the names and registration numbers of students who submitted to their own papers.
- Open private answer-sheet images through short-lived signed URLs.
- Set submission status, award marks and leave remarks.

## Student features
- Browse published papers and open private PDFs.
- Upload 1–10 answer-sheet photos (JPG, PNG or WEBP; 8 MB each).
- Track submission status and view marks and teacher feedback.
- Manage profile details.

## Security model
- The profile trigger always creates public signups with `role = student`; it does not trust user-supplied role metadata.
- Student, teacher and admin portals require exact matching roles. Each portal uses a separate Auth session storage key, so sessions do not bleed between portals.
- Role, approval-status, registration-number and teacher-login changes are blocked for all authenticated browser sessions, including admins. Supabase project-owner/SQL Editor operations are required for role promotion. The trusted service-role Edge Function may set teacher-only fields when it provisions a teacher.
- Teacher provisioning and password changes run server-side. The function verifies the caller's Auth JWT and checks the caller's profile is an approved admin before invoking Auth Admin.
- RLS rechecks active teacher/admin status for protected reads and writes. Suspending a teacher blocks submission and answer-image access even when the teacher still has an old browser session.
- Private storage buckets, short-lived signed URLs and row-level security remain enabled.
- Keep all service-role/secret keys in server-side function environment variables. Never commit them or send them to a browser.
