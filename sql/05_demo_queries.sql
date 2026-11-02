/* =====================================================================
   05_demo_queries.sql  -  CÁC TRUY VẤN ĐỂ XEM DỮ LIỆU TRƯỚC / SAU KHI NẠP (dùng khi quay video)
   Chạy từng khối trong SSMS (bôi đen một khối rồi bấm F5). Khối nào cũng chỉ ĐỌC dữ liệu.

   Thứ tự trong video:
     [A] trước lần nạp đầu          -> chạy Master.dtsx lần 1
     [B] sau lần nạp đầu            -> chạy 04_source_changes_batch2.sql
     [C] nguồn đã thay đổi, DDS chưa -> chạy Master.dtsx lần 2
     [D] sau lần nạp tăng dần       -> chạy Master.dtsx lần 3
     [E] sau lần chạy thứ 3 (không có gì mới)
     [F] kiểm tra tổng quát
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ================================================================
   [A] TRƯỚC LẦN NẠP ĐẦU: nguồn đã có dữ liệu đợt 1, DDS còn trống
   ================================================================ */
-- A1. Số dòng các bảng ở NGUỒN (Olist_Source)
SELECT 'customer' AS bang, COUNT(*) AS so_dong FROM Olist_Source.dbo.customer
UNION ALL SELECT 'product',          COUNT(*) FROM Olist_Source.dbo.product
UNION ALL SELECT 'product_category', COUNT(*) FROM Olist_Source.dbo.product_category
UNION ALL SELECT 'orders',           COUNT(*) FROM Olist_Source.dbo.orders
UNION ALL SELECT 'order_item',       COUNT(*) FROM Olist_Source.dbo.order_item;

-- A2. Vài dòng của nguồn (có created_at / updated_at phục vụ incremental extract)
SELECT TOP (5) * FROM Olist_Source.dbo.customer   ORDER BY customer_unique_id;
SELECT TOP (5) * FROM Olist_Source.dbo.product    ORDER BY product_id;
SELECT TOP (5) * FROM Olist_Source.dbo.order_item ORDER BY order_id, order_item_id;

-- A3. DDS còn trống: chỉ có dòng "unknown member" (khóa -1)
SELECT 'dim_date' AS bang, COUNT(*) AS so_dong FROM Olist_DDS.dbo.dim_date
UNION ALL SELECT 'dim_customer', COUNT(*) FROM Olist_DDS.dbo.dim_customer
UNION ALL SELECT 'dim_product',  COUNT(*) FROM Olist_DDS.dbo.dim_product
UNION ALL SELECT 'fact_sales',   COUNT(*) FROM Olist_DDS.dbo.fact_sales;
SELECT * FROM Olist_DDS.dbo.dim_customer;   -- chỉ có customer_key = -1
SELECT * FROM Olist_DDS.dbo.dim_product;    -- chỉ có product_key  = -1

-- A4. Metadata: LSET = 1900-01-01 nghĩa là chưa nạp lần nào -> lần đầu sẽ lấy TOÀN BỘ dữ liệu nguồn
SELECT * FROM Olist_DDS.meta.data_flow;
SELECT * FROM Olist_DDS.meta.etl_log;
GO

/* ================================================================
   [B] SAU LẦN NẠP ĐẦU (Master.dtsx lần 1)
   ================================================================ */
-- B1. Số dòng DDS (kỳ vọng: dim_customer 5153+1, dim_product 3068+1, fact_sales 5906, dim_date 86+1)
SELECT 'dim_date' AS bang, COUNT(*) AS so_dong FROM Olist_DDS.dbo.dim_date
UNION ALL SELECT 'dim_customer', COUNT(*) FROM Olist_DDS.dbo.dim_customer
UNION ALL SELECT 'dim_product',  COUNT(*) FROM Olist_DDS.dbo.dim_product
UNION ALL SELECT 'fact_sales',   COUNT(*) FROM Olist_DDS.dbo.fact_sales;

-- B2. Surrogate key do DDS tự cấp (IDENTITY), business key giữ từ nguồn, unknown member = -1
SELECT TOP (5) customer_key, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state, start_date, end_date, is_current
FROM Olist_DDS.dbo.dim_customer ORDER BY customer_key;
SELECT TOP (5) product_key, product_id, product_category_name, product_category_name_english, product_weight_g
FROM Olist_DDS.dbo.dim_product ORDER BY product_key;
SELECT * FROM Olist_DDS.dbo.dim_customer WHERE customer_key = -1;
SELECT * FROM Olist_DDS.dbo.dim_product  WHERE product_key  = -1;

-- B3. Lookup tên category tiếng Anh; sản phẩm không có bản dịch -> 'Unknown'
SELECT TOP (3) product_id, product_category_name, product_category_name_english FROM Olist_DDS.dbo.dim_product WHERE product_category_name_english <> 'Unknown' AND product_key > 0;
SELECT TOP (3) product_id, product_category_name, product_category_name_english FROM Olist_DDS.dbo.dim_product WHERE product_category_name_english = 'Unknown' AND product_key > 0;

-- B4. fact_sales: mỗi dòng = 1 order_item; khóa chính = 3 khóa chiều + degenerate dimension (order_id, order_item_id)
SELECT TOP (5) f.date_key, f.customer_key, f.product_key, f.order_id, f.order_item_id, f.price, f.freight_value, f.total_amount
FROM Olist_DDS.dbo.fact_sales f ORDER BY f.date_key, f.customer_key, f.product_key, f.order_id, f.order_item_id;
-- B4b. Vì sao phải thêm degenerate dimension: chỉ 3 khóa chiều thì còn trùng
--      (cùng khách mua cùng sản phẩm cùng ngày - phần lớn là 1 đơn mua nhiều đơn vị cùng sản phẩm)
SELECT N'(date_key, customer_key, product_key)' AS to_hop_khoa, COUNT(*) AS so_nhom_trung
FROM (SELECT date_key, customer_key, product_key FROM Olist_DDS.dbo.fact_sales GROUP BY date_key, customer_key, product_key HAVING COUNT(*) > 1) x
UNION ALL SELECT N'+ order_id', COUNT(*)
FROM (SELECT date_key, customer_key, product_key, order_id FROM Olist_DDS.dbo.fact_sales GROUP BY date_key, customer_key, product_key, order_id HAVING COUNT(*) > 1) x
UNION ALL SELECT N'+ order_id + order_item_id (khóa chính)', COUNT(*)
FROM (SELECT date_key, customer_key, product_key, order_id, order_item_id FROM Olist_DDS.dbo.fact_sales GROUP BY date_key, customer_key, product_key, order_id, order_item_id HAVING COUNT(*) > 1) x;

-- B5. Đối chiếu tổng tiền nguồn <-> DDS (phải bằng nhau: 741960.19 / 113557.51)
SELECT 'nguon' AS noi, SUM(price) AS tong_price, SUM(freight_value) AS tong_freight FROM Olist_Source.dbo.order_item
UNION ALL SELECT 'dds', SUM(price), SUM(freight_value) FROM Olist_DDS.dbo.fact_sales;

-- B6. Metadata: LSET của mỗi luồng đã tiến lên bằng CET của lần chạy, status = 0
SELECT * FROM Olist_DDS.meta.data_flow;
-- B7. Nhật ký chạy (số dòng lấy ra / thêm / sửa / không đổi)
SELECT log_id, package_name, status, lset, cet, rows_extracted, rows_inserted, rows_updated, rows_unchanged,
       DATEDIFF(MILLISECOND, start_time, end_time) AS ms, error_message
FROM Olist_DDS.meta.etl_log ORDER BY log_id;
GO

/* ================================================================
   [C] NGUỒN ĐÃ THAY ĐỔI (sau khi chạy 04_source_changes_batch2.sql), DDS CHƯA ĐỔI
   ================================================================ */
-- C1. Nguồn tăng thêm dữ liệu tháng 4 (kỳ vọng: customer 7506, product 4187, orders 7666, order_item 8590)
SELECT 'customer' AS bang, COUNT(*) AS so_dong FROM Olist_Source.dbo.customer
UNION ALL SELECT 'product',    COUNT(*) FROM Olist_Source.dbo.product
UNION ALL SELECT 'orders',     COUNT(*) FROM Olist_Source.dbo.orders
UNION ALL SELECT 'order_item', COUNT(*) FROM Olist_Source.dbo.order_item;

-- C2. Các dòng ĐÃ BỊ SỬA ở nguồn (updated_at khác NULL): 3 khách đổi địa chỉ, 3 sản phẩm đổi thuộc tính, 3 dòng hàng sửa giá
SELECT 'SCD2 - customer' AS loai, customer_unique_id AS khoa, customer_zip_code_prefix AS zip, customer_city AS city, customer_state AS state, created_at, updated_at
FROM Olist_Source.dbo.customer WHERE updated_at IS NOT NULL;
SELECT 'SCD1 - product' AS loai, product_id, product_category_name, product_weight_g, product_length_cm, product_height_cm, product_width_cm, updated_at
FROM Olist_Source.dbo.product WHERE updated_at IS NOT NULL;
SELECT 'Upsert - order_item' AS loai, order_id, order_item_id, price, freight_value, updated_at
FROM Olist_Source.dbo.order_item WHERE updated_at IS NOT NULL;

-- C3. DDS CHƯA đổi: 3 khách vẫn chỉ có 1 dòng (địa chỉ cũ); 3 sản phẩm còn giá trị cũ; fact còn giá cũ
SELECT customer_key, customer_unique_id, customer_zip_code_prefix, customer_city, start_date, end_date, is_current
FROM Olist_DDS.dbo.dim_customer
WHERE customer_unique_id IN ('c51a1ea9fa9851c70f89d1178c861150', 'd3f15df5924e63131bcdac6364b6a6fd', 'da5bbfd583efb762f6fda762f1aaf4a9')
ORDER BY customer_unique_id, customer_key;
SELECT product_key, product_id, product_category_name, product_category_name_english, product_weight_g, product_length_cm, product_height_cm, product_width_cm
FROM Olist_DDS.dbo.dim_product
WHERE product_id IN ('0152f69b6cf919bcdaf117aa8c43e5a2', '0233dd6f06e23c705ab76dc3ab165837', '02ce467092b184e71d3967d29110adc1') ORDER BY product_id;
SELECT order_id, order_item_id, customer_key, product_key, price, freight_value, total_amount, dds_updated_at
FROM Olist_DDS.dbo.fact_sales
WHERE (order_id = '00042b26cf59d7ce69dfabb4e55b4fd9' AND order_item_id = 1) OR (order_id = '00125cb692d04887809806618a2a145f' AND order_item_id = 1)
   OR (order_id = '001dbc16dc51075e987543d23a0507c7' AND order_item_id = 1) ORDER BY order_id;

-- C4. Metadata: LSET vẫn là CET của lần nạp trước -> lần này chỉ lấy dòng có created_at/updated_at >= LSET
SELECT * FROM Olist_DDS.meta.data_flow;
GO

/* ================================================================
   [D] SAU LẦN NẠP TĂNG DẦN (Master.dtsx lần 2)
   ================================================================ */
-- D1. Số dòng DDS (kỳ vọng: dim_customer 7510, dim_product 4188, fact_sales 8590, dim_date 117)
SELECT 'dim_date' AS bang, COUNT(*) AS so_dong FROM Olist_DDS.dbo.dim_date
UNION ALL SELECT 'dim_customer', COUNT(*) FROM Olist_DDS.dbo.dim_customer
UNION ALL SELECT 'dim_product',  COUNT(*) FROM Olist_DDS.dbo.dim_product
UNION ALL SELECT 'fact_sales',   COUNT(*) FROM Olist_DDS.dbo.fact_sales;

-- D2. SCD TYPE 2: mỗi khách đổi địa chỉ có 2 dòng: dòng cũ có end_date (is_current = 0), dòng mới end_date NULL (is_current = 1)
SELECT customer_key, customer_unique_id, customer_zip_code_prefix, customer_city, start_date, end_date, is_current
FROM Olist_DDS.dbo.dim_customer
WHERE customer_unique_id IN ('c51a1ea9fa9851c70f89d1178c861150', 'd3f15df5924e63131bcdac6364b6a6fd', 'da5bbfd583efb762f6fda762f1aaf4a9')
ORDER BY customer_unique_id, customer_key;

-- D3. Đơn quý 1 của họ vẫn trỏ customer_key CŨ, đơn tháng 4 trỏ customer_key MỚI
SELECT c.customer_unique_id,
       CASE WHEN o.order_purchase_timestamp < '2017-04-01' THEN N'Quý 1 (đợt 1)' ELSE N'Tháng 4 (đợt 2)' END AS dot,
       f.customer_key, c.customer_city, c.is_current, COUNT(*) AS so_dong_fact
FROM Olist_DDS.dbo.fact_sales f
JOIN Olist_DDS.dbo.dim_customer c ON c.customer_key = f.customer_key
JOIN Olist_Source.dbo.orders o    ON o.order_id = f.order_id
WHERE c.customer_unique_id IN ('c51a1ea9fa9851c70f89d1178c861150', 'd3f15df5924e63131bcdac6364b6a6fd', 'da5bbfd583efb762f6fda762f1aaf4a9')
GROUP BY c.customer_unique_id, CASE WHEN o.order_purchase_timestamp < '2017-04-01' THEN N'Quý 1 (đợt 1)' ELSE N'Tháng 4 (đợt 2)' END, f.customer_key, c.customer_city, c.is_current
ORDER BY c.customer_unique_id, dot;

-- D4. SCD TYPE 1: sản phẩm được ghi đè tại chỗ, product_key GIỮ NGUYÊN (18 / 25 / 32), không thêm dòng
SELECT product_key, product_id, product_category_name, product_category_name_english, product_weight_g, product_length_cm, product_height_cm, product_width_cm
FROM Olist_DDS.dbo.dim_product
WHERE product_id IN ('0152f69b6cf919bcdaf117aa8c43e5a2', '0233dd6f06e23c705ab76dc3ab165837', '02ce467092b184e71d3967d29110adc1') ORDER BY product_id;

-- D5. UPSERT fact: 3 dòng cũ được UPDATE (giá mới, dds_updated_at có giá trị), key giữ nguyên; số dòng fact tăng đúng 2684
SELECT order_id, order_item_id, date_key, customer_key, product_key, price, freight_value, total_amount, dds_created_at, dds_updated_at
FROM Olist_DDS.dbo.fact_sales
WHERE (order_id = '00042b26cf59d7ce69dfabb4e55b4fd9' AND order_item_id = 1) OR (order_id = '00125cb692d04887809806618a2a145f' AND order_item_id = 1)
   OR (order_id = '001dbc16dc51075e987543d23a0507c7' AND order_item_id = 1) ORDER BY order_id;

-- D6. Nhật ký: lần 2 chỉ lấy đúng phần thay đổi (dim_date 30 | dim_customer 2356 = 2353 mới + 3 đổi | dim_product 1122 = 1119 mới + 3 đổi | fact 2687 = 2684 mới + 3 sửa)
SELECT log_id, package_name, status, lset, cet, rows_extracted, rows_inserted, rows_updated, rows_unchanged
FROM Olist_DDS.meta.etl_log ORDER BY log_id;
SELECT * FROM Olist_DDS.meta.data_flow;
GO

/* ================================================================
   [E] SAU LẦN CHẠY THỨ 3 (không có gì mới ở nguồn) -> 0 dòng, DDS không đổi
   ================================================================ */
-- E1. Lần chạy cuối cùng phải là 0 / 0 / 0 / 0 cho mọi package (xem 5 dòng cuối)
SELECT TOP (5) log_id, package_name, status, lset, cet, rows_extracted, rows_inserted, rows_updated, rows_unchanged
FROM Olist_DDS.meta.etl_log ORDER BY log_id DESC;
-- E2. Số dòng DDS không đổi so với [D1]; surrogate key không đổi (so với D2, D4)
SELECT 'dim_customer' AS bang, COUNT(*) AS so_dong FROM Olist_DDS.dbo.dim_customer
UNION ALL SELECT 'dim_product', COUNT(*) FROM Olist_DDS.dbo.dim_product
UNION ALL SELECT 'fact_sales',  COUNT(*) FROM Olist_DDS.dbo.fact_sales;
GO

/* ================================================================
   [F] KIỂM TRA TỔNG QUÁT (mọi giá trị "loi" phải bằng 0)
   ================================================================ */
SELECT N'Trùng khóa chính fact_sales' AS kiem_tra, COUNT(*) AS loi
FROM (SELECT date_key, customer_key, product_key, order_id, order_item_id FROM Olist_DDS.dbo.fact_sales GROUP BY date_key, customer_key, product_key, order_id, order_item_id HAVING COUNT(*) > 1) x
UNION ALL SELECT N'1 dòng hàng nguồn (order_id, order_item_id) bị nạp thành >1 dòng fact', COUNT(*)
FROM (SELECT order_id, order_item_id FROM Olist_DDS.dbo.fact_sales GROUP BY order_id, order_item_id HAVING COUNT(*) > 1) x
UNION ALL SELECT N'fact_sales mồ côi customer_key', COUNT(*) FROM Olist_DDS.dbo.fact_sales f LEFT JOIN Olist_DDS.dbo.dim_customer d ON d.customer_key = f.customer_key WHERE d.customer_key IS NULL
UNION ALL SELECT N'fact_sales mồ côi product_key',  COUNT(*) FROM Olist_DDS.dbo.fact_sales f LEFT JOIN Olist_DDS.dbo.dim_product  d ON d.product_key  = f.product_key  WHERE d.product_key  IS NULL
UNION ALL SELECT N'fact_sales mồ côi date_key',     COUNT(*) FROM Olist_DDS.dbo.fact_sales f LEFT JOIN Olist_DDS.dbo.dim_date     d ON d.date_key     = f.date_key     WHERE d.date_key     IS NULL
UNION ALL SELECT N'Khách có >1 phiên bản hiện hành', COUNT(*) FROM (SELECT customer_unique_id FROM Olist_DDS.dbo.dim_customer WHERE end_date IS NULL GROUP BY customer_unique_id HAVING COUNT(*) > 1) x
UNION ALL SELECT N'Dòng fact dùng unknown member (-1)', COUNT(*) FROM Olist_DDS.dbo.fact_sales WHERE customer_key = -1 OR product_key = -1 OR date_key = -1
UNION ALL SELECT N'Chênh lệch tổng price nguồn - DDS',
       CAST((SELECT SUM(price) FROM Olist_Source.dbo.order_item) - (SELECT SUM(price) FROM Olist_DDS.dbo.fact_sales) AS INT)
UNION ALL SELECT N'Chênh lệch số dòng order_item nguồn - fact',
       (SELECT COUNT(*) FROM Olist_Source.dbo.order_item) - (SELECT COUNT(*) FROM Olist_DDS.dbo.fact_sales)
UNION ALL SELECT N'Luồng nạp còn status = 1 (chưa xong)', COUNT(*) FROM Olist_DDS.meta.data_flow WHERE status <> 0
UNION ALL SELECT N'Lần chạy FAILED trong etl_log', COUNT(*) FROM Olist_DDS.meta.etl_log WHERE status = 'FAILED';
GO
