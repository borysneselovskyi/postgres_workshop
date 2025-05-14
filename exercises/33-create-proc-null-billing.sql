CREATE OR REPLACE PROCEDURE tst.proc_billing0 (
    p_start DATE,
    p_stop DATE,
    p_cust_id NUMERIC,
    p_batch VARCHAR DEFAULT 'Batch ' || to_char(CURRENT_TIMESTAMP, 'YYYY-MM-DD_HH24:MI:SS_TZ')
)
-- no search prices => everything has a fixed price 10
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    v_unit_price NUMERIC(10, 2);
    v_count INT := 0;
BEGIN
    raise notice '% : Started', clock_timestamp()::varchar;
    -- Loop through the usage table with the required filters
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

        -- Fetch unit_price from tst.service_price based on the matching criteria
 /*       SELECT sp.unit_price
        INTO v_unit_price
        FROM tst.service_price sp
        WHERE sp.sname = rec.sname
          AND rec.ts BETWEEN sp.ts_from AND COALESCE(sp.ts_to, '9999-12-31')
          AND (sp.cust_id = rec.cust_id OR sp.cust_id = 0)
        ORDER BY sp.cust_id DESC
        LIMIT 1;
*/
        v_unit_price=10;
        -- Insert a row into tst.billing table
        INSERT INTO tst.billing (id, cust_id, sname, ts, qty, unit_price, total_price, batch)
        VALUES (rec.id, rec.cust_id, rec.sname, rec.ts, rec.qty, v_unit_price, rec.qty * v_unit_price, p_batch);

        -- Increment the counter and commit every 10,000 rows
        v_count := v_count + 1;
        IF v_count % 10000 = 0 THEN
            COMMIT;
        END IF;
        if v_count % (100*1000) = 0 then
            raise notice '% : % rows processed.', clock_timestamp()::varchar, v_count::varchar;
        end if;

    END LOOP;

    -- Final commit if there are any remaining rows
    COMMIT;
    raise notice '% : Process ended, % rows processed.',clock_timestamp()::varchar, v_count::varchar;
END $$;

