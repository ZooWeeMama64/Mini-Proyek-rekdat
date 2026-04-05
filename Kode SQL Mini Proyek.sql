CREATE DATABASE coffee;
USE coffee;

-- Mengecek member_flag yang ditulis bukan 'Yes' atau 'No'
SELECT *
FROM coffee_customers
WHERE member_flag NOT REGEXP 'Yes|No';

-- Menyeragamkan member_flag menjadi 'Yes' atau 'No'
UPDATE coffee_customers
SET member_flag = CASE 
    WHEN LOWER(member_flag) IN ('yes', 'y') THEN 'Yes'
    WHEN LOWER(member_flag) IN ('no', 'n') THEN 'No'
    ELSE member_flag 
END;

SELECT *
FROM coffee_customers;

SELECT *
FROM coffee_transactions;

-- Buat tabel penampung hasil normalisasi
CREATE TABLE coffee_transaction_details (
    transaction_id INT,
    product_name VARCHAR(255),
    quantity INT
);

-- Menggunakan Recursive CTE untuk memecah string berdasarkan '|'
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
    -- Logika memisahkan Nama Produk (hapus angka di akhir)
    TRIM(REGEXP_REPLACE(raw_part, ' x?[0-9]+$', '')) AS product_name,
    -- Logika mengambil angka sebagai Quantity (default 1 jika tidak ada angka)
    COALESCE(CAST(REGEXP_SUBSTR(raw_part, '[0-9]+$') AS UNSIGNED), 1) AS quantity
FROM split_items;

-- Standarisasi untuk menu untuk JOIN dengan price_list 
UPDATE coffee_transaction_details SET product_name = 'Iced Latte' WHERE product_name LIKE 'Iced%Latte%';
UPDATE coffee_transaction_details SET product_name = 'Latte' WHERE product_name = 'Latte' OR product_name LIKE 'Latte%';
UPDATE coffee_transaction_details SET product_name = 'Cappuccino' WHERE product_name LIKE 'Cappuccino%';
UPDATE coffee_transaction_details SET product_name = 'Americano' WHERE product_name LIKE 'Americano%';
UPDATE coffee_transaction_details SET product_name = 'Mocha' WHERE product_name LIKE 'Mocha%';
UPDATE coffee_transaction_details SET product_name = 'Muffin' WHERE product_name LIKE 'Muffin%';
UPDATE coffee_transaction_details SET product_name = 'Croissant' WHERE product_name LIKE 'Croissant%';
UPDATE coffee_transaction_details SET product_name = 'Donut' WHERE product_name LIKE 'Donut%';
UPDATE coffee_transaction_details SET product_name = 'Cheesecake' WHERE product_name LIKE 'Cheesecake%';
UPDATE coffee_transaction_details SET product_name = 'Espresso' WHERE product_name LIKE 'Espresso%';

SELECT *
FROM coffee_transaction_details
ORDER BY transaction_id ASC;

SELECT 
    d.transaction_id,
    -- Kolom Agregat
    SUM(p.price * d.quantity) AS total_seharusnya,
    -- Kolom Non-Agregat
    t.total_bayar AS total_tercatat,
    -- Kalkulasi Selisih
    (SUM(p.price * d.quantity) - t.total_bayar) AS selisih_harga
FROM coffee_transaction_details d
JOIN coffee_price_list p ON d.product_name = p.product_name
JOIN coffee_transactions t ON d.transaction_id = t.transaction_id
GROUP BY d.transaction_id, t.total_bayar;

SELECT 
    m.member_name,
    -- Kolom Agregat
    SUM(t.total_bayar) AS total_belanja,
    -- Kolom Non-Agregat
    m.poin_didapat AS poin_tercatat,
    -- Kalkulasi poin 1%
    FLOOR(SUM(t.total_bayar) * 0.01) AS poin_seharusnya,
    -- Selisih poin
    (m.poin_didapat - FLOOR(SUM(t.total_bayar) * 0.01)) AS selisih_poin
FROM coffee_membership_points m
JOIN coffee_transactions t ON m.member_name = t.member_name
GROUP BY m.member_name, m.poin_didapat;
