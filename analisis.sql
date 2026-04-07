CREATE DATABASE coffee;
USE coffee;

-- data awal:
SELECT * FROM coffee_customers;
SELECT * FROM coffee_membership_points;
SELECT * FROM coffee_price_list;
SELECT * FROM coffee_transactions;

-- 1. COFFEE_CUSTOMERS (PERBAIKAN YES/NO)
DROP TABLE IF EXISTS clean_coffee_customers; -- kalau mau run ulang

CREATE TABLE clean_coffee_customers AS
SELECT 
    customer_id,
    nama,
    phone,
    CASE 
        WHEN LOWER(member_flag) IN ('yes', 'y') THEN 'Yes'
        WHEN LOWER(member_flag) IN ('no', 'n') THEN 'No'
        ELSE member_flag 
    END AS member_flag
FROM coffee_customers;

SELECT * FROM clean_coffee_customers; -- panggil

-- 2. COFFEE_PRICE_LIST

ALTER TABLE coffee_price_list
ADD COLUMN product_id INT AUTO_INCREMENT PRIMARY KEY FIRST;

SET SQL_SAFE_UPDATES = 0; 

UPDATE coffee_price_list
SET product_name = LOWER(TRIM(product_name));

SET SQL_SAFE_UPDATES = 1;

SELECT * FROM coffee_price_list
ORDER BY product_id ASC; -- panggil

-- 3. COFFEE TRANSACTION
DROP TABLE IF EXISTS coffee_transaction_details; 

CREATE TABLE coffee_transaction_details (
    detail_id INT AUTO_INCREMENT PRIMARY KEY, -- buat tabel baru dgn primary key 
    transaction_id INT,
    product_name VARCHAR(255),
    quantity INT,
    product_id INT -- untuk mapping 
);

-- pisah item_text
SET SQL_SAFE_UPDATES = 0;

INSERT INTO coffee_transaction_details (transaction_id, product_name, quantity)
WITH RECURSIVE split_items AS (
    SELECT 
        transaction_id,
        TRIM(REPLACE(SUBSTRING_INDEX(items_text, '|', 1), '"', '')) AS raw_part,
        TRIM(REPLACE(SUBSTRING(items_text, LOCATE('|', items_text) + 1), '"', '')) AS remaining_text,
        LOCATE('|', items_text) AS has_more
    FROM coffee_transactions
    UNION ALL
    SELECT 
        transaction_id,
        TRIM(SUBSTRING_INDEX(remaining_text, '|', 1)),
        TRIM(SUBSTRING(remaining_text, LOCATE('|', remaining_text) + 1)),
        LOCATE('|', remaining_text)
    FROM split_items
    WHERE has_more > 0
)
SELECT 
    transaction_id,
    product_name,
    SUM(quantity) AS quantity
FROM (
    SELECT 
        transaction_id,
        -- 1. BERSINKAN NAMA PRODUK: Hapus angka dan "x" di belakang teks
        -- Regex ini mengantisipasi spasi ekstra, misal: "Muffin 3" atau "Mocha x 1"
        TRIM(LOWER(REGEXP_REPLACE(raw_part, ' *x? *[0-9]+$', ''))) AS product_name,

        -- 2. AMBIL KUANTITAS: Ekstrak angka di paling belakang
        -- Jika tidak ada angka (NULL), jadikan 1
        COALESCE(
            CAST(REGEXP_SUBSTR(raw_part, '[0-9]+$') AS UNSIGNED),
            1
        ) AS quantity

    FROM split_items
) t
GROUP BY transaction_id, product_name; -- Menggabungkan item yang sama di satu struk (misal: "Donut | Donut" menjadi Donut qty 2)

-- standarisasi nama produk (1 kata)
UPDATE coffee_transaction_details SET product_name = 'iced latte' WHERE product_name LIKE '%iced%latte%' AND detail_id > 0;
UPDATE coffee_transaction_details SET product_name = 'cheesecake' WHERE product_name LIKE '%cheesecake%' AND detail_id > 0;

-- 2 kata
UPDATE coffee_transaction_details SET product_name = 'latte' WHERE product_name LIKE '%latte%' AND product_name != 'iced latte' AND detail_id > 0;
UPDATE coffee_transaction_details SET product_name = 'cappuccino' WHERE product_name LIKE '%cappuccino%' AND detail_id > 0;
UPDATE coffee_transaction_details SET product_name = 'americano' WHERE product_name LIKE '%americano%' AND detail_id > 0;
UPDATE coffee_transaction_details SET product_name = 'espresso' WHERE product_name LIKE '%espresso%' AND detail_id > 0;
UPDATE coffee_transaction_details SET product_name = 'mocha' WHERE product_name LIKE '%mocha%' AND detail_id > 0;
UPDATE coffee_transaction_details SET product_name = 'croissant' WHERE product_name LIKE '%croissant%' AND detail_id > 0;
UPDATE coffee_transaction_details SET product_name = 'muffin' WHERE product_name LIKE '%muffin%' AND detail_id > 0;
UPDATE coffee_transaction_details SET product_name = 'donut' WHERE product_name LIKE '%donut%' AND detail_id > 0;

-- gabung dengan tabel price list
UPDATE coffee_transaction_details d
JOIN coffee_price_list p 
    ON d.product_name = p.product_name
SET d.product_id = p.product_id
WHERE d.detail_id > 0;

SET SQL_SAFE_UPDATES = 1;

SELECT * FROM coffee_transaction_details
ORDER BY transaction_id ASC, detail_id ASC; -- panggil

SELECT DISTINCT product_name 
FROM coffee_transaction_details 
WHERE product_id IS NULL; -- apakah ada yg gagal dipetakan (tidak ada)

-- 4. PERBAIKAN TOTAL HARGA

CREATE TABLE tabel_validasi_transaksi AS
SELECT 
    d.transaction_id,
    SUM(p.price * d.quantity) AS total_seharusnya,
    MAX(t.total_bayar) AS total_tercatat,
    SUM(p.price * d.quantity) - MAX(t.total_bayar) AS selisih_harga
FROM coffee_transaction_details d
JOIN coffee_price_list p 
    ON d.product_id = p.product_id
JOIN coffee_transactions t 
    ON d.transaction_id = t.transaction_id
GROUP BY d.transaction_id;

SELECT * FROM tabel_validasi_transaksi; -- panggil
SELECT * FROM tabel_validasi_transaksi WHERE selisih_harga = 0;

-- 5. TRANSAKSI FULL

CREATE TABLE tabel_transaksi_full_bersih AS
SELECT 
    d.detail_id,
    d.transaction_id,
    t.tanggal,
    t.cashier_name,
    t.member_name,
    CASE 
        WHEN t.member_name IS NULL OR TRIM(t.member_name) = '' THEN 'Non-Member'
        ELSE 'Member'
    END AS status_member,
    d.product_id,
    p.product_name,
    p.price AS harga_satuan,
    d.quantity,
    (COALESCE(p.price, 0) * d.quantity) AS subtotal_sistem, -- hitungan sistem
    t.total_bayar AS total_bayar_kasir -- hitungan kasir
FROM coffee_transaction_details d
LEFT JOIN coffee_transactions t 
    ON d.transaction_id = t.transaction_id
LEFT JOIN coffee_price_list p 
    ON d.product_id = p.product_id
ORDER BY d.transaction_id ASC, d.detail_id ASC;

SELECT * FROM tabel_transaksi_full_bersih; -- panggil

-- 6. POIN MEMBER

CREATE TABLE tabel_poin_member_bersih AS
SELECT 
    member_name,
    SUM(subtotal_sistem) AS total_belanja_valid, -- total belanja yg valid
    FLOOR(SUM(subtotal_sistem) * 0.01) AS poin_didapat_seharusnya -- total poin
    
FROM tabel_transaksi_full_bersih
WHERE status_member = 'Member'
GROUP BY member_name;

SELECT * FROM tabel_poin_member_bersih; -- panggil

-- ================================================================================
-- untuk analisis
-- ==================================================================================

SELECT * FROM clean_coffee_customers;

SELECT * FROM coffee_price_list
ORDER BY product_id ASC;

SELECT * FROM coffee_transaction_details
ORDER BY transaction_id ASC, detail_id ASC;

SELECT * FROM tabel_transaksi_full_bersih;

SELECT * FROM tabel_validasi_transaksi;
SELECT * FROM tabel_validasi_transaksi WHERE selisih_harga = 0;

SELECT * FROM tabel_poin_member_bersih;

-- jawaban pertanyaan

-- 1. produk best seller
SELECT 
    product_name, 
    SUM(quantity) AS total_item_terjual
FROM tabel_transaksi_full_bersih
GROUP BY product_name
ORDER BY total_item_terjual DESC
LIMIT 1; 

-- 2. total penjualan untuk setiap produk
SELECT 
    product_name, 
    SUM(quantity) AS total_item_terjual,
    SUM(subtotal_sistem) AS total_pendapatan
FROM tabel_transaksi_full_bersih
GROUP BY product_name
ORDER BY total_pendapatan DESC;

-- 3. apakah ada selisih harga? ya
SELECT 
    transaction_id,
    SUM(subtotal_sistem) AS total_harga_asli,
    MAX(total_bayar_kasir) AS total_input_kasir,
    MAX(total_bayar_kasir) - SUM(subtotal_sistem) AS selisih_pembayaran
FROM tabel_transaksi_full_bersih
GROUP BY transaction_id
HAVING selisih_pembayaran != 0; 

-- 4. kontributor transaksi terbesar
SELECT 
    member_name, 
    SUM(subtotal_sistem) AS total_belanja
FROM tabel_transaksi_full_bersih
WHERE status_member = 'Member'
GROUP BY member_name
ORDER BY total_belanja DESC
LIMIT 1; 

-- 5. aturan 1%
SELECT 
    mentah.member_name,
    mentah.poin_didapat AS poin_di_sistem_lama,
    bersih.poin_didapat_seharusnya AS poin_aturan_1_persen,
    mentah.poin_didapat - bersih.poin_didapat_seharusnya AS selisih_poin_error
FROM coffee_membership_points mentah
JOIN tabel_poin_member_bersih bersih
    ON mentah.member_name = bersih.member_name
WHERE mentah.poin_didapat != bersih.poin_didapat_seharusnya;

-- OPSI LAIN
-- 1. Produk apa yang paling sering terjual?
SELECT product_name AS Produk, SUM(quantity) AS Total_Terjual
FROM coffee_transaction_details
GROUP BY product_name
ORDER BY total_terjual DESC
LIMIT 1;

-- 2. Berapa total penjualan untuk setiap produk?
SELECT td.product_name AS Produk, SUM(td.quantity) AS Total_Terjual, SUM(td.quantity * pl.price) AS Total_Penjualan
FROM coffee_transaction_details AS td
JOIN coffee_price_list AS pl ON td.product_id = pl.product_id
GROUP BY td.product_name
ORDER BY total_penjualan DESC;

-- 3. Apakah terdapat selisih antara total pembayaran dan harga produk yang seharusnya?
SELECT td.transaction_id, SUM(td.quantity * pl.price) AS Total_Penjualan, 
		MAX(t.total_bayar) AS Total_Dibayar,
		SUM(pl.price * td.quantity) - MAX(t.total_bayar) AS Selisih_Harga
FROM coffee_transaction_details AS td       
JOIN coffee_price_list AS pl ON td.product_id = pl.product_id
JOIN coffee_transactions AS t ON td.transaction_id = t.transaction_id
GROUP BY td.transaction_id
HAVING Selisih_Harga != 0;      

-- 4. Siapa pelanggan dengan kontribusi transaksi terbesar?
SELECT
	member_name AS Nama,
    SUM(total_bayar) AS Total_Transaksi
FROM coffee_transactions
WHERE member_name IS NOT NULL AND member_name != ''
GROUP BY member_name
ORDER BY Total_Transaksi DESC
LIMIT 1;    

-- 5. Apakah poin membership yang tercatat sudah sesuai dengan aturan 1% dari transaksi?
SELECT 
    m.member_name AS Nama,
    SUM(t.total_bayar) AS total_belanja,
    m.poin_didapat,
    FLOOR(SUM(t.total_bayar) * 0.01) AS poin_seharusnya,
    m.poin_didapat - FLOOR(SUM(t.total_bayar) * 0.01) AS selisih
FROM coffee_membership_points m
JOIN coffee_transactions t 
    ON m.member_name = t.member_name
GROUP BY m.member_name, m.poin_didapat;

