#!/bin/bash
# Copyright 2020 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# =======================
# WHAT IS THIS SCRIPT FOR
# =======================
# Given a project ID, this script completes a list of setup steps that are
# required to facilitate usage of the `gcloud [alpha|beta] compute instances
# ops-agents policies` commands. See the `WHAT DOES THIS SCRIPT DO?` section for
# more details.

# ==========================
# WHO SHOULD RUN THIS SCRIPT
# ==========================
# This script is designed for project OWNERS to run. Non-owner users may be able
# to run it if they have high-priveleged permissions. Reach out to your project
# owner for help if certain permission (e.g. enabling API for the entire
# project) is
# denied.

# ========================
# WHAT DOES THIS SCRIPT DO
# ========================
# Given a project ID, this script takes care of the following setup:
#
# 1. Enable the Cloud Logging API, the Cloud Monitoring API and the OS Config
#    API for the project. This is required for logs and metrics to be ingested
#    to the backend.
# 2. Grant the `roles/logging.logWriter` and the `roles/monitoring.metricWriter`
#    roles to the Compute Engine default service account of this project. The
#    Compute Engine default service account is automatically set up on GCE VMs.
#    Granting it these permissions allows the Cloud Operation Suite agents that
#    are installed by the policies on the GCE VMs in this project to write to
#    the Cloud Logging and Monitoring APIs to ingest logs and metrics.
# 3. Enable and verify the OS Config metadata for the project. This ensures the
#    OS Config Agent installed on each GCE VMs is active and ready to pull and
#    apply policies.
# 4. [Optional] Grant permissions to non-owner users or service accounts to
#    create and manage policies. Project owner(s) automatically have full access
#    to create and manage policies. For all other users or service accounts, the
#    project owner(s) need to explicit grant permissions to them. The available
#    options for the permissions are:
#    *  roles/osconfig.guestPolicyAdmin: Full access to the policies.
#    *  roles/osconfig.guestPolicyEditor: Edit access to get, update, and list policies
#    *  roles/osconfig.guestPolicyViewer: Read-only access to get and list policies.

# ============
# Sample usage
# ============
#
# A sample command that does 1, 2 and 3 as mentioned above:
# $  bash set-permissions.sh --project=PROJECT
#
# A sample command that does 1, 2, 3 and 4 (grant permission to a user):
# $  bash set-permissions.sh --project=PROJECT \
#      --iam-user=USER_EMAIL \
#      --iam-permission-role=[guestPolicyAdmin or guestPolicyEditor or guestPolicyViewer]
#
# A sample command that does 1, 2, 3 and 4 (grant permission to a service account):
# $  bash set-permissions.sh --project=PROJECT \
#      --iam-service-account=SERVICE_ACCT_EMAIL \
#      --iam-permission-role=[guestPolicyAdmin or guestPolicyEditor or guestPolicyViewer]

# ===============
# TROUBLESHOOTING
# ===============
#
# PERMISSION_DENIED errors
#
# If you see an error like:
#
#     WARNING: You do not appear to have access to project [PROJECT_ID] or it
#     does not exist.
#
# Make sure the project exists and you have access to it. Ask your project owner
# for help if needed.
#
# If you see an error like:
#
#     ERROR: (gcloud.services.enable) PERMISSION_DENIED: The caller does not
#     have permission.
#
# Refer to the `WHO SHOULD RUN THIS SCRIPT` section to make sure you are an
# owner of this project or ask the owner to grant you sufficient permission
# following https://cloud.google.com/service-usage/docs/access-control#permissions.

# Ignore the return code of command substitution in variables.
# shellcheck disable=SC2155

set -e

function troubleshooting {
  echo 'If you see a "Successfully finished executing the script." message above, everything should be all set. If any step failed, check out the TROUBLESHOOTING section of this script to see how to handle the error.'
}

trap troubleshooting EXIT

show_usage(){
  case "$1" in
    0)
    echo "Usage: bash set-permissions.sh --project=PROJECT --iam-user=USER_EMAIL --iam-permission-role=[guestPolicyAdmin or guestPolicyEditor or guestPolicyViewer]."
    echo "Usage: bash set-permissions.sh --project=PROJECT --iam-service-account=SERVICE_ACCT_EMAIL --iam-permission-role=[guestPolicyAdmin or guestPolicyEditor or guestPolicyViewer]."
    echo "Usage: bash set-permissions.sh --project=PROJECT.";;
    1)
    echo "Usage: allowable value for --iam-permission-role=[guestPolicyAdmin or guestPolicyEditor or guestPolicyViewer].";;
    2)
    echo "Usage: --iam-service-account and --iam-user are mutually exclusive.";;
  esac
}

# It should take 1 param (--project) or 3 params (--project, --iam-user/--iam-service-account, --iam-permission-role).
if [[ $# -le 0 ]] && [[$# -le 2 ]]; then
  show_usage 0
  exit 1
fi

OPTS="$(getopt -o vhns: --long project:,iam-user:,iam-service-account:,iam-permission-role: -n 'policy-set-up' -- "$@")"

if [[ $? != 0 ]]; then echo "Failed parsing options." >&2 ; exit 1 ; fi

echo "$OPTS"
eval set -- "$OPTS"

while true; do
  case "$1" in
    --iam-service-account)
      IAM_SERVICE_ACCOUNT="$2"; shift; shift ;;
    --iam-user)
      IAM_USER="$2"; shift; shift ;;
    --iam-permission-role)
      IAM_PERMISSION_ROLE="$2"; shift; shift ;;
    --project)
      PROJECT="$2"; shift; shift ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

if  [[ -n ${IAM_PERMISSION_ROLE} ]] && [[ "${IAM_PERMISSION_ROLE}" != "guestPolicyEditor" ]] && [[ "${IAM_PERMISSION_ROLE}" != "guestPolicyViewer" ]] && [[ "${IAM_PERMISSION_ROLE}" != "guestPolicyAdmin" ]]; then
  show_usage 1
  exit 1
fi

if [[ -n ${IAM_SERVICE_ACCOUNT} ]] && [[ -n ${IAM_USER} ]]; then
  show_usage 2
  exit 1
fi

echo "Step 1: Enable the Cloud Logging API, the Cloud Monitoring API and the OS Config API for the project by running the following set of commands:"
gcloud config set project "$PROJECT"
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable osconfig.googleapis.com
echo "Successfully finished step 1."

echo "Step 2: Grant the roles/logging.logWriter and the roles/monitoring.metricWriter roles to the Compute Engine default service account:"
DEFAULT_COMPUTE_SERVICE_ACCOUNT=$(gcloud iam service-accounts list \
  --filter=NAME:"Compute Engine default service account" \
  --filter=EMAIL:"compute@developer.gserviceaccount.com" --format="value(EMAIL)")
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member "serviceAccount:$DEFAULT_COMPUTE_SERVICE_ACCOUNT" --role "roles/logging.logWriter"
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member "serviceAccount:$DEFAULT_COMPUTE_SERVICE_ACCOUNT" --role "roles/monitoring.metricWriter"
echo "Successfully finished step 2."

echo "Step 3: Enable and verify the OS Config metadata for the project:"
gcloud compute project-info add-metadata --metadata=enable-guest-attributes=TRUE,enable-osconfig=TRUE
echo "Successfully finished step 3."

if [[ -n ${IAM_SERVICE_ACCOUNT} ]]; then
  echo "Step 4: Grant the corresponding Identity and Access Management (IAM) permission for the gcloud user:"
  gcloud projects add-iam-policy-binding "${PROJECT}" \
    --role "roles/osconfig.${IAM_PERMISSION_ROLE}" \
    --member "serviceAccount:${IAM_SERVICE_ACCOUNT}"
  echo "Successfully finished step 4."
fi

if [[ -n ${IAM_USER} ]]; then
  echo "Step 4: Grant the corresponding Identity and Access Management (IAM) permission for the service account:"
  gcloud projects add-iam-policy-binding "${PROJECT}" \
    --role "roles/osconfig.${IAM_PERMISSION_ROLE}" \
    --member "user:${IAM_USER}"
  echo "Successfully finished step 4."
fi

echo "Successfully finished executing the script."

