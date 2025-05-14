truncate table tst.billing;
\timing on
call tst.proc_billing (date '2024-01-01', date '2024-03-31', 0);
