import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};


// ============================================================
// SHA-256 PRE-HASH
//
// Flutter sends the password exactly as typed.
// This transformation happens ONLY on the server.
//
// bcrypt receives the fixed-length SHA-256 representation,
// avoiding bcrypt's input-length limitation.
// ============================================================

async function preHashPassword(
  rawPassword: string,
): Promise<string> {

  const encoder = new TextEncoder();

  const digest = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(rawPassword),
  );

  const bytes = new Uint8Array(digest);

  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}


// ============================================================
// JSON RESPONSE
// ============================================================

function json(
  body: Record<string, unknown>,
  status = 200,
) {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: corsHeaders,
    },
  );
}


// ============================================================
// SUPABASE KEYS
//
// Supports current secret/publishable keys.
// Falls back to legacy variables if the project still exposes
// them.
// ============================================================

function getSecretKey(): string {

  const current =
    Deno.env.get("SUPABASE_SECRET_KEYS");

  if (current) {

    const parsed = JSON.parse(current);

    return parsed.default;
  }

  return Deno.env.get(
    "SUPABASE_SERVICE_ROLE_KEY",
  )!;
}


function getPublishableKey(): string {

  const current =
    Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");

  if (current) {

    const parsed = JSON.parse(current);

    return parsed.default;
  }

  return Deno.env.get(
    "SUPABASE_ANON_KEY",
  )!;
}


// ============================================================
// MAIN
// ============================================================

serve(async (req) => {

  if (req.method === "OPTIONS") {
    return new Response(
      "ok",
      { headers: corsHeaders },
    );
  }


  if (req.method !== "POST") {
    return json(
      {
        success: false,
        error: "Method not allowed",
      },
      405,
    );
  }


  try {

    const supabaseUrl =
      Deno.env.get("SUPABASE_URL");

    if (!supabaseUrl) {
      throw new Error(
        "SUPABASE_URL is not configured",
      );
    }


    const secretKey =
      getSecretKey();

    const publishableKey =
      getPublishableKey();


    // ========================================================
    // PRIVILEGED ADMIN CLIENT
    // ========================================================

    const admin = createClient(
      supabaseUrl,
      secretKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );


    // ========================================================
    // AUTH CLIENT
    //
    // This client performs the legitimate internal
    // signInWithPassword() against GoTrue.
    // ========================================================

    const authClient = createClient(
      supabaseUrl,
      publishableKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );


    const body = await req.json();

    const action =
      typeof body.action === "string"
        ? body.action
        : "";

    const username =
      typeof body.username === "string"
        ? body.username
        : "";

    const password =
      typeof body.password === "string"
        ? body.password
        : "";


    // Empty username/password are required for login/register,
    // but admin deleteUser uses the authenticated caller token
    // and therefore does not send username/password.
    //
    // Whitespace is NOT normalized.
    if (
      action !== "deleteUser" &&
      (
        username.length === 0 ||
        password.length === 0
      )
    ) {
      return json(
        {
          success: false,
          error:
            "Username and password required",
        },
        400,
      );
    }


    // ========================================================
    // IP + EXACT USERNAME RATE-LIMIT KEY
    // ========================================================

    const forwarded =
      req.headers.get("x-forwarded-for");

    const clientIp =
      forwarded
        ?.split(",")[0]
        ?.trim()
        || "unknown";

    const rateLimitKey =
      `rl_${clientIp}_${username}`;


    // ========================================================
    // LOGIN
    // ========================================================

    if (action === "login") {

      // ------------------------------------------------------
      // 1. Atomically reserve/check attempt
      // ------------------------------------------------------

      const {
        data: attempt,
        error: attemptError,
      } = await admin.rpc(
        "begin_auth_attempt",
        {
          p_identifier: rateLimitKey,
          p_max_attempts: 5,
          p_lockout_seconds: 300,
        },
      );


      if (attemptError) {
        console.error(
          "Rate-limit error:",
          attemptError.message,
        );

        return json(
          {
            success: false,
            error: "Authentication temporarily unavailable",
          },
          503,
        );
      }


      if (
        attempt?.[0] &&
        attempt[0].allowed === false
      ) {

        return json(
          {
            success: false,
            error:
              "Too many failed attempts. Please try again later.",
            retry_after:
              attempt[0].remaining_seconds,
          },
          429,
        );
      }


      // ------------------------------------------------------
      // 2. Exact username lookup
      // ------------------------------------------------------

      const {
        data: credential,
        error: credentialError,
      } = await admin
        .from("user_credentials")
        .select(
          "user_id,password_hash,internal_email,internal_auth_secret",
        )
        .eq("username", username)
        .maybeSingle();


      if (credentialError) {

        console.error(
          "Credential lookup error:",
          credentialError.message,
        );

        return json(
          {
            success: false,
            error:
              "Authentication temporarily unavailable",
          },
          503,
        );
      }


      // ------------------------------------------------------
      // 3. Server-side SHA-256 + bcrypt
      // ------------------------------------------------------

      const preHashed =
        await preHashPassword(password);


      let passwordValid = false;

      if (credential) {

        passwordValid =
          await bcrypt.compare(
            preHashed,
            credential.password_hash,
          );
      }


      // ------------------------------------------------------
      // 4. Invalid credentials
      // ------------------------------------------------------

      if (
        !credential ||
        !passwordValid
      ) {

        await admin.rpc(
          "finish_auth_attempt",
          {
            p_identifier: rateLimitKey,
            p_success: false,
            p_max_attempts: 5,
            p_lockout_seconds: 300,
          },
        );


        return json(
          {
            success: false,
            error:
              "Invalid username or password",
          },
          401,
        );
      }


      // ------------------------------------------------------
      // 5. Valid credentials
      // ------------------------------------------------------

      await admin.rpc(
        "finish_auth_attempt",
        {
          p_identifier: rateLimitKey,
          p_success: true,
        },
      );


      // ------------------------------------------------------
      // 6. Admin activation check
      // ------------------------------------------------------

      const {
        data: userProfile,
        error: profileError,
      } = await admin
        .from("users")
        .select("is_active,role")
        .eq("id", credential.user_id)
        .maybeSingle();


      if (profileError) {

        console.error(
          "Profile lookup error:",
          profileError.message,
        );

        return json(
          {
            success: false,
            error:
              "Authentication temporarily unavailable",
          },
          503,
        );
      }


      const role =
        String(
          userProfile?.role ?? "user",
        ).toLowerCase();


      const isActive =
        userProfile?.is_active === true;


      if (
        role !== "admin" &&
        !isActive
      ) {

        return json(
          {
            success: false,
            is_inactive: true,
            error:
              "Your account is awaiting administrator activation.",
          },
          403,
        );
      }


      // ------------------------------------------------------
      // 7. REAL SUPABASE AUTH SESSION
      // ------------------------------------------------------

      const {
        data: sessionData,
        error: sessionError,
      } = await authClient.auth
        .signInWithPassword({
          email:
            credential.internal_email,

          password:
            credential.internal_auth_secret,
        });


      if (
        sessionError ||
        !sessionData?.session
      ) {

        console.error(
          "Internal Auth session error:",
          sessionError?.message,
        );

        return json(
          {
            success: false,
            error:
              "Authentication temporarily unavailable",
          },
          500,
        );
      }


      // ------------------------------------------------------
      // 8. Return REAL Auth tokens
      // ------------------------------------------------------

      return json({
        success: true,

        access_token:
          sessionData.session.access_token,

        refresh_token:
          sessionData.session.refresh_token,

        expires_in:
          sessionData.session.expires_in,
      });
    }


    // ========================================================
    // REGISTER
    // ========================================================

    if (action === "register") {

      const name =
        typeof body.name === "string"
          ? body.name
          : username;

      const phone =
        typeof body.phone === "string"
          ? body.phone
          : "";


      // ------------------------------------------------------
      // 1. Exact duplicate pre-check
      //
      // The UNIQUE index remains the final authority.
      // ------------------------------------------------------

      const {
        data: existing,
        error: existingError,
      } = await admin
        .from("user_credentials")
        .select("user_id")
        .eq("username", username)
        .maybeSingle();


      if (existingError) {

        console.error(
          "Username lookup error:",
          existingError.message,
        );

        return json(
          {
            success: false,
            error:
              "Registration temporarily unavailable",
          },
          503,
        );
      }


      if (existing) {

        return json(
          {
            success: false,
            error:
              "Username already taken",
          },
          409,
        );
      }


      // ------------------------------------------------------
      // 2. Generate private Auth identity
      // ------------------------------------------------------

      const internalEmail =
        `u_${crypto
          .randomUUID()
          .replaceAll("-", "")}@sana-app.com`;


      const internalAuthSecret =
        `${crypto.randomUUID()}${crypto.randomUUID()}`;


      // ------------------------------------------------------
      // 3. Create actual auth.users identity
      // ------------------------------------------------------

      const {
        data: authResult,
        error: createError,
      } = await admin.auth.admin.createUser({
        email: internalEmail,

        password:
          internalAuthSecret,

        email_confirm: true,

        user_metadata: {
          username,
          name,
          phone,
          role: "user",
          is_active: false,
        },
      });


      if (
        createError ||
        !authResult?.user
      ) {

        console.error(
          "Auth creation error:",
          createError?.message,
        );

        return json(
          {
            success: false,
            error:
              "Registration failed",
          },
          500,
        );
      }


      const userId =
        authResult.user.id;


      try {

        // ----------------------------------------------------
        // 4. Server-side password hashing
        // ----------------------------------------------------

        const preHashed =
          await preHashPassword(password);


        const salt =
          await bcrypt.genSalt(10);


        const passwordHash =
          await bcrypt.hash(
            preHashed,
            salt,
          );


        // ----------------------------------------------------
        // 5. Credential vault insert
        // ----------------------------------------------------

        const {
          error: credentialInsertError,
        } = await admin
          .from("user_credentials")
          .insert({
            user_id: userId,
            username,
            password_hash: passwordHash,
            internal_email: internalEmail,
            internal_auth_secret:
              internalAuthSecret,
          });


        if (credentialInsertError) {

          throw new Error(
            credentialInsertError.code ===
              "23505"
              ? "Username already taken"
              : "Failed to store credentials",
          );
        }


        // ----------------------------------------------------
        // 6. Ensure public.users is correct
        // ----------------------------------------------------

        const {
          error: usersError,
        } = await admin
          .from("users")
          .upsert(
            {
              id: userId,
              username,
              name,
              email: internalEmail,
              phone,
              is_active: false,
              role: "user",
            },
            {
              onConflict: "id",
            },
          );


        if (usersError) {
          throw new Error(
            "Failed to create user profile",
          );
        }


        // ----------------------------------------------------
        // 7. Ensure profiles is correct
        // ----------------------------------------------------

        const {
          error: profilesError,
        } = await admin
          .from("profiles")
          .upsert(
            {
              id: userId,
              name,
              email: internalEmail,
              phone,
              is_active: false,
              role: "user",
              status: "pending",
            },
            {
              onConflict: "id",
            },
          );


        if (profilesError) {
          throw new Error(
            "Failed to create profile",
          );
        }


        // ----------------------------------------------------
        // Registration succeeds.
        // Account remains inactive.
        // ----------------------------------------------------

        return json({
          success: true,
          user_id: userId,
          is_active: false,
        });

      } catch (error) {

        // Credential/profile creation failed.
        // Delete Auth identity so registration is atomic
        // from the application's perspective.

        await admin.auth.admin.deleteUser(
          userId,
        );

        throw error;
      }
    }


    // ========================================================
    // ADMIN DELETE USER
    // ========================================================

    if (action === "deleteUser") {
      const authorization =
        req.headers.get("Authorization") ?? "";

      if (!authorization.startsWith("Bearer ")) {
        return json(
          {
            success: false,
            error: "Unauthorized",
          },
          401,
        );
      }

      // Verify the real logged-in caller.
      const callerClient = createClient(
        supabaseUrl,
        publishableKey,
        {
          global: {
            headers: {
              Authorization: authorization,
            },
          },
          auth: {
            autoRefreshToken: false,
            persistSession: false,
          },
        },
      );

      const {
        data: callerData,
        error: callerError,
      } =
          await callerClient.auth.getUser();

      if (callerError || !callerData?.user) {
        return json(
          {
            success: false,
            error: "Unauthorized",
          },
          401,
        );
      }

      // Only an existing SANA admin may delete users.
      const {
        data: callerProfile,
        error: callerProfileError,
      } = await admin
          .from("users")
          .select("role")
          .eq("id", callerData.user.id)
          .maybeSingle();

      if (
        callerProfileError ||
        callerProfile?.role?.toString().toLowerCase() !=
            "admin"
      ) {
        return json(
          {
            success: false,
            error: "Admin access required",
          },
          403,
        );
      }

      const userId =
          typeof body.userId === "string"
              ? body.userId
              : "";

      if (userId.length === 0) {
        return json(
          {
            success: false,
            error: "User ID required",
          },
          400,
        );
      }

      // Never allow the admin to delete the admin account.
      if (userId === callerData.user.id) {
        return json(
          {
            success: false,
            error: "Admin account cannot be deleted",
          },
          400,
        );
      }

      const {
        data: targetProfile,
        error: targetProfileError,
      } = await admin
          .from("users")
          .select("role")
          .eq("id", userId)
          .maybeSingle();

      if (targetProfileError) {
        return json(
          {
            success: false,
            error: "Unable to verify target user",
          },
          500,
        );
      }

      // Never allow deletion of another admin account.
      if (
        targetProfile?.role?.toString().toLowerCase() ==
            "admin"
      ) {
        return json(
          {
            success: false,
            error: "Admin account cannot be deleted",
          },
          400,
        );
      }

      // Delete the real Supabase Auth identity.
      // Foreign-key ON DELETE CASCADE removes dependent
      // user-owned records where the database defines cascade.
      const {
        error: deleteAuthError,
      } = await admin.auth.admin.deleteUser(
        userId,
      );

      if (deleteAuthError) {
        console.error(
          "Admin delete user error:",
          deleteAuthError.message,
        );

        return json(
          {
            success: false,
            error: "User deletion failed",
          },
          500,
        );
      }

      // Safety cleanup for profile/credential rows that
      // may not be covered by a foreign-key cascade.
      await admin
          .from("user_credentials")
          .delete()
          .eq("user_id", userId);

      await admin
          .from("profiles")
          .delete()
          .eq("id", userId);

      await admin
          .from("users")
          .delete()
          .eq("id", userId);

      return json({
        success: true,
      });
    }

    return json(
      {
        success: false,
        error: "Invalid action",
      },
      400,
    );

  } catch (error) {

    console.error(
      "sana-auth error:",
      error,
    );

    return json(
      {
        success: false,
        error: "Server error",
      },
      500,
    );
  }
});