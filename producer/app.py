import argparse
import os
import time

import boto3


def send_jobs(queue_url: str, count: int, delay: float, sqs=None) -> int:
    sqs = sqs or boto3.client("sqs", region_name=os.getenv("AWS_REGION", "eu-central-1"))
    sent = 0
    for start in range(0, count, 10):
        batch = [
            {"Id": str(i), "MessageBody": f"job-{i}"}
            for i in range(start, min(start + 10, count))
        ]
        response = sqs.send_message_batch(QueueUrl=queue_url, Entries=batch)
        if response.get("Failed"):
            raise RuntimeError(f"SQS rejected messages: {response['Failed']}")
        sent += len(response.get("Successful", []))
        print(f"Sent {sent}/{count} jobs", flush=True)
        if delay:
            time.sleep(delay)
    return sent


def main() -> None:
    parser = argparse.ArgumentParser(description="Send a burst of jobs to SQS")
    parser.add_argument("--count", type=int, default=int(os.getenv("MESSAGE_COUNT", "100")))
    parser.add_argument("--delay", type=float, default=float(os.getenv("BATCH_DELAY_SECONDS", "0.1")))
    args = parser.parse_args()
    send_jobs(os.environ["QUEUE_URL"], args.count, args.delay)


if __name__ == "__main__":
    main()
