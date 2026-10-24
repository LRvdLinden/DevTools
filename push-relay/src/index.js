/**
 * DevTools push relay (Cloudflare Worker).
 *
 * POST /register      {key} → returns {webhookURL, secret} for App Store Connect webhooks. The app itself logs in
 *                     to OneSignal with the same key (external_id). Legacy: {key, token} also creates the OneSignal user.
 * POST /hook/:key     App Store Connect webhook delivery → checks X-Apple-SIGNATURE → OneSignal push to that device.
 *
 * Stateless: the per-device webhook secret is HMAC(HOOK_SECRET, key), so nothing has to be stored.
 * Secrets (wrangler secret put): ONESIGNAL_APP_ID, ONESIGNAL_REST_KEY, HOOK_SECRET.
 */

const enc = new TextEncoder();

async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, typeof message === 'string' ? enc.encode(message) : message);
  return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, '0')).join('');
}

function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

const KEY_RE = /^[0-9a-f-]{32,40}$/;
const TOKEN_RE = /^[0-9a-f]{32,200}$/i;

export const secretFor = (env, key) => hmacHex(env.HOOK_SECRET, `devtools-webhook:${key}`);

// ---------- OneSignal ----------

async function oneSignal(env, path, body) {
  return fetch(`https://api.onesignal.com${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Key ${env.ONESIGNAL_REST_KEY}` },
    body: JSON.stringify(body),
  });
}

async function register(env, request, origin) {
  let input;
  try { input = await request.json(); } catch { return json({ error: 'invalid json' }, 400); }
  const { key, token, sandbox, language } = input || {};
  if (!KEY_RE.test(String(key || ''))) return json({ error: 'invalid key' }, 400);
  // The DevTools app registers itself with the OneSignal SDK (external_id = key). Older builds sent the raw APNs
  // token instead; in that case the relay creates the OneSignal user itself.
  if (token !== undefined) {
    if (!TOKEN_RE.test(String(token))) return json({ error: 'invalid token' }, 400);
    const subscription = { type: 'iOSPush', token, enabled: true };
    if (sandbox) subscription.test_type = 1;
    let res = await oneSignal(env, `/apps/${env.ONESIGNAL_APP_ID}/users`, {
      properties: { language: String(language || 'en').slice(0, 2) },
      identity: { external_id: key },
      subscriptions: [subscription],
    });
    if (res.status === 409) {
      res = await oneSignal(env, `/apps/${env.ONESIGNAL_APP_ID}/users/by/external_id/${key}/subscriptions`, { subscription });
    }
    if (!res.ok && res.status !== 409) {
      return json({ error: `OneSignal ${res.status}`, detail: (await res.text()).slice(0, 300) }, 502);
    }
  }
  return json({ webhookURL: `${origin}/hook/${key}`, secret: await secretFor(env, key) });
}

// ---------- Messages ----------

const T = {
  en: {
    live: 'is live on the App Store 🎉', review: 'is in review', waiting: 'is waiting for review', approved: 'was approved and is ready for release',
    rejected: 'was rejected', metadataRejected: 'metadata was rejected', distribution: 'is ready for distribution', processing: 'is being processed',
    state: 'status: %s', buildDone: 'Build processed and ready for TestFlight', buildFailed: 'Build processing failed', buildState: 'Build: %s',
    betaApproved: 'Approved for external TestFlight testing', betaRejected: 'Rejected for external TestFlight testing', betaState: 'External TestFlight: %s',
    feedback: 'New TestFlight feedback from a tester', crash: 'New crash report from a tester', ping: 'Test message received. Push notifications work!',
    other: 'App Store Connect update',
  },
  nl: {
    live: 'staat live in de App Store 🎉', review: 'is in review', waiting: 'wacht op review', approved: 'is goedgekeurd en klaar voor release',
    rejected: 'is afgewezen', metadataRejected: 'metadata is afgewezen', distribution: 'is klaar voor distributie', processing: 'wordt verwerkt',
    state: 'status: %s', buildDone: 'Build verwerkt en klaar voor TestFlight', buildFailed: 'Verwerken van de build is mislukt', buildState: 'Build: %s',
    betaApproved: 'Goedgekeurd voor externe TestFlight-tests', betaRejected: 'Afgewezen voor externe TestFlight-tests', betaState: 'Externe TestFlight: %s',
    feedback: 'Nieuwe TestFlight-feedback van een tester', crash: 'Nieuwe crashmelding van een tester', ping: 'Testbericht ontvangen. Pushmeldingen werken!',
    other: 'Update van App Store Connect',
  },
  de: {
    live: 'ist live im App Store 🎉', review: 'wird geprüft', waiting: 'wartet auf Prüfung', approved: 'wurde genehmigt und ist bereit zur Veröffentlichung',
    rejected: 'wurde abgelehnt', metadataRejected: 'Metadaten wurden abgelehnt', distribution: 'ist bereit zur Verteilung', processing: 'wird verarbeitet',
    state: 'Status: %s', buildDone: 'Build verarbeitet und bereit für TestFlight', buildFailed: 'Verarbeitung des Builds fehlgeschlagen', buildState: 'Build: %s',
    betaApproved: 'Für externe TestFlight-Tests genehmigt', betaRejected: 'Für externe TestFlight-Tests abgelehnt', betaState: 'Externes TestFlight: %s',
    feedback: 'Neues TestFlight-Feedback von einem Tester', crash: 'Neuer Absturzbericht von einem Tester', ping: 'Testnachricht empfangen. Push funktioniert!',
    other: 'App Store Connect-Update',
  },
  fr: {
    live: 'est en ligne sur l’App Store 🎉', review: 'est en cours d’examen', waiting: 'attend l’examen', approved: 'a été approuvée et est prête à être publiée',
    rejected: 'a été refusée', metadataRejected: 'les métadonnées ont été refusées', distribution: 'est prête pour la distribution', processing: 'est en cours de traitement',
    state: 'statut : %s', buildDone: 'Build traité et prêt pour TestFlight', buildFailed: 'Échec du traitement du build', buildState: 'Build : %s',
    betaApproved: 'Approuvé pour les tests TestFlight externes', betaRejected: 'Refusé pour les tests TestFlight externes', betaState: 'TestFlight externe : %s',
    feedback: 'Nouveau retour TestFlight d’un testeur', crash: 'Nouveau rapport de plantage d’un testeur', ping: 'Message de test reçu. Les notifications fonctionnent !',
    other: 'Mise à jour App Store Connect',
  },
  es: {
    live: 'ya está en el App Store 🎉', review: 'está en revisión', waiting: 'espera revisión', approved: 'se ha aprobado y está lista para publicarse',
    rejected: 'se ha rechazado', metadataRejected: 'se han rechazado los metadatos', distribution: 'está lista para distribución', processing: 'se está procesando',
    state: 'estado: %s', buildDone: 'Build procesada y lista para TestFlight', buildFailed: 'Error al procesar la build', buildState: 'Build: %s',
    betaApproved: 'Aprobada para pruebas externas de TestFlight', betaRejected: 'Rechazada para pruebas externas de TestFlight', betaState: 'TestFlight externo: %s',
    feedback: 'Nuevos comentarios de TestFlight de un tester', crash: 'Nuevo informe de fallo de un tester', ping: 'Mensaje de prueba recibido. ¡Las notificaciones funcionan!',
    other: 'Actualización de App Store Connect',
  },
  pl: {
    live: 'jest już w App Store 🎉', review: 'jest w trakcie weryfikacji', waiting: 'czeka na weryfikację', approved: 'została zatwierdzona i jest gotowa do publikacji',
    rejected: 'została odrzucona', metadataRejected: 'metadane zostały odrzucone', distribution: 'jest gotowa do dystrybucji', processing: 'jest przetwarzana',
    state: 'status: %s', buildDone: 'Build przetworzony i gotowy do TestFlight', buildFailed: 'Przetwarzanie buildu nie powiodło się', buildState: 'Build: %s',
    betaApproved: 'Zatwierdzono do zewnętrznych testów TestFlight', betaRejected: 'Odrzucono do zewnętrznych testów TestFlight', betaState: 'Zewnętrzny TestFlight: %s',
    feedback: 'Nowa opinia TestFlight od testera', crash: 'Nowy raport awarii od testera', ping: 'Wiadomość testowa odebrana. Powiadomienia działają!',
    other: 'Aktualizacja App Store Connect',
  },
  nb: {
    live: 'er live i App Store 🎉', review: 'er under vurdering', waiting: 'venter på vurdering', approved: 'er godkjent og klar for lansering',
    rejected: 'ble avvist', metadataRejected: 'metadata ble avvist', distribution: 'er klar for distribusjon', processing: 'behandles',
    state: 'status: %s', buildDone: 'Build behandlet og klar for TestFlight', buildFailed: 'Behandling av build mislyktes', buildState: 'Build: %s',
    betaApproved: 'Godkjent for ekstern TestFlight-testing', betaRejected: 'Avvist for ekstern TestFlight-testing', betaState: 'Ekstern TestFlight: %s',
    feedback: 'Ny TestFlight-tilbakemelding fra en tester', crash: 'Ny krasjrapport fra en tester', ping: 'Testmelding mottatt. Varsler fungerer!',
    other: 'Oppdatering fra App Store Connect',
  },
  da: {
    live: 'er live i App Store 🎉', review: 'er under gennemgang', waiting: 'venter på gennemgang', approved: 'er godkendt og klar til udgivelse',
    rejected: 'blev afvist', metadataRejected: 'metadata blev afvist', distribution: 'er klar til distribution', processing: 'behandles',
    state: 'status: %s', buildDone: 'Build behandlet og klar til TestFlight', buildFailed: 'Behandling af build mislykkedes', buildState: 'Build: %s',
    betaApproved: 'Godkendt til ekstern TestFlight-test', betaRejected: 'Afvist til ekstern TestFlight-test', betaState: 'Ekstern TestFlight: %s',
    feedback: 'Ny TestFlight-feedback fra en tester', crash: 'Ny nedbrudsrapport fra en tester', ping: 'Testbesked modtaget. Notifikationer virker!',
    other: 'Opdatering fra App Store Connect',
  },
  sv: {
    live: 'är live i App Store 🎉', review: 'granskas', waiting: 'väntar på granskning', approved: 'har godkänts och är redo att släppas',
    rejected: 'har avvisats', metadataRejected: 'metadata har avvisats', distribution: 'är redo för distribution', processing: 'bearbetas',
    state: 'status: %s', buildDone: 'Build bearbetad och redo för TestFlight', buildFailed: 'Bearbetningen av builden misslyckades', buildState: 'Build: %s',
    betaApproved: 'Godkänd för extern TestFlight-testning', betaRejected: 'Avvisad för extern TestFlight-testning', betaState: 'Extern TestFlight: %s',
    feedback: 'Ny TestFlight-feedback från en testare', crash: 'Ny kraschrapport från en testare', ping: 'Testmeddelande mottaget. Notiser fungerar!',
    other: 'Uppdatering från App Store Connect',
  },
};

const pretty = s => String(s || '').replace(/_/g, ' ').toLowerCase();

const VERSION_STATE = {
  READY_FOR_SALE: 'live', IN_REVIEW: 'review', WAITING_FOR_REVIEW: 'waiting', PENDING_DEVELOPER_RELEASE: 'approved', PENDING_APPLE_RELEASE: 'approved',
  ACCEPTED: 'approved', REJECTED: 'rejected', METADATA_REJECTED: 'metadataRejected', READY_FOR_DISTRIBUTION: 'distribution',
  PROCESSING_FOR_DISTRIBUTION: 'processing', PROCESSING_FOR_APP_STORE: 'processing',
};

/** Builds {title, body} for an App Store Connect webhook payload. */
export function message(payload, appName, lang) {
  const t = T[lang] || T.en;
  const data = (payload && payload.data) || {};
  const type = String(data.type || '');
  const a = data.attributes || {};
  const title = appName || 'App Store Connect';
  const fmt = (tpl, v) => tpl.replace('%s', pretty(v));
  switch (type) {
    case 'webhookPingCreated':
      return { title: 'DevTools', body: t.ping };
    case 'appStoreVersionAppVersionStateUpdated': {
      const key = VERSION_STATE[a.newValue];
      return { title, body: key ? `${title} ${t[key]}` : fmt(t.state, a.newValue) };
    }
    case 'buildUploadStateUpdated':
      if (a.newState === 'COMPLETE') return { title, body: t.buildDone };
      if (a.newState === 'FAILED') return { title, body: t.buildFailed };
      return { title, body: fmt(t.buildState, a.newState) };
    case 'buildBetaDetailExternalBuildStateUpdated':
      if (a.newExternalBuildState === 'BETA_APPROVED') return { title, body: t.betaApproved };
      if (a.newExternalBuildState === 'BETA_REJECTED') return { title, body: t.betaRejected };
      return { title, body: fmt(t.betaState, a.newExternalBuildState) };
    case 'betaFeedbackScreenshotSubmissionCreated':
      return { title, body: t.feedback };
    case 'betaFeedbackCrashSubmissionCreated':
      return { title, body: t.crash };
    default:
      return { title, body: t.other };
  }
}

/** Skip intermediate states nobody wants a push for. */
export function isNoise(payload) {
  const d = (payload && payload.data) || {};
  const a = d.attributes || {};
  if (d.type === 'buildUploadStateUpdated') return !['COMPLETE', 'FAILED'].includes(a.newState);
  if (d.type === 'appStoreVersionAppVersionStateUpdated') return a.newValue === 'PREPARE_FOR_SUBMISSION';
  return false;
}

async function hook(env, request, key, url) {
  if (!KEY_RE.test(key)) return new Response('not found', { status: 404 });
  const raw = await request.arrayBuffer();
  const header = request.headers.get('x-apple-signature') || '';
  const given = header.replace(/^hmacsha256=/i, '').trim().toLowerCase();
  const expected = await hmacHex(await secretFor(env, key), new Uint8Array(raw));
  if (!given || !safeEqual(given, expected)) return new Response('invalid signature', { status: 401 });

  let payload = {};
  try { payload = JSON.parse(new TextDecoder().decode(raw)); } catch { /* keep empty */ }
  if (isNoise(payload)) return new Response('ignored', { status: 200 });

  const lang = (url.searchParams.get('lang') || 'en').slice(0, 2);
  const appName = url.searchParams.get('app') || '';
  const { title, body } = message(payload, appName, lang);
  const res = await oneSignal(env, '/notifications', {
    app_id: env.ONESIGNAL_APP_ID,
    target_channel: 'push',
    include_aliases: { external_id: [key] },
    headings: { en: title },
    contents: { en: body },
    ios_sound: 'default',
    thread_id: appName || 'devtools',
    data: { event: String((payload.data || {}).type || ''), id: String((payload.data || {}).id || '') },
  });
  // Always 200 to Apple once the signature is valid, so it doesn't retry for OneSignal problems.
  return new Response(res.ok ? 'sent' : `onesignal ${res.status}`, { status: 200 });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/') return new Response('DevTools push relay', { status: 200 });
    if (request.method === 'POST' && url.pathname === '/register') return register(env, request, url.origin);
    const m = url.pathname.match(/^\/hook\/([0-9a-f-]+)$/);
    if (request.method === 'POST' && m) return hook(env, request, m[1], url);
    return new Response('not found', { status: 404 });
  },
};
