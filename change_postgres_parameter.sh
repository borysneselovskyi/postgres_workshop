 
rt PGDATA=/opt/postgres/data                                                                                                 
echo -e "\nMake backup of the postgresql.conf"                                                                                   
echo "cp ${PGDATA}/postgresql.conf ${PGDATA}/postgresql.conf_back"                                                               
cp ${PGDATA}/postgresql.conf ${PGDATA}/postgresql.conf_back                                                                      
                                                                                                                                 
echo -e "\nParameter shared_preload_libraries - old value:"                                                                      
grep shared_preload ${PGDATA}/postgresql.conf                                                                                    
                                                                                                                                 
echo -e "\nParameter shared_preload_libraries - new value:"                                                                      
grep shared_preload ${PGDATA}/postgresql.conf                                                                                    
                                                                                                                                 
sed -i 's/#shared_preload_libraries.*/shared_preload_libraries='\''pg_stat_statements'\''/' ${PGDATA}/postgresql.conf           
                                                                                                                                 
echo -e "\nRestart the postgres server:"                                                                                         
echo "/usr/lib/postgresql/17/bin/pg_ctl restart -D ${PGDATA}"                                                                    
/usr/lib/postgresql/17/bin/pg_ctl restart -D ${PGDATA}   
