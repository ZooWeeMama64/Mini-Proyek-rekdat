CREATE DATABASE coffee;
USE coffee;

-- Validasi dan cleaning tabel customers

-- Cek member_flag tidak valid
SELECT member_flag
FROM coffee_customers
WHERE member_flag NOT REGEXP '^(Yes|No|yes|no|y|n)$';

-- Standarisasi member_flag
UPDATE coffee_customers
SET member_flag = CASE 
    WHEN LOWER(member_flag) IN ('yes', 'y') THEN 'Yes'
    WHEN LOWER(member_flag) IN ('no', 'n') THEN 'No'
    ELSE member_flag 
END;

-- Membuat tabel detail baru

CREATE TABLE coffee_transaction_details (
    detail_id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id INT,
    product_name VARCHAR(255),
    quantity INT
);

-- Pisah items_text
TRUNCATE TABLE coffee_transaction_details;

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

        -- Bersihkan nama produk
        TRIM(LOWER(REGEXP_REPLACE(raw_part, ' x?[0-9]+$', ''))) AS product_name,

        -- Ambil kuantitas
        COALESCE(
            CAST(REGEXP_SUBSTR(raw_part, '[0-9]+$') AS UNSIGNED),
            1
        ) AS quantity

    FROM split_items
) t
GROUP BY transaction_id, product_name;

-- Hapus tanda kutip
UPDATE coffee_transaction_details
SET product_name = TRIM(REPLACE(product_name, '"', ''));

-- Normalisasi huruf
UPDATE coffee_transaction_details
SET product_name = LOWER(TRIM(product_name));

UPDATE coffee_price_list
SET product_name = LOWER(TRIM(product_name));

-- Standarisasi nama produk

UPDATE coffee_transaction_details SET product_name = 'iced latte' WHERE product_name LIKE '%iced%latte%';
UPDATE coffee_transaction_details SET product_name = 'latte' WHERE product_name LIKE 'latte%';
UPDATE coffee_transaction_details SET product_name = 'cappuccino' WHERE product_name LIKE 'cappuccino%';
UPDATE coffee_transaction_details SET product_name = 'americano' WHERE product_name LIKE 'americano%';
UPDATE coffee_transaction_details SET product_name = 'mocha' WHERE product_name LIKE 'mocha%';
UPDATE coffee_transaction_details SET product_name = 'muffin' WHERE product_name LIKE 'muffin%';
UPDATE coffee_transaction_details SET product_name = 'croissant' WHERE product_name LIKE 'croissant%';
UPDATE coffee_transaction_details SET product_name = 'donut' WHERE product_name LIKE 'donut%';
UPDATE coffee_transaction_details SET product_name = 'cheesecake' WHERE product_name LIKE 'cheesecake%';
UPDATE coffee_transaction_details SET product_name = 'espresso' WHERE product_name LIKE 'espresso%';

-- Periksa hasil
SELECT *
FROM coffee_transaction_details
ORDER BY transaction_id ASC;

-- Tambahkan product_id

ALTER TABLE coffee_price_list
ADD COLUMN product_id INT AUTO_INCREMENT PRIMARY KEY;

ALTER TABLE coffee_transaction_details
ADD COLUMN product_id INT;

-- Mapping
UPDATE coffee_transaction_details d
JOIN coffee_price_list p 
    ON d.product_name = p.product_name
SET d.product_id = p.product_id;

-- Cek yang gagal mapping
SELECT DISTINCT product_name
FROM coffee_transaction_details
WHERE product_id IS NULL;

-- Periksa total pembayaran

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

-- Periksa poin member

SELECT 
    m.member_name,
    SUM(t.total_bayar) AS total_belanja,
    MAX(m.poin_didapat) AS poin_tercatat,
    FLOOR(SUM(t.total_bayar) * 0.01) AS poin_seharusnya,
    MAX(m.poin_didapat) - FLOOR(SUM(t.total_bayar) * 0.01) AS selisih_poin
FROM coffee_membership_points m
JOIN coffee_transactions t 
    ON m.member_name = t.member_name
GROUP BY m.member_name;

-- Perbaiki poin membership agar sesuai aturan 1%

UPDATE coffee_membership_points m
JOIN (
    SELECT 
        member_name,
        FLOOR(SUM(total_bayar) * 0.01) AS poin_baru
    FROM coffee_transactions
    WHERE member_name IS NOT NULL AND member_name != ''
    GROUP BY member_name
) t
ON m.member_name = t.member_name
SET m.poin_didapat = t.poin_baru;

-- Cek ulang setelah perbaikan

SELECT 
    m.member_name,
    SUM(t.total_bayar) AS total_belanja,
    m.poin_didapat AS poin_setelah_update,
    FLOOR(SUM(t.total_bayar) * 0.01) AS poin_seharusnya,
    m.poin_didapat - FLOOR(SUM(t.total_bayar) * 0.01) AS selisih
FROM coffee_membership_points m
JOIN coffee_transactions t 
    ON m.member_name = t.member_name
GROUP BY m.member_name, m.poin_didapat;

-- Buat tampilan view

CREATE OR REPLACE VIEW coffee_full_data AS
SELECT 
    d.detail_id,
    d.transaction_id,
    t.member_name,
     CASE 
        WHEN t.member_name IS NULL OR TRIM(t.member_name) = '' THEN 'Non-Member'
        ELSE 'Member'
    END AS status_member,
    d.product_id,
    p.product_name,
    p.price,
    d.quantity,
    (p.price * d.quantity) AS subtotal,
    t.total_bayar
FROM coffee_transaction_details d
JOIN coffee_transactions t 
    ON d.transaction_id = t.transaction_id
JOIN coffee_price_list p 
    ON d.product_id = p.product_id
ORDER BY transaction_id ASC;    
