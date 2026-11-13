"""AWS Cost Guardian - stops tagged EC2 instances when a budget action alert arrives.

Triggered by the "action" SNS topic. AWS Budgets publishes to that topic when
spend crosses the action threshold; you can also publish a test message to it.

Safety rules:
- Only RUNNING instances tagged TAG_KEY=TAG_VALUE are touched.
- Instances are STOPPED, never terminated (EBS data is kept).
- DRY_RUN=true logs what would happen without stopping anything.
"""

import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("TAG_KEY", "AutoStop")
TAG_VALUE = os.environ.get("TAG_VALUE", "true")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"

ec2 = boto3.client("ec2")


def find_tagged_running_instances():
    """Return IDs of running instances that carry the opt-in tag."""
    instance_ids = []
    paginator = ec2.get_paginator("describe_instances")
    pages = paginator.paginate(
        Filters=[
            {"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    for page in pages:
        for reservation in page["Reservations"]:
            for instance in reservation["Instances"]:
                instance_ids.append(instance["InstanceId"])
    return instance_ids


def lambda_handler(event, context):
    records = event.get("Records", [])
    for record in records:
        sns = record.get("Sns", {})
        logger.info("Alert received | subject=%s | message=%s",
                    sns.get("Subject"), sns.get("Message", "")[:500])

    instance_ids = find_tagged_running_instances()
    logger.info("Running instances tagged %s=%s: %s", TAG_KEY, TAG_VALUE, instance_ids)

    if not instance_ids:
        result = {"action": "none", "reason": "no running tagged instances"}
        logger.info(json.dumps(result))
        return result

    if DRY_RUN:
        result = {"action": "dry_run", "would_stop": instance_ids}
        logger.info(json.dumps(result))
        return result

    response = ec2.stop_instances(InstanceIds=instance_ids)
    stopped = [
        {"id": i["InstanceId"], "state": i["CurrentState"]["Name"]}
        for i in response.get("StoppingInstances", [])
    ]
    result = {"action": "stopped", "instances": stopped}
    logger.info(json.dumps(result))
    return result
