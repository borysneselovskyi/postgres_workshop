CREATE OR REPLACE PROCEDURE tst.proc_billing5_4(
	IN p_start date,
	IN p_stop date,
	IN p_cust_id numeric,
	IN p_batch character varying DEFAULT ('Batch '::text || to_char(CURRENT_TIMESTAMP,
	'YYYY-MM-DD HH24:MI:SS.US_TZ'::text)))
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    rec RECORD;
    v_unit_price NUMERIC(10, 2);
    v_count INT := 0;
    missing_count INT := 0;  -- Track how many rows are missing
    price_map JSONB := '{}'::JSONB;  -- JSONB map to cache the service_price data
    price_data JSONB;
    current_period JSONB;
    ts_from TIMESTAMP;
    ts_to TIMESTAMP;
    price_period_count INT;  -- Number of pricing periods for the current sname_cust_key
BEGIN
    raise notice '% : Started.', clock_timestamp()::varchar;
    
    -- Cache the service_price data as JSONB, with row numbers and count

    SELECT jsonb_object_agg(sub.sname_cust_key, jsonb_build_object(
        'pricing_periods', sub.pricing_periods, 
        'count', sub.period_count
    ))
    INTO price_map
    FROM (
        SELECT sname_cust_key, 
               jsonb_agg(jsonb_build_object(
                   'row_num', row_num,
                   'ts_from', priced_rows.ts_from,  -- Qualified ts_from
                   'ts_to', priced_rows.ts_to,      -- Qualified ts_to
                   'unit_price', priced_rows.unit_price  -- Qualified unit_price
               )) AS pricing_periods,
               period_count
        FROM (
            -- Subquery to calculate row number and count
            SELECT sp.sname || '_' || sp.cust_id AS sname_cust_key, 
                   sp.ts_from, sp.ts_to, sp.unit_price, 
                   ROW_NUMBER() OVER (PARTITION BY sp.sname, sp.cust_id ORDER BY sp.ts_from) AS row_num,
                   COUNT(*) OVER (PARTITION BY sp.sname, sp.cust_id) AS period_count
            FROM tst.service_price sp
            WHERE sp.ts_from <= p_stop + INTERVAL '1 day' - INTERVAL '1 microsecond'
              AND (sp.ts_to IS NULL OR sp.ts_to >= p_start)
        ) AS priced_rows
        GROUP BY sname_cust_key, period_count
    ) AS sub;

    raise notice '% : Cache for SERVICE_PRICE loaded.', clock_timestamp()::varchar;
    -- Loop through the usage table
    FOR rec IN
        SELECT u.id, u.cust_id, u.sname, u.ts, u.qty
        FROM tst.usage u
        WHERE NOT EXISTS (
            SELECT 1
            FROM tst.billing b
            WHERE b.id = u.id
              AND b.ts BETWEEN p_start AND p_stop + INTERVAL '1 day' - INTERVAL '1 microsecond'
        )
        AND u.ts BETWEEN p_start AND p_stop + INTERVAL '1 day' - INTERVAL '1 microsecond'
        AND (p_cust_id = 0 OR u.cust_id = p_cust_id)
    LOOP
        if v_count < 1 then
           raise notice '% : first row attempted', clock_timestamp()::varchar;
        end if;
        -- Initialize unit price as null
        v_unit_price := NULL;

        -- Construct the key for price lookup
        price_data := price_map -> (rec.sname || '_' || rec.cust_id);

        -- Fallback to default customer price if no customer-specific data found
        IF price_data IS NULL THEN
            price_data := price_map -> (rec.sname || '_0');
        END IF;

        -- If price data exists, iterate over the pricing periods by row number
        IF price_data IS NOT NULL THEN
            price_period_count := (price_data ->> 'count')::INT;

            FOR row_num IN 1..price_period_count LOOP
                current_period := price_data -> 'pricing_periods' -> (row_num - 1);
                ts_from := (current_period ->> 'ts_from')::TIMESTAMP;
                ts_to := (current_period ->> 'ts_to')::TIMESTAMP;
                v_unit_price := (current_period ->> 'unit_price')::NUMERIC(10, 2);

                -- Check if the event's timestamp falls within this pricing period
                IF rec.ts BETWEEN ts_from AND ts_to THEN
                    EXIT;
                END IF;
            END LOOP;
        END IF;

        -- If no valid price was found, track the missing price
        IF v_unit_price IS NULL THEN
            missing_count := missing_count + 1;
            RAISE NOTICE 'Price not found for usage id: %, cust_id: %, sname: %, ts: %', 
                          rec.id, rec.cust_id, rec.sname, rec.ts;
        ELSE
            -- Insert the row into tst.billing if a valid price was found
            INSERT INTO tst.billing (id, cust_id, sname, ts, qty, unit_price, total_price, batch)
            VALUES (rec.id, rec.cust_id, rec.sname, rec.ts, rec.qty, v_unit_price, rec.qty * v_unit_price, p_batch);

            -- Commit every 10,000 rows
            v_count := v_count + 1;
            IF v_count % 10000 = 0 THEN
                COMMIT;
            END IF;
            if v_count % (100*1000) = 0 then
               raise notice '% : % rows processed.', clock_timestamp()::varchar, v_count::varchar;
            end if;
        END IF;
    END LOOP;

    -- Final commit
    COMMIT;

    -- Log the total number of missing prices
    RAISE NOTICE 'Total number of rows with missing prices: %', missing_count;
    raise notice '% : Process ended, % rows processed.',clock_timestamp(), v_count::varchar;
    
END 
$BODY$;
