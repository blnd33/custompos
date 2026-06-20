# Full POS

Offline-first Flutter desktop POS prototype backed by a local SQLite database.

## Current scope

- Offline login with seeded roles, users, and permissions.
- Dashboard for sales, profit, expenses, invoices, low stock, best sellers, cashier sales, and stock value.
- POS selling screen with barcode/name search, cart quantity, discounts, manual price changes, below-cost warning, invoice saving, stock decrease, and price-change logging.
- Product and category storage with existing or generated CODE128 barcodes.
- Inventory adjustments for added stock, reduced stock, damaged items, returned items, and stock history.
- Expenses, expense types, and basic cash drawer opening sessions.
- Offline settings for store, currency, tax, receipt, printers, permissions toggles, low stock, and backup preferences.
- Manual SQLite database backup export.

## Seed logins

- Super Admin: `admin` / `admin123`
- Cashier: `cashier` / `cashier123`

## Run

```powershell
flutter pub get
flutter run -d windows
```

## Build

```powershell
flutter build windows
```

Windows builds require the Visual Studio C++ desktop toolchain. If Flutter reports that no suitable Visual Studio toolchain is available, install the Visual Studio Build Tools workload for desktop C++ development and rerun the build.

## Database

The app stores `full_pos.sqlite` under the platform application support directory. Backups are exported to the user's Documents folder in `Full POS Backups`.

## Later online version

The local SQLite database should remain the working database. Add Laravel API sync and PostgreSQL as backup/reporting/cloud state after the offline workflows are stable.
