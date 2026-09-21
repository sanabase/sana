import { createClient } from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const vapidPublicKey = Deno.env.get("SANA_VAPID_PUBLIC_KEY")!;
const vapidPrivateKey = Deno.env.get("SANA_VAPID_PRIVATE_KEY")!;
const vapidSubject =
  Deno.env.get("SANA_VAPID_SUBJECT") ?? "mailto:admin@sanabase.com";

webpush.setVapidDetails(
  vapidSubject,
  vapidPublicKey,
  vapidPrivateKey,
);

const supabase = createClient(
  supabaseUrl,
  serviceRoleKey,
);

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

  const get = (type: string) =>
    parts.find((p) => p.type === type)?.value ?? "";

  return {
    date: `${get("year")}-${get("month")}-${get("day")}`,
    hour: Number(get("hour")),
    minute: Number(get("minute")),
  };
}

function parseTimes(value: unknown): string[] {
  if (value == null) return [];

  const raw = String(value).trim();

  if (!raw) return [];

  try {
    const decoded = JSON.parse(raw);

    if (Array.isArray(decoded)) {
      return decoded
        .map((x) => String(x).trim())
        .filter(Boolean);
    }
  } catch (_) {}

  return raw
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
}

function parseTime(value: string): { hour: number; minute: number } | null {
  const m = value
    .trim()
    .match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i);

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

    if (
      parsed.hour !== now.hour ||
      parsed.minute !== now.minute
    ) {
      continue;
    }

    const reminderDate =
      String(reminder.reminder_date ?? "").trim().toLowerCase();

    const daily =
      reminderDate === "daily" ||
      reminderDate === "";

    if (!daily && reminderDate !== now.date) {
      continue;
    }

    return {
      time,
      scheduledKey: `${now.date} ${time}`,
    };
  }

  return null;
}

Deno.serve(async () => {
  try {
    const { data: reminders, error: reminderError } =
      await supabase
        .from("reminders")
        .select(
          "id,user_id,name,dosage,reminder_time,reminder_date,is_active",
        )
        .eq("is_active", true)
        .not("user_id", "is", null);

    if (reminderError) {
      throw reminderError;
    }

    let sent = 0;
    let skipped = 0;

    for (const reminder of reminders ?? []) {
      const { data: subscriptions, error: subError } =
        await supabase
          .from("push_subscriptions")
          .select(
            "id,user_id,endpoint,p256dh,auth,timezone",
          )
          .eq("user_id", reminder.user_id);

      if (subError) {
        console.error("Subscription lookup failed", subError);
        continue;
      }

      for (const sub of subscriptions ?? []) {
        const timeZone =
          String(sub.timezone ?? "UTC").trim() || "UTC";

        const match = matchesReminder(
          reminder,
          timeZone,
        );

        if (!match) {
          skipped++;
          continue;
        }

        const { data: existing } =
          await supabase
            .from("web_push_deliveries")
            .select("id")
            .eq("endpoint", sub.endpoint)
            .eq("reminder_id", reminder.id)
            .eq("scheduled_key", match.scheduledKey)
            .maybeSingle();

        if (existing) {
          continue;
        }

        const payload = {
          title: "SANA Reminder",
          body: `${reminder.name ?? ""}${reminder.dosage ? ` — ${reminder.dosage}` : ""}`,
          reminder_id: String(reminder.id),
          reminder_time: match.time,
          reminder_date: String(
            reminder.reminder_date ?? "",
          ),
        };

        try {
          await webpush.sendNotification(
            {
              endpoint: sub.endpoint,
              keys: {
                p256dh: sub.p256dh,
                auth: sub.auth,
              },
            },
            JSON.stringify(payload),
            {
              TTL: 120,
            },
          );

          await supabase
            .from("web_push_deliveries")
            .insert({
              endpoint: sub.endpoint,
              reminder_id: reminder.id,
              scheduled_key: match.scheduledKey,
            });

          sent++;
        } catch (pushError) {
          console.error(
            "Web push failed:",
            pushError,
          );

          const status =
            pushError &&
            typeof pushError === "object" &&
            "statusCode" in pushError
              ? Number(
                  (pushError as { statusCode: unknown })
                    .statusCode,
                )
              : 0;

          if (status === 404 || status === 410) {
            await supabase
              .from("push_subscriptions")
              .delete()
              .eq("endpoint", sub.endpoint);
          }
        }
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        sent,
        skipped,
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  } catch (error) {
    console.error(error);

    return new Response(
      JSON.stringify({
        ok: false,
        error: String(error),
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  }
});