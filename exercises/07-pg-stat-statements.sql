\x
select query, plans, mean_plan_time, min_exec_time, mean_exec_time, max_exec_time, calls, rows, shared_blks_hit from pg_stat_statements
--select * from pg_stat_statements
where 
upper (query) like 'SELECT * FROM S1.TST_BIND_BIGINT%';
