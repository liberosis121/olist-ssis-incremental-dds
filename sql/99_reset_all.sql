/* =====================================================================
   99_reset_all.sql
   Xóa cả 2 database của bài (Olist_Source, Olist_DDS) để làm lại từ đầu.
   Sau đó chạy lần lượt: 01 -> 02 -> 03  (hoặc chạy sql\reset_and_prepare.cmd).
   Chỉ đụng tới 2 database của bài này, không đụng database nào khác.
   ===================================================================== */
USE master;
GO
IF DB_ID(N'Olist_Source') IS NOT NULL
BEGIN
    ALTER DATABASE Olist_Source SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Olist_Source;
END
GO
IF DB_ID(N'Olist_DDS') IS NOT NULL
BEGIN
    ALTER DATABASE Olist_DDS SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Olist_DDS;
END
GO
PRINT N'Đã xóa Olist_Source và Olist_DDS.';
GO
