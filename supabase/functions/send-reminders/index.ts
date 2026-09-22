Deno.serve(() =>
  new Response(
    JSON.stringify({
      ok: false,
      error: "send-reminders is deprecated. Use send-web-reminders.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  )
);