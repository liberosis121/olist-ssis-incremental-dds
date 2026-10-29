#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
prepare_datasource.py  -  Chuẩn bị DATASOURCE cho bài tập SSIS (incremental extract + SCD)

Đọc bộ dữ liệu Kaggle "Brazilian E-Commerce Public Dataset by Olist" (các file CSV gốc)
rồi tạo ra:

  1. datasource/batch1_initial/*.csv   Đợt 1 = dữ liệu nạp ban đầu (đơn mua 01/2017 - 03/2017)
  2. datasource/batch2_april/*.csv     Đợt 2 = dữ liệu phát sinh thêm (đơn mua 04/2017)
  3. sql/02_seed_source_batch1.sql     Script INSERT đợt 1 vào Olist_Source (chạy 1 lần lúc khởi tạo)
  4. sql/04_source_changes_batch2.sql  Script "một ngày làm việc mới" ở nguồn: INSERT đợt 2 +
                                       UPDATE vài dòng để minh họa SCD 1, SCD 2 và upsert

Chỉ lấy các khách hàng / sản phẩm xuất hiện trong đơn của đợt tương ứng.
Không dùng các file geolocation, payments, reviews, sellers (bài này không cần).

Cách chạy (Python 3 + pandas):
    py datasource\\prepare_datasource.py
    py datasource\\prepare_datasource.py --raw "D:\\duong-dan\\toi\\thu-muc-csv-kaggle"

Kết quả là xác định (deterministic): chạy lại cho đúng cùng file và cùng các id được chọn.
"""
import argparse
import os
from decimal import Decimal, ROUND_HALF_UP

import pandas as pd

DEFAULT_RAW = r"D:\HK7\BI\Seminar\bi-miniproject\data\raw"

BATCH1 = ("2017-01-01", "2017-04-01")   # [từ, đến)  -> đơn mua 01..03/2017
BATCH2 = ("2017-04-01", "2017-05-01")   # [từ, đến)  -> đơn mua 04/2017


# ---------------------------------------------------------------- tiện ích định dạng
def sql_str(v):
    """Chuỗi -> literal T-SQL N'...' (escape dấu nháy đơn); NaN/None -> NULL."""
    if v is None or (isinstance(v, float) and pd.isna(v)) or (not isinstance(v, str) and pd.isna(v)):
        return "NULL"
    return "N'" + str(v).replace("'", "''") + "'"


def sql_num(v):
    if v is None or pd.isna(v):
        return "NULL"
    if isinstance(v, (float,)) and float(v).is_integer():
        return str(int(v))
    return str(v)


def sql_dec(v):
    return "NULL" if v is None or pd.isna(v) else str(Decimal(str(v)).quantize(Decimal("0.01")))


def write_inserts(f, table, cols, rows, chunk=1000):
    """Ghi các lệnh INSERT ... VALUES (tối đa `chunk` dòng / lệnh) cho danh sách tuple literal đã định dạng."""
    head = "INSERT INTO dbo.%s (%s) VALUES\n" % (table, ", ".join(cols))
    for i in range(0, len(rows), chunk):
        part = rows[i:i + chunk]
        f.write(head)
        f.write(",\n".join("    (" + ", ".join(r) + ")" for r in part))
        f.write(";\n")
    f.write("PRINT N'  %s: %d dòng';\nGO\n\n" % (table, len(rows)))


def read_raw(raw):
    def rd(name, **kw):
        return pd.read_csv(os.path.join(raw, name), dtype=str, keep_default_na=False, na_values=[""], **kw)
    orders = rd("olist_orders_dataset.csv")
    items = rd("olist_order_items_dataset.csv")
    cust = rd("olist_customers_dataset.csv")
    prod = rd("olist_products_dataset.csv")
    cat = rd("product_category_name_translation.csv", encoding="utf-8-sig")
    return orders, items, cust, prod, cat


def money(x):
    return Decimal(str(x)).quantize(Decimal("0.01"))


# ---------------------------------------------------------------- xây dữ liệu từng đợt
def build(raw):
    orders, items, cust, prod, cat = read_raw(raw)

    orders["ts"] = pd.to_datetime(orders["order_purchase_timestamp"])
    o = orders.merge(cust, on="customer_id", how="inner")      # gắn customer_unique_id + địa chỉ của đơn

    def slice_batch(lo, hi):
        ob = o[(o.ts >= lo) & (o.ts < hi)].copy()
        ib = items[items.order_id.isin(ob.order_id)].copy()
        return ob, ib

    o1, i1 = slice_batch(*BATCH1)
    o2, i2 = slice_batch(*BATCH2)

    # --- khách hàng: 1 dòng / customer_unique_id, địa chỉ lấy từ đơn mới nhất trong đợt
    def customers_of(ob):
        c = ob.sort_values(["ts", "order_id"]).groupby("customer_unique_id").last().reset_index()
        return c[["customer_unique_id", "customer_zip_code_prefix", "customer_city", "customer_state"]] \
            .sort_values("customer_unique_id").reset_index(drop=True)

    c1 = customers_of(o1)
    c2_all = customers_of(o2)
    c2_new = c2_all[~c2_all.customer_unique_id.isin(c1.customer_unique_id)].reset_index(drop=True)

    # --- sản phẩm
    prod = prod.rename(columns={"product_name_lenght": "x1", "product_description_lenght": "x2"})
    keep = ["product_id", "product_category_name", "product_photos_qty", "product_weight_g",
            "product_length_cm", "product_height_cm", "product_width_cm"]
    pr = prod[keep].set_index("product_id")
    p1_ids = sorted(set(i1.product_id))
    p2_ids_all = sorted(set(i2.product_id))
    p2_new_ids = sorted(set(p2_ids_all) - set(p1_ids))
    p1 = pr.loc[p1_ids].reset_index()
    p2_new = pr.loc[p2_new_ids].reset_index()

    # --- đơn hàng
    ocols = ["order_id", "customer_unique_id", "order_status", "order_purchase_timestamp", "order_approved_at",
             "order_delivered_customer_date", "order_estimated_delivery_date"]
    ord1 = o1[ocols].sort_values("order_id").reset_index(drop=True)
    ord2 = o2[ocols].sort_values("order_id").reset_index(drop=True)
    icols = ["order_id", "order_item_id", "product_id", "price", "freight_value"]
    it1 = i1[icols].copy()
    it2 = i2[icols].copy()
    for d in (it1, it2):
        d["order_item_id"] = d["order_item_id"].astype(int)
    it1 = it1.sort_values(["order_id", "order_item_id"]).reset_index(drop=True)
    it2 = it2.sort_values(["order_id", "order_item_id"]).reset_index(drop=True)

    return dict(cat=cat, c1=c1, c2_all=c2_all, c2_new=c2_new, p1=p1, p2_new=p2_new, pr=pr,
                ord1=ord1, ord2=ord2, it1=it1, it2=it2, p2_ids_all=p2_ids_all, p1_ids=p1_ids)


# ---------------------------------------------------------------- chọn các dòng "thay đổi" cho đợt 2
def pick_changes(d):
    ch = {}
    c1 = d["c1"].set_index("customer_unique_id")
    c2 = d["c2_all"].set_index("customer_unique_id")
    shared = sorted(set(c1.index) & set(c2.index))
    cols = ["customer_zip_code_prefix", "customer_city", "customer_state"]
    # SCD2: khách mua ở cả 2 đợt và địa chỉ thật sự khác nhau giữa 2 đợt (dữ liệu thật của Olist)
    scd2 = [u for u in shared if c1.loc[u, cols].tolist() != c2.loc[u, cols].tolist()]
    ch["shared_customers"] = len(shared)
    ch["scd2"] = [(u, c1.loc[u, cols].tolist(), c2.loc[u, cols].tolist()) for u in scd2]

    # SCD1: sản phẩm đã có ở đợt 1 và cũng được mua lại ở đợt 2 (544 sp), có category + cân nặng
    pr = d["pr"]
    both = sorted(set(d["p1_ids"]) & set(d["p2_ids_all"]))
    cand = [p for p in both
            if isinstance(pr.loc[p, "product_category_name"], str) and isinstance(pr.loc[p, "product_weight_g"], str)
            and isinstance(pr.loc[p, "product_length_cm"], str)]
    ch["scd1_weight"] = cand[0]
    ch["scd1_dims"] = cand[1]
    ch["scd1_cat"] = cand[2]
    # category mới: một category khác có trong bảng dịch
    cats = sorted(d["cat"].product_category_name)
    cur = pr.loc[ch["scd1_cat"], "product_category_name"]
    ch["scd1_cat_new"] = "utilidades_domesticas" if cur != "utilidades_domesticas" else "esporte_lazer"
    assert ch["scd1_cat_new"] in cats

    # Upsert fact: 3 dòng hàng của đợt 1 (đơn delivered, không thuộc khách SCD2) bị "sửa giá"
    scd2_ids = set(u for u, _, _ in ch["scd2"])
    ord1 = d["ord1"]
    ok_orders = set(ord1[(ord1.order_status == "delivered") & (~ord1.customer_unique_id.isin(scd2_ids))].order_id)
    it1 = d["it1"]
    fx = it1[(it1.order_id.isin(ok_orders)) & (it1.order_item_id == 1)]
    fx = fx[(fx.price.astype(float) >= 60) & (fx.price.astype(float) <= 300)].sort_values("order_id")
    sel = fx.iloc[[0, 1, 2]]
    fixes = []
    for k, (_, r) in enumerate(sel.iterrows()):
        p_old, f_old = money(r.price), money(r.freight_value)
        if k == 0:      # chỉ sửa giá
            p_new, f_new = p_old - Decimal("10.00"), f_old
        elif k == 1:    # chỉ sửa phí vận chuyển
            p_new, f_new = p_old, f_old + Decimal("5.00")
        else:           # sửa cả hai
            p_new, f_new = (p_old * Decimal("0.90")).quantize(Decimal("0.01"), ROUND_HALF_UP), f_old + Decimal("2.50")
        fixes.append((r.order_id, int(r.order_item_id), p_old, f_old, p_new, f_new))
    ch["fixes"] = fixes
    return ch


# ---------------------------------------------------------------- ghi CSV
def write_csv(df, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    df.to_csv(path, index=False, encoding="utf-8", lineterminator="\n")


def write_all_csv(d, out):
    b1 = os.path.join(out, "datasource", "batch1_initial")
    b2 = os.path.join(out, "datasource", "batch2_april")
    write_csv(d["cat"], os.path.join(b1, "product_category.csv"))
    write_csv(d["c1"], os.path.join(b1, "customer.csv"))
    write_csv(d["p1"], os.path.join(b1, "product.csv"))
    write_csv(d["ord1"], os.path.join(b1, "orders.csv"))
    write_csv(d["it1"], os.path.join(b1, "order_item.csv"))
    write_csv(d["c2_new"], os.path.join(b2, "customer.csv"))
    write_csv(d["p2_new"], os.path.join(b2, "product.csv"))
    write_csv(d["ord2"], os.path.join(b2, "orders.csv"))
    write_csv(d["it2"], os.path.join(b2, "order_item.csv"))


# ---------------------------------------------------------------- ghi SQL
def sql_rows(d_cust, d_prod, d_ord, d_it):
    cust = [(sql_str(r.customer_unique_id), sql_str(r.customer_zip_code_prefix), sql_str(r.customer_city),
             sql_str(r.customer_state)) for r in d_cust.itertuples()]
    prod = [(sql_str(r.product_id), sql_str(r.product_category_name), sql_num(r.product_photos_qty),
             sql_num(r.product_weight_g), sql_num(r.product_length_cm), sql_num(r.product_height_cm),
             sql_num(r.product_width_cm)) for r in d_prod.itertuples()]
    ordr = [(sql_str(r.order_id), sql_str(r.customer_unique_id), sql_str(r.order_status),
             sql_str(r.order_purchase_timestamp), sql_str(r.order_approved_at),
             sql_str(r.order_delivered_customer_date), sql_str(r.order_estimated_delivery_date))
            for r in d_ord.itertuples()]
    itm = [(sql_str(r.order_id), str(int(r.order_item_id)), sql_str(r.product_id), sql_dec(r.price),
            sql_dec(r.freight_value)) for r in d_it.itertuples()]
    return cust, prod, ordr, itm


CUST_COLS = ["customer_unique_id", "customer_zip_code_prefix", "customer_city", "customer_state"]
PROD_COLS = ["product_id", "product_category_name", "product_photos_qty", "product_weight_g",
             "product_length_cm", "product_height_cm", "product_width_cm"]
ORD_COLS = ["order_id", "customer_unique_id", "order_status", "order_purchase_timestamp", "order_approved_at",
            "order_delivered_customer_date", "order_estimated_delivery_date"]
ITEM_COLS = ["order_id", "order_item_id", "product_id", "price", "freight_value"]


def write_seed_sql(d, out):
    path = os.path.join(out, "sql", "02_seed_source_batch1.sql")
    cust, prod, ordr, itm = sql_rows(d["c1"], d["p1"], d["ord1"], d["it1"])
    cats = [(sql_str(r.product_category_name), sql_str(r.product_category_name_english))
            for r in d["cat"].itertuples()]
    with open(path, "w", encoding="utf-8-sig", newline="\n") as f:
        f.write("""/* =====================================================================
   02_seed_source_batch1.sql   (FILE SINH TỰ ĐỘNG bởi datasource/prepare_datasource.py)
   Nạp ĐỢT 1 vào Olist_Source = trạng thái ban đầu của hệ thống nguồn:
     đơn mua từ 2017-01-01 đến 2017-03-31
       product_category : %d dòng (toàn bộ file translation)
       customer         : %d khách (customer_unique_id)
       product          : %d sản phẩm
       orders           : %d đơn
       order_item       : %d dòng hàng
   created_at của mọi dòng = thời điểm chạy script (DEFAULT SYSDATETIME()), updated_at = NULL.
   Không dùng BULK INSERT (tài khoản dịch vụ SQL Server không đọc được ổ D:), nên dữ liệu
   nằm sẵn trong file .sql này.  Chạy:
       sqlcmd -S localhost -E -C -f 65001 -b -i sql\\02_seed_source_batch1.sql
   Chỉ chạy 1 lần sau 01_create_source_db.sql (muốn làm lại: chạy sql\\reset_and_prepare.cmd).
   ===================================================================== */
USE Olist_Source;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
PRINT N'Đang nạp đợt 1 vào Olist_Source ...';
GO

""" % (len(cats), len(cust), len(prod), len(ordr), len(itm)))
        write_inserts(f, "product_category", ["product_category_name", "product_category_name_english"], cats)
        write_inserts(f, "customer", CUST_COLS, cust)
        write_inserts(f, "product", PROD_COLS, prod)
        write_inserts(f, "orders", ORD_COLS, ordr)
        write_inserts(f, "order_item", ITEM_COLS, itm)
        f.write("""PRINT N'Hoàn tất đợt 1.';
SELECT 'product_category' AS bang, COUNT(*) AS so_dong FROM dbo.product_category
UNION ALL SELECT 'customer',   COUNT(*) FROM dbo.customer
UNION ALL SELECT 'product',    COUNT(*) FROM dbo.product
UNION ALL SELECT 'orders',     COUNT(*) FROM dbo.orders
UNION ALL SELECT 'order_item', COUNT(*) FROM dbo.order_item;
GO
""")


def write_changes_sql(d, ch, out):
    path = os.path.join(out, "sql", "04_source_changes_batch2.sql")
    cust, prod, ordr, itm = sql_rows(d["c2_new"], d["p2_new"], d["ord2"], d["it2"])
    first_order = d["ord2"].order_id.iloc[0]
    scd2 = ch["scd2"]
    in_list = ", ".join("'%s'" % u for u, _, _ in scd2)
    pr = d["pr"]

    def prow(pid):
        r = pr.loc[pid]
        return r

    with open(path, "w", encoding="utf-8-sig", newline="\n") as f:
        f.write("""/* =====================================================================
   04_source_changes_batch2.sql   (FILE SINH TỰ ĐỘNG bởi datasource/prepare_datasource.py)
   "MỘT NGÀY LÀM VIỆC MỚI Ở HỆ THỐNG NGUỒN"  -  chạy SAU lần nạp DDS đầu tiên.
   Mọi dòng thêm/sửa ở đây đều có created_at / updated_at = thời điểm chạy script,
   nên lần chạy SSIS tiếp theo (incremental extract) chỉ lấy đúng các dòng này.

   A. INSERT dữ liệu mới: đơn mua tháng 04/2017
        customer %d khách mới | product %d sản phẩm mới | orders %d đơn | order_item %d dòng hàng
        (%d khách khác mua cả đợt 1 và đợt 2 -> đã có sẵn trong customer, không INSERT lại;
         %d sản phẩm của đơn tháng 4 đã có từ đợt 1)
   B. SCD TYPE 2 (dim_customer): %d khách ĐỔI ĐỊA CHỈ  -> UPDATE customer + updated_at
   C. SCD TYPE 1 (dim_product) : 3 sản phẩm ĐỔI THUỘC TÍNH -> UPDATE product + updated_at
   D. UPSERT fact_sales        : 3 dòng hàng quý 1 bị SỬA GIÁ / PHÍ VẬN CHUYỂN -> UPDATE order_item + updated_at
   E. Lookup không khớp: trong dữ liệu mới có sản phẩm category NULL / chưa có bản dịch (vd pc_gamer)

   CHỈ CHẠY 1 LẦN (script tự dừng nếu thấy đợt 2 đã nằm trong nguồn).
   Muốn làm lại từ đầu:  sql\\reset_and_prepare.cmd
   Chạy:  sqlcmd -S localhost -E -C -f 65001 -b -i sql\\04_source_changes_batch2.sql
   ===================================================================== */
USE Olist_Source;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
-- Chốt chặn: nếu đơn đầu tiên của đợt 2 đã có thì không chạy nữa
IF EXISTS (SELECT 1 FROM dbo.orders WHERE order_id = '%s')
BEGIN
    RAISERROR (N'Đợt 2 đã được nạp vào nguồn rồi. Muốn làm lại hãy chạy sql\\reset_and_prepare.cmd', 16, 1);
    SET NOEXEC ON;
END
GO

PRINT N'=== A. INSERT dữ liệu mới (đơn mua tháng 04/2017) ===';
GO
""" % (len(cust), len(prod), len(ordr), len(itm), ch["shared_customers"],
       len(d["p2_ids_all"]) - len(prod), len(scd2), first_order))
        write_inserts(f, "customer", CUST_COLS, cust)
        write_inserts(f, "product", PROD_COLS, prod)
        write_inserts(f, "orders", ORD_COLS, ordr)
        write_inserts(f, "order_item", ITEM_COLS, itm)

        # ---- B. SCD2
        f.write("PRINT N'=== B. SCD TYPE 2: khách đổi địa chỉ ===';\nGO\n")
        f.write("/* %d khách mua cả 2 đợt VÀ có địa chỉ khác nhau giữa 2 đợt (đây là dữ liệu thật của Olist):\n"
                % len(scd2))
        for u, old, new in scd2:
            f.write("     %s : %s  ->  %s\n" % (u, " / ".join(old), " / ".join(new)))
        f.write("   Kỳ vọng ở dim_customer: mỗi khách có 2 dòng (cũ end_date có giá trị, mới end_date NULL);\n"
                "   đơn quý 1 vẫn trỏ customer_key cũ, đơn tháng 4 trỏ customer_key mới. */\n")
        f.write("-- Trước khi đổi:\n"
                "SELECT customer_unique_id, customer_zip_code_prefix, customer_city, customer_state, created_at, updated_at\n"
                "FROM dbo.customer WHERE customer_unique_id IN (%s);\n" % in_list)
        for u, old, new in scd2:
            f.write("UPDATE dbo.customer SET customer_zip_code_prefix = %s, customer_city = %s, customer_state = %s,\n"
                    "       updated_at = SYSDATETIME()\nWHERE customer_unique_id = '%s';\n"
                    % (sql_str(new[0]), sql_str(new[1]), sql_str(new[2]), u))
        f.write("-- Sau khi đổi:\n"
                "SELECT customer_unique_id, customer_zip_code_prefix, customer_city, customer_state, created_at, updated_at\n"
                "FROM dbo.customer WHERE customer_unique_id IN (%s);\nGO\n\n" % in_list)

        # ---- C. SCD1
        pw, pd_, pc = ch["scd1_weight"], ch["scd1_dims"], ch["scd1_cat"]
        rw, rd_, rc = prow(pw), prow(pd_), prow(pc)
        new_w = int(rw.product_weight_g) + 500
        nl, nh, nwid = int(rd_.product_length_cm) + 5, int(rd_.product_height_cm) + 3, int(rd_.product_width_cm) + 2
        f.write("PRINT N'=== C. SCD TYPE 1: sản phẩm đổi thuộc tính (ghi đè) ===';\nGO\n")
        f.write("/* %s : weight %s g -> %d g\n"
                "   %s : length/height/width %s/%s/%s cm -> %d/%d/%d cm\n"
                "   %s : category %s -> %s\n"
                "   Kỳ vọng ở dim_product: cập nhật tại chỗ, product_key KHÔNG đổi, KHÔNG thêm dòng. */\n"
                % (pw, rw.product_weight_g, new_w, pd_, rd_.product_length_cm, rd_.product_height_cm,
                   rd_.product_width_cm, nl, nh, nwid, pc, rc.product_category_name, ch["scd1_cat_new"]))
        ids3 = "'%s', '%s', '%s'" % (pw, pd_, pc)
        f.write("-- Trước khi đổi:\nSELECT * FROM dbo.product WHERE product_id IN (%s);\n" % ids3)
        f.write("UPDATE dbo.product SET product_weight_g = %d, updated_at = SYSDATETIME() WHERE product_id = '%s';\n"
                % (new_w, pw))
        f.write("UPDATE dbo.product SET product_length_cm = %d, product_height_cm = %d, product_width_cm = %d,\n"
                "       updated_at = SYSDATETIME() WHERE product_id = '%s';\n" % (nl, nh, nwid, pd_))
        f.write("UPDATE dbo.product SET product_category_name = '%s', updated_at = SYSDATETIME() WHERE product_id = '%s';\n"
                % (ch["scd1_cat_new"], pc))
        f.write("-- Sau khi đổi:\nSELECT * FROM dbo.product WHERE product_id IN (%s);\nGO\n\n" % ids3)

        # ---- D. fact upsert
        f.write("PRINT N'=== D. UPSERT fact_sales: sửa giá / phí vận chuyển của dòng hàng cũ ===';\nGO\n")
        f.write("/* Giả lập việc bên bán hàng sửa sai giá của các dòng hàng đã nhập trước đó:\n")
        for oid, iid, po, fo, pn, fn in ch["fixes"]:
            f.write("     %s #%d : price %s -> %s ; freight %s -> %s\n" % (oid, iid, po, pn, fo, fn))
        f.write("   Kỳ vọng ở fact_sales: UPDATE đúng %d dòng (số dòng fact KHÔNG tăng vì các dòng này),\n"
                "   customer_key / product_key / date_key của các dòng này giữ nguyên. */\n" % len(ch["fixes"]))
        cond = " OR ".join("(order_id = '%s' AND order_item_id = %d)" % (o, i) for o, i, *_ in ch["fixes"])
        f.write("-- Trước khi sửa:\nSELECT order_id, order_item_id, price, freight_value, updated_at FROM dbo.order_item WHERE %s;\n" % cond)
        for oid, iid, po, fo, pn, fn in ch["fixes"]:
            f.write("UPDATE dbo.order_item SET price = %s, freight_value = %s, updated_at = SYSDATETIME()\n"
                    "WHERE order_id = '%s' AND order_item_id = %d;\n" % (pn, fn, oid, iid))
        f.write("-- Sau khi sửa:\nSELECT order_id, order_item_id, price, freight_value, updated_at FROM dbo.order_item WHERE %s;\nGO\n\n" % cond)

        # ---- E. lookup no-match
        f.write("""PRINT N'=== E. Kiểm tra dữ liệu để Lookup đi nhánh "không khớp" ===';
GO
-- Sản phẩm có category NULL hoặc chưa có bản dịch trong product_category (-> dim_product dùng 'Unknown')
SELECT COUNT(*) AS sp_khong_co_ban_dich
FROM dbo.product p
WHERE p.product_category_name IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.product_category c WHERE c.product_category_name = p.product_category_name);
GO

SET NOEXEC OFF;
GO
PRINT N'Hoàn tất: đã tạo "dữ liệu thay đổi" ở nguồn. Chạy lại package Master.dtsx để nạp tăng dần.';
GO
SELECT 'customer' AS bang, COUNT(*) AS so_dong, SUM(CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END) AS so_dong_da_sua FROM dbo.customer
UNION ALL SELECT 'product',    COUNT(*), SUM(CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END) FROM dbo.product
UNION ALL SELECT 'orders',     COUNT(*), SUM(CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END) FROM dbo.orders
UNION ALL SELECT 'order_item', COUNT(*), SUM(CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END) FROM dbo.order_item;
GO
""")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", default=os.environ.get("OLIST_RAW", DEFAULT_RAW),
                    help="thư mục chứa các file CSV gốc của Kaggle (mặc định: %s)" % DEFAULT_RAW)
    ap.add_argument("--out", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    help="thư mục gốc của bài (mặc định: thư mục cha của datasource/)")
    a = ap.parse_args()

    d = build(a.raw)
    ch = pick_changes(d)
    write_all_csv(d, a.out)
    write_seed_sql(d, a.out)
    write_changes_sql(d, ch, a.out)

    print("Đợt 1: customer=%d product=%d orders=%d order_item=%d product_category=%d"
          % (len(d["c1"]), len(d["p1"]), len(d["ord1"]), len(d["it1"]), len(d["cat"])))
    print("Đợt 2: customer(mới)=%d product(mới)=%d orders=%d order_item=%d  (khách mua cả 2 đợt: %d)"
          % (len(d["c2_new"]), len(d["p2_new"]), len(d["ord2"]), len(d["it2"]), ch["shared_customers"]))
    print("SCD2 (khách đổi địa chỉ):", [(u, o, n) for u, o, n in ch["scd2"]])
    print("SCD1 sản phẩm:", ch["scd1_weight"], ch["scd1_dims"], ch["scd1_cat"], "->", ch["scd1_cat_new"])
    print("Sửa giá item:", ch["fixes"])


if __name__ == "__main__":
    main()
