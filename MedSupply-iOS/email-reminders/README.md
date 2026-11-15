# Email reorder reminders (Google Apps Script)

The app sends its reorder and run-out dates to a small script in your Google account. The script runs once a day and emails you from Gmail when something is due. It keeps working when the phone is off or the app's install has expired.

**It emails:**
- **"Time to reorder"** on the medication's reorder date: 7 days before run-out, 3 for controlled substances, or whatever the app's Settings say.
- **"Runs out tomorrow"** the day before run-out, if the medication hasn't been marked as reordered.

Each reminder is sent once. Marking a medication as reordered in the app stops its emails.

**What Google stores:** medication names, doses, dates, pharmacy and Rx numbers. They're kept in the script's own storage in your Google account. Nothing else is shared.

## Setup (about 10 minutes, on a computer)

1. **In the app:** go to **••• → Settings → Email reminders** and turn on **Send email reminders**. Enter the email address(es) to notify, separated by commas. Leave the app on this screen; you'll need the **Secret key** shown there.
2. **Create the script:** go to <https://script.google.com>, signed in to the Google account that should send the emails. Click **New project**, then click "Untitled project" at the top and rename it **Med Supply reminders**.
3. **Paste the code:** delete everything in the editor. Paste the entire contents of [`Code.gs`](Code.gs) from this folder.
4. **Add the secret:** on the `const SECRET = '…'` line near the top, replace `PASTE-THE-SECRET-KEY-FROM-THE-APP-HERE` with the Secret key from the app. Keep the quote marks. Press **⌘S** to save.
5. **Set the time zone:** click **⚙ Project Settings** in the left bar and check that the **Time zone** is yours (e.g. "(GMT-05:00) Eastern Time"). Then go back to **Editor** (`< >` icon).
6. **Schedule the daily check:** in the toolbar's function dropdown, choose **`setup`** and click **Run**. Google asks for permission:
   - Click **Review permissions** and choose your account.
   - If you see **"Google hasn't verified this app"**, click **Advanced → Go to Med Supply reminders (unsafe)**. This warning appears because it's your own unpublished script, not one from the internet.
   - Click **Allow**. The script asks to send email as you and to run on a schedule.
7. **Deploy as a web app:** click **Deploy → New deployment**. Click the ⚙ next to "Select type" and choose **Web app**. Set:
   - **Execute as:** Me
   - **Who has access:** Anyone
   
   Then click **Deploy** and copy the **Web app URL**. It ends in `/exec`.
   
   "Anyone" means anyone with the URL can reach the script. The script ignores anything that doesn't include the secret key from the app.
8. **Back in the app:** paste the URL into **Script URL** and tap **Send test email**. You should see "✓ Test email sent", and the email should arrive within a minute (check spam the first time).

From then on, every change in the app (adding, refilling, recounting, marking as reordered) updates the script automatically.

## Changing things later

- **Recipients:** edit them in the app. The next change, or tapping **Send test email**, updates the script.
- **Time of the daily email:** change `SEND_HOUR` in the script, save, and run **`setup`** again. Google runs it at some point within that hour.
- **Updating the script code:** paste the new code, then click **Deploy → Manage deployments → ✎ (edit) → Version: New version → Deploy**. The URL stays the same.
- **Stopping emails:** turn off **Send email reminders** in the app. To stop completely, in the script editor click **⏰ Triggers** in the left bar and delete the `dailyCheck` trigger.

## Troubleshooting

| Message in the app | Fix |
|---|---|
| "The script didn't answer as expected…" | Check the deployment's access is **Anyone** and the URL ends in `/exec` (not `/dev`). |
| "Secret key does not match the script." | Re-copy the key from the app into the `SECRET` line, save, and redeploy as a **new version** (see above). |
| "The SECRET line in the script has not been filled in." | Step 4, then redeploy as a new version. |
| Test works but no daily emails | In the editor, open **⏰ Triggers** and confirm `dailyCheck` is listed; if not, run `setup`. The **Executions** page shows each run and any errors. |
