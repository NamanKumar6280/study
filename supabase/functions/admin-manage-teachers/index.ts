import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const allowedOrigin = "https://namankumar6280.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function envJson(name: string): Record<string, string> {
  const raw = Deno.env.get(name);
  if (!raw) return {};
  try { return JSON.parse(raw); } catch { return {}; }
}

function normalizeTeacherLogin(value: unknown): string {
  return String(value ?? "")
    .trim()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9._-]/g, "")
    .replace(/[-_.]{2,}/g, "-")
    .replace(/^[-_.]+|[-_.]+$/g, "");
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  if (origin && origin !== allowedOrigin) return json({ error: "Origin not allowed." }, 403);
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const publishableKey =
      Deno.env.get("SUPABASE_ANON_KEY") ??
      envJson("SUPABASE_PUBLISHABLE_KEYS").default ??
      "";
    const secretKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      envJson("SUPABASE_SECRET_KEYS").default ??
      "";

    if (!url || !publishableKey || !secretKey) {
      console.error("Missing required Supabase Edge Function environment variables.");
      return json({ error: "Teacher management service is not configured. Contact the platform owner." }, 503);
    }

    const authorization = req.headers.get("Authorization") ?? "";
    if (!authorization.startsWith("Bearer ")) {
      return json({ error: "Please sign in again." }, 401);
    }

    // Verify the caller's actual Auth session with a user-scoped client.
    const userClient = createClient(url, publishableKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorization } },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return json({ error: "Your session is invalid or has expired. Sign in again." }, 401);

    // Only an active admin profile can reach privileged Auth Admin operations.
    const admin = createClient(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: caller, error: callerError } = await admin
      .from("profiles")
      .select("id, role, approval_status")
      .eq("id", authData.user.id)
      .maybeSingle();

    if (callerError) {
      console.error("Admin profile lookup failed:", callerError.message);
      return json({ error: "Unable to verify administrator access." }, 500);
    }
    if (!caller || caller.role !== "admin" || caller.approval_status !== "approved") {
      return json({ error: "Administrator access is required for this action." }, 403);
    }

    const body = await req.json();
    const action = String(body?.action ?? "");

    if (action === "create_teacher") {
      const fullName = String(body.full_name ?? "").trim().replace(/\s+/g, " ");
      const teacherLogin = normalizeTeacherLogin(body.teacher_login || fullName);
      const classOrTitle = String(body.class_or_title ?? "").trim().slice(0, 120);
      const password = String(body.password ?? "");

      if (fullName.length < 2 || fullName.length > 100) {
        return json({ error: "Enter a teacher name between 2 and 100 characters." }, 400);
      }
      if (teacherLogin.length < 3 || teacherLogin.length > 32 || !/^[a-z0-9][a-z0-9._-]*[a-z0-9]$/.test(teacherLogin)) {
        return json({ error: "Teacher login name must be 3–32 characters and use letters, numbers, dots, hyphens or underscores." }, 400);
      }
      if (password.length < 10 || password.length > 72) {
        return json({ error: "Use a temporary password between 10 and 72 characters." }, 400);
      }

      const { data: existing, error: existingError } = await admin
        .from("profiles")
        .select("id")
        .ilike("teacher_login", teacherLogin)
        .maybeSingle();
      if (existingError) throw existingError;
      if (existing) return json({ error: "That teacher login name is already in use. Choose another one." }, 409);

      // This internal identifier is never shown to the teacher and no email is sent.
      // Email confirmation is explicitly set to true so the teacher can sign in immediately.
      const internalEmail = `teacher-${teacherLogin}@swatiog.com`;
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email: internalEmail,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, account_type: "teacher" },
        app_metadata: { account_type: "teacher" },
      });
      if (createError || !created.user) {
        const message = createError?.message ?? "Supabase did not return the created teacher account.";
        if (/already|registered|exists/i.test(message)) {
          return json({ error: "That teacher login is already registered. Choose another login name." }, 409);
        }
        console.error("Teacher Auth creation failed:", message);
        return json({ error: "Could not create the teacher account. Check the login name and try again." }, 400);
      }

      const { data: teacher, error: profileError } = await admin
        .from("profiles")
        .update({
          full_name: fullName,
          teacher_login: teacherLogin,
          class_or_title: classOrTitle,
          role: "teacher",
          approval_status: "approved",
        })
        .eq("id", created.user.id)
        .select("id, full_name, teacher_login, class_or_title, role, approval_status")
        .single();

      if (profileError || !teacher) {
        await admin.auth.admin.deleteUser(created.user.id);
        console.error("Teacher profile setup failed:", profileError?.message);
        return json({ error: "The Auth account was rolled back because its teacher profile could not be created." }, 500);
      }

      const { error: auditError } = await admin.from("admin_activity").insert({
        actor_id: caller.id,
        action: "teacher_created",
        target_user_id: teacher.id,
        target_label: teacher.full_name,
        details: { teacher_login: teacher.teacher_login, class_or_title: teacher.class_or_title },
      });
      if (auditError) console.error("Audit write failed:", auditError.message);

      return json({
        success: true,
        teacher: {
          id: teacher.id,
          full_name: teacher.full_name,
          teacher_login: teacher.teacher_login,
          class_or_title: teacher.class_or_title,
          approval_status: teacher.approval_status,
        },
        temporary_password: password,
      }, 201);
    }

    if (action === "set_teacher_password") {
      const teacherId = String(body.teacher_id ?? "");
      const password = String(body.password ?? "");
      if (!/^[0-9a-f-]{36}$/i.test(teacherId)) return json({ error: "Invalid teacher account." }, 400);
      if (password.length < 10 || password.length > 72) return json({ error: "Use a password between 10 and 72 characters." }, 400);

      const { data: teacher, error: teacherError } = await admin
        .from("profiles").select("id, full_name, teacher_login, role")
        .eq("id", teacherId).maybeSingle();
      if (teacherError) throw teacherError;
      if (!teacher || teacher.role !== "teacher") return json({ error: "Teacher account not found." }, 404);

      const { error: updateError } = await admin.auth.admin.updateUserById(teacherId, { password });
      if (updateError) throw updateError;

      const { error: auditError } = await admin.from("admin_activity").insert({
        actor_id: caller.id,
        action: "teacher_password_reset",
        target_user_id: teacher.id,
        target_label: teacher.full_name,
        details: { teacher_login: teacher.teacher_login },
      });
      if (auditError) console.error("Audit write failed:", auditError.message);
      return json({ success: true, teacher_login: teacher.teacher_login, temporary_password: password });
    }

    if (action === "set_teacher_status") {
      const teacherId = String(body.teacher_id ?? "");
      const nextStatus = String(body.approval_status ?? "");
      if (!/^[0-9a-f-]{36}$/i.test(teacherId)) return json({ error: "Invalid teacher account." }, 400);
      if (!["approved", "rejected"].includes(nextStatus)) return json({ error: "Invalid account status." }, 400);

      const { data: teacher, error: teacherError } = await admin
        .from("profiles").select("id, full_name, teacher_login, role")
        .eq("id", teacherId).maybeSingle();
      if (teacherError) throw teacherError;
      if (!teacher || teacher.role !== "teacher") return json({ error: "Teacher account not found." }, 404);

      const { error: updateError } = await admin.from("profiles")
        .update({ approval_status: nextStatus })
        .eq("id", teacherId);
      if (updateError) throw updateError;

      const { error: auditError } = await admin.from("admin_activity").insert({
        actor_id: caller.id,
        action: nextStatus === "approved" ? "teacher_activated" : "teacher_suspended",
        target_user_id: teacher.id,
        target_label: teacher.full_name,
        details: { teacher_login: teacher.teacher_login, approval_status: nextStatus },
      });
      if (auditError) console.error("Audit write failed:", auditError.message);
      return json({ success: true, approval_status: nextStatus });
    }

    return json({ error: "Unsupported teacher-management action." }, 400);
  } catch (error) {
    console.error("admin-manage-teachers failed:", error instanceof Error ? error.message : "Unknown error");
    return json({ error: "The request could not be completed. Please try again." }, 500);
  }
});
