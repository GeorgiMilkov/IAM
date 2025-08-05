#!/usr/bin/env python3

import boto3
import datetime
import sys
import logging

# CONFIGURABLE PARAMETERS
KEY_AGE_LIMIT_DAYS = 90
DRY_RUN = True  # Set to False to actually delete/create keys
TARGET_USER = None  # Set to None for all users or specify a username

# Set up logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

def get_iam_users():
    iam = boto3.client('iam')
    paginator = iam.get_paginator('list_users')
    users = []
    for response in paginator.paginate():
        users.extend(response['Users'])
    return users

def rotate_keys_for_user(username):
    iam = boto3.client('iam')
    logging.info(f"Checking keys for user: {username}")
    response = iam.list_access_keys(UserName=username)

    keys = sorted(response['AccessKeyMetadata'], key=lambda x: x['CreateDate'])
    
    if len(keys) == 0:
        logging.info(f"No keys found for {username}. Creating a new access key.")
        if not DRY_RUN:
            new_key = iam.create_access_key(UserName=username)['AccessKey']
            logging.info(f"Created new key: {new_key['AccessKeyId']}")
        return

    for key in keys:
        key_id = key['AccessKeyId']
        age = (datetime.datetime.now(datetime.timezone.utc) - key['CreateDate']).days
        logging.info(f"Key {key_id} is {age} days old. Status: {key['Status']}")

        if age >= KEY_AGE_LIMIT_DAYS:
            logging.info(f"Rotating key {key_id} (age: {age} days)")

            if len(keys) >= 2:
                # AWS doesn't allow more than 2 active keys
                oldest_key = keys[0]
                logging.info(f"Deleting oldest key: {oldest_key['AccessKeyId']}")
                if not DRY_RUN:
                    iam.delete_access_key(UserName=username, AccessKeyId=oldest_key['AccessKeyId'])
                keys.pop(0)

            # Create a new key
            if not DRY_RUN:
                new_key = iam.create_access_key(UserName=username)['AccessKey']
                logging.info(f"Created new key: {new_key['AccessKeyId']}")

            # Deactivate old key
            if not DRY_RUN:
                iam.update_access_key(
                    UserName=username,
                    AccessKeyId=key_id,
                    Status='Inactive'
                )
                logging.info(f"Deactivated old key: {key_id}")

            return  # Rotate one key at a time to avoid lockout

def main():
    users = get_iam_users()
    for user in users:
        if TARGET_USER and user['UserName'] != TARGET_USER:
            continue
        rotate_keys_for_user(user['UserName'])

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.error(f"Error: {str(e)}")
        sys.exit(1)
