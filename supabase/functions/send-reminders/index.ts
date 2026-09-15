import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'https://esm.sh/web-push@3.6.7';

const SB_URL = Deno.env.get('SUPABASE_URL')!;
const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const VAPID_PUB = Deno.env.get('VAPID_PUBLIC')!;
const VAPID_PRIV = Deno.env.get('VAPID_PRIVATE')!;
const VAPID_SUBJ =
  Deno.env.get('VAPID_SUBJECT') ?? 'mailto:admin@sanabase.github.io';

const HOME_TZ = 'Asia/Beirut';

webpush.setVapidDetails(VAPID_SUBJ, VAPID_PUB, VAPID_PRIV);

function nowParts(tz: string): { hhmm: string; dateKey: string } {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

  const parts = fmt.formatToParts(new Date());
  const get = (t: string) =>
      parts.find((p) => p.type === t)?.value ?? '00';

  let h = get('hour');
  if (h === '24') h = '00';

  return {
    hhmm: `${h}:${get('minute')}`,
    dateKey: `${get('year')}-${get('month')}-${get('day')}`,
  };
}

function parseTimes(raw: unknown): string[] {
  if (raw == null) return [];

  const s = String(raw).trim();
  if (!s) return [];

  try {
    const j = JSON.parse(s);
    if (Array.isArray(j)) {
      return j
        .map((x) => String(x).trim())
        .filter(Boolean);
    }
  } catch (_) {}

  return s
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);
}

function normalizeTime(t: string): string | null {
  if (!t) return null;

  const norm = t.replace(/\s/g, '').toUpperCase();
  const isPM = norm.endsWith('PM');
  const isAM = norm.endsWith('AM');
  const parts = norm.replace(/AM|PM/g, '').split(':');

  if (parts.length < 2) return null;

  let h = parseInt(parts[0], 10);
  const m = parseInt(
    parts[1].replace(/[^0-9]/g, ''),
    10,
  );

  if (isNaN(h) || isNaN(m)) return null;

  if (isPM && h < 12) h += 12;
  if (isAM && h === 12) h = 0;

  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

serve(async () => {
  const sb = createClient(SB_URL, SB_KEY);
  const { hhmm, dateKey } = nowParts(HOME_TZ);

  const { data: reminders, error } = await sb
    .from('reminders')
    .select(
      'id, user_id, name, dosage, reminder_time, reminder_date, is_active',
    );

  if (error) {
    console.error('reminders query failed', error);
    return new Response('query failed', { status: 500 });
  }

  if (!reminders || reminders.length === 0) {
    return new Response('no reminders');
  }

  let sent = 0;

  for (const r of reminders) {
    if (r.is_active === false) continue;

    const times = parseTimes(r.reminder_time);
    if (times.length === 0) continue;

    for (const raw of times) {
      const hh24 = normalizeTime(raw);
      if (!hh24 || hh24 !== hhmm) continue;

      const rd = String(r.reminder_date ?? '')
        .trim()
        .toLowerCase();

      const isDaily = rd === 'daily';
      const isTodayCalendar = !isDaily && rd === dateKey;

      if (!isDaily && !isTodayCalendar) continue;

      const occurrenceKey = `${dateKey}T${hh24}`;

      const { data: subs } = await sb
        .from('push_subscriptions')
        .select('id, endpoint, p256dh, auth')
        .eq('user_id', r.user_id);

      if (!subs || subs.length === 0) continue;

      for (const s of subs) {
        const { data: dupe } = await sb
          .from('reminder_deliveries')
          .select('id')
          .eq('reminder_id', r.id)
          .eq('subscription_id', s.id)
          .eq('scheduled_occurrence_key', occurrenceKey)
          .maybeSingle();

        if (dupe) continue;

        try {
          await webpush.sendNotification(
            {
              endpoint: s.endpoint,
              keys: {
                p256dh: s.p256dh,
                auth: s.auth,
              },
            },
            JSON.stringify({
              title: 'SANA • Medication reminder',
              body: `${r.name ?? ''} — ${r.dosage ?? ''} — ${raw}`,
              reminder_id: r.id,
            }),
          );

          await sb.from('reminder_deliveries').insert({
            reminder_id: r.id,
            user_id: r.user_id,
            subscription_id: s.id,
            scheduled_occurrence_key: occurrenceKey,
            status: 'sent',
          });

          sent++;
        } catch (e) {
          console.error('push send failed', e);
          await sb
            .from('push_subscriptions')
            .delete()
            .eq('id', s.id);
        }
      }
    }
  }

  return new Response(`ok sent=${sent}`);
});
