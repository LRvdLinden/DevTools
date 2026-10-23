'use strict';

/** State colours (identical to the DevTools iOS app); labels live in /locales/<lang>.json → status. */
const COLORS = {
  READY_FOR_SALE: '#34D46A',
  READY_FOR_DISTRIBUTION: '#3CD3FF',
  WAITING_FOR_REVIEW: '#FFA733',
  IN_REVIEW: '#FFA733',
  READY_FOR_REVIEW: '#FFA733',
  PREPARE_FOR_SUBMISSION: '#2F8BFF',
  PENDING_DEVELOPER_RELEASE: '#9B85FF',
  PENDING_APPLE_RELEASE: '#9B85FF',
  PROCESSING_FOR_APP_STORE: '#FFA733',
  PROCESSING_FOR_DISTRIBUTION: '#FFA733',
  REJECTED: '#FF5A5F',
  METADATA_REJECTED: '#FF5A5F',
  INVALID_BINARY: '#FF5A5F',
  DEVELOPER_REJECTED: '#9A9DA8',
  REPLACED_WITH_NEW_VERSION: '#9A9DA8',
  DEVELOPER_REMOVED_FROM_SALE: '#9A9DA8',
  REMOVED_FROM_SALE: '#9A9DA8',
  VALID: '#34D46A',
  PROCESSING: '#FFA733',
  FAILED: '#FF5A5F',
  INVALID: '#FF5A5F',
  IN_BETA_TESTING: '#34D46A',
  READY_FOR_BETA_TESTING: '#2F8BFF',
  MISSING_EXPORT_COMPLIANCE: '#FFA733',
  EXPIRED: '#9A9DA8',
};

const CLOSED = new Set(['READY_FOR_SALE', 'REPLACED_WITH_NEW_VERSION', 'DEVELOPER_REMOVED_FROM_SALE', 'REMOVED_FROM_SALE', 'REMOVED_FROM_DISTRIBUTION']);
const REVIEW = new Set(['WAITING_FOR_REVIEW', 'IN_REVIEW']);
const REJECTED = new Set(['REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY']);

const cache = {};
function labels(lang) {
  if (!cache[lang]) {
    let en = {};
    try { en = require('../locales/en.json').status || {}; } catch (e) { /* ignore */ }
    let own = {};
    try { own = require(`../locales/${lang}.json`).status || {}; } catch (e) { /* ignore */ }
    cache[lang] = { ...en, ...own };
  }
  return cache[lang];
}

function label(state, lang = 'en') {
  const l = labels(lang)[state];
  if (l) return l;
  return state ? state.replace(/_/g, ' ').toLowerCase().replace(/^\w/, c => c.toUpperCase()) : '—';
}

function color(state) { return COLORS[state] || '#9A9DA8'; }

/** Summarises the versions of an app: live version, version in progress and headline state. */
function summarize(versions) {
  const live = versions.find(v => v.state === 'READY_FOR_SALE') || null;
  const pending = versions.find(v => !CLOSED.has(v.state)) || null;
  const headline = pending ? pending.state : (live ? live.state : (versions[0] ? versions[0].state : ''));
  return { live, pending, headline };
}

function buildState(b) {
  if (!b) return '';
  if (b.expired) return 'EXPIRED';
  if (b.internalState === 'MISSING_EXPORT_COMPLIANCE' || b.externalState === 'MISSING_EXPORT_COMPLIANCE') return 'MISSING_EXPORT_COMPLIANCE';
  if (b.processingState !== 'VALID') return b.processingState || '';
  return b.externalState && b.externalState !== 'READY_FOR_BETA_SUBMISSION' ? b.externalState : (b.internalState || 'VALID');
}

module.exports = { COLORS, CLOSED, REVIEW, REJECTED, label, color, summarize, buildState };
