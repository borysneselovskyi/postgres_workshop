\timing on

\echo Creating schema tst...
create schema tst;

\echo -------------------------------------------------------
\echo Creating table tst.customer and loading data...
\echo -------------------------------------------------------

create table tst.customer(
id         numeric primary key,
cust_name  varchar(40) not null unique,
cust_data  varchar(255) not null);

insert into tst.customer (id, cust_name, cust_data) values (0, '0 - Default Customer','No data');
commit;

DO $$
DECLARE
    i INT;
    random_data VARCHAR(255);
BEGIN
    FOR i IN 1..2*1000 LOOP
        -- Generate 255 random characters for cust_data
        random_data := (SELECT string_agg(chr((65 + round(random() * 61))::int), '') 
                        FROM generate_series(1, 255));
                        
        -- Insert the data into the customer table
        INSERT INTO tst.customer (id, cust_name, cust_data)
        VALUES (i, '#' || i || ' Customer Name', random_data);
    END LOOP;
END $$;

\echo ------------------------------------------------------------------
\echo Creating table tst.service (service catalog and loading data...
\echo ------------------------------------------------------------------

create table tst.service (
sname     varchar(10) primary key,
full_name varchar(80) not null unique);

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..50 LOOP
        -- Insert the data into the service table
        INSERT INTO tst.service (sname, full_name)
        VALUES ('#' || i, '#' || i || ' Full Service Name');
    END LOOP;
END $$;

\echo ----------------------------------------------------------------------
\echo Creating table tst.service_price (service pricing and loading data...
\echo ----------------------------------------------------------------------

create table tst.service_price
(sname      varchar(10) not null,
 cust_id    numeric not null,
 ts_from    timestamp not null,
 ts_to      timestamp,
 unit_price numeric(10,2) not null,
 constraint service_price_service_fk foreign key (sname) references tst.service(sname),
 constraint service_price_customer_fk foreign key (cust_id) references tst.customer(id));

DO $$
DECLARE
    svc RECORD;
    change_count INT;
    start_date DATE;
    current_price NUMERIC(10,2);
    previous_price NUMERIC(10,2);
    ts_start TIMESTAMP;
    ts_end TIMESTAMP;
    i INT;
    random_days INT;
    max_end_date DATE := DATE '2024-12-31';
BEGIN
    -- Loop over all services
    FOR svc IN (SELECT sname FROM tst.service) LOOP
        -- Randomly determine how many times the price has changed (between 1 and 20)
        change_count := FLOOR(1 + RANDOM() * 20);

        -- Randomly determine the number of days between 2020-01-01 and 2024-01-01
        random_days := FLOOR(RANDOM() * (DATE '2024-01-01' - DATE '2020-01-01')::numeric);

        -- Start date for this service (random date between 2020-01-01 and 2024-01-01)
        start_date := DATE '2020-01-01' + INTERVAL '1 day' * random_days;

        -- Initial price between 10 and 100 (cast to numeric before rounding)
        current_price := ROUND(CAST(10 + RANDOM() * 90 AS NUMERIC), 2);

        -- Loop to create the price history
        FOR i IN 1..change_count LOOP
            -- Set ts_from to be the start of the random period
            ts_start := start_date;
            
            -- Randomly select a number of days (between 1 and 365) for this price period
            
             random_days := FLOOR(1 + RANDOM() * 
                  ((max_end_date - ts_start::date)::numeric * i / change_count) -- pk
             );
            
            -- Set ts_to to be the end of the random period
            ts_end := ts_start + INTERVAL '1 day' * random_days - INTERVAL '1 microsecond';

            -- Make sure ts_end does not exceed the max end date 
            IF ts_end > max_end_date THEN
                ts_end := NULL::timestamp;
            END IF;

            -- Insert the historical record (except for the last one which will have ts_to = NULL)
            IF i < change_count and ts_end is not null THEN
                -- Insert with ts_to as end of the random period
                INSERT INTO tst.service_price (sname, cust_id, ts_from, ts_to, unit_price)
                VALUES (svc.sname, 0, ts_start, ts_end, current_price);

                -- Adjust price randomly for the next entry (between -5% and +5%)
                previous_price := current_price;
                current_price := ROUND(CAST(previous_price * (1 + (RANDOM() * 0.10 - 0.05)) AS NUMERIC), 2);

                -- Move start_date forward by the random period for the next entry
                start_date := ts_end + INTERVAL '1 second';

                -- Ensure that the next ts_from doesn't exceed the limit
                IF start_date > max_end_date THEN
                    start_date := max_end_date;
                END IF;
            ELSE
                -- The most recent entry has ts_to set to NULL
                INSERT INTO tst.service_price (sname, cust_id, ts_from, ts_to, unit_price)
                VALUES (svc.sname, 0, ts_start, NULL, current_price);
            END IF;

            -- Stop the loop if ts_start exceeds max_end_date
            IF ts_start >= max_end_date THEN
                EXIT;
            END IF;
        END LOOP;
    END LOOP;
END $$;

DO $$
DECLARE
    selected_customer RECORD;
    discounted_price NUMERIC(10,2);
BEGIN
    -- Step 1: Select % of customers from tst.customer where id > 0
    FOR selected_customer IN
        SELECT id
        FROM tst.customer
        WHERE id > 0
        ORDER BY RANDOM()
        LIMIT (SELECT COUNT(*) * 0.002 FROM tst.customer WHERE id > 0)
    LOOP
        -- Step 2: For each selected customer, replicate service_price entries from cust_id = 0
        INSERT INTO tst.service_price (sname, cust_id, ts_from, ts_to, unit_price)
        SELECT
            sp.sname, 
            selected_customer.id,  -- Use the selected customer's id
            sp.ts_from,
            sp.ts_to,
            -- Step 3: Apply a random discount between 10% and 50% to the unit_price
            ROUND(CAST(sp.unit_price * (1 - (0.10 + (RANDOM() * 0.40))) AS NUMERIC), 2) AS unit_price
        FROM tst.service_price sp
        WHERE sp.cust_id = 0;
        commit;  -- pk
    END LOOP;
END $$;

create index service_price_service_fk_i on tst.service_price(sname);
create index service_price_customer_fk_i on tst.service_price(cust_id);
create index service_price_i1 on tst.service_price(cust_id,sname,ts_from);


\echo ------------------------------------------------------------------------
\echo Creating table tst.usage => usage of service per customers
\echo .                        => partitions for CY'2024 and loading the data
\echo ------------------------------------------------------------------------

CREATE TABLE tst.usage (
    id        uuid NOT NULL,
    cust_id   NUMERIC NOT NULL,
    sname     VARCHAR(10) NOT NULL,
    ts        TIMESTAMP NOT NULL,
    qty       NUMERIC NOT NULL,
    technicals varchar(128) not null,
    CONSTRAINT usage_pk PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

\echo =>Adding partitions 2024-01 .. 2024-12

DO $$
DECLARE
    partition_start TIMESTAMP;
    partition_end TIMESTAMP;
    month_start DATE := '2024-01-01';  -- Next partition start date
BEGIN
    FOR i IN 1..12 LOOP  -- Create partitions for the next 12 months
        partition_start := month_start;
        partition_end := month_start + INTERVAL '1 month' - interval '1 microsecond';

        EXECUTE format('CREATE TABLE tst.usage_%s PARTITION OF tst.usage
                        FOR VALUES FROM (''%s'') TO (''%s'')',
                       to_char(month_start, 'YYYY_MM'), partition_start, partition_end);

        -- Create indexes for the new partition
        EXECUTE format('CREATE INDEX usage_%s_customer_fk_i ON tst.usage_%s (cust_id)',
                       to_char(month_start, 'YYYY_MM'), to_char(month_start, 'YYYY_MM'));

        EXECUTE format('CREATE INDEX usage_%s_service_fk_i ON tst.usage_%s (sname)',
                       to_char(month_start, 'YYYY_MM'), to_char(month_start, 'YYYY_MM'));

        -- Move to the next month
        month_start := month_start + INTERVAL '1 month';
    END LOOP;
END $$;



\echo => Loading the data ... 

DO $$
DECLARE
    customer_ids NUMERIC[];  -- Array to store customer ids (numeric)
    service_names VARCHAR(10)[];  -- Array to store service names
    i INT;
    random_qty NUMERIC;
    random_ts TIMESTAMP;
    selected_cust_id NUMERIC;  -- Use numeric for cust_id
    selected_sname VARCHAR(10);
    random_data varchar(120);
BEGIN
    -- Step 1: Preload tst.customer id values into an array
    SELECT ARRAY(SELECT distinct cust_id from tst.service_price c WHERE cust_id > 0) INTO customer_ids;

    -- Step 2: Preload tst.service sname values into an array
    SELECT ARRAY(SELECT sname FROM tst.service) INTO service_names;

    -- Step 3: Start generating 1,000,000 random entries
    FOR i IN 1..1000*1000 LOOP
        -- Step 4: Pick a random cust_id from the preloaded customer_ids array
        selected_cust_id := customer_ids[FLOOR(1 + RANDOM() * ARRAY_LENGTH(customer_ids, 1))::INT];

        -- Step 5: Pick a random sname from the preloaded service_names array
        selected_sname := service_names[FLOOR(1 + RANDOM() * ARRAY_LENGTH(service_names, 1))::INT];

        -- Step 6: Generate a random timestamp between 2024-01-01 and 2025-12-31 23:59:59.999999
        random_ts := '2024-01-01'::timestamp + (RANDOM() * (('2025-01-01'::timestamp - '2024-01-01'::timestamp)));

        -- Step 7: Generate qty with 80% chance of 1, 15% of 2, and 5% of 3 or 4
        random_qty := CASE
            WHEN RANDOM() < 0.80 THEN 1
            WHEN RANDOM() < 0.95 THEN 2
            ELSE FLOOR(3 + RANDOM() * 2) -- Randomly picks 3 or 4
        END;

        -- Step 8: Insert the generated row into tst.usage

--        random_data := (SELECT string_agg(chr((65 + round(random() * 61))::int), '')
--                        FROM generate_series(1, 50));
        random_data:='gfdfgdget#%$RDFDGFTERGFDVBDFGTRTRHGTHFTHFSDEFSDFsfsdfsdfsdfefefefw'||gen_random_uuid();

        INSERT INTO tst.usage (id, cust_id, sname, ts, qty, technicals)
        VALUES (gen_random_uuid(), selected_cust_id, selected_sname, random_ts, random_qty, random_data);

        -- Step 9: Commit after every 10,000 rows
        IF i % 10000 = 0 THEN
            COMMIT;
        END IF;
    END LOOP;

    -- Final commit for any remaining rows
    COMMIT;
END $$;

\echo ------------------------------------------------------------------------
\echo Creating table tst.billing 
\echo ------------------------------------------------------------------------

CREATE TABLE tst.billing (
    id        uuid NOT NULL,
    cust_id   NUMERIC NOT NULL,
    sname     VARCHAR(10) NOT NULL,
    ts        TIMESTAMP NOT NULL,
    qty       NUMERIC NOT NULL,
    unit_price  numeric(10,2) not null,
    total_price numeric(12,2) not null,
    batch     varchar(60) not null,
    CONSTRAINT billing_pk PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

DO $$
DECLARE
    partition_start TIMESTAMP;
    partition_end TIMESTAMP;
    month_start DATE := '2024-01-01';  -- Next partition start date
BEGIN
    FOR i IN 1..12 LOOP  -- Create partitions for the next 12 months
        partition_start := month_start;
        partition_end := month_start + INTERVAL '1 month' - interval '1 microsecond';

        EXECUTE format('CREATE TABLE tst.billing_%s PARTITION OF tst.billing
                        FOR VALUES FROM (''%s'') TO (''%s'')',
                       to_char(month_start, 'YYYY_MM'), partition_start, partition_end);

        -- Create indexes for the new partition
        EXECUTE format('CREATE INDEX billing_%s_customer_fk_i ON tst.billing_%s (cust_id)',
                       to_char(month_start, 'YYYY_MM'), to_char(month_start, 'YYYY_MM'));

        EXECUTE format('CREATE INDEX billing_%s_service_fk_i ON tst.billing_%s (sname)',
                       to_char(month_start, 'YYYY_MM'), to_char(month_start, 'YYYY_MM'));

        -- Move to the next month
        month_start := month_start + INTERVAL '1 month';
    END LOOP;
END $$;
