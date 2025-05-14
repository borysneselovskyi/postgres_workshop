
create extension hstore;

CREATE OR REPLACE PROCEDURE tst.proc_billing4_1(
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
    price_map hstore := hstore('');  -- Hash map to cache the service_price data
    price_data TEXT;
    price_array TEXT[];
    ts_from TIMESTAMP;
    ts_to TIMESTAMP;
    unit_price_candidate NUMERIC(10, 2);
    price_entry TEXT;

BEGIN
    raise notice '% : Started.', clock_timestamp()::varchar;
    -- Populate hstore with the relevant service_price data, serialize (ts_from, ts_to, unit_price)
    SELECT hstore(array_agg(sub.sname_cust_key), 
                  array_agg(sub.pricing_periods))
    INTO price_map
    FROM (
        SELECT sp.sname || '_' || sp.cust_id AS sname_cust_key, 
               string_agg(
                   to_char(sp.ts_from, 'YYYY-MM-DD HH24:MI:SS.US') || '|' || 
                   COALESCE(to_char(sp.ts_to, 'YYYY-MM-DD HH24:MI:SS.US'), '9999-12-31 23:59:59.999999') || '|' || 
                   to_char(sp.unit_price, 'FM999999999.00'),
                   '~'
               ) AS pricing_periods
        FROM tst.service_price sp
        WHERE sp.ts_from <= p_stop + INTERVAL '1 day' - INTERVAL '1 microsecond'
          AND (sp.ts_to IS NULL OR sp.ts_to >= p_start)
        GROUP BY sp.sname, sp.cust_id
    ) AS sub;

    raise notice '% : Cache for SERVICE_PRICE loaded.', clock_timestamp()::varchar;

    -- Log the content of the hstore for debugging
    --RAISE NOTICE 'Hstore content: %', price_map;

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

        -- Construct the key and try to retrieve cached price data
        price_data := price_map -> (rec.sname || '_' || rec.cust_id);

        -- Fallback to default customer price (cust_id = 0) if no specific data found
        IF price_data IS NULL THEN
            price_data := price_map -> (rec.sname || '_0');
        END IF;

        -- Process price data if found
        IF price_data IS NOT NULL THEN
            -- Split the cached price data into entries (multiple price periods)
            price_array := string_to_array(price_data, '~');  -- Split by ~ instead of ,

            -- Loop through the price periods to find the correct one
            FOREACH price_entry IN ARRAY price_array LOOP
                -- Split the price_entry into ts_from, ts_to, and unit_price
                ts_from := to_timestamp(split_part(price_entry, '|', 1), 'YYYY-MM-DD HH24:MI:SS.US');
                ts_to := to_timestamp(split_part(price_entry, '|', 2), 'YYYY-MM-DD HH24:MI:SS.US');
                unit_price_candidate := split_part(price_entry, '|', 3)::NUMERIC(10, 2);

                -- Check if the event's timestamp falls within this pricing period
                IF rec.ts BETWEEN ts_from AND ts_to THEN
                    v_unit_price := unit_price_candidate;
                    EXIT;  -- Exit once we find a match
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
--    RAISE NOTICE 'Total number of rows with missing prices: %', missing_count;
    raise notice '% : Process ended, % rows processed.',clock_timestamp()::varchar, v_count::varchar;
END 
$BODY$;
