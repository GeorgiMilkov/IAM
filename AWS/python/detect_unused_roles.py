#!/usr/bin/env python3

import boto3
import datetime
import logging
import sys

# === Configuration ===
THRESHOLD_DAYS = 90
DRY_RUN = True  # Set to False to enable deletion suggestions or tagging
TAG_UNUSED = False  # Optionally add a tag to unused roles
TAG_KEY = "Usage"
TAG_VALUE = "Unused"

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

iam = boto3.client('iam')

def get_roles():
    paginator = iam.get_paginator('list_roles')
    for page in paginator.paginate():
        for role in page['Roles']:
            yield role

def is_unused(role):
    role_name = role['RoleName']
    try:
        last_used = role.get('RoleLastUsed', {}).get('LastUsedDate')
        if not last_used:
            logging.info(f"Role {role_name} has **never been used**.")
            return True

        now = datetime.datetime.now(datetime.timezone.utc)
        days_unused = (now - last_used).days
        logging.info(f"Role {role_name} last used {days_unused} days ago.")

        return days_unused > THRESHOLD_DAYS
    except Exception as e:
        logging.warning(f"Could not evaluate role {role_name}: {e}")
        return False

def tag_role(role_name):
    try:
        logging.info(f"Tagging role {role_name} as unused")
        if not DRY_RUN:
            iam.tag_role(
                RoleName=role_name,
                Tags=[{'Key': TAG_KEY, 'Value': TAG_VALUE}]
            )
    except Exception as e:
        logging.error(f"Failed to tag role {role_name}: {e}")

def main():
    unused_roles = []
    for role in get_roles():
        if is_unused(role):
            unused_roles.append(role['RoleName'])

    print("\n=== Unused Roles (> {} days) ===".format(THRESHOLD_DAYS))
    for role in unused_roles:
        print(f"- {role}")
        if TAG_UNUSED:
            tag_role(role)

    if not unused_roles:
        print("No unused roles detected.")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.error(f"Script failed: {e}")
        sys.exit(1)
