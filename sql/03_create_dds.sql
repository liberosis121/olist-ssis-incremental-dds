/* =====================================================================
   03_create_dds.sql  -  SCRIPT TẠO DDS (Dimensional Data Store)
   Database: Olist_DDS  (star schema đơn giản, 3 chiều + 1 fact)

     dim_date      (chiều thời gian, khóa = YYYYMMDD)
     dim_customer  (chiều khách hàng  - SCD type 2: lưu lịch sử địa chỉ)
     dim_product   (chiều sản phẩm    - SCD type 1: ghi đè)
     fact_sales    (grain: 1 dòng = 1 sản phẩm (order_item) trong 1 đơn hàng)

   Metadata (schema meta):
     meta.data_flow : LSET/CET của từng luồng nạp (incremental extract)
     meta.etl_log   : nhật ký mỗi lần chạy package (số dòng, trạng thái, lỗi)

   QUẢN LÝ KHÓA
     - Mỗi chiều có surrogate key (SK) INT IDENTITY, do DDS tự cấp, độc lập với nguồn.
     - Giữ lại business key (BK) của nguồn để tra cứu / so khớp.
     - Mỗi chiều có "unknown member" với SK = -1 dành cho dòng fact không tra ra được chiều.
       (dim_date không IDENTITY: khóa = YYYYMMDD do ta tự tính.)
     - fact_sales: khóa chính = (order_id, order_item_id)  (degenerate dimension),
       các cột *_key là khóa ngoại tới 3 chiều.

   Cách chạy:  sqlcmd -S localhost -E -C -f 65001 -b -i sql\03_create_dds.sql
   CẢNH BÁO: chạy lại sẽ XÓA và tạo lại Olist_DDS.
   ===================================================================== */
-- Bắt buộc bật 2 tùy chọn này (sqlcmd mặc định tắt) vì có computed column + filtered index
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE master;
GO
IF DB_ID(N'Olist_DDS') IS NOT NULL
BEGIN
    ALTER DATABASE Olist_DDS SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Olist_DDS;
END
GO
CREATE DATABASE Olist_DDS;
GO
USE Olist_DDS;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE SCHEMA meta;
GO

/* ---------------------------------------------------------------------
   METADATA
   --------------------------------------------------------------------- */
-- Mỗi luồng nạp (1 package) có 1 dòng. status: 0 = đã xong, 1 = đang chạy / chưa xong.
-- LSET = Last Successful Extraction Time, CET = Current Extraction Time.
CREATE TABLE meta.data_flow
(
    name   VARCHAR(50)  NOT NULL,
    status INT          NOT NULL,
    LSET   DATETIME2(3) NOT NULL,
    CET    DATETIME2(3) NOT NULL,
    CONSTRAINT PK_data_flow PRIMARY KEY (name)
);

-- Nhật ký chạy: 1 dòng / lần chạy 1 package (Row Count của data flow được ghi vào đây)
CREATE TABLE meta.etl_log
(
    log_id           INT IDENTITY(1,1) NOT NULL,
    execution_id     UNIQUEIDENTIFIER  NOT NULL,            -- System::ExecutionInstanceGUID
    package_name     VARCHAR(100)      NOT NULL,
    start_time       DATETIME2(3)      NOT NULL,
    end_time         DATETIME2(3)      NULL,
    status           VARCHAR(10)       NOT NULL,            -- SUCCESS / FAILED
    lset             DATETIME2(3)      NULL,
    cet              DATETIME2(3)      NULL,
    rows_extracted   INT               NULL,                -- số dòng lấy từ nguồn
    rows_inserted    INT               NULL,                -- số dòng thêm mới vào DDS
    rows_updated     INT               NULL,                -- số dòng cập nhật (SCD1 / upsert / hết hạn SCD2)
    rows_unchanged   INT               NULL,                -- số dòng lấy ra nhưng không có gì thay đổi
    error_message    NVARCHAR(4000)    NULL,
    CONSTRAINT PK_etl_log PRIMARY KEY (log_id)
);
CREATE UNIQUE INDEX UX_etl_log_execution ON meta.etl_log (execution_id, package_name);

INSERT INTO meta.data_flow (name, status, LSET, CET)
VALUES ('dim_date',     0, '1900-01-01', '1900-01-01'),
       ('dim_customer', 0, '1900-01-01', '1900-01-01'),
       ('dim_product',  0, '1900-01-01', '1900-01-01'),
       ('fact_sales',   0, '1900-01-01', '1900-01-01');
GO

/* ---------------------------------------------------------------------
   DIM_DATE  -  khóa = YYYYMMDD (vd 20170405), package DDS_DimDate sinh các ngày còn thiếu
   --------------------------------------------------------------------- */
CREATE TABLE dbo.dim_date
(
    date_key           INT          NOT NULL,        -- YYYYMMDD
    full_date          DATE         NOT NULL,
    day_of_month       TINYINT      NOT NULL,
    month_number       TINYINT      NOT NULL,
    month_name         VARCHAR(20)  NOT NULL,
    quarter_number     TINYINT      NOT NULL,
    year_number        SMALLINT     NOT NULL,
    day_of_week_number TINYINT      NOT NULL,        -- 1 = Thứ hai ... 7 = Chủ nhật
    day_name           VARCHAR(20)  NOT NULL,
    is_weekend         BIT          NOT NULL,
    CONSTRAINT PK_dim_date PRIMARY KEY (date_key)
);
-- Unknown member
INSERT INTO dbo.dim_date (date_key, full_date, day_of_month, month_number, month_name, quarter_number,
                          year_number, day_of_week_number, day_name, is_weekend)
VALUES (-1, '1900-01-01', 1, 1, N'Không xác định', 1, 1900, 1, N'Không xác định', 0);
GO

/* ---------------------------------------------------------------------
   DIM_CUSTOMER  -  SCD TYPE 2 (mỗi lần đổi địa chỉ -> thêm 1 dòng mới, dòng cũ bị đóng lại)
     Phiên bản hiện hành : end_date IS NULL  (is_current = 1)
     Phiên bản đã hết hạn: end_date có giá trị = thời điểm phiên bản mới có hiệu lực
   --------------------------------------------------------------------- */
CREATE TABLE dbo.dim_customer
(
    customer_key             INT IDENTITY(1,1) NOT NULL,   -- surrogate key
    customer_unique_id       VARCHAR(32)       NOT NULL,   -- business key (nguồn: customer.customer_unique_id)
    customer_zip_code_prefix CHAR(5)           NULL,       -- 3 cột dưới là Historical attribute
    customer_city            NVARCHAR(100)     NULL,
    customer_state           CHAR(2)           NULL,
    start_date               DATETIME2(3)      NOT NULL,   -- hiệu lực từ
    end_date                 DATETIME2(3)      NULL,       -- hiệu lực đến (NULL = còn hiệu lực)
    is_current AS (CASE WHEN end_date IS NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END),
    CONSTRAINT PK_dim_customer PRIMARY KEY (customer_key)
);
-- Mỗi khách chỉ được có tối đa 1 phiên bản hiện hành
CREATE UNIQUE INDEX UX_dim_customer_current ON dbo.dim_customer (customer_unique_id) WHERE end_date IS NULL;
CREATE INDEX IX_dim_customer_bk ON dbo.dim_customer (customer_unique_id) INCLUDE (customer_key, end_date);

-- Unknown member (SK = -1)
SET IDENTITY_INSERT dbo.dim_customer ON;
INSERT INTO dbo.dim_customer (customer_key, customer_unique_id, customer_zip_code_prefix, customer_city,
                              customer_state, start_date, end_date)
VALUES (-1, 'UNKNOWN', NULL, N'Không xác định', 'XX', '1900-01-01', NULL);
SET IDENTITY_INSERT dbo.dim_customer OFF;
GO

/* ---------------------------------------------------------------------
   DIM_PRODUCT  -  SCD TYPE 1 (ghi đè, không giữ lịch sử; SK không đổi)
   product_category_name_english lấy từ bảng product_category của nguồn bằng Lookup
   (không khớp -> 'Unknown').
   --------------------------------------------------------------------- */
CREATE TABLE dbo.dim_product
(
    product_key                   INT IDENTITY(1,1) NOT NULL,  -- surrogate key
    product_id                    VARCHAR(32)       NOT NULL,  -- business key
    product_category_name         VARCHAR(100)      NULL,
    product_category_name_english VARCHAR(100)      NOT NULL,
    product_photos_qty            INT               NULL,
    product_weight_g              INT               NULL,
    product_length_cm             INT               NULL,
    product_height_cm             INT               NULL,
    product_width_cm              INT               NULL,
    CONSTRAINT PK_dim_product PRIMARY KEY (product_key),
    CONSTRAINT UQ_dim_product_bk UNIQUE (product_id)
);
SET IDENTITY_INSERT dbo.dim_product ON;
INSERT INTO dbo.dim_product (product_key, product_id, product_category_name, product_category_name_english)
VALUES (-1, 'UNKNOWN', NULL, N'Unknown');
SET IDENTITY_INSERT dbo.dim_product OFF;
GO

/* ---------------------------------------------------------------------
   FACT_SALES  -  grain: 1 dòng = 1 dòng hàng (order_item) của 1 đơn hàng
   Upsert theo khóa (order_id, order_item_id): chưa có -> INSERT, có rồi mà đổi giá -> UPDATE.
   total_amount là computed column (= price + freight_value) nên luôn khớp 2 cột gốc.
   --------------------------------------------------------------------- */
CREATE TABLE dbo.fact_sales
(
    order_id       VARCHAR(32)   NOT NULL,      -- degenerate dimension
    order_item_id  SMALLINT      NOT NULL,      -- degenerate dimension
    date_key       INT           NOT NULL,      -- ngày mua
    customer_key   INT           NOT NULL,      -- phiên bản khách hiện hành lúc nạp
    product_key    INT           NOT NULL,
    price          DECIMAL(10,2) NOT NULL,
    freight_value  DECIMAL(10,2) NOT NULL,
    total_amount   AS (price + freight_value) PERSISTED,
    dds_created_at DATETIME2(3)  NOT NULL CONSTRAINT DF_fact_sales_created DEFAULT SYSDATETIME(),
    dds_updated_at DATETIME2(3)  NULL,          -- thời điểm DDS sửa dòng này (NULL = chưa sửa)
    CONSTRAINT PK_fact_sales PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT FK_fact_sales_date     FOREIGN KEY (date_key)     REFERENCES dbo.dim_date (date_key),
    CONSTRAINT FK_fact_sales_customer FOREIGN KEY (customer_key) REFERENCES dbo.dim_customer (customer_key),
    CONSTRAINT FK_fact_sales_product  FOREIGN KEY (product_key)  REFERENCES dbo.dim_product (product_key)
);
CREATE INDEX IX_fact_sales_customer ON dbo.fact_sales (customer_key);
CREATE INDEX IX_fact_sales_product  ON dbo.fact_sales (product_key);
CREATE INDEX IX_fact_sales_date     ON dbo.fact_sales (date_key);
GO
PRINT N'Đã tạo Olist_DDS (3 chiều + fact_sales + meta). Chưa có dữ liệu - chạy package SSIS Master.dtsx để nạp.';
GO
