# Datasource của bài tập SSIS

## 1. Nguồn dữ liệu

**Brazilian E-Commerce Public Dataset by Olist** (Kaggle) — dữ liệu thật của một sàn thương mại điện tử Brazil,
khoảng 100 nghìn đơn hàng từ 09/2016 đến 10/2018.

- Link: <https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce>
- Giấy phép: **CC BY-NC-SA 4.0** (dùng cho mục đích học tập, phi thương mại).
- Đây cũng là dataset của mini project nhóm (Mage + dbt + PostgreSQL). Ở bài tập cá nhân này dữ liệu được nạp
  vào **SQL Server** để làm lại phần "Source → DDS" bằng **SSIS**.

Bài này chỉ dùng 5 trong 9 file CSV gốc (không dùng geolocation, payments, reviews, sellers):

| File gốc | Bảng trong `Olist_Source` |
|---|---|
| `olist_customers_dataset.csv` | `customer` (1 dòng / khách thật = `customer_unique_id`) |
| `olist_products_dataset.csv` | `product` |
| `product_category_name_translation.csv` | `product_category` |
| `olist_orders_dataset.csv` | `orders` |
| `olist_order_items_dataset.csv` | `order_item` |

## 2. Hai đợt dữ liệu (để mô phỏng incremental extract)

Dữ liệu tĩnh nên được chia theo **thời gian mua hàng** thành 2 đợt, mô phỏng "hôm nay nạp lần đầu" và "hôm sau có dữ liệu mới":

| | Đợt 1 – nạp ban đầu (`batch1_initial/`) | Đợt 2 – phát sinh thêm (`batch2_april/`) |
|---|---|---|
| Đơn mua | 01/01/2017 → 31/03/2017 | 01/04/2017 → 30/04/2017 |
| `orders.csv` | 5.262 đơn | 2.404 đơn |
| `order_item.csv` | 5.906 dòng hàng | 2.684 dòng hàng |
| `customer.csv` | 5.153 khách | 2.353 khách **mới** (còn 19 khách mua cả 2 đợt, đã có sẵn từ đợt 1) |
| `product.csv` | 3.068 sản phẩm | 1.119 sản phẩm **mới** (còn 544 sản phẩm đã có từ đợt 1) |
| `product_category.csv` | 71 dòng (toàn bộ bảng dịch) | không có |

Quy tắc lọc:

- Đơn vào đợt nào theo `order_purchase_timestamp`; dòng hàng đi theo đơn.
- Chỉ lấy khách / sản phẩm **xuất hiện trong các đơn của đợt đó**.
- Khách thật là `customer_unique_id` (file gốc có thêm `customer_id` = 1 id / đơn, bài này bỏ). Nếu khách có nhiều đơn
  trong cùng đợt thì lấy địa chỉ của **đơn mới nhất**. Mã zip giữ dạng text (`CHAR(5)`) để không mất số 0 đầu (vd `08240`).
- Đổi tên cột sai chính tả của dữ liệu gốc (`product_*_lenght`), bỏ 2 cột độ dài tên / mô tả sản phẩm cho gọn.

## 3. File trong thư mục này

| File | Vai trò |
|---|---|
| `prepare_datasource.py` | Đọc CSV gốc của Kaggle → ghi các file CSV bên dưới **và** sinh `sql/02_seed_source_batch1.sql`, `sql/04_source_changes_batch2.sql` |
| `batch1_initial/*.csv` | Đợt 1 (UTF-8, có dòng tiêu đề) |
| `batch2_april/*.csv` | Đợt 2 (UTF-8, có dòng tiêu đề) |

Các file CSV chỉ để **xem / đối chiếu**; việc nạp vào SQL Server dùng 2 file `.sql` (INSERT nhiều dòng) vì tài khoản dịch vụ
SQL Server không đọc được file trên ổ D: nên không dùng `BULK INSERT`.

### Chạy lại script sinh datasource

```powershell
py datasource\prepare_datasource.py                                   # CSV gốc ở đường dẫn mặc định
py datasource\prepare_datasource.py --raw "D:\duong-dan\csv-kaggle"   # hoặc chỉ ra thư mục CSV gốc
```

Cần Python 3 + pandas. Kết quả mang tính xác định (chạy lại cho đúng cùng file và cùng các `id` được chọn bên dưới).

## 4. "Một ngày làm việc mới" ở nguồn – `sql/04_source_changes_batch2.sql`

Ngoài việc thêm dữ liệu tháng 4, script này **sửa** một số dòng để minh họa từng kỹ thuật (mọi dòng đều đặt `updated_at = SYSDATETIME()`):

| Mục | Dòng được chọn | Thay đổi | Kỳ vọng ở DDS |
|---|---|---|---|
| **SCD type 2** (`dim_customer`) | khách `c51a1ea9fa9851c70f89d1178c861150` | zip 22775 → 22795 (Rio de Janeiro) | thêm dòng mới, dòng cũ có `end_date` |
| | khách `d3f15df5924e63131bcdac6364b6a6fd` | franca (SP, 14403) → diadema (SP, 09930) | như trên |
| | khách `da5bbfd583efb762f6fda762f1aaf4a9` | maringa (PR, 87020) → londrina (PR, 86050) | như trên |
| **SCD type 1** (`dim_product`) | sản phẩm `0152f69b6cf919bcdaf117aa8c43e5a2` | cân nặng 250 g → 750 g | ghi đè, `product_key` = 18 giữ nguyên |
| | sản phẩm `0233dd6f06e23c705ab76dc3ab165837` | dài/cao/rộng 20/16/16 → 25/19/18 cm | ghi đè, `product_key` = 25 |
| | sản phẩm `02ce467092b184e71d3967d29110adc1` | category `moveis_escritorio` → `utilidades_domesticas` | ghi đè cả tên category tiếng Anh, `product_key` = 32 |
| **Upsert fact** (`fact_sales`) | đơn `00042b26cf59d7ce69dfabb4e55b4fd9` #1 | price 199,90 → 189,90 | UPDATE đúng dòng, không thêm dòng |
| | đơn `00125cb692d04887809806618a2a145f` #1 | freight 25,51 → 30,51 | như trên |
| | đơn `001dbc16dc51075e987543d23a0507c7` #1 | price 69,90 → 62,91 và freight 18,00 → 20,50 | như trên |

Cả 3 khách SCD2 đều là **khách thật của Olist có địa chỉ khác nhau giữa đơn quý 1 và đơn tháng 4** (không phải dữ liệu tự bịa).
Mỗi khối trong `sql/04_source_changes_batch2.sql` đều có chú thích giá trị trước / sau và lệnh `SELECT` để xem lại.
