# Kịch bản quay video – Bài tập SSIS (Trần Kim Yến – 23120193)

> File này là ghi chú riêng để quay video, **không** nằm trong `23120193.zip`.
> Thời lượng mục tiêu: **12–15 phút**. Thoại để trong khung `> 🎙`, thao tác là các gạch đầu dòng.
> Số liệu trong kịch bản đã được chạy thật trên máy (29/10/2026). Nếu số trên màn hình khác, dừng quay và xem mục "Sự cố thường gặp" ở cuối.

---

## 0. Chuẩn bị (KHÔNG quay)

### 0.1 Đưa môi trường về trạng thái ban đầu
1. Mở File Explorer → `D:\HK7\BI\HW\SSIS_23120193\sql\` → **double-click `reset_and_prepare.cmd`**.
   Cửa sổ đen chạy khoảng 10–20 giây, cuối cùng hiện `=== XONG: moi truong da san sang (chua chay package) ===`.
   - Script này xoá rồi tạo lại 2 database: `Olist_Source` có dữ liệu đợt 1, `Olist_DDS` trống, LSET = 1900-01-01.
   - Mỗi lần muốn quay lại từ đầu thì chạy lại file này.

### 0.2 Mở SSMS 22
1. Mở **SQL Server Management Studio 22** → hộp *Connect*:
   - Server name: `localhost`
   - Authentication: `Windows Authentication`
   - Tích **Trust server certificate** (nếu có ô Encryption thì để `Optional`/`Mandatory` đều được khi đã tích Trust).
   - Bấm **Connect**.
2. *Object Explorer* bên trái → mở `Databases` → thấy `Olist_Source`, `Olist_DDS` (nếu chưa thấy: chuột phải `Databases` → **Refresh**).
3. **File → Open → File…** (Ctrl+O) → mở `sql\05_demo_queries.sql`.
4. Mở thêm (chưa chạy) `sql\04_source_changes_batch2.sql` và `sql\03_create_dds.sql` thành 2 tab khác.
5. Cách chạy **một khối**: bôi đen các dòng của khối (VD từ `-- A1.` đến hết A4) → bấm **F5** (hoặc nút *Execute*). SSMS chỉ chạy phần bôi đen. Kết quả hiện ở khung *Results* phía dưới, mỗi câu SELECT 1 lưới.
6. Phóng to chữ cho dễ đọc khi quay: giữ **Ctrl + lăn chuột** trong khung soạn thảo; kéo khung *Results* cao lên.

### 0.3 Mở project trong Visual Studio 2026
1. Mở **Visual Studio 2026** → *Open a project or solution* → chọn
   `D:\HK7\BI\HW\SSIS_23120193\SSIS_Olist_23120193\SSIS_Olist_23120193.slnx`.
2. Khung **Solution Explorer** (bên phải; nếu không thấy: *View → Solution Explorer*):
   - `Connection Managers`: `Olist_DDS.conmgr`, `Olist_Source.conmgr`
   - `SSIS Packages`: `DDS_DimCustomer.dtsx`, `DDS_DimDate.dtsx`, `DDS_DimProduct.dtsx`, `DDS_FactSales.dtsx`, `Master.dtsx`
3. Double-click lần lượt từng package để xem. Nếu các ô bị **chồng lên nhau / lộn xộn**: bấm vào nền trắng của tab → menu **Format → Auto Layout → Diagram** (làm cho cả tab *Control Flow* và tab *Data Flow*), rồi **Ctrl+S**.
4. ⚠ **Không double-click vào ô `Slowly Changing Dimension`** (nó mở wizard; nếu bấm Finish wizard sẽ sinh thêm một luồng chồng lên luồng có sẵn). Muốn xem cấu hình SCD thì dùng *Show Advanced Editor* (mục 3.4). Nếu lỡ mở wizard → bấm **Cancel**.
5. Khi đóng một hộp thoại editor của task/component trong lúc *giới thiệu* → bấm **Cancel** (không đổi gì). Nếu VS hỏi lưu thay đổi package → **No**.

### 0.4 Chạy thử một lượt trọn vẹn (rất nên làm)
Làm hết các bước 4 → 7 bên dưới một lần không quay để quen tay, xong **chạy lại `reset_and_prepare.cmd`** (bước 0.1). Sau khi reset, trong VS không cần làm gì thêm.

### 0.5 Công cụ quay
- **Snipping Tool** của Windows 11: **Win + Shift + R** → kéo chọn cả màn hình → bật micro (biểu tượng micro) → *Start*. Dừng bằng nút Stop trên thanh nhỏ phía trên. Video lưu `.mp4`.
  (Hoặc OBS Studio nếu bạn quen. Xbox Game Bar *không* hợp vì chỉ quay một cửa sổ, mà video cần chuyển qua lại VS ↔ SSMS.)
- Tắt thông báo (Focus / Do not disturb), đóng các tab không liên quan. Màn hình 1920×1080.
- Có thể quay thành nhiều đoạn (theo từng mục dưới đây) rồi ghép bằng **Clipchamp** (có sẵn trên Windows 11).

---

## 1. Mở đầu (≈ 0:00 – 1:00)

**Màn hình:** File Explorer mở thư mục `D:\HK7\BI\HW\SSIS_23120193` (hoặc README.md).

> 🎙 Em chào cô, em là Trần Kim Yến, MSSV 23120193. Đây là video bài tập cá nhân SSIS: tạo một DDS đơn giản dựa trên mini project Olist của nhóm, rồi xây dựng các SSIS package nạp dữ liệu từ source vào DDS theo phương pháp **incremental extract**, có áp dụng **SCD**, kiểm tra **upsert** và **quản lý khóa** trong DDS.
>
> Dữ liệu là bộ Brazilian E-Commerce của Olist trên Kaggle. Em dựng một database nguồn `Olist_Source` giả lập hệ thống bán hàng, và một DDS `Olist_DDS` dạng star schema với 3 chiều khách hàng, sản phẩm, thời gian và 1 bảng fact bán hàng.

- Chỉ chuột lần lượt các thư mục:
  - `datasource\`: *"dữ liệu nguồn: 2 đợt CSV – đợt 1 là đơn quý 1/2017, đợt 2 là đơn tháng 4/2017"*
  - `sql\`: *"script tạo database nguồn, script tạo DDS và script giả lập thay đổi ở nguồn"*
  - `SSIS_Olist_23120193\`: *"project SSIS gồm 5 package"*

---

## 2. Source và DDS trước khi nạp (≈ 1:00 – 3:00)

### 2.1 Script tạo DDS
**Màn hình:** SSMS, tab `03_create_dds.sql` (chỉ cuộn cho xem, KHÔNG chạy lại).

> 🎙 Đây là script tạo DDS. Chiều `dim_customer` dùng **SCD loại 2**: có khóa thay thế `customer_key` tự tăng (IDENTITY), khóa nghiệp vụ `customer_unique_id` lấy từ nguồn, và cặp cột `start_date`, `end_date` để giữ lịch sử khi khách đổi địa chỉ. Chiều `dim_product` dùng **SCD loại 1**, đổi thông tin thì ghi đè. Chiều `dim_date` có khóa dạng năm-tháng-ngày. Mỗi chiều có một dòng khóa **-1 "Unknown"** để fact không bị mồ côi khi tra khóa không thấy.
>
> Bảng `fact_sales` có grain là **một dòng = một sản phẩm trong một đơn hàng**, khóa chính là `order_id` + `order_item_id`, đo lường là `price`, `freight_value`, `total_amount`.
>
> Ngoài ra có schema `meta`: bảng `data_flow` lưu **LSET** – thời điểm trích xuất thành công gần nhất – và **CET** – thời điểm trích xuất hiện tại – cho từng luồng nạp, đúng như mẫu trong bài giảng; và bảng `etl_log` ghi nhật ký mỗi lần chạy.

- Cuộn tới các đoạn: `CREATE TABLE dbo.dim_customer` → `dim_product` → `fact_sales` → `meta.data_flow`.

### 2.2 Dữ liệu trước khi nạp – khối [A]
**Màn hình:** tab `05_demo_queries.sql` → bôi đen dòng **19 → 41** (A1 → A4) → **F5**.

> 🎙 Trước khi nạp: nguồn có 5.153 khách hàng, 3.068 sản phẩm, 5.262 đơn và 5.906 dòng chi tiết đơn. Mỗi bảng nguồn có cột `created_at` và `updated_at` – đây là căn cứ để trích xuất tăng dần.
>
> Bên DDS hiện đang trống, mỗi chiều chỉ có dòng -1. Bảng `data_flow` có LSET là năm 1900, nghĩa là chưa nạp lần nào, nên lần chạy đầu sẽ lấy toàn bộ dữ liệu nguồn.

- Lần lượt bấm vào các lưới kết quả: A1 (5 bảng nguồn), A2 (chỉ cột `created_at`, `updated_at` = NULL), A3 (DDS chỉ có -1), A4 (LSET = `1900-01-01`, `etl_log` rỗng).

---

## 3. Giới thiệu SSIS project (≈ 3:00 – 6:00)

**Màn hình:** Visual Studio.

### 3.1 Connection Managers và Master
- Double-click `Olist_Source.conmgr` → chỉ Server `localhost`, database `Olist_Source`, Windows Authentication → **Cancel**.

> 🎙 Project có 2 connection manager dùng chung: một nối tới database nguồn, một nối tới DDS, đều dùng Windows Authentication.

- Double-click **`Master.dtsx`** → tab *Control Flow*.

> 🎙 Package `Master` điều phối toàn bộ: chạy chiều thời gian, chiều khách hàng, chiều sản phẩm trước, rồi mới tới fact – vì fact phải tra khóa của các chiều. Cuối cùng ghi nhật ký.

### 3.2 Khung chung của mỗi package – lấy `DDS_DimCustomer` làm ví dụ
- Double-click **`DDS_DimCustomer.dtsx`** → tab *Control Flow*: 5 ô nối nhau
  `Set CET` → `Get LSET CET` → `Load dim_customer` → `Set LSET to CET` → `Write ETL log`.

> 🎙 Mỗi package làm theo đúng quy trình incremental extract trong bài giảng.

- Double-click **`Set CET`** → chỉ ô *SQLStatement* (`UPDATE meta.data_flow SET CET = SYSDATETIME(), status = 1 …`) → **Cancel**.
> 🎙 Bước 1, Set CET: ghi thời điểm hiện tại làm CET và đánh dấu luồng đang chạy.

- Double-click **`Get LSET CET`** → chỉ câu SELECT → bấm mục **Result Set** bên trái (2 dòng: `LSET` → `User::LSET`, `CET` → `User::CET`) → **Cancel**.
> 🎙 Bước 2, đọc LSET và CET từ bảng `data_flow` vào hai biến của package.

- Double-click **`Set LSET to CET`** → **Cancel**.
> 🎙 Bước 4, chỉ khi luồng dữ liệu chạy **thành công** – mũi tên xanh là ràng buộc Success – mới gán LSET = CET. Nếu lỗi giữa chừng thì LSET giữ nguyên, lần sau trích lại đúng khoảng đó, không mất dữ liệu.

- (Tuỳ chọn) Menu **SSIS → Variables** để chỉ các biến `LSET`, `CET`, `RowsExtracted`, `RowsNew`…

### 3.3 Data Flow của `DDS_DimCustomer` – SCD loại 2
- Double-click ô **`Load dim_customer`** (hoặc bấm tab **Data Flow**).
- Double-click **`Source customer`** → chỉ câu lệnh có `WHERE (created_at >= ? AND created_at < ?) OR (updated_at >= ? AND updated_at < ?)` → bấm nút **Parameters…** (4 tham số map với `User::LSET`, `User::CET`, `User::LSET`, `User::CET`) → **Cancel**, **Cancel**.

> 🎙 Nguồn chỉ lấy những khách được **tạo mới hoặc sửa** trong khoảng từ LSET đến trước CET. Bốn dấu chấm hỏi được gán bằng hai biến LSET và CET.

> 🎙 Dữ liệu đi vào component **Slowly Changing Dimension**. Component so sánh với `dim_customer` theo khóa nghiệp vụ `customer_unique_id` rồi chia luồng:
> – Khách chưa có → **New Output**.
> – Khách đổi zip, thành phố hoặc bang – là các thuộc tính **Historical** – thì đi nhánh **Historical Attribute Inserts Output**: ô *Set old row's expiry date* gán ngày hết hạn, *Expire the old row* cập nhật `end_date` cho dòng cũ, rồi gộp với khách mới qua *Union All*, gán *effective date* và chèn thành dòng mới với khóa thay thế mới.
> – Khách không đổi → **Unchanged Output**, chỉ đếm.

- Chỉ chuột theo từng nhánh khi nói.

### 3.4 Xem cấu hình SCD (không mở wizard)
- **Chuột phải** ô `Slowly Changing Dimension` → **Show Advanced Editor…**
  - Tab **Component Properties**: chỉ `SqlCommand` (đọc bảng `dim_customer`) và `CurrentRowWhere` = `[start_date] IS NOT NULL AND [end_date] IS NULL`.
  - Tab **Input and Output Properties** → mở `Slowly Changing Dimension Input` → `Input Columns` → bấm `customer_unique_id`: bên phải *Custom Properties* → `ColumnType = 1` (Business key); bấm `customer_city`: `ColumnType = 3` (Historical attribute).
  - Bấm **Cancel**.

> 🎙 Ở đây `customer_unique_id` là business key, còn zip, thành phố, bang là historical attribute – tức SCD loại 2. Dòng hiện hành là dòng có `end_date` rỗng.

### 3.5 `DDS_DimProduct` – Lookup + SCD loại 1
- Mở **`DDS_DimProduct.dtsx`** → tab **Data Flow**.

> 🎙 Chiều sản phẩm có thêm bước **Lookup** sang bảng loại sản phẩm để lấy tên tiếng Anh – đây là bước khử chuẩn hóa. Loại nào không có bản dịch thì đi nhánh *No Match* và được gán 'Unknown'. Sau đó SCD component cấu hình toàn bộ thuộc tính là **Changing attribute**, tức SCD loại 1: sản phẩm mới thì chèn, sản phẩm đổi thông tin thì đi *Changing Attribute Updates Output* và bị **ghi đè** tại chỗ, khóa giữ nguyên.

### 3.6 `DDS_FactSales` – tra khóa và upsert
- Mở **`DDS_FactSales.dtsx`** → tab **Data Flow**.

> 🎙 Fact lấy chi tiết đơn kèm đơn hàng, cũng theo LSET và CET. Ba Lookup lần lượt tra `date_key`, `customer_key` – chỉ lấy phiên bản khách **hiện hành** – và `product_key`. Không tìm thấy thì gán **-1** – đây là phần quản lý khóa.
>
> Sau đó Lookup vào chính `fact_sales` theo `order_id` và `order_item_id`. Dòng chưa có thì **Insert**. Dòng đã có thì Conditional Split so giá và phí vận chuyển: khác thì **Update**, giống thì bỏ qua. Đó chính là **upsert**: không bao giờ chèn trùng.

---

## 4. Nạp lần đầu (≈ 6:00 – 8:00)

**Màn hình:** Visual Studio.
1. Trong **Solution Explorer**: chuột phải **`Master.dtsx`** → **Execute Package**.
2. Đợi khoảng 15–20 giây. Các ô chuyển **vàng (đang chạy) → xanh lá có dấu ✓**. Visual Studio có thể tự mở thêm tab của từng package con.
3. Cuối màn hình hiện dòng *"Package execution completed with success. Click here to switch to design mode…"*.
4. **Trước khi dừng**: bấm sang tab package **`DDS_FactSales.dtsx`** (nếu tự mở) → tab **Data Flow** → chỉ số dòng trên mũi tên (VD `5,906 rows` từ nguồn đi tới *Insert rows to fact_sales*). Bấm tab **Progress** của `Master` để thấy log chi tiết.
   *(Nếu không thấy tab package con thì bỏ qua – số liệu sẽ xem ở SSMS.)*
5. Bấm link **"Click here to switch to design mode"** (hoặc **Shift+F5** / *Debug → Stop Debugging*). **Bắt buộc dừng** trước khi chạy lần sau.

> 🎙 Em chạy package Master lần thứ nhất. Vì LSET đang là năm 1900 nên lần này là nạp toàn bộ. Tất cả task đều xanh, tức chạy thành công.

**Màn hình:** SSMS → bôi đen **dòng 47 → 78** (khối [B]) → **F5**.

> 🎙 Sau lần nạp đầu:
> – DDS có 5.154 khách (5.153 + dòng -1), 3.069 sản phẩm, 87 ngày và 5.906 dòng fact – khớp với nguồn.
> – Khóa `customer_key`, `product_key` do DDS tự cấp từ 1 trở lên, khóa nghiệp vụ giữ nguyên từ nguồn.
> – Sản phẩm có loại chưa được dịch được gán 'Unknown'.
> – Tổng tiền ở nguồn và ở DDS bằng nhau: 741.960,19 và 113.557,51.
> – Bảng `data_flow`: LSET của 4 luồng đã tiến lên bằng CET của lần chạy, status về 0.
> – Bảng `etl_log` ghi số dòng lấy ra và chèn: 86 ngày, 5.153 khách, 3.068 sản phẩm, 5.906 dòng fact.

- Bấm vào từng lưới B1 → B7 khi nói. Ở B6, **khoanh vùng cột LSET** (ghi nhớ giá trị giờ này để so ở bước sau).

---

## 5. Giả lập dữ liệu mới / thay đổi ở nguồn (≈ 8:00 – 9:30)

**Màn hình:** SSMS, tab `04_source_changes_batch2.sql`.
1. Cuộn xuống **cuối file** cho xem 3 khối UPDATE (đổi địa chỉ 3 khách, đổi thông tin 3 sản phẩm, sửa giá 3 dòng hàng).
2. Bấm vào trong tab, **không bôi đen gì** → **F5** (chạy cả file, khoảng 4–5 giây). Thấy *Query executed successfully*.
3. Khung *Results* có sẵn các lưới "trước khi đổi / sau khi đổi" của 3 khối UPDATE → cuộn xuống cho xem nhanh (không bắt buộc, khối [C] bên dưới cũng cho thấy đủ). Tab *Messages* sẽ có rất nhiều dòng `(… rows affected)` – bình thường.

> 🎙 Bây giờ em giả lập một ngày làm việc mới ở hệ thống nguồn: thêm toàn bộ đơn hàng tháng 4/2017 cùng khách hàng và sản phẩm mới; 3 khách hàng cũ đổi địa chỉ; 3 sản phẩm đổi cân nặng, kích thước, có 1 sản phẩm đổi loại; và 3 dòng hàng của quý 1 bị sửa giá. Các dòng bị sửa đều được cập nhật cột `updated_at`.

**Màn hình:** tab `05_demo_queries.sql` → bôi đen **dòng 84 → 112** (khối [C]) → **F5**.

> 🎙 Nguồn đã tăng lên 7.506 khách, 4.187 sản phẩm, 8.590 dòng chi tiết. Ở đây là các dòng có `updated_at`.
>
> Ví dụ khách `d3f15df5…` chuyển từ Franca sang Diadema, sản phẩm có khóa 18 tăng cân nặng từ 250 lên 750 gam, dòng hàng `00042b26…` giảm giá từ 199,90 xuống 189,90.
>
> Bên DDS thì **chưa có gì thay đổi**, và LSET vẫn là thời điểm của lần nạp trước.

---

## 6. Nạp tăng dần (≈ 9:30 – 12:30) – phần quan trọng nhất

Để thấy rõ số dòng đi qua từng nhánh SCD, chạy **từng package theo đúng thứ tự** (thay vì Master):

| Thứ tự | Package | Mở tab Data Flow, chỉ vào… |
|---|---|---|
| 1 | `DDS_DimDate.dtsx` | 30 ngày mới của tháng 4 |
| 2 | `DDS_DimCustomer.dtsx` | **New Output 2,353 rows** · **Historical Attribute Inserts Output 3 rows** · Union All → Insert **2,356 rows** |
| 3 | `DDS_DimProduct.dtsx` | **New Output 1,119 rows** · **Changing Attribute Updates Output 3 rows** |
| 4 | `DDS_FactSales.dtsx` | nguồn **2,687 rows** → Insert **2,684 rows**, nhánh *Changed* → *Update fact_sales* **3 rows** |

Với **mỗi** package:
1. Double-click package trong Solution Explorer để mở → bấm tab **Data Flow** (để lúc chạy thấy số trên mũi tên).
2. Chuột phải package trong Solution Explorer → **Execute Package** (hoặc bấm **F5** khi đang mở đúng package đó – lưu ý *Debug → Start* có thể chạy package khởi động; dùng chuột phải cho chắc).
3. Đợi xanh hết → **chỉ chuột vào các con số** trên mũi tên khi nói.
4. **Shift+F5** (Stop Debugging) rồi mới chạy package kế tiếp.

> 🎙 Em chạy lại lần hai. Lần này LSET là thời điểm của lần trước, nên SSIS chỉ lấy những dòng mới hoặc mới bị sửa.
>
> **Chiều khách hàng:** 2.356 dòng được lấy ra. SCD component chia thành 2.353 khách mới đi New Output và 3 khách đổi địa chỉ đi Historical Attribute Inserts Output. Ba dòng cũ được gán ngày hết hạn, sau đó cả 2.356 dòng được chèn thành dòng hiện hành.
>
> **Chiều sản phẩm:** 1.119 sản phẩm mới được chèn; 3 sản phẩm thay đổi đi nhánh Changing Attribute Updates và bị ghi đè.
>
> **Fact:** 2.687 dòng được lấy ra. 2.684 dòng của tháng 4 được chèn mới; 3 dòng bị sửa giá đã có trong fact nên đi nhánh Update chứ không chèn trùng.

**Màn hình:** SSMS → bôi đen **dòng 118 → 155** (khối [D]) → **F5**.

> 🎙 Kiểm tra kết quả trong DDS:
> – D1: `dim_customer` có 7.510 dòng, `dim_product` 4.188, `fact_sales` 8.590 – bằng đúng số dòng chi tiết đơn ở nguồn.
> – D2, **SCD loại 2**: khách `d3f15df5…` giờ có 2 dòng. Dòng cũ ở Franca có `end_date` và `is_current = 0`. Dòng mới ở Diadema có khóa thay thế **mới**, `end_date` rỗng và `is_current = 1`.
> – D3: các đơn quý 1 của khách này vẫn trỏ về **khóa cũ**, đơn tháng 4 trỏ về **khóa mới**. Như vậy báo cáo theo thời gian vẫn đúng địa chỉ tại thời điểm mua – đó là ý nghĩa của SCD loại 2.
> – D4, **SCD loại 1**: 3 sản phẩm bị ghi đè giá trị mới – cân nặng 750, kích thước mới, loại mới là `housewares` – nhưng `product_key` vẫn là 18, 25, 32, không sinh dòng mới.
> – D5, **upsert**: 3 dòng fact được cập nhật giá mới, `total_amount` tự tính lại, cột `dds_updated_at` có giá trị, khóa không đổi và không bị trùng.
> – D6: nhật ký cho thấy lần hai chỉ trích đúng phần thay đổi; LSET đã tiến lên CET mới.

- Ở D6, lần 2 **không có dòng `Master`** trong `etl_log` – đúng, vì lần này chạy từng package riêng chứ không qua Master. Nếu cô hỏi: *"Lần này em chạy từng package để thấy số dòng qua từng nhánh; chạy qua Master thì kết quả như nhau."*

- Khi nói D2/D3: **khoanh** cặp `customer_key` cũ/mới. Nhắc chi tiết từ báo cáo:
  - `c51a1ea9…`: key cũ **3992** → key mới **7507**
  - `d3f15df5…`: **4282 → 7508**, Franca → Diadema
  - `da5bbfd5…`: **4397 → 7509**, Maringá → Londrina
  - Số key mới có thể khác nếu bạn đã chạy thử nhiều lần mà chưa reset; reset rồi chạy đúng thứ tự thì ra đúng các số này.

---

## 7. Chạy lại khi không có gì mới – idempotent (≈ 12:30 – 13:30)

**Màn hình:** VS → chuột phải **`Master.dtsx`** → **Execute Package** → xanh hết → **Shift+F5**.

**Màn hình:** SSMS → bôi đen **dòng 161 → 167** (khối [E]) → **F5**; sau đó bôi đen **dòng 173 → 185** (khối [F]) → **F5**.

> 🎙 Em chạy Master thêm một lần nữa khi nguồn không thay đổi. Nhật ký ghi 0 dòng lấy ra, 0 dòng chèn và 0 dòng cập nhật cho mọi package. Số dòng DDS và các khóa giữ nguyên. Nghĩa là chạy lại bao nhiêu lần cũng không sinh dữ liệu trùng.
>
> Khối kiểm tra cuối cùng: không trùng khóa chính, không có fact mồ côi, mỗi khách chỉ có một phiên bản hiện hành, tổng tiền giữa nguồn và DDS chênh 0, và không có lần chạy nào bị lỗi.

---

## 8. Kết luận (≈ 13:30 – 14:00)

> 🎙 Tóm lại, em đã:
> – Xây dựng DDS star schema gồm 3 chiều và 1 fact từ dữ liệu Olist.
> – Viết 5 package SSIS nạp theo incremental extract bằng LSET và CET lưu trong bảng metadata.
> – Áp dụng SCD loại 2 cho khách hàng và SCD loại 1 cho sản phẩm bằng component Slowly Changing Dimension.
> – Làm upsert cho fact.
> – Quản lý khóa thay thế bằng IDENTITY và dòng -1 cho các giá trị không xác định.
>
> Source project, script tạo DDS và datasource em đã nén trong file 23120193.zip. Em cảm ơn cô đã xem.

---

## Sự cố thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| Execute Package bị mờ / báo *"cannot … while in debug mode"* | Đang ở chế độ debug của lần trước → **Shift+F5** rồi chạy lại. |
| Một ô đỏ ✗ | Tab **Progress** / *Execution Results* → tìm dòng `[Error]` đầu tiên. Thường gặp nhất là chạy sai thứ tự hoặc quên reset. Muốn làm lại: Shift+F5 → chạy `reset_and_prepare.cmd` → làm lại từ mục 2.2. |
| Lỗi kết nối (*SSL / certificate*) | Connection manager đã có `Use Encryption for Data=Optional`. Nếu vẫn lỗi: kiểm tra dịch vụ **SQL Server (MSSQLSERVER)** đang Running (`services.msc`). |
| Số lần 2 khác bảng ở mục 6 | Đã chạy `04_…` 2 lần hoặc chưa reset → reset và làm lại từ đầu. |
| Mở package thấy các ô chồng nhau | **Format → Auto Layout → Diagram**, rồi Ctrl+S. |
| SSMS không thấy DB mới | Chuột phải **Databases → Refresh**. |
| Muốn chạy bằng dòng lệnh (dự phòng) | Build project (chuột phải project → *Build*), rồi `DTExec /Project "...\bin\Development\SSIS_Olist_23120193.ispac" /Package Master.dtsx` – xem README mục 10. |
