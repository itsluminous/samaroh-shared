# Samaroh - User guide

How to do everyday tasks in the Samaroh app (Android and web). Button names are written exactly as they appear in the app. Generated from help/guide.json - do not edit by hand.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/index.html

## Contents

- [Getting around the app](#app_shell)
- [Booking calendar](#booking_calendar)
- [Booking form (add or edit a booking)](#booking_form)
- [Booking card](#booking_card)
- [Record payment form](#record_payment)
- [Expenses - list of parties](#expenses_home)
- [Party ledger](#expenses_ledger)
- [Add expense (ledger entry form)](#add_expense)
- [Inventory - current stock](#inventory_stock)
- [Item list (master list)](#inventory_masterlist)
- [Item page (transaction history)](#inventory_item)
- [Notes and checklists](#notes)
- [Files](#files)
- [Menu](#menu)
- [Settings](#settings)
- [Members (staff and permissions)](#members)
- [Reports](#reports)
- [Sign in and first-time setup](#sign_in)

<a id="app_shell"></a>

## Getting around the app

The bottom bar has the main sections: Booking, Expenses, Inventory, Notes and Files. The Menu (settings, reports, members) opens from the three-dots button at the top right. On the phone, many buttons are only icons - press and hold any icon and its name pops up.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/app_shell.html

### Go to Booking, Expenses, Inventory, Notes or Files

1. Look at the bar at the bottom of the screen.
2. Tap Booking for the calendar, Expenses for the money ledger, Inventory for stock, Notes for notes, or Files for documents.
3. Only the sections you have permission for appear. If one is missing, ask the owner.

### Open the Menu (settings, reports, members)

1. At the top right of the screen, next to the cloud sync icon, tap the three-dots button called Menu.
2. The Menu lists Settings, Reports, Members and About.

### Find out what an icon button does *(Phone app only)*

1. Press and hold the icon (do not lift your finger) for about one second.
2. A small message appears with the name of the button, for example Record payment.

### Get help for the screen you are on

1. At the top right, next to the three-dots button, tap the question-mark icon called Help for this screen.
2. The guide opens at the section for this screen. Tap a task to see its steps.
3. Tap Show me under a task and the app takes you to the screen where it starts.
4. You can also open the full guide any time from Menu, then Help, and search it with the Search help box.

### Work without internet

1. You can keep adding bookings, payments and expenses without internet. A banner says Offline - changes will sync.
2. When internet returns, everything uploads on its own. To check, open Menu, then Settings, then Sync status.

<a id="booking_calendar"></a>

## Booking calendar

The Booking tab shows a month calendar. Coloured days have bookings; the list under the calendar shows this month's bookings with money received and pending. Tap a day to see or add bookings.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/booking_calendar.html

### See another month

1. Use the arrows beside the month name: Previous month on the left, Next month on the right. On the phone you can also swipe the calendar sideways.
2. Tap the month name to jump to any month (Choose month).

### Open a booking (the booking card)

1. Tap a coloured day on the calendar, or tap the booking in the list below the calendar.
2. If the day has more than one booking, a list opens - tap the one you want.
3. The booking card opens with the customer, dates, amounts and buttons like Record payment and Invoice.

### Add a new booking

*Needs permission: `booking.create`*

1. Tap an empty day on the calendar, or tap the round plus button (Add booking) at the bottom right.
2. If the day already has a booking, a list opens - tap Add new event at the bottom of it.
3. Fill the booking form (see the Booking form page) and tap Save.

### Block dates (no bookings allowed)

*Needs permission: `booking.edit`*

1. Tap the three-dots button (More options) at the top of the calendar.
2. Tap Block dates.
3. Choose the Start date and End date, type a Reason if you like, and tap Save.
4. To remove a block, tap the blocked day and tap Remove block.

### See all bookings as a list

1. Tap the three-dots button (More options) at the top of the calendar.
2. Tap Events view. All bookings appear as a list, today first. Tap Month view to go back to the calendar.

### Answer a payment reminder on the calendar *(Phone app only)*

*Needs permission: `booking.record_payment`*

1. After an event, a card titled Pending confirmations asks whether the customer paid. Tap Yes, full if the whole due came in.
2. Tap Partial… to type the amount received, or Not yet to be reminded again later.

<a id="booking_form"></a>

## Booking form (add or edit a booking)

The form where you type the customer's details, the event type, the dates and the amounts. The Due amount is calculated for you from Total amount minus Advance paid.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/booking_form.html

### Fill in a booking

1. Type the Customer name (required) and Phone number. On the phone you can tap Pick from contacts instead of typing.
2. Choose the Event type (wedding, birthday and so on). Choose Custom to type your own Event name and Icon.
3. Set the Start date and End date. The End date cannot be before the Start date.
4. Type the Total amount and the Advance paid. The Due (auto-calculated) line updates by itself.
5. Set the Status: Tentative (not final yet) or Confirmed.
6. Optional: Notes, Colour for the calendar, and Invoice number (leave blank to auto-generate).
7. Tap Save. If the date already has a booking, the app warns you - tap Save anyway or Go back.

### Change an existing booking

*Needs permission: `booking.edit`*

1. Open the booking card (tap the booking on the calendar).
2. Tap Edit (the pencil icon on the phone). The form opens with the title Edit booking.
3. Change what you need and tap Save.

### Security deposit, booking source and event times are missing from the form

*Needs permission: `settings.manage_business`*

1. These are optional fields. Open Menu, then Settings, then Booking form fields.
2. Switch on Security deposit, Booking source or Event times. They then appear in the booking form.

<a id="booking_card"></a>

## Booking card

One booking in detail: customer and phone, dates, Total, Paid and Due, the payment history and the expenses history. The buttons along the bottom let you record a payment, record an expense, make the invoice, send a WhatsApp reminder, edit or cancel. On the phone these buttons are icons - press and hold one to see its name.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/booking_card.html

### Record a payment received from the customer

*Needs permission: `booking.record_payment`*

1. Open the booking card from the calendar.
2. Tap Record payment (on the phone: the rupee ₹ icon at the bottom of the card).
3. Type the Amount, check the Date, choose the Method (Cash, UPI, Bank transfer, Cheque or Other) and tap Save.
4. The message Payment recorded appears and the Due amount goes down.

### Remove a wrongly entered payment

*Needs permission: `booking.record_payment`*

1. On the booking card, find the payment under Payment history.
2. Tap the dustbin icon next to it (Delete payment), then confirm with Delete payment.
3. The Due is recalculated. This cannot be undone - record the payment again if needed.

### Make and share the invoice (bill)

*Needs permission: `booking.generate_invoice`*

1. Open the booking card and tap Invoice (on the phone: the printer icon).
2. Choose Share PDF to send the bill as a PDF file (WhatsApp, email and so on), or Share as text to send it as a plain message.
3. Pick the app or contact to send it to.

### Send a WhatsApp payment reminder

1. Open the booking card and tap WhatsApp (on the phone: the share icon).
2. WhatsApp opens with a ready message that names the customer, the event and the Due amount. Tap send in WhatsApp.

### Call the customer

1. On the booking card, tap the phone icon next to the customer's number (Call).

### Record an expense for this event

*Needs permission: `expenses.create`*

1. Open the booking card and tap Record expense (on the phone: the wallet icon).
2. The expense form opens in the Expenses section with the event already filled in. Type the Amount (₹), add a bill photo if you like, and tap Save.
3. The expense then shows on the card under Expenses history.

### Cancel a booking

*Needs permission: `booking.delete`*

1. Open the booking card and tap the red Cancel booking button.
2. Confirm. The booking is marked cancelled and the date becomes free again. It is not deleted - you can still find it.

### Bring back a cancelled booking, or delete it for good

*Needs permission: `booking.edit`*

1. Open the cancelled booking (it shows struck through in the list).
2. Tap the green Restore booking button to make it active again.
3. Or tap Delete permanently to remove it from every device. This cannot be undone.

<a id="record_payment"></a>

## Record payment form

The small form that opens when you tap Record payment on a booking card: Amount, Date, Method and Notes.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/record_payment.html

### Fill in the payment

1. Amount: type the rupees received. The full Due amount is suggested - change it if the customer paid less.
2. Date: today is filled in. Tap it to pick another day.
3. Method: tap one of Cash, UPI, Bank transfer, Cheque, Other.
4. Notes are optional. Tap Save. Tap Cancel to close without saving.

<a id="expenses_home"></a>

## Expenses - list of parties

The Expenses tab is a ledger, person by person (a party is a supplier, worker or anyone you deal with). Each row shows the party and how much You gave or You got. Tap a party to open their ledger.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/expenses_home.html

### Find a party

1. Type the name in the search box at the top (Search by name). *(phone)*
2. Type the name in the search box at the top (Search parties). *(web)*
3. Tap the party row to open their ledger.

### Add a new party (person)

*Needs permission: `expenses.manage_parties`*

1. Tap the round plus button at the bottom right (Add party).
2. Type the Name. Phone (optional) can be typed or picked with Pick from contacts. *(phone)*
3. Type the Name and Phone (optional). *(web)*
4. Answer the business question: Yes if the party is for the business, No if it is a personal expense. Personal parties are kept out of business reports.
5. Tap Save. If a party with that name already exists, the app opens the existing one instead.

### See totals for this month, this year or all time *(Phone app only)*

1. Above the list, tap This month, This year or All time to change the You gave / You got totals.

### Sort the list *(Phone app only)*

1. Tap Sort and choose Last updated, Name (A to Z) or Name (Z to A).

<a id="expenses_ledger"></a>

## Party ledger

All entries with one party, newest first, with the running balance. Two big buttons at the bottom: You gave ₹ (money you paid out) and You got ₹ (money you received). The three-dots on an entry lets you edit or delete it.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/expenses_ledger.html

### Record money given or received

*Needs permission: `expenses.create`*

1. Open the party's ledger from the Expenses list.
2. Tap You gave ₹ (red) if you paid them, or You got ₹ (green) if they paid you.
3. Fill the form (Amount, Date, Notes, bill photo) and tap Save. See the Add expense page.

### Change or delete an entry

*Needs permission: `expenses.edit`*

1. Tap the three-dots on the entry (Entry options).
2. Tap Edit to change the amount, date or notes, then Save.
3. Tap Delete to remove the entry, and confirm. The balance is recalculated.

### See the bill attached to an entry

1. Tap the small bill picture on the entry (Attached invoice). It opens full screen. *(phone)*
2. Tap the attachment chip on the entry. It opens in Google Drive (Opens in Google Drive). *(web)*
3. If the bill says it is waiting to upload, connect your Google account in Settings so bills are saved in Google Drive.

### Open the booking an expense belongs to

1. Entries recorded from a booking card carry an event chip. Tap Show event to jump to that booking.

### Rename or delete the party

*Needs permission: `expenses.manage_parties`*

1. At the top right of the ledger, tap the three-dots (Party options).
2. Tap Edit party to change the name, phone or the business Yes/No answer, then Save.
3. Tap Delete party to remove the party and ALL its entries and bills. This cannot be undone.

<a id="add_expense"></a>

## Add expense (ledger entry form)

The form that opens from You gave ₹ / You got ₹ or from Record expense on a booking card. Type the amount, check the date, and attach the bill photo. Bill photos can be added only on the phone; they are kept in your Google Drive.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/add_expense.html

### Fill in the entry

1. Type the Amount (₹) - numbers only.
2. Date is today; tap it to change.
3. Notes: what the money was for (optional).
4. Tap Save. The entry appears at the top of the ledger.

### Attach a bill photo or PDF

1. Under Attach invoice tap Camera to take a photo now, Gallery to pick a photo from the phone, or PDF to pick a PDF file. *(phone)*
2. Up to 4 files can be attached. Tap the X on a thumbnail to remove it before saving. *(phone)*
3. The first time, the app asks Back up invoices to Google Drive? Tap Connect Google so bills are safe in your Drive, or Later to decide another time. *(phone)*
4. On the web, bills cannot be added - the form says Attach bills from the mobile app. Use the phone for that. *(web)*

<a id="inventory_stock"></a>

## Inventory - current stock

The Inventory tab lists every item with how much is in stock right now. Add or remove stock with Record transaction. The item list (master list) is where item names, units and photos live.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/inventory_stock.html

### Add stock or remove stock (update the count)

*Needs permission: `inventory.create`*

1. Tap the round plus button at the bottom right (Record transaction). *(phone)*
2. Tap the Record transaction button. *(web)*
3. In Item, start typing the name and pick the item from the suggestions. The current stock is shown.
4. Choose Add (stock came in) or Remove (stock was used or sold).
5. Type the Quantity and the Unit price (price for one unit). Notes are optional.
6. Tap Save. You cannot remove more than is in stock.

### Check how much of an item is in stock

1. Type the name in the Search items box at the top. *(phone)*
2. Type the name in the Search items box at the top. *(web)*
3. The row shows the quantity with its unit. Tap the row to see the item's full history.

### Open the item list (master list)

1. At the top right of the Inventory screen, tap the list icon (Item list). Tap it again (Current inventory) to come back. *(phone)*
2. Tap the Master list button at the top of the Inventory page. *(web)*

<a id="inventory_masterlist"></a>

## Item list (master list)

The list of all item names with their unit (pieces, kg, litre…) and photo. Add an item here once; after that you only record transactions for it.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/inventory_masterlist.html

### Add a new item

*Needs permission: `inventory.manage_master_items`*

1. Open the item list (see Inventory - current stock).
2. Tap the round plus button at the bottom right. The form Add item opens. *(phone)*
3. Tap the Add item button. *(web)*
4. Type the Name. If a similar name already exists the app shows Did you mean one of these? - tap the suggestion instead of making a duplicate. *(phone)*
5. Type the Name. If a similar name already exists the app shows Similar items already exist: - pick that instead of making a duplicate. *(web)*
6. Choose the Unit (Pieces, Kg, Litre, Boxes… or Custom to type your own). *(phone)*
7. Choose the Unit (Pieces, Kg, Litre or Custom…). *(web)*
8. Optional: tap Choose photo to add a picture of the item (phone only). *(phone)*
9. Tap Save.

### Change an item's name, unit or photo

*Needs permission: `inventory.manage_master_items`*

1. In the item list, tap the item (or its Edit action).
2. Change the Name, Unit or photo (Remove photo / Choose photo) and tap Save. *(phone)*
3. Change the Name or Unit and tap Save. Photos are changed from the phone (Add photos from the mobile app). *(web)*

### Delete an item

*Needs permission: `inventory.manage_master_items`*

1. Open the item and tap Delete, then confirm.
2. An item that already has transactions cannot be deleted - delete its transactions first from the item page.

<a id="inventory_item"></a>

## Item page (transaction history)

Opens when you tap an item in the stock list: current quantity, total value and every Add / Remove transaction. From here you can fix or delete a transaction, or edit and delete the item.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/inventory_item.html

### Correct or delete a transaction

*Needs permission: `inventory.edit`*

1. Under Transaction history, tap the three-dots on the transaction (Transaction options). *(phone)*
2. Under Transaction history, tap the three-dots on the transaction (Transaction options). *(web)*
3. Tap Edit to change the quantity, price, date or notes, then Save. Tap Delete to remove it and confirm.
4. The stock is recalculated. A change that would make the stock go below zero at any time is refused.

### Edit or delete the item from its page *(Phone app only)*

*Needs permission: `inventory.manage_master_items`*

1. Tap the three-dots at the top right (More options).
2. Tap Edit item or Delete item.

<a id="notes"></a>

## Notes and checklists

Quick notes and tick-off checklists shared with your team. Pinned notes stay at the top. Deleted notes go to Trash for 30 days.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/notes.html

### Write a new note

*Needs permission: `notes.create`*

1. Tap New note at the bottom of the Notes screen.
2. Type a Title and the note text. Optional: pick a Color and Tags. *(phone)*
3. Type a Title and the note text. Optional: pick a Color and Tags. *(web)*
4. Tap Save.

### Make a checklist and tick items off

*Needs permission: `notes.create`*

1. Tap New checklist at the bottom of the Notes screen.
2. Type a Title, then tap Add item for every line you need. Tap Save. *(phone)*
3. Type a Title, then tap Add item for every line you need. Tap Save. *(web)*
4. Later, open the checklist and tap the box next to an item to tick it. When everything is done, tap Mark complete.

### Keep a note at the top (pin)

*Needs permission: `notes.edit`*

1. Open the note and tap Pin. It moves to the Pinned section. Tap Unpin to undo.

### Find a note; see completed notes or the trash

1. Type in the Search notes box - it searches titles, text and tags.
2. Tap the menu lines at the top left (Open notes menu) to switch between Notes, Completed and Trash, or to filter by a tag.

### Delete a note, or bring it back from Trash

*Needs permission: `notes.edit`*

1. Open the note and tap Delete. It moves to Trash and is removed after 30 days.
2. To bring it back, open Trash from the notes menu, open the note and tap Restore. Delete forever removes it at once.

### Share a note

1. Open the note and tap Share. On the phone the share sheet opens (WhatsApp, email…); on the web the text is copied.

### Rename or delete tags

*Needs permission: `notes.edit`*

1. Open the notes menu (top left) and tap Manage tags.
2. Tap Rename tag or Delete tag next to a tag. Deleting a tag never deletes the notes.

<a id="files"></a>

## Files

A shared file cabinet for your business: folders and files (contracts, menus, photos, PDFs) stored in Google Drive and visible to your team. The path at the top (All files › …) shows where you are.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/files.html

### Upload a file

*Needs permission: `files.upload`*

1. Open the folder where the file should go (tap a folder; All files is the top).
2. Tap the round upload button at the bottom right (Upload). *(phone)*
3. Tap the Upload button at the top. *(web)*
4. The first time, the app asks to Connect Google Drive - tap Connect. Files are kept in your Google Drive.
5. Pick one or more files from the phone or computer. Each file must be under 25 MB. A message confirms the upload.

### Save a file received on WhatsApp into Files *(Phone app only)*

*Needs permission: `files.upload`*

1. In WhatsApp (or any app), open the file and tap its share button.
2. Choose Save to Samaroh, then Save to Files.
3. Pick the folder (Save where?) and tap Upload here.

### Make a new folder

*Needs permission: `files.manage_folders`*

1. Open the folder that should contain it, then tap the new-folder icon at the top right (New folder).
2. Type the Folder name and tap Save.

### Open or download a file

1. Tap the file to open it. Pictures open inside the app; other files open in the matching app on the phone.
2. Press and hold the file for more choices: Open, Open in Google Drive, Copy link, Download. *(phone)*
3. Tap the three-dots on the file for more choices: Open, Open in Google Drive, Copy link, Download. *(web)*

### Rename, move or delete a file or folder

*Needs permission: `files.manage_folders`*

1. Press and hold the file or folder (phone) or tap its three-dots (web).
2. Tap Rename file / Rename folder, type the new name and tap Save.
3. Tap Move to…, pick the destination folder (Move where?) and tap Move.
4. Tap Delete file / Delete folder and confirm. It is removed for every member and cannot be undone.

### Allow only some members to open a folder

*Needs permission: `files.manage_folders`*

1. Press and hold the folder (phone) or tap its three-dots (web), then tap Manage access.
2. Choose Everyone with Files access or Only selected members and tick the members. Tap Save. A Restricted badge appears on the folder.

### Search for a file

1. Type part of the name in the Search files and folders box. Results show the folder each file is in.

<a id="menu"></a>

## Menu

Opens from the three-dots button at the top right. Shows who is signed in, then Settings, Reports, Members and About. Sign out is on the identity row at the top.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/menu.html

### What is in the Menu

1. Settings - Language, theme, reminders, backup.
2. Reports - Charts and summaries.
3. Members - Invite staff and set permissions.
4. About - Version and licenses.
5. Help - How to use each screen, step by step. Every task has a Show me button that takes you to the right screen.
6. The Search menu box at the top finds any setting by name.

### Sign out

1. In the Menu, on the row that says Signed in as, tap Sign out.
2. Confirm. Your data stays safe in your account. If some changes have not synced yet, the app warns you - connect to the internet first.

<a id="settings"></a>

## Settings

Menu, then Settings. Language and theme, business profile (name, address, logo), booking form fields, event types, Google account, backup, image quality, reminders and sync status.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/settings.html

### Change the language (English / Hindi)

1. Open Menu, then Settings, then Language.
2. Tap English or हिन्दी. On the phone you can also choose Use device language.

### Light or dark look

1. Open Menu, then Settings, then Theme, and choose Light, Dark or System.

### Change the business name, address or logo

*Needs permission: `settings.manage_business`*

1. Open Menu, then Settings, then Business profile.
2. Edit Business name, Owner name, Address or Invoice prefix and tap Save. These appear on invoices.
3. Tap Change logo to pick a new logo picture (phone only). *(phone)*

### Add or change event types (wedding, birthday…)

*Needs permission: `settings.manage_business`*

1. Open Menu, then Settings, then Event types.
2. Tap the plus button to add (New event type): type the Name, pick an Icon and a Colour. Under Used for choose For bookings, or Just a marker to only mark a day on the calendar.
3. Tap an existing type to edit it. Move up / Move down changes the order in the booking form.

### Connect or disconnect the Google account (Drive, Calendar)

1. Open Menu, then Settings, then Google account.
2. Tap Link Google account and pick your Google account. Bills, item photos and files are then saved in your Google Drive. Tap Unlink to disconnect.
3. Switch on Google Calendar sync to push bookings into Google Calendar as well. *(phone)*

### Back up the data *(Phone app only)*

1. Open Menu, then Settings, then Backup. Tap Back up now.
2. Under Backup frequency choose Daily, Weekly, Monthly or Manual only. Backups go to your Google Drive (connect Google first). Only the owner can back up.

### Booking reminders (notifications) *(Phone app only)*

1. Open Menu, then Settings, then Booking reminders.
2. Choose when to be reminded about upcoming events and pending payments, and the Reminder sound. Allow notifications if the phone asks.

### Check that changes have synced

1. Tap the cloud icon at the top of the screen, or open Menu, then Settings, then Sync status.
2. Everything is synced means all changes are saved to your account. If changes are waiting, connect to the internet and tap Sync now.

<a id="members"></a>

## Members (staff and permissions)

Menu, then Members. Invite staff by email and choose exactly what each person may see and do. Only the owner can manage members.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/members.html

### Invite a staff member

1. Open Menu, then Members, then tap Add member.
2. Type their Email (the one they will sign in with) and a Display name.
3. Under Permissions tick what they may do - for example Booking: view and record payment, but not delete.
4. Tap Add. The member shows as Invited until they sign in with that email, then Active. *(phone)*
5. Tap Save. The member shows as Invited until they sign in with that email, then Active. *(web)*

### Change what a member can do

1. Tap the member. The form Edit member opens.
2. Tick or untick the Permissions and tap Save.

### Remove a member's access (or give it back)

1. Tap the member, then tap Revoke access and confirm. They lose access right away.
2. To give access back later, tap the member and tap Restore access.

<a id="reports"></a>

## Reports

Menu, then Reports. Ten reports: Revenue summary, Outstanding dues, Occupancy, Event types, Booking sources, Expense summary, Profit, Inventory value, Collection speed and Personal expenses. Each has a chart, a table and a date range.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/reports.html

### See who still owes money (and other reports)

1. Open Menu, then Reports.
2. Tap Outstanding dues to see who owes what and for how long. Tap Revenue summary for money collected vs pending by month, or Profit for income minus expenses.

### Change the report dates

1. At the top of the report tap −12 months, −3 months, This month, +3 months or +12 months.
2. Tap Custom to pick your own From and To dates.

### Share or download a report

1. At the bottom of the report tap Share PDF to send it as a document, or Share CSV for a spreadsheet file. *(phone)*
2. Tap Download CSV to save the table as a spreadsheet file. *(web)*

<a id="sign_in"></a>

## Sign in and first-time setup

Sign in with your email and password (or Continue with Google on the phone). New users create an account, then either create a business or join one they were invited to.

Online version: https://itsluminous.github.io/samaroh-shared/help/en/sign_in.html

### Sign in

1. Type your Email and Password and tap Sign in.
2. Or tap Continue with Google and pick your Google account. *(phone)*
3. If you have no account yet, tap New here? Create an account, then Create account.

### Join the business you were invited to *(Phone app only)*

1. Sign in with the SAME email the owner invited.
2. On How would you like to start? tap Join a business, then Accept & join next to the invitation.
3. No invitation shown? Ask the owner to add your email under Members, then tap Check again.
