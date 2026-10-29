/* =====================================================================
   01_create_source_db.sql
   Tạo database nguồn Olist_Source (giả lập hệ thống OLTP bán hàng).

   Dữ liệu gốc: Brazilian E-Commerce Public Dataset by Olist (Kaggle).
   Mỗi bảng có 2 cột phục vụ incremental extract:
     - created_at : thời điểm dòng được tạo trong nguồn (tự gán khi INSERT)
     - updated_at : thời điểm dòng được sửa gần nhất (NULL = chưa sửa lần nào)
   Package SSIS chỉ lấy các dòng có created_at hoặc updated_at nằm trong
   khoảng [LSET, CET)  (LSET = lần trích xuất thành công trước, CET = bây giờ).

   Cách chạy: SSMS (Ctrl+Shift+C ở chế độ SQLCMD không cần) hoặc
       sqlcmd -S localhost -E -C -f 65001 -b -i sql\01_create_source_db.sql
   CẢNH BÁO: chạy lại sẽ XÓA và tạo lại Olist_Source.
   ===================================================================== */
USE master;
GO
IF DB_ID(N'Olist_Source') IS NOT NULL
BEGIN
    ALTER DATABASE Olist_Source SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Olist_Source;
END
GO
CREATE DATABASE Olist_Source;
GO
USE Olist_Source;
GO

/* Danh mục sản phẩm + bản dịch tiếng Anh (file product_category_name_translation.csv) */
CREATE TABLE dbo.product_category
(
    product_category_name         VARCHAR(100) NOT NULL,   -- tên tiếng Bồ Đào Nha (khóa)
    product_category_name_english VARCHAR(100) NOT NULL,
    created_at                    DATETIME2(3) NOT NULL CONSTRAINT DF_product_category_created DEFAULT SYSDATETIME(),
    updated_at                    DATETIME2(3) NULL,
    CONSTRAINT PK_product_category PRIMARY KEY (product_category_name)
);

/* Khách hàng: 1 dòng / khách thật (customer_unique_id) */
CREATE TABLE dbo.customer
(
    customer_unique_id       VARCHAR(32)   NOT NULL,       -- khóa nghiệp vụ (business key)
    customer_zip_code_prefix CHAR(5)       NOT NULL,       -- giữ dạng text để không mất số 0 đầu
    customer_city            NVARCHAR(100) NOT NULL,
    customer_state           CHAR(2)       NOT NULL,
    created_at               DATETIME2(3)  NOT NULL CONSTRAINT DF_customer_created DEFAULT SYSDATETIME(),
    updated_at               DATETIME2(3)  NULL,
    CONSTRAINT PK_customer PRIMARY KEY (customer_unique_id)
);

/* Sản phẩm (đã đổi tên cột sai chính tả *_lenght; bỏ cột độ dài tên/mô tả vì không dùng) */
CREATE TABLE dbo.product
(
    product_id            VARCHAR(32)  NOT NULL,
    product_category_name VARCHAR(100) NULL,               -- có thể NULL hoặc chưa có bản dịch
    product_photos_qty    INT          NULL,
    product_weight_g      INT          NULL,
    product_length_cm     INT          NULL,
    product_height_cm     INT          NULL,
    product_width_cm      INT          NULL,
    created_at            DATETIME2(3) NOT NULL CONSTRAINT DF_product_created DEFAULT SYSDATETIME(),
    updated_at            DATETIME2(3) NULL,
    CONSTRAINT PK_product PRIMARY KEY (product_id)
);
-- Không đặt FK product -> product_category vì dữ liệu thật có sản phẩm
-- không có category (NULL) hoặc category chưa có bản dịch (vd: pc_gamer).

/* Đơn hàng */
CREATE TABLE dbo.orders
(
    order_id                      VARCHAR(32)  NOT NULL,
    customer_unique_id            VARCHAR(32)  NOT NULL,
    order_status                  VARCHAR(20)  NOT NULL,
    order_purchase_timestamp      DATETIME2(0) NOT NULL,
    order_approved_at             DATETIME2(0) NULL,
    order_delivered_customer_date DATETIME2(0) NULL,
    order_estimated_delivery_date DATETIME2(0) NULL,
    created_at                    DATETIME2(3) NOT NULL CONSTRAINT DF_orders_created DEFAULT SYSDATETIME(),
    updated_at                    DATETIME2(3) NULL,
    CONSTRAINT PK_orders PRIMARY KEY (order_id),
    CONSTRAINT FK_orders_customer FOREIGN KEY (customer_unique_id) REFERENCES dbo.customer (customer_unique_id)
);

/* Dòng hàng của đơn (1 dòng = 1 sản phẩm trong 1 đơn) */
CREATE TABLE dbo.order_item
(
    order_id      VARCHAR(32)   NOT NULL,
    order_item_id SMALLINT      NOT NULL,                  -- số thứ tự dòng trong đơn
    product_id    VARCHAR(32)   NOT NULL,
    price         DECIMAL(10,2) NOT NULL,
    freight_value DECIMAL(10,2) NOT NULL,
    created_at    DATETIME2(3)  NOT NULL CONSTRAINT DF_order_item_created DEFAULT SYSDATETIME(),
    updated_at    DATETIME2(3)  NULL,
    CONSTRAINT PK_order_item PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT FK_order_item_orders  FOREIGN KEY (order_id)   REFERENCES dbo.orders (order_id),
    CONSTRAINT FK_order_item_product FOREIGN KEY (product_id) REFERENCES dbo.product (product_id)
);
GO

-- Chỉ mục hỗ trợ truy vấn incremental theo created_at / updated_at
CREATE INDEX IX_customer_created   ON dbo.customer   (created_at) INCLUDE (updated_at);
CREATE INDEX IX_product_created    ON dbo.product    (created_at) INCLUDE (updated_at);
CREATE INDEX IX_orders_created     ON dbo.orders     (created_at) INCLUDE (updated_at);
CREATE INDEX IX_order_item_created ON dbo.order_item (created_at) INCLUDE (updated_at);
GO
PRINT N'Đã tạo Olist_Source (5 bảng, rỗng). Chạy tiếp 02_seed_source_batch1.sql.';
GO
