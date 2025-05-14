\echo Run as Postgres administrator

create database dev01;
create user u1 with password 'u1passwordSecure__';

grant all on database dev01 to u1;
\c dev01
create extension pg_stat_statements;


