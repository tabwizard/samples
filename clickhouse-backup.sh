#!/usr/bin/env bash 
echo "Script allow create backuped clickhouse database"
echo
echo "Syntax: clickhouse-backup.sh -u <xxx> -p <xxx> -r <xxx> -h <xxx> -b <xxx> -d <xxx>"
echo "options:"
echo " u               Username for connect to clickhouse"
echo " p               Password for connect to clickhouse"
echo " r               Port clickhouse"
echo " h               Host clickhouse"
echo " b               Database name to backup"
echo " d               Directory to create backup"
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

mkdir -p $DIRECTORY
cd $DIRECTORY
echo "DB="$DATABASE > list
clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="SELECT name FROM system.tables WHERE database = '$DATABASE' ORDER BY engine DESC" > tmp
echo "ListOfTables=("$(cat tmp)")" >> list
rm -rf tmp
source list
for tbl in ${ListOfTables[@]}; do
echo ${DB}.${tbl}
clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="SELECT * FROM ${DB}.${tbl} FORMAT Native" | gzip -9 > ${DB}.${tbl}.gz
clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="SHOW CREATE TABLE ${DB}.${tbl}" --format=TabSeparatedRaw > ${DB}.${tbl}.sql
clickhouse-client --host=$HOST --port=$PORT --user=$USERNAME --password=$PASSWORD --query="SHOW CREATE DATABASE ${DB}" --format=TabSeparatedRaw > ${DB}.sql
done
