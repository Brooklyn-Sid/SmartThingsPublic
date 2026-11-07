# Med Supply (iOS)

A small SwiftUI app that tracks medication **supply** and reminds you to **reorder**. It does not do dose reminders.

## Features

- **Per medication:** brand and generic name, dose, frequency, pills per dose, current count, last date the count was refreshed, pharmacy (+ phone), Rx number, prescribing doctor (+ phone), controlled substance yes/no, refills remaining, Rx expiration date, notes, photo.
- **Projected run-out date** = last refresh date + floor(count ÷ daily use). The current count is estimated the same way, so she doesn't need to update it every day.
- **Reorder reminders** (local notifications) **7 days** before run-out, or **3 days** for controlled substances. Both values and the time of day can be changed in Settings. A follow-up fires the day before run-out if the medication hasn't been marked as reordered.
- **Mark as reordered:** silences reminders until the refill is recorded. Available in the app and as a button on the notification itself.
- **Refill button:** asks for the count added (pre-filled with the last refill amount) and the pickup date, adds that to the current estimated count, and sets that date as the last refresh date. It also decrements refills remaining if she tracks them.
- **Recount:** enter the actual count to correct drift from missed or extra doses.
- **Brand ↔ generic auto-fill** using the free NIH **RxNorm** API. Type either name and tap the magnifier. When a generic has several brands, the app lets her pick one.
- **Image lookup** from NIH **DailyMed** (FDA label images). She can also pick from Photos or take a photo of her own bottle or pill.
- Home screen sorted by run-out date, a "Reorder now" section, an app badge count, swipe-to-refill, archive for stopped meds, refill history, tap-to-call pharmacy or doctor, and "Share refill info" (text with Rx #, pharmacy, and doctor).

## Importing from a spreadsheet

Menu (•••) › **Import from spreadsheet…** reads a CSV file with column headers in the first row. In Google Sheets, use File › Download › Comma-separated values, AirDrop the file to the iPhone, and save it to Files. Columns are matched by header name, and unknown columns are ignored. Recognized headers include: Medication name / Brand name, Generic name, Strength / Dose, Amount per dose, Schedule / Frequency, Quantity on hand / Count, Count verified date, Pharmacy, Pharmacy phone, Prescription number / Rx number, Prescribing doctor, Doctor phone, Refills remaining, Controlled, and Notes.

The importer understands schedules such as "Daily", "BID", "Twice weekly", "3 times a week", "Every 28 days" and "As needed", and amounts such as "1 tablet", "¼ tablet" and "1 1/2 tablets". The preview flags anything it couldn't read and leaves rows that are already in the app unchecked. Blank brand or generic names are filled from RxNorm after import.

Medication data is never stored in this repository; it stays on the phone.

## Build & install (requires a Mac with Xcode 16 or later)

1. `brew install xcodegen`
2. `cd MedSupply-iOS && xcodegen generate`
3. Open `MedSupply.xcodeproj`. Under **Signing & Capabilities**, choose your team and change the bundle ID (e.g. `com.yourname.medsupply`).
4. Plug in her iPhone (enable Developer Mode on the phone), select it as the run target, and press Run.

With a free Apple ID the install expires after 7 days and must be re-run from Xcode. A paid Apple Developer account ($99/yr) gives 1-year installs and TestFlight.

No Xcode project generator? Create a new iOS App project in Xcode (SwiftUI, SwiftData, iOS 17), delete the generated Swift files, drag in the `MedSupply/` folder, and add `NSCameraUsageDescription` to Info.

## Notes / limitations

- **Why not WebMD:** WebMD has no public API, and its terms prohibit scraping. DailyMed is the official NIH/FDA source. Its images are label photos, which may show a different manufacturer or strength than her pills, so she picks the match. A photo of her own bottle is the most reliable option.
- Name lookup and image search need internet; everything else works offline. Data is stored on-device only (SwiftData).
- The models are CloudKit-compatible. Turning on iCloud sync (to share between two phones, or as a backup) requires a paid developer account plus the iCloud and CloudKit capability.
