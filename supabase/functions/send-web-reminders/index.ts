import { createClient } from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const vapidPublicKey = Deno.env.get("VAPID_PUBLIC");
const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE");
const vapidSubject =
  Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@sanabase.com";

if (!supabaseUrl || !serviceRoleKey || !vapidPublicKey || !vapidPrivateKey) {
  throw new Error(
    "Preflight failed: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, VAPID_PUBLIC, VAPID_PRIVATE must all be set.",
  );
}

webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);
const supabase = createClient(supabaseUrl, serviceRoleKey);

function localParts(timeZone: string) {
  const now = new Date();
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);

  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return {
    date: `${get("year")}-${get("month")}-${get("day")}`,
    hour: Number(get("hour")),
    minute: Number(get("minute")),
  };
}

function isValidIana(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date());
    return true;
  } catch {
    return false;
  }
}

function parseTimes(value: unknown): string[] {
  if (value == null) return [];
  const raw = String(value).trim();
  if (!raw) return [];
  try {
    const decoded = JSON.parse(raw);
    if (Array.isArray(decoded)) {
      return decoded.map((x) => String(x).trim()).filter(Boolean);
    }
  } catch (_) {}
  return raw.split(",").map((x) => x.trim()).filter(Boolean);
}

function parseTime(value: string): { hour: number; minute: number } | null {
  const m = value.trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i);
  if (!m) return null;
  let hour = Number(m[1]);
  const minute = Number(m[2]);
  const ampm = m[3]?.toUpperCase();
  if (minute < 0 || minute > 59) return null;
  if (ampm === "AM") {
    if (hour < 1 || hour > 12) return null;
    if (hour === 12) hour = 0;
  } else if (ampm === "PM") {
    if (hour < 1 || hour > 12) return null;
    if (hour !== 12) hour += 12;
  } else {
    if (hour < 0 || hour > 23) return null;
  }
  return { hour, minute };
}

function matchesReminder(
  reminder: Record<string, unknown>,
  timeZone: string,
): { time: string; scheduledKey: string } | null {
  const now = localParts(timeZone);
  const times = parseTimes(reminder.reminder_time);

  for (const time of times) {
    const parsed = parseTime(time);
    if (!parsed) continue;
    if (parsed.hour !== now.hour || parsed.minute !== now.minute) continue;

    const reminderDate = String(reminder.reminder_date ?? "").trim().toLowerCase();
    const daily = reminderDate === "daily";
    if (!daily && reminderDate !== now.date) continue;

    return { time, scheduledKey: `${now.date} ${time}` };
  }
  return null;
}

Deno.serve(async () => {
  try {
    const { data: reminders, error: reminderError } = await supabase
      .from("reminders")
      .select("id,user_id,name,dosage,reminder_time,reminder_date,is_active")
      .eq("is_active", true);

    if (reminderError) throw reminderError;

    let sent = 0;
    let skipped = 0;
    let missingTimezone = 0;

    for (const reminder of reminders ?? []) {
      const reminderUserId =
        reminder.user_id == null ? null : String(reminder.user_id);
      const isGuestReminder = reminderUserId == null;

      let subscriptions: any[] = [];
      let subError: any = null;

      if (isGuestReminder) {
        const res = await supabase
          .from("push_subscriptions")
          .select("id,user_id,endpoint,p256dh,auth,timezone");
        subscriptions = res.data ?? [];
        subError = res.error;
      } else {
        const res = await supabase
          .from("push_subscriptions")
          .select("id,user_id,endpoint,p256dh,auth,timezone")
          .eq("user_id", reminderUserId);
        subscriptions = res.data ?? [];
        subError = res.error;
      }

      if (subError) {
        console.error("Subscription lookup failed", subError);
        continue;
      }

      // First pass: find which subscriptions match this reminder at this minute.
      type Matched = {
        sub: any;
        match: { time: string; scheduledKey: string };
      };
      const matched: Matched[] = [];

      for (const sub of subscriptions ?? []) {
        const rawTz = String(sub.timezone ?? "").trim();
        if (!rawTz || !isValidIana(rawTz)) {
          missingTimezone++;
          continue;
        }
        const match = matchesReminder(reminder, rawTz);
        if (!match) {
          skipped++;
          continue;
        }
        matched.push({ sub, match });
      }

      if (matched.length === 0) continue;

      // One dedup query per distinct scheduled_key, not per subscription.
      const scheduledKey = matched[0].match.scheduledKey;
      const { data: existingRows } = await supabase
        .from("web_push_deliveries")
        .select("endpoint")
        .eq("reminder_id", reminder.id)
        .eq("scheduled_key", scheduledKey);

      const alreadySent = new Set<string>(
        (existingRows ?? []).map((r: { endpoint: string }) => r.endpoint),
      );

      // Second pass: send in parallel.
      const tasks = matched
        .filter(({ sub }) => !alreadySent.has(sub.endpoint))
        .map(async ({ sub, match }) => {
          const payload = {
            title: "SANA Reminder",
            body: `${reminder.name ?? ""}${reminder.dosage ? ` — ${reminder.dosage}` : ""}`,
            reminder_id: String(reminder.id),
            reminder_time: match.time,
            reminder_date: String(reminder.reminder_date ?? ""),
          };

          try {
            await webpush.sendNotification(
              {
                endpoint: sub.endpoint,
                keys: { p256dh: sub.p256dh, auth: sub.auth },
              },
              JSON.stringify(payload),
              { TTL: 120 },
            );

            await supabase.from("web_push_deliveries").insert({
              endpoint: sub.endpoint,
              reminder_id: reminder.id,
              scheduled_key: match.scheduledKey,
            });

            sent++;
          } catch (pushError) {
            console.error("Web push failed:", pushError);
            const status =
              pushError && typeof pushError === "object" && "statusCode" in pushError
                ? Number((pushError as { statusCode: unknown }).statusCode)
                : 0;
            if (status === 404 || status === 410) {
              await supabase
                .from("push_subscriptions")
                .delete()
                .eq("endpoint", sub.endpoint);
            }
          }
        });

      await Promise.all(tasks);
    }

    return new Response(
      JSON.stringify({ ok: true, sent, skipped, missingTimezone }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ ok: false, error: String(error) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});