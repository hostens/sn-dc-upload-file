#!/bin/bash

function check_upload_status()
{
  request_url="${sn_instance}/api/sn_cdm/applications/upload-status/$1"
  response=$(curl -s -X GET ${request_url} -u ${sn_user}:${sn_password})
  state=$(echo ${response}|jq -r ".result.state")

  counter=0

  while [[ ${counter} -lt 120 ]] && [[ ${state} != "completed" ]]; do
    counter=$((counter+1))
    response=$(curl -s -X GET ${request_url} -u ${sn_user}:${sn_password})
    echo ${response}
    state=$(echo ${response}|jq -r ".result.state")

    if [[ ${state} == "error" ]]; then
      echo "Error encountered during upload process:"
      echo ${response}|jq -r ".result.output"
      echo "Aborting..."
      exit 1
    fi

    sleep 1
  done

  changeset=$(echo ${response}|jq -r ".result.output.number")
  echo "changeset=${changeset}" >> $GITHUB_OUTPUT
  get_snapshot_validation_status ${changeset} $2
}

function get_snapshot_validation_status()
{
  request_url="${sn_instance}/api/now/table/sn_cdm_snapshot?sysparm_query=changeset_id.number=$1"
  response=$(curl -s -X GET ${request_url} -u ${sn_user}:${sn_password})
  status="not_validated"
  errors_found=0
  declare -A errors

  while [[ ${status} == "not_validated" ]]; do
    status="validated"
    response=$(curl -s -X GET ${request_url} -u ${sn_user}:${sn_password})
    for row in $(echo ${response}|jq -r ".result[]| @base64"); do
      _jq() {
        echo ${row}| base64 --decode | jq -r ${1}
      }
      validation_status=$(_jq ".validation")
      snapshot=$(_jq ".name")

      echo "Validation status for snapshot ${snapshot}: ${validation_status}"
      if [[ ${validation_status} == "not_validated" ]] || [[ ${validation_status} == "in_progress" ]]; then
        status="not_validated"
      elif [[ ${validation_status} == "failed" ]]; then
        errors_found=1
        errors[${snapshot}]=${validation_status}
      fi
    done
    sleep 1
  done

  if [[ ${errors_found} -eq 1 ]]; then
    for snapshot in ${!errors[@]}; do
      echo "Validation failed for snapshot ${snapshot} with following errors:"
      policy_url="${sn_instance}/api/now/table/sn_cdm_policy_validation_result?sysparm_query=snapshot.name%3D${snapshot}%5Etype%3Dfailure%5Esnapshot.cdm_application_id.name%3D$2&sysparm_fields=policy.name%2Cdescription%2Cnode_path"
      policy_response=$(curl -s -X GET ${policy_url} -u ${sn_user}:${sn_password})
      echo ${policy_response}|jq -r ".result[]"
    done

    echo "Validation failures, aborting..."
    exit 1
  fi

  echo ${response}
}

function upload()
{
  case $1 in
    "component")
      request_url="$sn_instance/api/sn_cdm/applications/uploads/components?appName=$2&dataFormat=$3&autoCommit=$4&autoValidate=$5&publishOption=$6&namePath=$7"
      if [[ $# -eq 9 ]] && [[ $9 != "" ]]; then
        echo "Uploading with changeset $9"
        request_url="${request_url}&changesetNumber=$9"
      fi
      file=$8
      application=$2
      ;;
    "collection")
      request_url="$sn_instance/api/sn_cdm/applications/uploads/collections?appName=$3&collectionName=$2&dataFormat=$4&autoCommit=$5&autoValidate=$6&publishOption=$7&namePath=$8"
      if [[ $# -eq 10 ]] && [[ ${10} != "" ]]; then
        echo "Uploading with changeset ${10}"
        request_url="${request_url}&changesetNumber=${10}"
      fi
      file=$9
      application=$3
      ;;
    "deployable")
      request_url="$sn_instance/api/sn_cdm/applications/uploads/deployables?appName=$3&deployableName=$2&dataFormat=$4&autoCommit=$5&autoValidate=$6&publishOption=$7&namePath=$8"
      if [[ $# -eq 10 ]] && [[ ${10} != "" ]]; then
        echo "Uploading with changeset ${10}"
        request_url="${request_url}&changesetNumber=${10}"
      fi
      file=$9
      application=$3
      ;;
    *)
      echo "Target should be 1 of: component, collection or deployable, $1 provided.  Aborting..."
      exit 1
  esac

  echo "Uploading file ${file} to name path ${name_path}"
  response=$(curl -s -X PUT ${request_url} -u $sn_user:$sn_password -H "Content-Type: text/plain" --data-binary @$file)
  echo ${response}
  upload_id=$(echo ${response}|jq -r ".result.upload_id")
  
  check_upload_status ${upload_id} ${application}
}

declare sn_instance=$1
declare sn_user=$2
declare sn_password=$3

target=$5
target_name=$6

echo "Starting execution with target ${target} and target name ${target_name}"

if [[ $# -eq 12 ]] && [[ ${12} != "" ]]; then
  upload $5 $6 $4 $8 "true" $9 ${10} ${11} $7 ${12}
else
  upload $5 $6 $4 $8 "true" $9 ${10} ${11} $7
fi
