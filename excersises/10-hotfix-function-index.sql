\timing on
create index tst_bind_bigint_hotfix_i2 on s1.tst_bind_bigint (cast (ext_id as numeric));
