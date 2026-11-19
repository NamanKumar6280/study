-- MANUALLY PROVISION AN ADMINISTRATOR
-- Run this ONLY in Supabase Dashboard > SQL Editor as the project owner.
-- First create the person's account through the STUDENT portal (or create/confirm
-- the Auth user yourself and ensure profiles.registration_number is set).
-- Then replace the registration number below with the trusted person's number.
-- Their profile role changes from student to admin; the person can no longer
-- enter the student or teacher portals with this account.

update public.profiles
set role = 'admin',
    approval_status = 'approved'
where registration_number = 'REPLACE_WITH_TRUSTED_ADMIN_REGISTRATION'
returning id, full_name, registration_number, role, approval_status;

-- Verify that exactly the intended trusted account was returned.
-- Never execute a broad UPDATE without a WHERE clause.
