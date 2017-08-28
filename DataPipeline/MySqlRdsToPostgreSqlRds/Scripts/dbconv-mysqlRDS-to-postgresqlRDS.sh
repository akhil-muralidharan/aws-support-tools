
#!/bin/bash
#Example Invocation
#./dbconv.sh --rds_jdbc=jdbc:mysql://dbtest.cob91vaba6fq.us-east-1.rds.amazonaws.com:3306/sakila
# --rds_tbl=customer --rds_pwd=testpassword --rds_usr=admin
# --red_jdbc=jdbc:postgresql://eudb3.cvprvckckqrm.eu-west-1.redshift.amazonaws.com:5439/dbtest?tcpKeepAlive=true
# --red_usr=admin --red_pwd=test123E —red_tbl=RedTub
# —red_dist=customer_id —red_sort=create_date --red_ins=OVERWRITE_EXISTING


echo "Number of arguments: $#"
#echo "Arguments: $@"

for i in "$@"
do
case "$i" in
    --rds_jdbc=*|-a=*)
    RDSJdbc="${i#*=}"
    shift
    ;;
    -b=*|--rds_usr=*)
    RDSUsr="${i#*=}"
    shift
    ;;
    -c=*|--rds_pwd=*)
    RDSPwd="${i#*=}"
    shift
    ;;
    -d=*|--rds_tbl=*)
    RDSTbl="${i#*=}"
    shift
    ;;
    -e=*|--red_jdbc=*)
    REDJdbc="${i#*=}"
    shift
    ;;
    -f=*|--red_usr=*)
    REDUsr="${i#*=}"
    shift
    ;;
    -g=*|--red_pwd=*)
    REDPwd="${i#*=}"
    shift
    ;;
    -h=*|--red_tbl=*)
    REDTbl="${i#*=}"
    shift
    ;;
    -i=*|--red_dist=*)
    REDDist="${i#*=}"
    shift
    ;;
    -j=*|--red_sort=*)
    REDSort="${i#*=}"
    shift
    ;;
    -k=*|--red_map=*)
    REDMap="${i#*=}"
    shift
    ;;
    -l=*|--red_ins=*)
    REDIns="${i#*=}"
    shift
    ;;
    *)
    echo "unknown option"
    ;;
esac
done

echo "RDS Jdbc: $RDSJdbc"
echo "RDS Usr: $RDSUsr"
#echo "RDS Pwd: $RDSPwd"
echo "RDS Tbl: $RDSTbl"

echo "REDShift Jdbc: $REDJdbc"
echo "RED Usr: $REDUsr"
#echo "RED Pwd: $REDPwd"
echo "(Optional) REDShift Generated Tbl: $REDTbl"
echo "(Optional) REDShift Distribution Key: $REDDist"
echo "(Optional) REDShift Sort Key(s): $REDSort"
echo "(Optional) REDShift Default Translation Override Map: $REDMap"
echo "(Optional) REDShift Data Insert Mode: $REDIns"

# exit script on error
set -e

#1. Install MySQL and Postgresql client including mysqldump. Match the version of postgresql client to that of your RDS Postgresql version.
sudo yum install mysql postgresql93 -y

#3. Parse RDS Jdbc Connect String
RDSHost=`echo $RDSJdbc | awk -F: '{print $3}' | sed 's/\///g'`
echo "RDS Host: $RDSHost"
RDSPort=`echo $RDSJdbc | awk -F: '{print $4}' | awk -F/ '{print $1}'`
echo "RDS Port: $RDSPort"
MySQLDb=`echo $RDSJdbc | awk -F: '{print $4}' | awk -F/ '{print $2}'`
echo "RDS MySQLDB: $MySQLDb"

#4. Parse Redshift Jdbc Connect String
#"jdbc:postgresql://eudb3.cvprvckckqrm.eu-west-1.redshift.amazonaws.com:5439/dbtest?tcpKeepAlive=true"
REDHost=`echo $REDJdbc | awk -F: '{print $3}' | sed 's/\///g'`
echo "REDShift Host: $REDHost"
REDPort=`echo $REDJdbc | awk -F: '{print $4}' | awk -F/ '{print $1}'`
echo "REDShift Port: $REDPort"
REDDb=`echo $REDJdbc | awk -F: '{print $4}' | awk -F/ '{print $2}' | awk -F? '{print $1}'`
echo "REDShift DB: $REDDb"

#5. Dump MySQL Table definition
MySQLFile=rdsmy$(date +%m%d%H%M%S).sql
echo "My SQL dump file: $MySQLFile"
`mysqldump -h $RDSHost --port=$RDSPort -u $RDSUsr --password=$RDSPwd  --compatible=postgresql --default-character-set=utf8 -n -d -r $MySQLFile $MySQLDb $RDSTbl`
echo "$MySQLFile created with mysqldump command"

#6. Download the translator python script.
curl -O https://s3.amazonaws.com/datapipeline-us-east-1/sample-scripts/mysql_to_redshift.py

#7. Translate MySQL to Postgresql
RedFile=red$(date +%m%d%H%M%S).psql
echo "created $RedFile file for writing"
echo "calling python script to generate schema file"
python mysql_to_redshift.py --input_file=$MySQLFile --output_file=$RedFile --table_name=$REDTbl  --dist_key=$REDDist --sort_keys=$REDSort --map_types=$REDMap --insert_mode=$REDIns
echo "Generated Redshift file: $RedFile"

#8. Import it into Postgresql RDS and create the table
export PGPASSWORD=$REDPwd
psql -h $REDHost -p $REDPort -U $REDUsr -d $REDDb -f $RedFile
echo "postgresql Target table created"

fname=`find /home/ec2-user/ -name '*.csv'|xargs basename`
echo filename=$fname
#9. Copy CSV data from S3 to local EC2 and then copy the row data to target Postgresql RDS table
psql -h $REDHost -p $REDPort -U $REDUsr -d $REDDb -c '\COPY '$REDTbl' FROM '/home/ec2-user/$fname' CSV'
echo "Data copied to Target table"
