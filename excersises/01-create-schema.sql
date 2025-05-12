\timing on

\echo Creating schema s1...
create schema s1;

\echo -------------------------------------------------------
\echo Creating table s1.tst_bind_bigint...
\echo -------------------------------------------------------
create table s1.tst_bind_bigint(
id     bigint not null constraint tst_bind_bigint_pk primary key,
ext_id bigint not null,
info   text not null
);

\echo -------------------------------------------------------
\echo Loading some data to the table s1.tst_bind_bigint...
\echo -------------------------------------------------------
insert into s1.tst_bind_bigint
select id::bigint, floor (random()*50*1000 +1 )::int, 'txt '||id::text from
(select generate_series(1,500*1000) as id) as q;


\echo -------------------------------------------------------
\echo Creating index on s1.tst_bind_bigint(ext_id)...
\echo -------------------------------------------------------
create index tst_bind_bigint_i1 on s1.tst_bind_bigint (ext_id);

\echo -------------------------------------------------------
\echo Setting the highest statistics_target for analyzing the table
\echo -------------------------------------------------------
show default_statistics_target;
set default_statistics_target=10000;
\echo -------------------------------------------------------
\echo Analyzing the table
\echo -------------------------------------------------------
analyze verbose s1.tst_bind_bigint;

\echo -------------------------------------------------------
\echo Table description
\echo -------------------------------------------------------
\d s1.tst_bind_bigint;

