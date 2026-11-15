/**
 * Med Supply — email reorder reminders.
 *
 * The iPhone app sends its current reorder/run-out dates here whenever the data changes.
 * A daily trigger emails the recipients set in the app when a medication is due:
 *   - "Time to reorder" once its reorder date arrives (7 days before run-out, 3 for controlled,
 *     or whatever the app's Settings say), and
 *   - "Runs out tomorrow" the day before run-out,
 * unless it has been marked as reordered in the app. Each email is sent once.
 *
 * Setup (once):
 *   1. Paste the app's Secret key (Settings › Email reminders) into SECRET below and save.
 *   2. Run `setup` from the toolbar and approve the permissions.
 *   3. Deploy › New deployment › Web app: Execute as "Me", Who has access "Anyone".
 *      Copy the Web app URL into the app's Settings › Email reminders › Script URL.
 *   4. In the app, tap "Send test email".
 */

const SECRET = 'PASTE-THE-SECRET-KEY-FROM-THE-APP-HERE';
const SEND_HOUR = 8; // hour of the daily check, in this script's time zone (Project Settings)

// ---------------------------------------------------------------------------
// Web endpoint (called by the app)

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    if (!SECRET || SECRET.indexOf('PASTE-') === 0) {
      return json_({ ok: false, error: 'The SECRET line in the script has not been filled in.' });
    }
    if (body.secret !== SECRET) {
      return json_({ ok: false, error: 'Secret key does not match the script.' });
    }
    if (!Array.isArray(body.recipients) || body.recipients.length === 0) {
      return json_({ ok: false, error: 'No email address set in the app.' });
    }

    saveState_({
      recipients: body.recipients,
      timeZone: body.timeZone || Session.getScriptTimeZone(),
      meds: body.meds || [],
      receivedAt: new Date().toISOString(),
    });

    if (body.test) {
      sendTest_(body.recipients, (body.meds || []).length);
      return json_({ ok: true, message: 'Test email sent.' });
    }
    return json_({ ok: true });
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  }
}

function doGet() {
  return json_({ ok: true, message: 'Med Supply email reminders are running.' });
}

// ---------------------------------------------------------------------------
// Daily check (time-driven trigger)

function dailyCheck() {
  const state = loadState_();
  if (!state || !state.meds || state.meds.length === 0) return;

  const today = Utilities.formatDate(new Date(), state.timeZone, 'yyyy-MM-dd');
  const sent = loadSent_();
  const reorder = [];
  const final = [];

  state.meds.forEach(function (med) {
    if (med.ordered || !med.reorderDate || !med.runOutDate) return;

    const finalDay = addDays_(med.runOutDate, -1);
    const finalKey = med.id + ':final:' + med.runOutDate;
    const reorderKey = med.id + ':reorder:' + med.reorderDate;

    if (today >= finalDay && today <= med.runOutDate && !sent[finalKey]) {
      final.push(med);
      sent[finalKey] = today;
      sent[reorderKey] = sent[reorderKey] || today; // don't also send the earlier reminder
    } else if (today >= med.reorderDate && today < med.runOutDate && !sent[reorderKey]) {
      reorder.push(med);
      sent[reorderKey] = today;
    }
  });

  if (reorder.length === 0 && final.length === 0) return;

  const nameList = function (meds) { return meds.map(function (m) { return m.name; }).join(', '); };
  const subjectParts = [];
  if (final.length) subjectParts.push('Runs out tomorrow: ' + nameList(final));
  if (reorder.length) subjectParts.push('Time to reorder: ' + nameList(reorder));
  const subject = subjectParts.join(' | ');

  const sections = [];
  if (final.length) sections.push(section_('Runs out tomorrow (not marked as reordered)', final, true));
  if (reorder.length) sections.push(section_('Time to reorder', reorder, false));

  MailApp.sendEmail({
    to: state.recipients.join(','),
    subject: subject,
    htmlBody: sections.join('') +
      '<p style="color:#888;font-size:12px">Sent by Med Supply. Mark a medication as reordered in the app to stop its reminders.</p>',
  });
  saveSent_(sent, today);
}

// ---------------------------------------------------------------------------
// One-time setup: installs the daily trigger (run from the editor).

function setup() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'dailyCheck') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('dailyCheck').timeBased().everyDays(1).atHour(SEND_HOUR).create();
  Logger.log('Daily check scheduled for about ' + SEND_HOUR + ':00 ' + Session.getScriptTimeZone() + '.');
}

// ---------------------------------------------------------------------------
// Email formatting

function section_(title, meds, isFinal) {
  const rows = meds.map(function (m) {
    const lines = [];
    let name = '<b>' + esc_(m.name) + '</b>';
    if (m.generic) name += ' (' + esc_(m.generic) + ')';
    if (m.dose) name += ' ' + esc_(m.dose);
    lines.push(name);
    const left = isFinal ? (m.onHandFinal || m.onHand) : m.onHand;
    lines.push('About ' + esc_(left) + ' left; runs out ' + prettyDate_(m.runOutDate) + '.');
    if (m.pharmacy) {
      let p = 'Pharmacy: ' + esc_(m.pharmacy);
      if (m.pharmacyPhone) p += ', ' + esc_(m.pharmacyPhone);
      if (m.rxNumber) p += ' — Rx #' + esc_(m.rxNumber);
      lines.push(p);
    } else if (m.rxNumber) {
      lines.push('Rx #' + esc_(m.rxNumber));
    }
    if (m.refillsRemaining === 0) {
      lines.push('<span style="color:#c00">No refills left: contact ' +
        esc_(m.prescriber || 'the prescriber') +
        (m.prescriberPhone ? ' (' + esc_(m.prescriberPhone) + ')' : '') +
        ' for a new prescription.</span>');
    }
    if (m.rxExpiration && m.rxExpiration <= m.runOutDate) {
      lines.push('<span style="color:#c00">Prescription expires ' + prettyDate_(m.rxExpiration) + '.</span>');
    }
    if (m.controlled) lines.push('Controlled substance.');
    return '<li style="margin-bottom:12px">' + lines.join('<br>') + '</li>';
  });
  return '<h3>' + esc_(title) + '</h3><ul>' + rows.join('') + '</ul>';
}

function sendTest_(recipients, count) {
  MailApp.sendEmail({
    to: recipients.join(','),
    subject: 'Med Supply: test email',
    htmlBody: '<p>Email reminders are set up. The script has ' + count +
      ' medication(s) and checks them every day at about ' + SEND_HOUR + ':00.</p>',
  });
}

// ---------------------------------------------------------------------------
// Storage. Script properties hold at most ~9 KB per value, so the state is split into chunks.

const CHUNK = 8000;

function saveState_(state) {
  const props = PropertiesService.getScriptProperties();
  const text = JSON.stringify(state);
  const old = Number(props.getProperty('state_chunks') || 0);
  const chunks = Math.ceil(text.length / CHUNK);
  const values = { state_chunks: String(chunks) };
  for (let i = 0; i < chunks; i++) values['state_' + i] = text.substr(i * CHUNK, CHUNK);
  props.setProperties(values);
  for (let i = chunks; i < old; i++) props.deleteProperty('state_' + i);
}

function loadState_() {
  const props = PropertiesService.getScriptProperties();
  const chunks = Number(props.getProperty('state_chunks') || 0);
  if (!chunks) return null;
  let text = '';
  for (let i = 0; i < chunks; i++) text += props.getProperty('state_' + i) || '';
  return JSON.parse(text);
}

function loadSent_() {
  const raw = PropertiesService.getScriptProperties().getProperty('sent');
  return raw ? JSON.parse(raw) : {};
}

/** Keeps only the last 120 days of "already sent" markers. */
function saveSent_(sent, today) {
  const cutoff = addDays_(today, -120);
  const kept = {};
  Object.keys(sent).forEach(function (k) { if (sent[k] >= cutoff) kept[k] = sent[k]; });
  PropertiesService.getScriptProperties().setProperty('sent', JSON.stringify(kept));
}

// ---------------------------------------------------------------------------
// Helpers

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

/** 'yyyy-MM-dd' plus n days, as 'yyyy-MM-dd' (calendar math in UTC, so no DST issues). */
function addDays_(ymd, n) {
  const p = ymd.split('-').map(Number);
  const d = new Date(Date.UTC(p[0], p[1] - 1, p[2] + n));
  return d.toISOString().slice(0, 10);
}

function prettyDate_(ymd) {
  const p = ymd.split('-').map(Number);
  const d = new Date(Date.UTC(p[0], p[1] - 1, p[2]));
  return Utilities.formatDate(d, 'UTC', 'EEE, MMM d');
}

function esc_(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
