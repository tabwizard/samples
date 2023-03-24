#!/usr/bin/env bash 
echo "Script allow restore backuped clickhouse database"
echo
echo "Syntax: clickhouse-restore.sh -u <xxx> -p <xxx> -r <xxx> -h <xxx> [-b <xxx>] -d <xxx>"
echo "options:"
echo " u               Username for connect to clickhouse"
echo " p               Password for connect to clickhouse"
echo " r               Port clickhouse"
echo " h               Host clickhouse"
echo " b(optional)     Database name to restore backup"
echo " d               Directory from restore backup"
echo

while getopts ":u:p:r:h:b:d:" flag
do
    case "${flag}" in
        u) USERNAME=${OPTARG};;
        p) PASSWORD=${OPTARG};;
        r) PORT=${OPTARG};;
        h) HOST=${OPTARG};;
        b) DATABASE=${OPTARG};;
        d) DIRECTORY=${OPTARG};;
    esac
done

cd $DIRECTORY
source list
if [[ $DATABASE != "" ]] && [[ $DATABASE != ${DB} ]]
then
    if [[ $(clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="SELECT COUNT() FROM system.databases WHERE database = '${DATABASE}'") == 0 ]]
    then 
        cp ${DB}.sql ${DATABASE}.sql
        sed -i "s/${DB}/${DATABASE}/g" "${DATABASE}.sql"
        clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD < ${DATABASE}.sql
        rm -rf ${DATABASE}.sql
    fi
    for tbl in ${ListOfTables[@]}; do
        clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="DROP TABLE IF EXISTS ${DATABASE}.${tbl}"
        cp ${DB}.${tbl}.sql ${DATABASE}.${tbl}.sql
        sed -i "s/${DB}/${DATABASE}/g" "${DATABASE}.${tbl}.sql"
        clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD < ${DATABASE}.${tbl}.sql
        rm -rf ${DATABASE}.${tbl}.sql
        gzip -d ${DB}.${tbl}.gz 
        clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="INSERT INTO ${DATABASE}.${tbl} FORMAT Native" < ${DB}.${tbl}
        gzip -9 ${DB}.${tbl}
    done
else
    if [[ $(clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="SELECT COUNT() FROM system.databases WHERE database = '${DB}'") == 0 ]]
    then 
        clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD < ${DB}.sql
    fi
    for tbl in ${ListOfTables[@]}; do
        clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="DROP TABLE IF EXISTS ${DB}.${tbl}"
        clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD < ${DB}.${tbl}.sql
        gzip -d ${DB}.${tbl}.gz 
        clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="INSERT INTO ${DB}.${tbl} FORMAT Native" < ${DB}.${tbl}
        gzip -9 ${DB}.${tbl}
    done
fi
