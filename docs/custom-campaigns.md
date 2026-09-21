# CRY-52: custom campaign and experiment creation

Use the plus button beside Campaigns or R&D Experiments, then select Custom name.
Enter a name and eligible formula. The new record starts with Sublot A and Bag 1;
upload images there or add more sublots/bags through the existing workspace.
Standard creation remains available in the same dialog. The floating add button
has been replaced with the title action on both list pages.

Names are trimmed, single-line, 1–100 Unicode code points. Equal names are allowed.
Production details are omitted in the custom form and are not fabricated in the
backend. List/detail headers show the name alongside the formula. Reports and
normal review, qualification, upload, and locking actions retain existing rules.

Deploy backend migration 035 before this client. New nullable production fields
are accepted for custom records; standard records retain their existing values.
Renaming existing records and adding production metadata later are follow-up
scope decisions, not part of this initial creation flow.
