import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum AppLanguage { ar, en }

final appLanguage = ValueNotifier<AppLanguage>(AppLanguage.ar);

bool get isArabic => appLanguage.value == AppLanguage.ar;

String tx(String ar, String en) => isArabic ? ar : en;

const brandLogo = 'assets/branding/bangeen_crystal_logo.png';
const scanQrImage = 'assets/branding/scan_me_qr.jpeg';
const brandGold = Color(0xffc99a2e);
const brandDark = Color(0xff100d07);
const brandCream = Color(0xfff6f0e6);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final store = PosStore();
  await store.open();
  runApp(FullPosApp(store: store));
}

class FullPosApp extends StatelessWidget {
  const FullPosApp({super.key, required this.store});

  final PosStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandGold,
      brightness: Brightness.light,
    );
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguage,
      builder: (context, language, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: tx('به نگين كريستال', 'Bangeen Crystal'),
          builder: (context, child) {
            return Directionality(
              textDirection: isArabic
                  ? ui.TextDirection.rtl
                  : ui.TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          theme: ThemeData(
            colorScheme: scheme,
            useMaterial3: true,
            scaffoldBackgroundColor: brandCream,
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: brandGold,
                foregroundColor: Colors.white,
              ),
            ),
            cardTheme: const CardThemeData(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          home: LoginPage(store: store),
        );
      },
    );
  }
}

class PosStore {
  late final Database db;
  String dbPath = '';

  Future<void> open() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    dbPath = p.join(dir.path, 'full_pos.sqlite');
    db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 1, onCreate: _create),
    );
    await _ensureSchema();
    await _seed();
    await _arabizeSeedData();
  }

  Future<void> _ensureSchema() async {
    final categoryColumns = await db.rawQuery('PRAGMA table_info(categories)');
    final hasCategoryImage = categoryColumns.any(
      (column) => column['name'] == 'image_path',
    );
    if (!hasCategoryImage) {
      await db.execute('ALTER TABLE categories ADD COLUMN image_path TEXT');
    }
    final hasCategoryInventoryValue = categoryColumns.any(
      (column) => column['name'] == 'inventory_value',
    );
    if (!hasCategoryInventoryValue) {
      await db.execute(
        'ALTER TABLE categories ADD COLUMN inventory_value REAL NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _create(Database db, int version) async {
    final statements = <String>[
      '''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        role_id INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
      ''',
      'CREATE TABLE roles (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)',
      'CREATE TABLE permissions (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, label TEXT NOT NULL)',
      'CREATE TABLE role_permissions (role_id INTEGER NOT NULL, permission_id INTEGER NOT NULL, PRIMARY KEY(role_id, permission_id))',
      '''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        icon TEXT,
        image_path TEXT,
        inventory_value REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1
      )
      ''',
      '''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER,
        purchase_price REAL NOT NULL,
        selling_price REAL NOT NULL,
        minimum_price REAL,
        stock REAL NOT NULL DEFAULT 0,
        unit_type TEXT NOT NULL DEFAULT 'piece',
        image_path TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        low_stock_alert REAL NOT NULL DEFAULT 5,
        created_at TEXT NOT NULL
      )
      ''',
      'CREATE TABLE product_barcodes (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, barcode TEXT UNIQUE NOT NULL, generated INTEGER NOT NULL DEFAULT 0)',
      '''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT UNIQUE NOT NULL,
        user_id INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        discount_amount REAL NOT NULL,
        total_cost REAL NOT NULL,
        total REAL NOT NULL,
        profit REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        refunded INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
      ''',
      '''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        cost_price REAL NOT NULL,
        discount_amount REAL NOT NULL,
        total REAL NOT NULL
      )
      ''',
      '''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        qty REAL NOT NULL,
        user_id INTEGER NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
      ''',
      'CREATE TABLE expense_types (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)',
      '''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_type_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        receipt_path TEXT,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
      ''',
      '''
      CREATE TABLE cash_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        opening_cash REAL NOT NULL,
        cash_in REAL NOT NULL DEFAULT 0,
        cash_out REAL NOT NULL DEFAULT 0,
        closing_cash REAL,
        expected_cash REAL,
        difference REAL,
        opened_at TEXT NOT NULL,
        closed_at TEXT
      )
      ''',
      '''
      CREATE TABLE price_change_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        original_selling_price REAL NOT NULL,
        cost_price REAL NOT NULL,
        sold_price REAL NOT NULL,
        user_id INTEGER NOT NULL,
        invoice_no TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
      ''',
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      'CREATE TABLE printers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)',
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  Future<void> _seed() async {
    if (firstInt(await db.rawQuery('SELECT COUNT(*) FROM roles'))! > 0) {
      return;
    }
    final roles = [
      'مدير النظام',
      'مالك المتجر',
      'المدير',
      'الكاشير',
      'المحاسب',
      'مسؤول المخزون',
    ];
    for (final role in roles) {
      await db.insert('roles', {'name': role});
    }
    final permissions = {
      'view_dashboard': 'عرض لوحة التحكم',
      'use_pos': 'استخدام نقطة البيع',
      'add_product': 'إضافة منتج',
      'edit_product': 'تعديل منتج',
      'delete_product': 'حذف منتج',
      'change_price': 'تغيير السعر أثناء البيع',
      'give_discount': 'إعطاء خصم',
      'sell_below_cost': 'البيع تحت سعر الكلفة',
      'view_profit': 'عرض الربح',
      'add_expenses': 'إضافة مصروفات',
      'view_reports': 'عرض التقارير المالية',
      'refund_invoice': 'استرجاع فاتورة',
      'open_settings': 'فتح الإعدادات',
    };
    for (final entry in permissions.entries) {
      await db.insert('permissions', {'code': entry.key, 'label': entry.value});
    }
    final allPerms = await db.query('permissions');
    for (final roleId in [1, 2, 3]) {
      for (final perm in allPerms) {
        await db.insert('role_permissions', {
          'role_id': roleId,
          'permission_id': perm['id'],
        });
      }
    }
    final cashierPerms = ['use_pos', 'give_discount'];
    for (final code in cashierPerms) {
      final permId = firstInt(
        await db.rawQuery('SELECT id FROM permissions WHERE code = ?', [code]),
      );
      await db.insert('role_permissions', {
        'role_id': 4,
        'permission_id': permId,
      });
    }
    final stockPerms = ['add_product', 'edit_product'];
    for (final code in stockPerms) {
      // Line 252
      final permId = firstInt(
        await db.rawQuery('SELECT id FROM permissions WHERE code = ?', [code]),
      );
      await db.insert('role_permissions', {
        'role_id': 6,
        'permission_id': permId,
      });
    }
    await db.insert('users', {
      'name': 'مدير النظام',
      'username': 'admin',
      'password': 'admin123',
      'role_id': 1,
    });
    await db.insert('users', {
      'name': 'الكاشير',
      'username': 'cashier',
      'password': 'cashier123',
      'role_id': 4,
    });

    for (final type in [
      'إيجار',
      'رواتب',
      'كهرباء',
      'إنترنت',
      'توصيل',
      'صيانة',
      'تسويق',
      'دفعة مورد',
      'أخرى',
    ]) {
      await db.insert('expense_types', {'name': type});
    }
    final settings = {
      'store_name': 'به نگين كريستال',
      'store_phone': '+964-7514302386',
      'store_address': 'دهوك، اقليم كردستان العراق',
      'currency': 'IQD',
      'tax_enabled': 'false',
      'receipt_size': '80mm',
      'barcode_label_size': '40x30mm',
      'default_printer': 'طابعة ويندوز الافتراضية',
      'allow_discount': 'true',
      'allow_price_change': 'true',
      'allow_below_cost_sale': 'true',
      'require_manager_password_below_cost': 'false',
      'low_stock_alert': '5',
      'auto_backup': 'false',
    };
    for (final entry in settings.entries) {
      await db.insert('settings', {'key': entry.key, 'value': entry.value});
    }
  }

  Future<void> _arabizeSeedData() async {
    Future<void> rename(String table, String from, String to) {
      return db.update(
        table,
        {'name': to},
        where: 'name = ?',
        whereArgs: [from],
      );
    }

    final names = {
      'Super Admin': 'مدير النظام',
      'Cashier': 'الكاشير',
      'Store Owner': 'مالك المتجر',
      'Manager': 'المدير',
      'Accountant': 'المحاسب',
      'Stock Keeper': 'مسؤول المخزون',
    };
    for (final entry in names.entries) {
      await rename('roles', entry.key, entry.value);
      await rename('users', entry.key, entry.value);
    }

    final categories = {
      'Clothes': 'ملابس',
      'Drinks': 'مشروبات',
      'Snacks': 'سناكات',
      'T-shirts': 'تيشيرتات',
      'Water': 'ماء',
    };
    for (final entry in categories.entries) {
      await rename('categories', entry.key, entry.value);
    }

    final products = {
      'Cola Can': 'علبة كولا',
      'Water Bottle': 'قنينة ماء',
      'Local T-shirt': 'تيشيرت محلي',
      'Chips': 'شيبس',
    };
    for (final entry in products.entries) {
      await rename('products', entry.key, entry.value);
    }

    final expenses = {
      'Rent': 'إيجار',
      'Salary': 'رواتب',
      'Electricity': 'كهرباء',
      'Internet': 'إنترنت',
      'Delivery': 'توصيل',
      'Maintenance': 'صيانة',
      'Marketing': 'تسويق',
      'Supplier payment': 'دفعة مورد',
      'Other': 'أخرى',
    };
    for (final entry in expenses.entries) {
      await rename('expense_types', entry.key, entry.value);
    }

    await db.update(
      'settings',
      {'value': 'به نگين كريستال'},
      where: 'key = ? AND value = ?',
      whereArgs: ['store_name', 'Full POS Store'],
    );
    await db.update(
      'settings',
      {'value': 'طابعة ويندوز الافتراضية'},
      where: 'key = ? AND value = ?',
      whereArgs: ['default_printer', 'Windows default printer'],
    );
  }

  Future<void> _seedProduct(
    String name,
    int categoryId,
    String barcode,
    double cost,
    double price,
    double stock,
    String unit,
    bool generated,
  ) async {
    final id = await db.insert('products', {
      'name': name,
      'category_id': categoryId,
      'purchase_price': cost,
      'selling_price': price,
      'minimum_price': cost,
      'stock': stock,
      'unit_type': unit,
      'low_stock_alert': 5,
      'created_at': now(),
    });
    await db.insert('product_barcodes', {
      'product_id': id,
      'barcode': barcode,
      'generated': generated ? 1 : 0,
    });
  }

  Future<UserSession?> login(String username, String password) async {
    final rows = await db.rawQuery(
      '''
      SELECT users.*, roles.name AS role
      FROM users JOIN roles ON roles.id = users.role_id
      WHERE username = ? AND password = ? AND active = 1
    ''',
      [username.trim(), password],
    );
    if (rows.isEmpty) return null;
    final user = rows.first;
    final perms = await db.rawQuery(
      '''
      SELECT permissions.code
      FROM role_permissions
      JOIN permissions ON permissions.id = role_permissions.permission_id
      WHERE role_permissions.role_id = ?
    ''',
      [user['role_id']],
    );
    return UserSession(
      id: user['id'] as int,
      name: user['name'] as String,
      username: user['username'] as String,
      role: user['role'] as String,
      permissions: perms.map((row) => row['code'] as String).toSet(),
    );
  }

  Future<Map<String, Object?>> dashboard() async {
    final start = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final sales = (await db.rawQuery(
      "SELECT COUNT(*) invoices, COALESCE(SUM(total),0) sales, COALESCE(SUM(profit),0) profit FROM sales WHERE refunded = 0 AND date(created_at) = ?",
      [start],
    )).first;
    final expenses = (await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) expenses FROM expenses WHERE date(created_at) = ?",
      [start],
    )).first;
    final lowStock =
        firstInt(
          await db.rawQuery(
            'SELECT COUNT(*) FROM products WHERE active = 1 AND stock <= low_stock_alert',
          ),
        ) ??
        0;
    final stockValue =
        firstInt(
          await db.rawQuery(
            'SELECT CAST(COALESCE(SUM(stock * purchase_price),0) AS INTEGER) FROM products WHERE active = 1',
          ),
        ) ??
        0;
    final categoryStockValue =
        firstInt(
          await db.rawQuery(
            'SELECT CAST(COALESCE(SUM(inventory_value),0) AS INTEGER) FROM categories WHERE active = 1',
          ),
        ) ??
        0;
    final best = await db.rawQuery(
      '''
      SELECT products.name, SUM(sale_items.qty) qty
      FROM sale_items
      JOIN products ON products.id = sale_items.product_id
      JOIN sales ON sales.id = sale_items.sale_id
      WHERE sales.refunded = 0 AND date(sales.created_at) = ?
      GROUP BY products.id
      ORDER BY qty DESC
      LIMIT 5
    ''',
      [start],
    );
    final cashier = await db.rawQuery(
      '''
      SELECT users.name, COALESCE(SUM(sales.total),0) total
      FROM sales JOIN users ON users.id = sales.user_id
      WHERE sales.refunded = 0 AND date(sales.created_at) = ?
      GROUP BY users.id ORDER BY total DESC
    ''',
      [start],
    );
    final categorySales = await db.rawQuery(
      '''
      SELECT categories.name, COALESCE(SUM(sale_items.total),0) total
      FROM sale_items
      JOIN sales ON sales.id = sale_items.sale_id
      JOIN categories ON categories.id = -sale_items.product_id
      WHERE categories.active = 1
        AND sales.refunded = 0
        AND sale_items.product_id < 0
        AND date(sales.created_at) = ?
      GROUP BY categories.id
      ORDER BY total DESC
      LIMIT 5
    ''',
      [start],
    );
    return {
      'sales': sales['sales'] ?? 0,
      'profit': sales['profit'] ?? 0,
      'expenses': expenses['expenses'] ?? 0,
      'net':
          (sales['profit'] as num? ?? 0) - (expenses['expenses'] as num? ?? 0),
      'invoices': sales['invoices'] ?? 0,
      'lowStock': lowStock,
      'stockValue': stockValue + categoryStockValue,
      'best': best,
      'cashier': cashier,
      'categorySales': categorySales,
    };
  }

  Future<List<Map<String, Object?>>> categories() {
    return db.rawQuery('''
      SELECT categories.*,
        (SELECT COUNT(*) FROM products WHERE products.category_id = categories.id AND products.active = 1) AS product_count,
        (
          SELECT COALESCE(SUM(sale_items.total), 0)
          FROM sale_items
          JOIN sales ON sales.id = sale_items.sale_id
          WHERE sales.refunded = 0 AND sale_items.product_id = -categories.id
        ) AS category_sold
      FROM categories
      WHERE categories.active = 1
      ORDER BY categories.name
    ''');
  }

  Future<List<Map<String, Object?>>> categorySalesReport() {
    return db.rawQuery('''
      SELECT categories.id,
             categories.name,
             categories.inventory_value,
             COUNT(DISTINCT CASE WHEN sales.refunded = 0 THEN sales.id END) AS invoices,
             COALESCE(SUM(CASE WHEN sales.refunded = 0 THEN sale_items.qty ELSE 0 END), 0) AS sale_count,
             COALESCE(SUM(CASE WHEN sales.refunded = 0 THEN sale_items.total ELSE 0 END), 0) AS sold_total
      FROM categories
      LEFT JOIN sale_items ON sale_items.product_id = -categories.id
      LEFT JOIN sales ON sales.id = sale_items.sale_id
      WHERE categories.active = 1
      GROUP BY categories.id
      ORDER BY sold_total DESC, categories.name
    ''');
  }

  Future<void> addCategory({
    required String name,
    int? parentId,
    String? icon,
    String? imagePath,
    double inventoryValue = 0,
    bool active = true,
  }) async {
    await db.insert('categories', {
      'name': name,
      'parent_id': parentId,
      'icon': icon,
      'image_path': imagePath,
      'inventory_value': inventoryValue,
      'active': active ? 1 : 0,
    });
  }

  Future<void> updateCategory({
    required int id,
    required String name,
    int? parentId,
    String? icon,
    String? imagePath,
    double inventoryValue = 0,
    bool active = true,
  }) async {
    await db.update(
      'categories',
      {
        'name': name,
        'parent_id': parentId,
        'icon': icon,
        'image_path': imagePath,
        'inventory_value': inventoryValue,
        'active': active ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCategory(int categoryId) async {
    await db.transaction((txn) async {
      await txn.update(
        'categories',
        {'active': 0},
        where: 'id = ?',
        whereArgs: [categoryId],
      );
      await txn.update(
        'products',
        {'active': 0},
        where: 'category_id = ?',
        whereArgs: [categoryId],
      );
    });
  }

  Future<List<Map<String, Object?>>> products([String query = '']) {
    final like = '%${query.trim()}%';
    return db.rawQuery(
      '''
      SELECT products.*, categories.name AS category, product_barcodes.barcode
      FROM products
      LEFT JOIN categories ON categories.id = products.category_id
      LEFT JOIN product_barcodes ON product_barcodes.product_id = products.id
      WHERE products.active = 1 AND (? = '%%' OR products.name LIKE ? OR product_barcodes.barcode LIKE ?)
      GROUP BY products.id
      ORDER BY products.name
    ''',
      [like, like, like],
    );
  }

  Future<Map<String, Object?>?> productByBarcode(String barcode) async {
    final rows = await db.rawQuery(
      '''
      SELECT products.*, product_barcodes.barcode
      FROM product_barcodes JOIN products ON products.id = product_barcodes.product_id
      WHERE product_barcodes.barcode = ? AND products.active = 1
    ''',
      [barcode.trim()],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> addProduct(
    Map<String, Object?> product,
    String barcode,
    bool generated,
  ) async {
    final id = await db.insert('products', {...product, 'created_at': now()});
    await db.insert('product_barcodes', {
      'product_id': id,
      'barcode': barcode,
      'generated': generated ? 1 : 0,
    });
  }

  Future<void> updateProduct(
    int productId,
    Map<String, Object?> product,
    String barcode,
    bool generated,
  ) async {
    await db.transaction((txn) async {
      await txn.update(
        'products',
        product,
        where: 'id = ?',
        whereArgs: [productId],
      );
      await txn.delete(
        'product_barcodes',
        where: 'product_id = ?',
        whereArgs: [productId],
      );
      await txn.insert('product_barcodes', {
        'product_id': productId,
        'barcode': barcode,
        'generated': generated ? 1 : 0,
      });
    });
  }

  Future<void> deleteProduct(int productId) async {
    await db.update(
      'products',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> adjustStock(
    int productId,
    double qty,
    String action,
    int userId,
    String note,
  ) async {
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE products SET stock = stock + ? WHERE id = ?',
        [qty, productId],
      );
      await txn.insert('stock_movements', {
        'product_id': productId,
        'action': action,
        'qty': qty,
        'user_id': userId,
        'note': note,
        'created_at': now(),
      });
    });
  }

  Future<String> completeSale(
    List<CartLine> cart,
    double invoiceDiscount,
    UserSession user, {
    String paymentMethod = 'cash',
  }) async {
    final invoice =
        'INV-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}';
    await db.transaction((txn) async {
      final subtotal = cart.fold<double>(
        0,
        (sum, item) => sum + item.lineSubtotal,
      );
      final totalCost = cart.fold<double>(
        0,
        (sum, item) => sum + item.cost * item.qty,
      );
      final total = max(0, subtotal - invoiceDiscount);
      final profit = total - totalCost;
      final saleId = await txn.insert('sales', {
        'invoice_no': invoice,
        'user_id': user.id,
        'subtotal': subtotal,
        'discount_amount': invoiceDiscount,
        'total_cost': totalCost,
        'total': total,
        'profit': profit,
        'payment_method': paymentMethod,
        'created_at': now(),
      });
      for (final item in cart) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': item.id,
          'qty': item.qty,
          'unit_price': item.soldPrice,
          'cost_price': item.cost,
          'discount_amount': item.discount,
          'total': item.lineSubtotal,
        });
        if (!item.isCategorySale) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [item.qty, item.id],
          );
          await txn.insert('stock_movements', {
            'product_id': item.id,
            'action': 'Sale',
            'qty': -item.qty,
            'user_id': user.id,
            'note': invoice,
            'created_at': now(),
          });
        } else {
          await txn.rawUpdate(
            'UPDATE categories SET inventory_value = MAX(0, inventory_value - ?) WHERE id = ?',
            [item.lineSubtotal, -item.id],
          );
        }
        if (!item.isCategorySale &&
            (item.soldPrice != item.defaultPrice ||
                item.soldPrice < item.cost)) {
          await txn.insert('price_change_logs', {
            'product_id': item.id,
            'product_name': item.name,
            'original_selling_price': item.defaultPrice,
            'cost_price': item.cost,
            'sold_price': item.soldPrice,
            'user_id': user.id,
            'invoice_no': invoice,
            'created_at': now(),
          });
        }
      }
    });
    return invoice;
  }

  Future<Map<String, Object?>> financeSummary() async {
    final sales = (await db.rawQuery('''
      SELECT COUNT(*) invoices,
             COALESCE(SUM(total),0) total_sales,
             COALESCE(SUM(total_cost),0) total_cost,
             COALESCE(SUM(discount_amount),0) discounts,
             COALESCE(AVG(total),0) avg_ticket
      FROM sales
      WHERE refunded = 0
    ''')).first;
    final expenses = (await db.rawQuery(
      'SELECT COALESCE(SUM(amount),0) expenses FROM expenses',
    )).first;
    final returns = (await db.rawQuery(
      'SELECT COUNT(*) count, COALESCE(SUM(total),0) total FROM sales WHERE refunded = 1',
    )).first;
    final categorySales = (await db.rawQuery('''
      SELECT COUNT(DISTINCT sales.id) invoices,
             COALESCE(SUM(sale_items.total),0) total
      FROM sale_items
      JOIN sales ON sales.id = sale_items.sale_id
      WHERE sales.refunded = 0 AND sale_items.product_id < 0
    ''')).first;
    final stockValue =
        firstInt(
          await db.rawQuery(
            'SELECT CAST(COALESCE(SUM(stock * purchase_price),0) AS INTEGER) FROM products WHERE active = 1',
          ),
        ) ??
        0;
    final categoryStockValue =
        firstInt(
          await db.rawQuery(
            'SELECT CAST(COALESCE(SUM(inventory_value),0) AS INTEGER) FROM categories WHERE active = 1',
          ),
        ) ??
        0;
    final lowStock =
        firstInt(
          await db.rawQuery(
            'SELECT COUNT(*) FROM products WHERE active = 1 AND stock <= low_stock_alert',
          ),
        ) ??
        0;
    final totalSales = (sales['total_sales'] as num?)?.toDouble() ?? 0;
    final totalCost = (sales['total_cost'] as num?)?.toDouble() ?? 0;
    final totalExpenses = (expenses['expenses'] as num?)?.toDouble() ?? 0;
    return {
      ...sales,
      'expenses': totalExpenses,
      'gross_profit': totalSales - totalCost,
      'net_profit': totalSales - totalCost - totalExpenses,
      'returns_count': returns['count'] ?? 0,
      'returns_total': returns['total'] ?? 0,
      'category_sales': categorySales['total'] ?? 0,
      'category_invoices': categorySales['invoices'] ?? 0,
      'stock_value': stockValue + categoryStockValue,
      'low_stock': lowStock,
    };
  }

  Future<List<Map<String, Object?>>> salesHistory([String query = '']) {
    final like = '%${query.trim()}%';
    return db.rawQuery(
      '''
      SELECT sales.*, users.name AS cashier
      FROM sales JOIN users ON users.id = sales.user_id
      WHERE ? = '%%' OR sales.invoice_no LIKE ? OR users.name LIKE ?
      ORDER BY sales.created_at DESC
      LIMIT 100
      ''',
      [like, like, like],
    );
  }

  Future<List<Map<String, Object?>>> saleItems(int saleId) {
    return db.rawQuery(
      '''
      SELECT sale_items.*,
             COALESCE(products.name, categories.name) AS product_name,
             COALESCE(products.unit_type, 'category') AS unit_type
      FROM sale_items
      LEFT JOIN products ON products.id = sale_items.product_id
      LEFT JOIN categories ON categories.id = -sale_items.product_id
      WHERE sale_items.sale_id = ?
      ORDER BY sale_items.id
      ''',
      [saleId],
    );
  }

  Future<void> voidSale(int saleId, int userId, String reason) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (rows.isEmpty || rows.first['refunded'] == 1) return;
      final items = await txn.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      for (final item in items) {
        final productId = item['product_id'] as int;
        final qty = (item['qty'] as num).toDouble();
        if (productId > 0) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [qty, productId],
          );
          await txn.insert('stock_movements', {
            'product_id': productId,
            'action': 'Returned',
            'qty': qty,
            'user_id': userId,
            'note': reason,
            'created_at': now(),
          });
        } else {
          await txn.rawUpdate(
            'UPDATE categories SET inventory_value = inventory_value + ? WHERE id = ?',
            [(item['total'] as num).toDouble(), -productId],
          );
        }
      }
      await txn.update(
        'sales',
        {'refunded': 1},
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
  }

  Future<String> exchangeSale(
    int saleId,
    List<CartLine> newCart,
    UserSession user,
  ) async {
    await voidSale(saleId, user.id, 'Exchange');
    return completeSale(newCart, 0, user);
  }

  Future<List<Map<String, Object?>>> expenses() => db.rawQuery('''
    SELECT expenses.*, expense_types.name AS type, users.name AS user
    FROM expenses
    JOIN expense_types ON expense_types.id = expenses.expense_type_id
    JOIN users ON users.id = expenses.user_id
    ORDER BY expenses.created_at DESC LIMIT 100
  ''');

  Future<List<Map<String, Object?>>> expenseTypes() =>
      db.query('expense_types', orderBy: 'name');

  Future<void> addExpense(
    int typeId,
    double amount,
    String note,
    int userId,
  ) async {
    await db.insert('expenses', {
      'expense_type_id': typeId,
      'amount': amount,
      'note': note,
      'user_id': userId,
      'created_at': now(),
    });
  }

  Future<void> openCash(double openingCash, int userId) async {
    await db.insert('cash_sessions', {
      'user_id': userId,
      'opening_cash': openingCash,
      'opened_at': now(),
    });
  }

  Future<void> closeCash(int sessionId, double closingCash) async {
    final row = (await db.rawQuery(
      '''
      SELECT cash_sessions.*, COALESCE(SUM(sales.total),0) cash_sales
      FROM cash_sessions
      LEFT JOIN sales ON sales.user_id = cash_sessions.user_id
        AND sales.created_at >= cash_sessions.opened_at
        AND sales.payment_method = 'cash'
        AND sales.refunded = 0
      WHERE cash_sessions.id = ?
      GROUP BY cash_sessions.id
    ''',
      [sessionId],
    )).first;
    final expected =
        (row['opening_cash'] as num) +
        (row['cash_sales'] as num) +
        (row['cash_in'] as num) -
        (row['cash_out'] as num);
    await db.update(
      'cash_sessions',
      {
        'closing_cash': closingCash,
        'expected_cash': expected,
        'difference': closingCash - expected,
        'closed_at': now(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<Map<String, Object?>>> cashSessions() => db.rawQuery('''
    SELECT cash_sessions.*, users.name AS user
    FROM cash_sessions JOIN users ON users.id = cash_sessions.user_id
    ORDER BY opened_at DESC LIMIT 20
  ''');

  Future<Map<String, String>> settings() async {
    final rows = await db.query('settings');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> saveSetting(String key, String value) => db.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<String> autoPrintReceipt({
    required String invoice,
    required List<CartLine> cart,
    required double invoiceDiscount,
    required UserSession user,
    String paymentMethod = 'cash',
    double? paid,
  }) async {
    final values = await settings();
    final receiptDir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'receipts'),
    );
    await receiptDir.create(recursive: true);
    final receiptPath = p.join(receiptDir.path, '$invoice.txt');
    final textFile = File(receiptPath);
    await textFile.writeAsString(
      _receiptText(
        invoice: invoice,
        cart: cart,
        invoiceDiscount: invoiceDiscount,
        user: user,
        settings: values,
        paymentMethod: paymentMethod,
        paid: paid,
      ),
      flush: true,
    );
    final htmlPath = p.join(receiptDir.path, '$invoice.html');
    await File(htmlPath).writeAsString(
      await _receiptHtml(
        invoice: invoice,
        cart: cart,
        invoiceDiscount: invoiceDiscount,
        user: user,
        settings: values,
        paymentMethod: paymentMethod,
        paid: paid,
      ),
      flush: true,
    );
    if (Platform.isWindows) {
      await Process.start('cmd', [
        '/c',
        'start',
        '',
        htmlPath,
      ], mode: ProcessStartMode.detached);
    }
    return htmlPath;
  }

  Future<void> resetAllData() async {
    await db.transaction((txn) async {
      for (final table in [
        'sale_items',
        'sales',
        'stock_movements',
        'expenses',
        'cash_sessions',
        'price_change_logs',
        'product_barcodes',
        'products',
        'categories',
      ]) {
        await txn.delete(table);
      }
    });
  }

  Future<String> backup() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'Full POS Backups'));
    await backupDir.create(recursive: true);
    final file = File(
      p.join(
        backupDir.path,
        'full_pos_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.sqlite',
      ),
    );
    await File(dbPath).copy(file.path);
    return file.path;
  }

  Future<String> restoreBackup(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw Exception('Backup file not found');
    }
    final safetyBackup = await backup();
    await db.close();
    try {
      await source.copy(dbPath);
      db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 1, onCreate: _create),
      );
      await _ensureSchema();
      return safetyBackup;
    } catch (error) {
      db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 1, onCreate: _create),
      );
      rethrow;
    }
  }
}

String _receiptText({
  required String invoice,
  required List<CartLine> cart,
  required double invoiceDiscount,
  required UserSession user,
  required Map<String, String> settings,
  required String paymentMethod,
  double? paid,
}) {
  final subtotal = cart.fold<double>(0, (sum, item) => sum + item.lineSubtotal);
  final total = max(0, subtotal - invoiceDiscount);
  final paidAmount = paid ?? total;
  final change = max(0, paidAmount - total);
  final storeName = settings['store_name']?.trim().isNotEmpty == true
      ? settings['store_name']!.trim()
      : tx('نظام نقاط البيع', 'Point of Sale');
  final phone = settings['store_phone']?.trim() ?? '';
  final address = settings['store_address']?.trim() ?? '';
  const width = 32;
  String rule(String char) => List.filled(width, char).join();
  String center(String value) => value
      .padLeft(((width - value.length) ~/ 2) + value.length)
      .padRight(width);
  String row(String left, String right) {
    final leftText = left.length > 18 ? left.substring(0, 18) : left;
    final rightText = right.length > 12 ? right.substring(0, 12) : right;
    return leftText.padRight(width - rightText.length) + rightText;
  }

  final lines = <String>[
    center('BANGEEN CRYSTAL'),
    center(storeName),
    if (address.isNotEmpty) center(address),
    if (phone.isNotEmpty) center(phone),
    rule('='),
    row(tx('فاتورة رقم', 'Invoice'), invoice.replaceFirst('INV-', '')),
    row(tx('الكاشير', 'Cashier'), user.name),
    row(
      tx('التاريخ', 'Date'),
      DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
    ),
    rule('='),
    row(tx('الفئة/المادة', 'Item'), tx('الصافي', 'Total')),
    rule('-'),
  ];
  for (final item in cart) {
    lines.add(row(item.name, money(item.lineSubtotal)));
    lines.add(
      row(
        '${tx('الكمية', 'Qty')} ${NumberFormat('#,##0.##').format(item.qty)}',
        '${tx('السعر', 'Price')} ${money(item.soldPrice)}',
      ),
    );
  }
  lines.add(rule('='));
  lines.add(row(tx('المجموع الجزئي', 'Subtotal'), money(subtotal)));
  if (invoiceDiscount > 0) {
    lines.add(row(tx('الخصم', 'Discount'), money(invoiceDiscount)));
  }
  lines.add(rule('#'));
  lines.add(row(tx('الإجمالي', 'TOTAL'), money(total)));
  lines.add(rule('#'));
  lines.add(row(tx('طريقة الدفع', 'Payment'), _paymentLabel(paymentMethod)));
  lines.add(row(tx('المبلغ المستلم', 'Paid'), money(paidAmount)));
  lines.add(row(tx('الباقي', 'Change'), money(change)));
  lines.add(rule('-'));
  lines.add(center(tx('شكرا لزيارتكم', 'Thank you for shopping')));
  lines.add(center('Bangeen Crystal'));
  lines.add(rule('-'));
  lines.add(center('Powered & Developed by'));
  lines.add(center('Coda Agency for ICT Solutions'));
  lines.add(center('+964 750 730 8005'));
  return lines.join('\r\n');
}

Future<String> _receiptHtml({
  required String invoice,
  required List<CartLine> cart,
  required double invoiceDiscount,
  required UserSession user,
  required Map<String, String> settings,
  required String paymentMethod,
  double? paid,
}) async {
  final subtotal = cart.fold<double>(0, (sum, item) => sum + item.lineSubtotal);
  final total = max(0, subtotal - invoiceDiscount);
  final paidAmount = paid ?? total;
  final change = max(0, paidAmount - total);
  final storeName = settings['store_name']?.trim().isNotEmpty == true
      ? settings['store_name']!.trim()
      : tx('به نگين كريستال', 'Bangeen Crystal');
  final phone = settings['store_phone']?.trim() ?? '';
  final address = settings['store_address']?.trim() ?? '';
  // In a Flutter Windows release build, assets live at:
  // {exe_dir}/data/flutter_assets/{asset_path}
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final logoFile = File(p.join(exeDir, 'data', 'flutter_assets', brandLogo));
  final logoSrc = logoFile.existsSync()
      ? 'data:image/png;base64,${base64Encode(await logoFile.readAsBytes())}'
      : '';
  final qrFile = File(p.join(exeDir, 'data', 'flutter_assets', scanQrImage));
  final qrSrc = qrFile.existsSync()
      ? 'data:image/jpeg;base64,${base64Encode(await qrFile.readAsBytes())}'
      : '';
  final dir = isArabic ? 'rtl' : 'ltr';
  final itemRows = cart
      .map(
        (item) =>
            '<tr>'
            '<td>${_html(item.name)}</td>'
            '<td class="num">${NumberFormat('#,##0.##').format(item.qty)}</td>'
            '<td class="amt">${_html(money(item.soldPrice))}</td>'
            '<td class="amt">${_html(money(item.lineSubtotal))}</td>'
            '</tr>',
      )
      .join();

  return '''
<!doctype html>
<html lang="${isArabic ? 'ar' : 'en'}" dir="$dir">
<head>
  <meta charset="utf-8">
  <title>${_html(invoice)}</title>
  <style>
    /* ── screen defaults ── */
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body {
      background: #fff;
      font-family: Arial, Tahoma, 'Segoe UI', sans-serif;
      color: #000;
      font-size: 9.5px;
      font-weight: 600;
      width: 72mm;
      margin: 0;
      padding: 0;
    }
    .receipt {
      width: 72mm;
      max-width: 72mm;
      margin: 0;
      padding: 2mm;
      box-sizing: border-box;
    }
    /* ── header ── */
    .header { text-align: center; padding-bottom: 1.5mm; }
    .logo { width: 26mm; height: 20mm; object-fit: contain; display: block; margin: 0 auto 1.5mm; max-width: 100%; }
    .store-name { font-size: 13px; font-weight: 900; line-height: 1.2; }
    .store-sub { font-size: 8.5px; line-height: 1.4; }
    /* ── dividers ── */
    .dbl { border-top: 3px double #000; margin: 1.5mm 0; }
    .sng { border-top: 1px solid #000; margin: 1mm 0; }
    .dsh { border-top: 1px dashed #000; margin: 1mm 0; }
    /* ── info rows ── */
    .info-row { display: flex; justify-content: space-between; font-size: 9px; line-height: 1.7; }
    .info-row span:last-child { font-weight: 700; }
    /* ── items table ── */
    table { width: 100%; border-collapse: collapse; font-size: 9px; table-layout: fixed; }
    thead tr { border-bottom: 1px solid #000; }
    th { padding: 1mm .5mm; font-size: 8.5px; font-weight: 800; }
    td { padding: .7mm .5mm; vertical-align: top; overflow-wrap: anywhere; word-break: break-word; }
    tbody tr:last-child td { border-bottom: 1px solid #000; }
    .num { text-align: center; }
    .amt { text-align: end; white-space: nowrap; }
    /* ── totals ── */
    .totals { font-size: 9px; }
    .totals .info-row { line-height: 1.8; }
    .total-box {
      border: 2.5px solid #000;
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 1.5mm 2mm;
      margin: 1.5mm 0;
      font-size: 14px;
      font-weight: 900;
    }
    /* ── footer ── */
    .footer { text-align: center; font-size: 8.5px; line-height: 1.6; padding-bottom: 4mm; }
    .footer .thanks { font-size: 10px; font-weight: 900; }
    .qr { width: 18mm; height: 18mm; object-fit: contain; display: block; margin: 1.5mm auto 0; max-width: 100%; height: auto; }
    img { max-width: 100%; height: auto; }
    /* ── print ── */
    @media print {
      @page {
        size: 80mm auto;
        margin: 0;
      }
      html, body {
        width: 72mm;
        margin: 0;
        padding: 0;
        background: #fff;
      }
      .receipt {
        width: 72mm;
        max-width: 72mm;
        margin: 0;
        padding: 2mm;
        box-sizing: border-box;
      }
      table {
        width: 100%;
        border-collapse: collapse;
        table-layout: fixed;
      }
      img {
        max-width: 100%;
        height: auto;
      }
    }
  </style>
  <script>
    window.addEventListener('load', () => {
      setTimeout(() => {
        window.print();
      }, 500);
    });
  </script>
</head>
<body>
<div class="receipt">

  <div class="header">
    ${logoSrc.isEmpty ? '' : '<img class="logo" src="$logoSrc" alt="logo">'}
    <div class="store-name">${_html(storeName)}</div>
    ${address.isNotEmpty ? '<div class="store-sub">${_html(address)}</div>' : ''}
    ${phone.isNotEmpty ? '<div class="store-sub">${_html(phone)}</div>' : ''}
  </div>

  <div class="dbl"></div>

  <div class="info-row"><span>${tx('فاتورة رقم', 'Invoice #')}</span><span>${_html(invoice.replaceFirst('INV-', ''))}</span></div>
  <div class="info-row"><span>${tx('الكاشير', 'Cashier')}</span><span>${_html(user.name)}</span></div>
  <div class="info-row"><span>${tx('التاريخ', 'Date')}</span><span>${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}</span></div>

  <div class="dbl"></div>

  <table>
    <thead>
      <tr>
        <th style="text-align:start">${tx('الصنف', 'Item')}</th>
        <th class="num">${tx('كمية', 'Qty')}</th>
        <th class="amt">${tx('سعر', 'Price')}</th>
        <th class="amt">${tx('المجموع', 'Total')}</th>
      </tr>
    </thead>
    <tbody>
      $itemRows
    </tbody>
  </table>

  <div class="sng"></div>
  <div class="totals">
    <div class="info-row"><span>${tx('المجموع الجزئي', 'Subtotal')}</span><span>${_html(money(subtotal))}</span></div>
    ${invoiceDiscount > 0 ? '<div class="info-row"><span>${tx('الخصم', 'Discount')}</span><span>- ${_html(money(invoiceDiscount))}</span></div>' : ''}
  </div>

  <div class="total-box">
    <span>${tx('الإجمالي', 'TOTAL')}</span>
    <span>${_html(money(total))}</span>
  </div>

  <div class="dsh"></div>
  <div class="info-row"><span>${tx('طريقة الدفع', 'Payment')}</span><span>${_html(_paymentLabel(paymentMethod))}</span></div>
  <div class="info-row"><span>${tx('المبلغ المستلم', 'Paid')}</span><span>${_html(money(paidAmount))}</span></div>
  <div class="info-row"><span>${tx('الباقي', 'Change')}</span><span>${_html(money(change))}</span></div>

  <div class="dbl"></div>

  <div class="footer">
    <div class="thanks">${tx('شكراً لزيارتكم', 'Thank you for shopping!')}</div>
    <div>Bangeen Crystal</div>
    <div class="sng"></div>
    <div>Powered &amp; Developed by</div>
    <div><strong>Coda Agency for ICT Solutions</strong></div>
    <div>+964 750 730 8005</div>
    ${qrSrc.isEmpty ? '' : '<img class="qr" src="$qrSrc" alt="Scan me"><div><strong>SCAN ME</strong></div>'}
  </div>

</div>
</body>
</html>
''';
}

String _html(Object? value) {
  return '$value'
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _paymentLabel(String value) {
  return switch (value) {
    'cash' => tx('نقدا', 'Cash'),
    'card' => tx('بطاقة', 'Card'),
    'debt' => tx('دين', 'Debt'),
    _ => value,
  };
}

class UserSession {
  UserSession({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    required this.permissions,
  });
  final int id;
  final String name;
  final String username;
  final String role;
  final Set<String> permissions;
  bool can(String permission) => permissions.contains(permission);
}

class CartLine {
  CartLine(Map<String, Object?> row)
    : id = row['id'] as int,
      name = row['name'] as String,
      defaultPrice = (row['selling_price'] as num).toDouble(),
      soldPrice = (row['selling_price'] as num).toDouble(),
      cost = (row['purchase_price'] as num).toDouble(),
      stock = (row['stock'] as num).toDouble(),
      unit = row['unit_type'] as String,
      barcode = row['barcode'] as String? ?? '',
      isCategorySale = row['category_sale'] == true;

  final int id;
  final String name;
  final double defaultPrice;
  double soldPrice;
  final double cost;
  final double stock;
  final String unit;
  final String barcode;
  final bool isCategorySale;
  final qtyController = TextEditingController(text: '1');
  double _qty = 1;
  double get qty => _qty;
  set qty(double v) {
    _qty = v;
    final text = v == v.truncateToDouble() ? '${v.toInt()}' : '$v';
    if (qtyController.text != text) qtyController.text = text;
  }
  double discount = 0;
  double get lineSubtotal => max(0, (soldPrice * qty) - discount);
  bool get belowCost => !isCategorySale && soldPrice < cost;
}

String now() => DateTime.now().toIso8601String();

int? firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return null;
  final value = rows.first.values.first;
  return value is int ? value : (value as num?)?.toInt();
}

String _newBarcode() {
  final stamp = DateFormat('yyMMddHHmmss').format(DateTime.now());
  final suffix = Random().nextInt(9000) + 1000;
  return 'FP$stamp$suffix';
}

String money(Object? value, [String currency = 'IQD']) {
  final number = value is num ? value : num.tryParse('$value') ?? 0;
  return '${NumberFormat('#,##0.##').format(number)} $currency';
}

String roleLabel(Object? value) {
  final ar =
      const {
        'Super Admin': 'مدير النظام',
        'Store Owner': 'مالك المتجر',
        'Manager': 'المدير',
        'Cashier': 'الكاشير',
        'Accountant': 'المحاسب',
        'Stock Keeper': 'مسؤول المخزون',
      }['$value'] ??
      '$value';
  if (isArabic) return ar;
  return const {
        'مدير النظام': 'Super Admin',
        'مالك المتجر': 'Store Owner',
        'المدير': 'Manager',
        'الكاشير': 'Cashier',
        'المحاسب': 'Accountant',
        'مسؤول المخزون': 'Stock Keeper',
      }['$value'] ??
      '$value';
}

String unitLabel(Object? value) {
  if (!isArabic) return '$value';
  return const {
        'piece': 'قطعة',
        'box': 'كرتون',
        'kg': 'كغم',
        'liter': 'لتر',
        'category': 'فئة',
      }['$value'] ??
      '$value';
}

String stockActionLabel(Object? value) {
  if (!isArabic) return '$value';
  return const {
        'Stock added': 'إضافة مخزون',
        'Reduce stock': 'تقليل مخزون',
        'Stock adjustment': 'تسوية مخزون',
        'Damaged': 'تالف',
        'Returned': 'مرتجع',
        'Sale': 'بيع',
      }['$value'] ??
      '$value';
}

String expenseTypeLabel(Object? value) {
  final ar =
      const {
        'Rent': 'إيجار',
        'Salary': 'رواتب',
        'Electricity': 'كهرباء',
        'Internet': 'إنترنت',
        'Delivery': 'توصيل',
        'Maintenance': 'صيانة',
        'Marketing': 'تسويق',
        'Supplier payment': 'دفعة مورد',
        'Other': 'أخرى',
      }['$value'] ??
      '$value';
  if (isArabic) return ar;
  return const {
        'إيجار': 'Rent',
        'رواتب': 'Salary',
        'كهرباء': 'Electricity',
        'إنترنت': 'Internet',
        'توصيل': 'Delivery',
        'صيانة': 'Maintenance',
        'تسويق': 'Marketing',
        'دفعة مورد': 'Supplier payment',
        'أخرى': 'Other',
      }['$value'] ??
      '$value';
}

String settingLabel(String key) {
  if (!isArabic) return key.replaceAll('_', ' ');
  return const {
        'store_name': 'اسم المتجر',
        'store_phone': 'هاتف المتجر',
        'store_address': 'عنوان المتجر',
        'currency': 'العملة',
        'tax_enabled': 'تفعيل الضريبة',
        'receipt_size': 'حجم الوصل',
        'barcode_label_size': 'حجم ملصق الباركود',
        'default_printer': 'الطابعة الافتراضية',
        'allow_discount': 'السماح بالخصم',
        'allow_price_change': 'السماح بتغيير السعر',
        'allow_below_cost_sale': 'السماح بالبيع تحت الكلفة',
        'require_manager_password_below_cost':
            'طلب كلمة مرور المدير للبيع تحت الكلفة',
        'low_stock_alert': 'تنبيه انخفاض المخزون',
        'auto_backup': 'نسخ احتياطي تلقائي',
      }[key] ??
      key.replaceAll('_', ' ');
}

Widget optionalPhoto(String? path, {double size = 48}) {
  if (path == null || path.trim().isEmpty || !File(path).existsSync()) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xffe9efec),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.image_outlined, size: 20),
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.file(File(path), width: size, height: size, fit: BoxFit.cover),
  );
}

Widget optionalProductImage(String? path) {
  if (path == null || path.trim().isEmpty || !File(path).existsSync()) {
    return Container(
      color: const Color(0xffe4ece8),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 34),
    );
  }
  return Image.file(File(path), width: double.infinity, fit: BoxFit.cover);
}

Future<String?> choosePhoto(BuildContext context) async {
  try {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
        ),
      ],
    );
    return file?.path;
  } catch (error) {
    if (!context.mounted) return null;
    return showDialog<String?>(
      context: context,
      builder: (_) => ManualPhotoPathDialog(error: '$error'),
    );
  }
}

class ManualPhotoPathDialog extends StatefulWidget {
  const ManualPhotoPathDialog({super.key, required this.error});
  final String error;

  @override
  State<ManualPhotoPathDialog> createState() => _ManualPhotoPathDialogState();
}

class _ManualPhotoPathDialogState extends State<ManualPhotoPathDialog> {
  final path = TextEditingController();
  String message = '';

  void submit() {
    final value = path.text.trim();
    if (value.isEmpty) {
      Navigator.pop(context);
      return;
    }
    if (!File(value).existsSync()) {
      setState(() => message = 'This file path does not exist');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختيار الصورة غير متاح'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'لم يفتح ويندوز نافذة اختيار الملفات. الصق مسار الصورة بدلا من ذلك.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: path,
              decoration: const InputDecoration(
                labelText: 'مسار الصورة',
                hintText: r'C:\Users\rand\Pictures\product.jpg',
              ),
              onSubmitted: (_) => submit(),
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 10),
            Text(
              widget.error,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: submit, child: const Text('استخدام المسار')),
      ],
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.store});
  final PosStore store;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController(text: 'admin123');
  String error = '';

  Future<void> submit() async {
    final user = await widget.store.login(username.text, password.text);
    if (!mounted) return;
    if (user == null) {
      setState(
        () => error = tx(
          'اسم المستخدم أو كلمة المرور غير صحيحة',
          'Invalid username or password',
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => Shell(store: widget.store, user: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      brandLogo,
                      width: 170,
                      height: 130,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tx('به نگين كريستال', 'Bangeen Crystal'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: brandGold,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        appLanguage.value = isArabic
                            ? AppLanguage.en
                            : AppLanguage.ar;
                      },
                      icon: const Icon(Icons.language),
                      label: Text(tx('English', 'العربية')),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tx('نظام نقطة البيع', 'Point of sale system'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: username,
                    decoration: InputDecoration(
                      labelText: tx('اسم المستخدم', 'Username'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    decoration: InputDecoration(
                      labelText: tx('كلمة المرور', 'Password'),
                    ),
                    obscureText: true,
                    onSubmitted: (_) => submit(),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: submit,
                    icon: const Icon(Icons.login),
                    label: Text(tx('تسجيل الدخول', 'Login')),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tx(
                      'حسابات جاهزة: admin/admin123 و cashier/cashier123',
                      'Seed users: admin/admin123 and cashier/cashier123',
                    ),
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.store, required this.user});
  final PosStore store;
  final UserSession user;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  List<String> get labels => [
    tx('لوحة التحكم', 'Dashboard'),
    tx('نقطة البيع', 'POS'),
    tx('بيع الفئات', 'Cat POS'),
    tx('المنتجات', 'Products'),
    tx('الفئات', 'Categories'),
    tx('المخزون', 'Inventory'),
    tx('المالية', 'Finance'),
    tx('الإعدادات', 'Settings'),
    tx('النسخ الاحتياطي', 'Backup'),
  ];
  final icons = const [
    Icons.dashboard,
    Icons.point_of_sale,
    Icons.grid_view,
    Icons.inventory_2,
    Icons.category,
    Icons.warehouse,
    Icons.payments,
    Icons.settings,
    Icons.backup,
  ];

  void logout() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginPage(store: widget.store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(store: widget.store),
      PosPage(store: widget.store, user: widget.user),
      CatPosPage(store: widget.store, user: widget.user),
      ProductsPage(store: widget.store),
      CategoriesPage(store: widget.store),
      InventoryPage(store: widget.store, user: widget.user),
      FinancePage(store: widget.store, user: widget.user),
      SettingsPage(store: widget.store),
      BackupPage(store: widget.store),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: brandDark,
            selectedIconTheme: const IconThemeData(color: brandGold),
            unselectedIconTheme: const IconThemeData(color: Color(0xffd8d0c2)),
            selectedLabelTextStyle: const TextStyle(
              color: brandGold,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelTextStyle: const TextStyle(color: Color(0xffd8d0c2)),
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    brandLogo,
                    width: 72,
                    height: 58,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  PopupMenuButton<String>(
                    tooltip: tx('قائمة المستخدم', 'User menu'),
                    onSelected: (value) {
                      if (value == 'logout') logout();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(roleLabel(widget.user.role)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'logout',
                        child: Row(
                          children: [
                            const Icon(Icons.logout),
                            const SizedBox(width: 10),
                            Text(tx('تسجيل الخروج', 'Logout')),
                          ],
                        ),
                      ),
                    ],
                    child: CircleAvatar(
                      backgroundColor: brandGold,
                      foregroundColor: Colors.white,
                      child: Text(widget.user.name.characters.first),
                    ),
                  ),
                ],
              ),
            ),
            destinations: [
              for (var i = 0; i < labels.length; i++)
                NavigationRailDestination(
                  icon: Icon(icons[i]),
                  label: Text(labels[i]),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.centerLeft,
                  decoration: const BoxDecoration(color: Colors.white),
                  child: Row(
                    children: [
                      Text(
                        labels[index],
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${widget.user.name} • ${roleLabel(widget.user.role)}',
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          appLanguage.value = isArabic
                              ? AppLanguage.en
                              : AppLanguage.ar;
                          setState(() {});
                        },
                        icon: const Icon(Icons.language),
                        label: Text(tx('English', 'العربية')),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: pages[index]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.store});
  final PosStore store;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>>(
      future: store.dashboard(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '${tx('خطأ في لوحة التحكم', 'Dashboard error')}:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final d = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Metric(
                  tx('مبيعات اليوم', 'Today sales'),
                  money(d['sales']),
                  Icons.sell,
                ),
                Metric(
                  tx('ربح اليوم', 'Today profit'),
                  money(d['profit']),
                  Icons.trending_up,
                ),
                Metric(
                  tx('مصروفات اليوم', 'Today expenses'),
                  money(d['expenses']),
                  Icons.receipt_long,
                ),
                Metric(
                  tx('صافي الربح', 'Net profit'),
                  money(d['net']),
                  Icons.account_balance_wallet,
                ),
                Metric(
                  tx('الفواتير', 'Invoices'),
                  '${d['invoices']}',
                  Icons.description,
                ),
                Metric(
                  tx('مخزون منخفض', 'Low stock'),
                  '${d['lowStock']}',
                  Icons.warning_amber,
                ),
                Metric(
                  tx('قيمة المخزون', 'Stock value'),
                  money(d['stockValue']),
                  Icons.inventory,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SimpleList(
                    title: tx('الأكثر مبيعا', 'Best selling items'),
                    rows: d['best'] as List<Map<String, Object?>>,
                    valueKeyName: 'qty',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SimpleList(
                    title: tx('مبيعات الكاشير', 'Cashier sales'),
                    rows: d['cashier'] as List<Map<String, Object?>>,
                    valueKeyName: 'total',
                    formatMoney: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SimpleList(
                    title: tx('مبيعات الفئات', 'Category sales'),
                    rows: d['categorySales'] as List<Map<String, Object?>>,
                    valueKeyName: 'total',
                    formatMoney: true,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class Metric extends StatelessWidget {
  const Metric(this.title, this.value, this.icon, {super.key});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 104,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SimpleList extends StatelessWidget {
  const SimpleList({
    super.key,
    required this.title,
    required this.rows,
    required this.valueKeyName,
    this.formatMoney = false,
  });
  final String title;
  final List<Map<String, Object?>> rows;
  final String valueKeyName;
  final bool formatMoney;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (rows.isEmpty) Text(tx('لا توجد بيانات بعد', 'No data yet')),
            for (final row in rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${row['name']}'),
                trailing: Text(
                  formatMoney
                      ? money(row[valueKeyName])
                      : '${row[valueKeyName]}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.store, required this.user});
  final PosStore store;
  final UserSession user;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final search = TextEditingController();
  final discount = TextEditingController(text: '0');
  List<Map<String, Object?>> products = [];
  final cart = <CartLine>[];
  String warning = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    products = await widget.store.products(search.text);
    if (mounted) setState(() {});
  }

  void add(Map<String, Object?> product) {
    final existing = cart.where((item) => item.id == product['id']).firstOrNull;
    setState(() {
      if (existing == null) {
        cart.add(CartLine(product));
      } else {
        existing.qty += 1;
      }
    });
  }

  Future<void> scan(String value) async {
    final product = await widget.store.productByBarcode(value);
    if (!mounted) return;
    if (product == null) {
      setState(
        () => warning = tx(
          'لم يتم العثور على الباركود: $value',
          'Barcode not found: $value',
        ),
      );
      return;
    }
    warning = '';
    add(product);
    search.clear();
    await load();
  }

  Future<void> complete() async {
    if (cart.isEmpty) return;
    final below = cart.where((item) => item.belowCost).toList();
    if (below.isNotEmpty) {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(tx('تحذير البيع تحت الكلفة', 'Below cost warning')),
          content: Text(
            tx(
              'تحذير: ${below.map((e) => e.name).join(', ')} يباع تحت سعر الكلفة. سيتم حفظ العملية في سجل تغيير الأسعار.',
              'Warning: ${below.map((e) => e.name).join(', ')} is being sold below cost price. The sale will be saved in the price-change log.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tx('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tx('متابعة', 'Continue')),
            ),
          ],
        ),
      );
      if (allowed != true) return;
    }
    final invoice = await widget.store.completeSale(
      cart,
      double.tryParse(discount.text) ?? 0,
      widget.user,
    );
    String? receiptPath;
    try {
      receiptPath = await widget.store.autoPrintReceipt(
        invoice: invoice,
        cart: List<CartLine>.from(cart),
        invoiceDiscount: double.tryParse(discount.text) ?? 0,
        user: widget.user,
      );
    } catch (error) {
      receiptPath = null;
      warning = tx(
        'تم حفظ الفاتورة لكن فشلت الطباعة: $error',
        'Invoice saved, but printing failed: $error',
      );
    }
    if (!mounted) return;
    setState(() {
      cart.clear();
      discount.text = '0';
    });
    await load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tx(
            receiptPath == null
                ? 'تم حفظ الفاتورة $invoice.'
                : 'تم حفظ الفاتورة $invoice وإرسال الوصل للطباعة.',
            receiptPath == null
                ? 'Invoice $invoice saved.'
                : 'Invoice $invoice saved and receipt sent to printer.',
          ),
        ),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final invoiceDiscount = double.tryParse(discount.text) ?? 0;
    final subtotal = cart.fold<double>(
      0,
      (sum, item) => sum + item.lineSubtotal,
    );
    final total = max(0, subtotal - invoiceDiscount);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: search,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: tx(
                      'ابحث بالاسم أو امسح الباركود',
                      'Search name or scan barcode',
                    ),
                  ),
                  onChanged: (_) => load(),
                  onSubmitted: scan,
                ),
                if (warning.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      warning,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 230,
                          mainAxisExtent: 220,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: products.length,
                    itemBuilder: (_, i) {
                      final product = products[i];
                      return Card(
                        child: InkWell(
                          onTap: () => add(product),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: optionalProductImage(
                                        product['image_path'] as String?,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${product['name']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${tx('المخزون', 'Stock')}: ${product['stock']} ${unitLabel(product['unit_type'])}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  money(product['selling_price']),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 460,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tx('السلة', 'Cart'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (_, i) {
                      final item = cart[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        setState(() => cart.removeAt(i)),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 84,
                                    child: TextFormField(
                                      controller: item.qtyController,
                                      decoration: InputDecoration(
                                        labelText: tx('الكمية', 'Qty'),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) => setState(
                                        () =>
                                            item._qty = double.tryParse(v) ?? 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 118,
                                    child: TextFormField(
                                      initialValue: '${item.soldPrice}',
                                      decoration: InputDecoration(
                                        labelText: tx('السعر', 'Price'),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) => setState(
                                        () => item.soldPrice =
                                            double.tryParse(v) ??
                                            item.defaultPrice,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 102,
                                    child: TextFormField(
                                      initialValue: '${item.discount}',
                                      decoration: InputDecoration(
                                        labelText: tx('الخصم', 'Discount'),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) => setState(
                                        () => item.discount =
                                            double.tryParse(v) ?? 0,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    money(item.lineSubtotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              if (item.belowCost)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    tx(
                                      'تحذير: السعر تحت الكلفة',
                                      'Warning: below cost price',
                                    ),
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                TextField(
                  controller: discount,
                  decoration: InputDecoration(
                    labelText: tx(
                      'خصم الفاتورة بالمبلغ',
                      'Invoice discount by money',
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text('${tx('المجموع الفرعي', 'Subtotal')}: ${money(subtotal)}'),
                Text(
                  '${tx('الإجمالي', 'Total')}: ${money(total)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: complete,
                  icon: const Icon(Icons.check_circle),
                  label: Text(tx('إتمام البيع', 'Complete sale')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CatPosPage extends StatefulWidget {
  const CatPosPage({super.key, required this.store, required this.user});
  final PosStore store;
  final UserSession user;

  @override
  State<CatPosPage> createState() => _CatPosPageState();
}

class _CatPosPageState extends State<CatPosPage> {
  final discount = TextEditingController(text: '0');
  final paid = TextEditingController(text: '0');
  final categoryScroll = ScrollController();
  final cart = <CartLine>[];
  List<Map<String, Object?>> categories = [];
  Map<String, Object?>? selectedCategory;
  String amountText = '0';
  String message = '';
  String paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    categoryScroll.dispose();
    discount.dispose();
    paid.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final rows = await widget.store.categories();
    categories = rows.where((row) => row['active'] == 1).toList();
    selectedCategory = categories.isEmpty ? null : categories.first;
    if (mounted) setState(() {});
  }

  void pressDigit(String digit) {
    setState(() {
      message = '';
      if (amountText == '0') {
        amountText = digit;
      } else if (amountText.length < 7) {
        amountText += digit;
      }
    });
  }

  void backspace() {
    setState(() {
      message = '';
      if (amountText.length <= 1) {
        amountText = '0';
      } else {
        amountText = amountText.substring(0, amountText.length - 1);
      }
    });
  }

  void addCategoryAmount() {
    final category = selectedCategory;
    final units = int.tryParse(amountText) ?? 0;
    if (category == null) {
      setState(
        () => message = tx(
          'أضف أو فعّل فئة واحدة على الأقل أولا.',
          'Add or activate at least one category first.',
        ),
      );
      return;
    }
    if (units <= 0) {
      setState(
        () => message = tx(
          'أدخل رقما أولا. مثال: 5 ثم X = 5,000 د.ع.',
          'Enter a number first. Example: 5 then X = 5,000 IQD.',
        ),
      );
      return;
    }
    final amount = units * 1000.0;
    final categoryId = category['id'] as int;
    final available = (category['inventory_value'] as num?)?.toDouble() ?? 0;
    final inCart = cart
        .where((item) => item.isCategorySale && item.id == -categoryId)
        .fold<double>(0, (sum, item) => sum + item.lineSubtotal);
    if (available > 0 && inCart + amount > available) {
      setState(
        () => message = tx(
          'قيمة مخزون هذه الفئة غير كافية.',
          'This category inventory value is not enough.',
        ),
      );
      return;
    }
    final name = '${category['name']}';
    setState(() {
      cart.add(
        CartLine({
          'id': -categoryId,
          'name': name,
          'selling_price': amount,
          'purchase_price': 0,
          'stock': 0,
          'unit_type': 'category',
          'barcode': '',
          'category_sale': true,
        }),
      );
      amountText = '0';
      paid.text = '${max(total, amount)}';
      message = '';
    });
  }

  Future<void> complete() async {
    if (cart.isEmpty) return;
    final categorySold = <int, double>{};
    for (final item in cart) {
      if (item.isCategorySale) {
        final categoryId = -item.id;
        categorySold[categoryId] =
            (categorySold[categoryId] ?? 0) + item.lineSubtotal;
      }
    }
    final invoice = await widget.store.completeSale(
      cart,
      double.tryParse(discount.text) ?? 0,
      widget.user,
      paymentMethod: paymentMethod,
    );
    String? receiptPath;
    try {
      receiptPath = await widget.store.autoPrintReceipt(
        invoice: invoice,
        cart: List<CartLine>.from(cart),
        invoiceDiscount: double.tryParse(discount.text) ?? 0,
        user: widget.user,
        paymentMethod: paymentMethod,
        paid: double.tryParse(paid.text),
      );
    } catch (error) {
      receiptPath = null;
      message = tx(
        'تم حفظ الفاتورة لكن فشلت الطباعة: $error',
        'Invoice saved, but printing failed: $error',
      );
    }
    if (!mounted) return;
    setState(() {
      categories = [
        for (final category in categories)
          if (categorySold.containsKey(category['id']))
            {
              ...category,
              'inventory_value': max(
                0,
                ((category['inventory_value'] as num?)?.toDouble() ?? 0) -
                    categorySold[category['id']]!,
              ),
            }
          else
            category,
      ];
      if (selectedCategory != null) {
        final selectedId = selectedCategory!['id'];
        selectedCategory = categories.firstWhere(
          (category) => category['id'] == selectedId,
          orElse: () => selectedCategory!,
        );
      }
      cart.clear();
      amountText = '0';
      discount.text = '0';
      paid.text = '0';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tx(
            receiptPath == null
                ? 'تم حفظ فاتورة الفئة $invoice.'
                : 'تم حفظ فاتورة الفئة $invoice وإرسال الوصل للطباعة.',
            receiptPath == null
                ? 'Category invoice $invoice saved.'
                : 'Category invoice $invoice saved and receipt sent to printer.',
          ),
        ),
      ),
    );
    await load();
  }

  double get subtotal =>
      cart.fold<double>(0, (sum, item) => sum + item.lineSubtotal);
  double get total => max(0, subtotal - (double.tryParse(discount.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xffc99527);
    final amount = (int.tryParse(amountText) ?? 0) * 1000;
    return Container(
      color: const Color(0xffeeeae4),
      child: Row(
        children: [
          SizedBox(
            width: 430,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: _CategoryCartPanel(
                      cart: cart,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(tx('خصم الفاتورة', 'Invoice discount')),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: discount,
                                  decoration: const InputDecoration(
                                    suffixText: 'IQD',
                                  ),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.end,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${tx('المجموع الفرعي', 'Subtotal')}: ${money(subtotal)}',
                          ),
                          Text(
                            '${tx('الإجمالي', 'Total')}: ${money(total)}',
                            style: TextStyle(
                              color: accent,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<String>(
                            segments: [
                              ButtonSegment(
                                value: 'cash',
                                label: Text(tx('نقدا', 'Cash')),
                              ),
                              ButtonSegment(
                                value: 'card',
                                label: Text(tx('بطاقة', 'Card')),
                              ),
                              ButtonSegment(
                                value: 'debt',
                                label: Text(tx('دين', 'Debt')),
                              ),
                            ],
                            selected: {paymentMethod},
                            onSelectionChanged: (value) =>
                                setState(() => paymentMethod = value.first),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: paid,
                            decoration: InputDecoration(
                              labelText: tx('المدفوع', 'Paid'),
                              suffixText: 'IQD',
                            ),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.end,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: cart.isEmpty ? null : complete,
                            icon: const Icon(Icons.check_circle),
                            label: Text(tx('إتمام البيع', 'Complete sale')),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(54),
                            ),
                          ),
                          TextButton(
                            onPressed: cart.isEmpty
                                ? null
                                : () => setState(() {
                                    cart.clear();
                                    paid.text = '0';
                                  }),
                            child: Text(tx('مسح الكل', 'Clear all')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Text(
                        tx('اختر الفئة', 'Choose category'),
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 126,
                    child: Scrollbar(
                      controller: categoryScroll,
                      thumbVisibility: true,
                      trackVisibility: true,
                      interactive: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ListView.separated(
                          controller: categoryScroll,
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          itemBuilder: (_, i) {
                            final category = categories[i];
                            final selected =
                                selectedCategory?['id'] == category['id'];
                            final colors = [
                              const Color(0xffe67e22),
                              const Color(0xffc0392b),
                              const Color(0xff8e44ad),
                              const Color(0xff27ae60),
                              accent,
                              const Color(0xff2874a6),
                            ];
                            return SizedBox(
                              width: 150,
                              child: Card(
                                color: selected
                                    ? const Color(0xfffff7df)
                                    : Colors.white,
                                child: InkWell(
                                  onTap: () => setState(
                                    () => selectedCategory = category,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            colors[i % colors.length],
                                        radius: 18,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        '${category['name']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        money(category['inventory_value']),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xff7a6a52),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemCount: categories.length,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                            height: 76,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: const Color(0xfff2eee8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              money(amount),
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final row in const [
                            ['7', '8', '9'],
                            ['4', '5', '6'],
                            ['1', '2', '3'],
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  for (final digit in row)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: OutlinedButton(
                                          onPressed: () => pressDigit(digit),
                                          child: Text(
                                            digit,
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: OutlinedButton(
                                    onPressed: () => pressDigit('0'),
                                    child: const Text(
                                      '0',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: OutlinedButton.icon(
                                    onPressed: backspace,
                                    icon: const Icon(Icons.backspace_outlined),
                                    label: const Text(''),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      backgroundColor: const Color(0xffffeeee),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: addCategoryAmount,
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(62),
                            ),
                            child: Text(
                              tx('اضغط  X', 'PRESS  X'),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            tx(
                              'الرقم × 1,000 د.ع. مثال: اضغط 5 ثم X = 5,000 د.ع.',
                              'Number x 1,000 IQD. Example: press 5 then X = 5,000 IQD.',
                            ),
                            style: TextStyle(color: Colors.brown.shade500),
                          ),
                          if (message.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                message,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCartPanel extends StatelessWidget {
  const _CategoryCartPanel({required this.cart, required this.onChanged});
  final List<CartLine> cart;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tx('السلة', 'Cart'),
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const Divider(height: 24),
            Expanded(
              child: cart.isEmpty
                  ? Center(child: Text(tx('السلة فارغة', 'Cart is empty')))
                  : ListView.separated(
                      itemCount: cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = cart[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            tx('بيع مبلغ على الفئة', 'Category amount sale'),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                money(item.lineSubtotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  cart.removeAt(i);
                                  onChanged();
                                },
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.store});
  final PosStore store;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.store.products();
    if (mounted) setState(() {});
  }

  Future<void> addProduct() async {
    final result = await showDialog<Map<String, Object?>?>(
      context: context,
      builder: (_) => ProductDialog(store: widget.store),
    );
    if (result == null) return;
    final barcode = result.remove('barcode') as String;
    final generated = result.remove('generated') as bool;
    await widget.store.addProduct(result, barcode, generated);
    await load();
  }

  Future<void> editProduct(Map<String, Object?> row) async {
    final result = await showDialog<Map<String, Object?>?>(
      context: context,
      builder: (_) => ProductDialog(store: widget.store, product: row),
    );
    if (result == null) return;
    final barcode = result.remove('barcode') as String;
    final generated = result.remove('generated') as bool;
    await widget.store.updateProduct(
      row['id'] as int,
      result,
      barcode,
      generated,
    );
    await load();
  }

  Future<void> deleteProduct(Map<String, Object?> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tx('حذف المنتج', 'Delete product')),
        content: Text(
          tx(
            'سيتم إخفاء هذا المنتج من شاشة البيع مع حفظ الفواتير القديمة.',
            'This product will be hidden from sale screens while old invoices stay saved.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tx('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: Text(tx('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.deleteProduct(row['id'] as int);
    await load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              FilledButton.icon(
                onPressed: addProduct,
                icon: const Icon(Icons.add),
                label: Text(tx('منتج', 'Product')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: ListView(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(tx('الصورة', 'Photo'))),
                        DataColumn(label: Text(tx('المنتج', 'Product'))),
                        DataColumn(label: Text(tx('الفئة', 'Category'))),
                        DataColumn(label: Text(tx('الباركود', 'Barcode'))),
                        DataColumn(label: Text(tx('الكلفة', 'Cost'))),
                        DataColumn(label: Text(tx('السعر', 'Price'))),
                        DataColumn(label: Text(tx('المخزون', 'Stock'))),
                        DataColumn(label: Text(tx('إجراء', 'Action'))),
                      ],
                      rows: [
                        for (final row in rows)
                          DataRow(
                            cells: [
                              DataCell(
                                optionalPhoto(row['image_path'] as String?),
                              ),
                              DataCell(Text('${row['name']}')),
                              DataCell(Text('${row['category'] ?? ''}')),
                              DataCell(Text('${row['barcode'] ?? ''}')),
                              DataCell(Text(money(row['purchase_price']))),
                              DataCell(Text(money(row['selling_price']))),
                              DataCell(
                                Text(
                                  '${row['stock']} ${unitLabel(row['unit_type'])}',
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () => editProduct(row),
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: tx(
                                        'تعديل المنتج',
                                        'Edit product',
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => deleteProduct(row),
                                      icon: const Icon(Icons.delete_outline),
                                      color: Colors.red,
                                      tooltip: tx(
                                        'حذف المنتج',
                                        'Delete product',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductDialog extends StatefulWidget {
  const ProductDialog({super.key, required this.store, this.product});
  final PosStore store;
  final Map<String, Object?>? product;

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final name = TextEditingController();
  final barcode = TextEditingController();
  final cost = TextEditingController();
  final price = TextEditingController();
  final stock = TextEditingController(text: '0');
  final low = TextEditingController(text: '5');
  String unit = 'piece';
  String? imagePath;
  int? categoryId;
  bool generated = false;
  List<Map<String, Object?>> categories = [];

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product != null) {
      name.text = '${product['name'] ?? ''}';
      barcode.text = '${product['barcode'] ?? ''}';
      cost.text = '${product['purchase_price'] ?? 0}';
      price.text = '${product['selling_price'] ?? 0}';
      stock.text = '${product['stock'] ?? 0}';
      low.text = '${product['low_stock_alert'] ?? 5}';
      unit = '${product['unit_type'] ?? 'piece'}';
      imagePath = product['image_path'] as String?;
      categoryId = product['category_id'] as int?;
    }
    widget.store.categories().then(
      (value) => setState(
        () => categories = value
            .where((category) => (category['active'] as int? ?? 1) == 1)
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.product == null
            ? tx('إضافة منتج', 'Add product')
            : tx('تعديل المنتج', 'Edit product'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: tx('اسم المنتج', 'Product name'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  optionalPhoto(imagePath, size: 64),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      imagePath == null || imagePath!.isEmpty
                          ? tx(
                              'لم يتم اختيار صورة للمنتج',
                              'No product photo selected',
                            )
                          : imagePath!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await choosePhoto(context);
                      if (selected != null) {
                        setState(() => imagePath = selected);
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('صورة'),
                  ),
                  IconButton(
                    onPressed: imagePath == null
                        ? null
                        : () => setState(() => imagePath = null),
                    icon: const Icon(Icons.close),
                    tooltip: 'حذف الصورة',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: categoryId,
                decoration: const InputDecoration(labelText: 'الفئة'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text('${c['name']}'),
                    ),
                ],
                onChanged: (v) => setState(() => categoryId = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: barcode,
                      decoration: const InputDecoration(
                        labelText: 'باركود موجود أو مولد',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      barcode.text = _newBarcode();
                      generated = true;
                    }),
                    icon: const Icon(Icons.qr_code_2),
                    tooltip: 'توليد باركود CODE128',
                  ),
                ],
              ),
              if (barcode.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: barcode.text,
                    height: 54,
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: cost,
                      decoration: const InputDecoration(
                        labelText: 'سعر الشراء',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: price,
                      decoration: const InputDecoration(labelText: 'سعر البيع'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: stock,
                      decoration: const InputDecoration(labelText: 'المخزون'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: low,
                      decoration: const InputDecoration(
                        labelText: 'تنبيه انخفاض المخزون',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: 'الوحدة'),
                      items: ['piece', 'box', 'kg', 'liter']
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(unitLabel(u)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => unit = v ?? 'piece'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tx('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'name': name.text,
              'category_id': categoryId,
              'purchase_price': double.tryParse(cost.text) ?? 0,
              'selling_price': double.tryParse(price.text) ?? 0,
              'minimum_price': double.tryParse(cost.text) ?? 0,
              'stock': double.tryParse(stock.text) ?? 0,
              'unit_type': unit,
              'image_path': imagePath,
              'active': 1,
              'low_stock_alert': double.tryParse(low.text) ?? 5,
              'barcode': barcode.text.isEmpty ? _newBarcode() : barcode.text,
              'generated': generated || barcode.text.isEmpty,
            });
          },
          child: Text(tx('حفظ', 'Save')),
        ),
      ],
    );
  }
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.store});
  final PosStore store;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final name = TextEditingController();
  final icon = TextEditingController();
  final inventoryValue = TextEditingController(text: '0');
  int? editingId;
  int? parentId;
  String? imagePath;
  bool active = true;
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.store.categories();
    if (mounted) setState(() {});
  }

  Future<void> save() async {
    final categoryName = name.text.trim();
    if (categoryName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اسم الفئة مطلوب')));
      return;
    }
    final wasEditing = editingId != null;
    if (!wasEditing) {
      await widget.store.addCategory(
        name: categoryName,
        parentId: parentId,
        icon: icon.text.trim().isEmpty ? null : icon.text.trim(),
        imagePath: imagePath,
        inventoryValue: double.tryParse(inventoryValue.text) ?? 0,
        active: active,
      );
    } else {
      await widget.store.updateCategory(
        id: editingId!,
        name: categoryName,
        parentId: parentId,
        icon: icon.text.trim().isEmpty ? null : icon.text.trim(),
        imagePath: imagePath,
        inventoryValue: double.tryParse(inventoryValue.text) ?? 0,
        active: active,
      );
    }
    name.clear();
    icon.clear();
    inventoryValue.text = '0';
    editingId = null;
    parentId = null;
    imagePath = null;
    active = true;
    await load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasEditing
              ? tx('تم تحديث الفئة', 'Category updated')
              : tx('تم حفظ الفئة', 'Category saved'),
        ),
      ),
    );
  }

  void editCategory(Map<String, Object?> row) {
    setState(() {
      editingId = row['id'] as int;
      name.text = '${row['name'] ?? ''}';
      icon.text = '${row['icon'] ?? ''}';
      inventoryValue.text = '${row['inventory_value'] ?? 0}';
      parentId = row['parent_id'] as int?;
      imagePath = row['image_path'] as String?;
      active = (row['active'] as int? ?? 1) == 1;
    });
  }

  void cancelEdit() {
    setState(() {
      editingId = null;
      name.clear();
      icon.clear();
      inventoryValue.text = '0';
      parentId = null;
      imagePath = null;
      active = true;
    });
  }

  Future<void> deleteCategory(Map<String, Object?> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tx('حذف الفئة', 'Delete category')),
        content: Text(
          tx(
            'سيتم إخفاء هذه الفئة وكل منتجاتها من شاشات البيع مع حفظ الفواتير القديمة.',
            'This category and its products will be hidden from sale screens while old invoices stay saved.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tx('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: Text(tx('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.deleteCategory(row['id'] as int);
    await load();
  }

  String parentName(Object? id) {
    if (id == null) return tx('فئة رئيسية', 'Main category');
    final matches = rows.where((row) => row['id'] == id);
    return matches.isEmpty
        ? tx('فئة رئيسية', 'Main category')
        : '${matches.first['name']}';
  }

  @override
  Widget build(BuildContext context) {
    final mainCategories = rows
        .where((row) => row['parent_id'] == null && row['id'] != editingId)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editingId == null
                      ? tx('إضافة فئة', 'Add category')
                      : tx('تعديل فئة', 'Edit category'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    optionalPhoto(imagePath, size: 64),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: name,
                        decoration: InputDecoration(
                          labelText: tx('اسم الفئة', 'Category name'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final selected = await choosePhoto(context);
                        if (selected != null) {
                          setState(() => imagePath = selected);
                        }
                      },
                      icon: const Icon(Icons.image),
                      label: Text(tx('صورة', 'Photo')),
                    ),
                    IconButton(
                      onPressed: imagePath == null
                          ? null
                          : () => setState(() => imagePath = null),
                      icon: const Icon(Icons.close),
                      tooltip: tx('حذف الصورة', 'Remove photo'),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<int?>(
                        value: parentId,
                        decoration: InputDecoration(
                          labelText: tx('الفئة الرئيسية', 'Parent category'),
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(tx('فئة رئيسية', 'Main category')),
                          ),
                          for (final category in mainCategories)
                            DropdownMenuItem<int?>(
                              value: category['id'] as int,
                              child: Text('${category['name']}'),
                            ),
                        ],
                        onChanged: (value) => setState(() => parentId = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: icon,
                        decoration: InputDecoration(
                          labelText: tx(
                            'ملاحظة الأيقونة/الصورة',
                            'Icon/photo note',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: inventoryValue,
                        decoration: InputDecoration(
                          labelText: tx(
                            'قيمة مخزون الفئة',
                            'Category inventory value',
                          ),
                          suffixText: 'IQD',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 140,
                      child: SwitchListTile(
                        value: active,
                        onChanged: (value) => setState(() => active = value),
                        title: Text(tx('نشط', 'Active')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: save,
                      icon: Icon(
                        editingId == null ? Icons.add : Icons.save_outlined,
                      ),
                      label: Text(
                        editingId == null
                            ? tx('إضافة', 'Add')
                            : tx('حفظ التعديل', 'Save edit'),
                      ),
                    ),
                    if (editingId != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: cancelEdit,
                        icon: const Icon(Icons.close),
                        label: Text(tx('إلغاء التعديل', 'Cancel edit')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(tx('الصورة', 'Photo'))),
                DataColumn(label: Text(tx('الفئة', 'Category'))),
                DataColumn(label: Text(tx('الأصل', 'Parent'))),
                DataColumn(label: Text(tx('المنتجات', 'Products'))),
                DataColumn(label: Text(tx('المباع', 'Sold'))),
                DataColumn(label: Text(tx('قيمة المخزون', 'Inventory value'))),
                DataColumn(label: Text(tx('الأيقونة/الصورة', 'Icon/photo'))),
                DataColumn(label: Text(tx('الحالة', 'Status'))),
                DataColumn(label: Text(tx('إجراء', 'Action'))),
              ],
              rows: [
                if (rows.isEmpty)
                  DataRow(
                    cells: [
                      DataCell(Text(tx('لا توجد صورة', 'No photo'))),
                      DataCell(
                        Text(tx('لا توجد فئات بعد', 'No categories yet')),
                      ),
                      DataCell(Text(tx('أضف فئة من الأعلى', 'Add one above'))),
                      const DataCell(Text('0')),
                      const DataCell(Text('0 IQD')),
                      const DataCell(Text('0 IQD')),
                      const DataCell(Text('')),
                      DataCell(Text(tx('فارغ', 'Empty'))),
                      const DataCell(SizedBox.shrink()),
                    ],
                  ),
                for (final row in rows)
                  DataRow(
                    cells: [
                      DataCell(optionalPhoto(row['image_path'] as String?)),
                      DataCell(Text('${row['name']}')),
                      DataCell(Text(parentName(row['parent_id']))),
                      DataCell(Text('${row['product_count'] ?? 0}')),
                      DataCell(Text(money(row['category_sold']))),
                      DataCell(Text(money(row['inventory_value']))),
                      DataCell(Text('${row['icon'] ?? ''}')),
                      DataCell(
                        Text(
                          (row['active'] as int? ?? 1) == 1
                              ? tx('نشط', 'Active')
                              : tx('غير نشط', 'Inactive'),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => editCategory(row),
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: tx('تعديل الفئة', 'Edit category'),
                            ),
                            IconButton(
                              onPressed: (row['active'] as int? ?? 1) == 1
                                  ? () => deleteCategory(row)
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red,
                              tooltip: tx('حذف الفئة', 'Delete category'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.store, required this.user});
  final PosStore store;
  final UserSession user;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Map<String, Object?>> products = [];
  int? productId;
  final qty = TextEditingController();
  final note = TextEditingController();
  String action = 'Stock added';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    products = await widget.store.products();
    if (mounted) setState(() {});
  }

  Future<void> save() async {
    if (productId == null) return;
    var amount = double.tryParse(qty.text) ?? 0;
    if (['Reduce stock', 'Damaged'].contains(action)) amount = -amount.abs();
    await widget.store.adjustStock(
      productId!,
      amount,
      action,
      widget.user.id,
      note.text,
    );
    qty.clear();
    note.clear();
    await load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: productId,
                    decoration: InputDecoration(
                      labelText: tx('المنتج', 'Product'),
                    ),
                    items: [
                      for (final p in products)
                        DropdownMenuItem(
                          value: p['id'] as int,
                          child: Text('${p['name']}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => productId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: action,
                    decoration: InputDecoration(
                      labelText: tx('الحركة', 'Action'),
                    ),
                    items:
                        [
                              'Stock added',
                              'Reduce stock',
                              'Stock adjustment',
                              'Damaged',
                              'Returned',
                            ]
                            .map(
                              (a) => DropdownMenuItem(
                                value: a,
                                child: Text(stockActionLabel(a)),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => action = v ?? action),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: qty,
                    decoration: InputDecoration(
                      labelText: tx('الكمية', 'Quantity'),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: note,
                    decoration: InputDecoration(
                      labelText: tx('المورد/ملاحظة', 'Supplier/note'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save),
                  label: Text(tx('حفظ', 'Save')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(tx('المنتج', 'Product'))),
                DataColumn(label: Text(tx('المخزون', 'Stock'))),
                DataColumn(label: Text(tx('تنبيه الانخفاض', 'Low alert'))),
                DataColumn(label: Text(tx('القيمة', 'Value'))),
              ],
              rows: [
                for (final p in products)
                  DataRow(
                    cells: [
                      DataCell(Text('${p['name']}')),
                      DataCell(
                        Text('${p['stock']} ${unitLabel(p['unit_type'])}'),
                      ),
                      DataCell(Text('${p['low_stock_alert']}')),
                      DataCell(
                        Text(
                          money(
                            (p['stock'] as num) * (p['purchase_price'] as num),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class FinancePage extends StatefulWidget {
  const FinancePage({super.key, required this.store, required this.user});
  final PosStore store;
  final UserSession user;

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  int tab = 0;
  Map<String, Object?> summary = {};
  List<Map<String, Object?>> expenses = [];
  List<Map<String, Object?>> types = [];
  List<Map<String, Object?>> sessions = [];
  List<Map<String, Object?>> sales = [];
  List<Map<String, Object?>> categorySales = [];
  List<Map<String, Object?>> selectedItems = [];
  List<Map<String, Object?>> productResults = [];
  Map<String, Object?>? selectedSale;
  int? typeId;
  final amount = TextEditingController();
  final note = TextEditingController();
  final opening = TextEditingController();
  final invoiceSearch = TextEditingController();
  final productSearch = TextEditingController();
  final exchangeCart = <CartLine>[];
  String message = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    summary = await widget.store.financeSummary();
    expenses = await widget.store.expenses();
    types = await widget.store.expenseTypes();
    sessions = await widget.store.cashSessions();
    sales = await widget.store.salesHistory(invoiceSearch.text);
    categorySales = await widget.store.categorySalesReport();
    productResults = productSearch.text.trim().isEmpty
        ? []
        : await widget.store.products(productSearch.text);
    typeId ??= types.isEmpty ? null : types.first['id'] as int;
    if (mounted) setState(() {});
  }

  Future<void> selectSale(Map<String, Object?> sale) async {
    selectedSale = sale;
    selectedItems = await widget.store.saleItems(sale['id'] as int);
    exchangeCart.clear();
    message = '';
    if (mounted) setState(() {});
  }

  Future<void> saveExpense() async {
    if (typeId == null) return;
    await widget.store.addExpense(
      typeId!,
      double.tryParse(amount.text) ?? 0,
      note.text,
      widget.user.id,
    );
    amount.clear();
    note.clear();
    await load();
  }

  Future<void> openCash() async {
    await widget.store.openCash(
      double.tryParse(opening.text) ?? 0,
      widget.user.id,
    );
    opening.clear();
    await load();
  }

  void addExchangeProduct(Map<String, Object?> product) {
    final existing = exchangeCart
        .where((item) => item.id == product['id'])
        .firstOrNull;
    setState(() {
      if (existing == null) {
        exchangeCart.add(CartLine(product));
      } else {
        existing.qty += 1;
      }
    });
  }

  Future<void> voidSelected() async {
    final sale = selectedSale;
    if (sale == null) return;
    await widget.store.voidSale(
      sale['id'] as int,
      widget.user.id,
      'Void / return',
    );
    selectedSale = null;
    selectedItems = [];
    exchangeCart.clear();
    message = tx(
      'تم إلغاء الفاتورة وإرجاع المخزون.',
      'Invoice voided and stock restored.',
    );
    await load();
  }

  Future<void> confirmExchange() async {
    final sale = selectedSale;
    if (sale == null || exchangeCart.isEmpty) return;
    final invoice = await widget.store.exchangeSale(
      sale['id'] as int,
      exchangeCart,
      widget.user,
    );
    selectedSale = null;
    selectedItems = [];
    exchangeCart.clear();
    productSearch.clear();
    message = tx(
      'تمت المبادلة. الفاتورة الجديدة: $invoice',
      'Exchange completed. New invoice: $invoice',
    );
    await load();
  }

  double get exchangeTotal =>
      exchangeCart.fold<double>(0, (sum, item) => sum + item.lineSubtotal);

  @override
  Widget build(BuildContext context) {
    final tabs = [
      tx('تقرير المبيعات', 'Sales Report'),
      tx('المصروفات', 'Expenses'),
      tx('الأرباح والخسائر', 'P&L Statement'),
      tx('الديون', 'Debts'),
      tx('التدفق النقدي', 'Cash Flow'),
      tx('قيمة المخزون', 'Inventory Value'),
      tx('مبيعات الفئات', 'Category Sales'),
      tx('المبادلة والاسترجاع', 'Exchange & Returns'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(tabs[i]),
                      selected: tab == i,
                      selectedColor: brandGold,
                      labelStyle: TextStyle(
                        color: tab == i ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w800,
                      ),
                      onSelected: (_) => setState(() => tab = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (tab == 0)
          _salesReport()
        else if (tab == 1)
          _expensesTab()
        else if (tab == 2)
          _profitLoss()
        else if (tab == 3)
          _placeholder(
            tx('لا توجد ديون مسجلة حاليا.', 'No debts recorded yet.'),
          )
        else if (tab == 4)
          _cashFlow()
        else if (tab == 5)
          _inventoryValue()
        else if (tab == 6)
          _categorySales()
        else
          _exchangeReturns(),
      ],
    );
  }

  Widget _salesReport() {
    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FinanceMetric(
              tx('إجمالي المبيعات', 'Total Sales'),
              money(summary['total_sales']),
              Icons.sell,
            ),
            FinanceMetric(
              tx('الفواتير', 'Invoices'),
              '${summary['invoices'] ?? 0}',
              Icons.description,
            ),
            FinanceMetric(
              tx('متوسط الفاتورة', 'Avg Ticket'),
              money(summary['avg_ticket']),
              Icons.confirmation_number,
            ),
            FinanceMetric(
              tx('إجمالي الخصومات', 'Total Discounts'),
              money(summary['discounts']),
              Icons.discount,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _panel(
                tx('مخطط الإيرادات', 'Revenue Chart'),
                _bar(summary['total_sales']),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _panel(tx('طرق الدفع', 'Payment Methods'), _donut()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _expensesTab() {
    return _panel(
      tx('المصروفات', 'Expenses'),
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: typeId,
                  decoration: InputDecoration(labelText: tx('النوع', 'Type')),
                  items: [
                    for (final t in types)
                      DropdownMenuItem(
                        value: t['id'] as int,
                        child: Text(expenseTypeLabel(t['name'])),
                      ),
                  ],
                  onChanged: (v) => setState(() => typeId = v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: amount,
                  decoration: InputDecoration(
                    labelText: tx('المبلغ', 'Amount'),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: note,
                  decoration: InputDecoration(labelText: tx('ملاحظة', 'Note')),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: saveExpense,
                icon: const Icon(Icons.add),
                label: Text(tx('إضافة', 'Add')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final e in expenses)
            ListTile(
              title: Text(expenseTypeLabel(e['type'])),
              subtitle: Text('${e['note'] ?? ''}'),
              trailing: Text(money(e['amount'])),
            ),
        ],
      ),
    );
  }

  Widget _profitLoss() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FinanceMetric(
          tx('المبيعات', 'Sales'),
          money(summary['total_sales']),
          Icons.sell,
        ),
        FinanceMetric(
          tx('الكلفة', 'Cost'),
          money(summary['total_cost']),
          Icons.inventory,
        ),
        FinanceMetric(
          tx('الربح الإجمالي', 'Gross Profit'),
          money(summary['gross_profit']),
          Icons.trending_up,
        ),
        FinanceMetric(
          tx('المصروفات', 'Expenses'),
          money(summary['expenses']),
          Icons.receipt,
        ),
        FinanceMetric(
          tx('صافي الربح', 'Net Profit'),
          money(summary['net_profit']),
          Icons.account_balance_wallet,
        ),
        FinanceMetric(
          tx('المرتجعات', 'Returns'),
          money(summary['returns_total']),
          Icons.undo,
        ),
      ],
    );
  }

  Widget _cashFlow() {
    return _panel(
      tx('صندوق النقد', 'Cash drawer'),
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: opening,
                  decoration: InputDecoration(
                    labelText: tx('النقد الافتتاحي', 'Opening cash'),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: openCash,
                icon: const Icon(Icons.lock_open),
                label: Text(tx('فتح', 'Open')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final s in sessions)
            ListTile(
              title: Text('${s['user']} - ${money(s['opening_cash'])}'),
              subtitle: Text('${s['opened_at']}'),
              trailing: Text(
                s['closed_at'] == null
                    ? tx('مفتوح', 'Open')
                    : money(s['difference']),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inventoryValue() {
    return Wrap(
      spacing: 12,
      children: [
        FinanceMetric(
          tx('قيمة المخزون', 'Inventory Value'),
          money(summary['stock_value']),
          Icons.warehouse,
        ),
        FinanceMetric(
          tx('مخزون منخفض', 'Low Stock'),
          '${summary['low_stock'] ?? '-'}',
          Icons.warning,
        ),
      ],
    );
  }

  Widget _categorySales() {
    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FinanceMetric(
              tx('مبيعات الفئات', 'Category Sales'),
              money(summary['category_sales']),
              Icons.grid_view,
            ),
            FinanceMetric(
              tx('فواتير الفئات', 'Category Invoices'),
              '${summary['category_invoices'] ?? 0}',
              Icons.receipt_long,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _panel(
          tx('قائمة مبيعات الفئات', 'Category Sales List'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(tx('الفئة', 'Category'))),
                DataColumn(label: Text(tx('المباع', 'Sold'))),
                DataColumn(label: Text(tx('الفواتير', 'Invoices'))),
                DataColumn(label: Text(tx('عدد العمليات', 'Sales count'))),
                DataColumn(
                  label: Text(tx('قيمة المخزون المتبقية', 'Remaining value')),
                ),
              ],
              rows: [
                if (categorySales.isEmpty)
                  DataRow(
                    cells: [
                      DataCell(Text(tx('لا توجد فئات', 'No categories'))),
                      const DataCell(Text('0 IQD')),
                      const DataCell(Text('0')),
                      const DataCell(Text('0')),
                      const DataCell(Text('0 IQD')),
                    ],
                  ),
                for (final row in categorySales)
                  DataRow(
                    cells: [
                      DataCell(Text('${row['name']}')),
                      DataCell(Text(money(row['sold_total']))),
                      DataCell(Text('${row['invoices'] ?? 0}')),
                      DataCell(Text('${row['sale_count'] ?? 0}')),
                      DataCell(Text(money(row['inventory_value']))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _exchangeReturns() {
    return Column(
      children: [
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              message,
              style: const TextStyle(
                color: brandGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _invoiceFinder()),
            const SizedBox(width: 14),
            Expanded(child: _newExchangeCart()),
          ],
        ),
        if (selectedSale != null) ...[
          const SizedBox(height: 14),
          _selectedInvoicePanel(),
        ],
      ],
    );
  }

  Widget _invoiceFinder() {
    return _panel(
      tx('ابحث عن الفاتورة الأصلية', 'Find Original Invoice'),
      Column(
        children: [
          TextField(
            controller: invoiceSearch,
            decoration: InputDecoration(
              labelText: tx('رقم الفاتورة', 'Invoice number'),
            ),
            onChanged: (_) => load(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: ListView.builder(
              itemCount: sales.length,
              itemBuilder: (_, i) {
                final sale = sales[i];
                final refunded = sale['refunded'] == 1;
                return ListTile(
                  selected: selectedSale?['id'] == sale['id'],
                  title: Text('${sale['invoice_no']}'),
                  subtitle: Text('${sale['created_at']} - ${sale['cashier']}'),
                  trailing: Chip(
                    label: Text(
                      refunded ? tx('ملغاة', 'Void') : money(sale['total']),
                    ),
                  ),
                  onTap: refunded ? null : () => selectSale(sale),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedInvoicePanel() {
    return _panel(
      '${selectedSale!['invoice_no']}',
      Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(tx('المادة', 'Item'))),
                DataColumn(label: Text(tx('الكمية', 'Qty'))),
                DataColumn(label: Text(tx('السعر', 'Price'))),
                DataColumn(label: Text(tx('المجموع', 'Total'))),
              ],
              rows: [
                for (final item in selectedItems)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          '${item['product_name'] ?? tx('بيع فئة', 'Category sale')}',
                        ),
                      ),
                      DataCell(Text('${item['qty']}')),
                      DataCell(Text(money(item['unit_price']))),
                      DataCell(Text(money(item['total']))),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(),
          Row(
            children: [
              Text(
                '${tx('الإجمالي', 'Total')}: ${money(selectedSale!['total'])}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: voidSelected,
                icon: const Icon(Icons.delete),
                label: Text(
                  tx('إلغاء وإرجاع المخزون', 'Cancel & Restore Stock'),
                ),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: exchangeCart.isEmpty ? null : confirmExchange,
                icon: const Icon(Icons.swap_horiz),
                label: Text(
                  tx('مبادلة بالمواد الجديدة', 'Exchange with New Items'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _newExchangeCart() {
    return _panel(
      tx('مواد جديدة للمبادلة', 'New Items for Exchange'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: productSearch,
            decoration: InputDecoration(
              labelText: tx('ابحث عن منتج', 'Search product'),
            ),
            onChanged: (_) => load(),
          ),
          for (final product in productResults.take(5))
            ListTile(
              title: Text('${product['name']}'),
              subtitle: Text(money(product['selling_price'])),
              trailing: const Icon(Icons.add_circle),
              onTap: () => addExchangeProduct(product),
            ),
          const Divider(),
          Text(
            tx('السلة الجديدة', 'New Cart'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          if (exchangeCart.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(child: Text(tx('السلة فارغة', 'Cart is empty'))),
            ),
          for (var i = 0; i < exchangeCart.length; i++)
            ListTile(
              title: Text(exchangeCart[i].name),
              subtitle: Text(
                '${exchangeCart[i].qty} x ${money(exchangeCart[i].soldPrice)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(money(exchangeCart[i].lineSubtotal)),
                  IconButton(
                    onPressed: () => setState(() => exchangeCart.removeAt(i)),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          const Divider(),
          Text(
            '${tx('الإجمالي الجديد', 'New Total')}: ${money(exchangeTotal)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: selectedSale != null && exchangeCart.isNotEmpty
                ? confirmExchange
                : null,
            child: Text(tx('تأكيد المبادلة', 'Confirm Exchange')),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(String text) => _panel(text, const SizedBox(height: 80));

  Widget _panel(String title, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _bar(Object? value) {
    final amount = (value as num?)?.toDouble() ?? 0;
    final barHeight = max(42.0, min(180.0, amount / 250));
    return SizedBox(
      height: 230,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < 5; i++)
                        Container(height: 1, color: const Color(0x16000000)),
                    ],
                  ),
                ),
                Positioned(
                  bottom: barHeight + 10,
                  child: Text(
                    money(amount),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  width: 150,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: brandGold.withOpacity(.78),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 2, color: const Color(0x22000000)),
          const SizedBox(height: 8),
          Text(
            tx('الإيرادات', 'Revenue'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _donut() {
    return SizedBox(
      height: 260,
      child: Center(
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: brandGold, width: 46),
          ),
          alignment: Alignment.center,
          child: Text(
            tx('نقدا', 'Cash'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class FinanceMetric extends StatelessWidget {
  const FinanceMetric(this.title, this.value, this.icon, {super.key});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 138,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: brandGold, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final PosStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, String> values = {};
  bool saving = false;

  @override
  void initState() {
    super.initState();
    widget.store.settings().then((v) => setState(() => values = v));
  }

  Future<void> saveAll() async {
    setState(() => saving = true);
    for (final entry in values.entries) {
      await widget.store.saveSetting(entry.key, entry.value);
    }
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
  }

  @override
  Widget build(BuildContext context) {
    final keys = [
      'store_name',
      'store_phone',
      'store_address',
      'currency',
      'tax_enabled',
      'receipt_size',
      'barcode_label_size',
      'default_printer',
      'allow_discount',
      'allow_price_change',
      'allow_below_cost_sale',
      'require_manager_password_below_cost',
      'low_stock_alert',
      'auto_backup',
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final key in keys)
                      SizedBox(
                        width: 320,
                        child: TextFormField(
                          key: ValueKey('$key-${values[key] ?? ''}'),
                          initialValue: values[key] ?? '',
                          decoration: InputDecoration(
                            labelText: settingLabel(key),
                          ),
                          onChanged: (value) => values[key] = value,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: saving ? null : saveAll,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(saving ? 'جار الحفظ...' : 'حفظ الإعدادات'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xfffff0f0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xffff4444), width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xffcc0000), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx('منطقة الخطر — حذف جميع البيانات', 'Danger Zone — Delete All Data'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xffcc0000),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tx(
                          'يحذف هذا الإجراء جميع المبيعات والمنتجات والفئات والمخزون والمصروفات والجلسات النقدية بشكل نهائي. لا يمكن التراجع عنه.',
                          'This permanently deletes all sales, products, categories, inventory, expenses and cash sessions. Cannot be undone.',
                        ),
                        style: const TextStyle(color: Color(0xff880000)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xffcc0000),
                    side: const BorderSide(color: Color(0xffcc0000)),
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xffcc0000)),
                            const SizedBox(width: 8),
                            Text(tx('تأكيد حذف البيانات', 'Confirm Data Reset')),
                          ],
                        ),
                        content: Text(
                          tx(
                            'هل أنت متأكد؟ سيتم حذف جميع البيانات (المبيعات، المنتجات، الفئات، المخزون، المصروفات) بشكل نهائي ولا يمكن استعادتها.',
                            'Are you sure? All data (sales, products, categories, inventory, expenses) will be permanently deleted and cannot be recovered.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(tx('إلغاء', 'Cancel')),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xffcc0000)),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(tx('نعم، احذف كل شيء', 'Yes, delete everything')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    await widget.store.resetAllData();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(tx('تم حذف جميع البيانات بنجاح', 'All data deleted successfully')),
                        backgroundColor: const Color(0xffcc0000),
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_forever),
                  label: Text(tx('حذف جميع البيانات', 'Reset All Data')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.store});
  final PosStore store;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  String message = '';
  bool busy = false;

  Future<void> backup() async {
    setState(() => busy = true);
    final path = await widget.store.backup();
    if (!mounted) return;
    setState(() {
      busy = false;
      message = '${tx('تم إنشاء النسخة الاحتياطية', 'Backup created')}: $path';
    });
  }

  Future<void> restore() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'SQLite backup', extensions: ['sqlite', 'db']),
      ],
    );
    if (file == null) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tx('استعادة نسخة احتياطية', 'Restore backup')),
        content: Text(
          tx(
            'سيتم استبدال قاعدة البيانات الحالية. سيتم إنشاء نسخة أمان قبل الاستعادة.',
            'The current database will be replaced. A safety backup will be created first.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tx('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.restore),
            label: Text(tx('استعادة', 'Restore')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      final safetyPath = await widget.store.restoreBackup(file.path);
      if (!mounted) return;
      setState(() {
        busy = false;
        message =
            '${tx('تمت الاستعادة. نسخة الأمان محفوظة في', 'Restore complete. Safety backup saved at')}: $safetyPath';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        busy = false;
        message = '${tx('فشلت الاستعادة', 'Restore failed')}: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 560,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tx('نسخ احتياطي يدوي', 'Manual backup'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tx(
                    'ينشئ نسخة من قاعدة بيانات SQLite المحلية. يمكنك تصدير نسخة احتياطية أو استعادة نسخة محفوظة.',
                    'Creates a copy of the local SQLite database. You can export a backup or restore a saved backup.',
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : backup,
                      icon: const Icon(Icons.backup),
                      label: Text(tx('تصدير نسخة احتياطية', 'Export backup')),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : restore,
                      icon: const Icon(Icons.restore),
                      label: Text(tx('استعادة نسخة', 'Restore backup')),
                    ),
                  ],
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(message),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
