import argparse
import os
import time

import boto3


def send_jobs(
    queue_url: str,
    count: int,
    delay: float,
    burst_count: int = 1,
    burst_interval: float = 0,
    sqs=None,
) -> int:
    sqs = sqs or boto3.client("sqs", region_name=os.getenv("AWS_REGION", "eu-central-1"))
    sent = 0
    for burst in range(burst_count):
        print(f"Starting burst {burst + 1}/{burst_count}", flush=True)
        for start in range(0, count, 10):
            batch = [
                {
                    "Id": str(i),
                    "MessageBody": f"burst-{burst + 1}-job-{i}",
                }
                for i in range(start, min(start + 10, count))
            ]
            response = sqs.send_message_batch(QueueUrl=queue_url, Entries=batch)
            if response.get("Failed"):
                raise RuntimeError(f"SQS rejected messages: {response['Failed']}")
            sent += len(response.get("Successful", []))
            print(f"Sent {sent}/{count * burst_count} jobs", flush=True)
            if delay:
                time.sleep(delay)
        if burst < burst_count - 1 and burst_interval:
            print(f"Waiting {burst_interval} seconds before the next burst", flush=True)
            time.sleep(burst_interval)
    return sent


def main() -> None:
    parser = argparse.ArgumentParser(description="Send a burst of jobs to SQS")
    parser.add_argument("--count", type=int, default=int(os.getenv("MESSAGE_COUNT", "100")))
    parser.add_argument("--delay", type=float, default=float(os.getenv("BATCH_DELAY_SECONDS", "0.1")))
    parser.add_argument("--bursts", type=int, default=int(os.getenv("BURST_COUNT", "1")))
    parser.add_argument(
        "--burst-interval",
        type=float,
        default=float(os.getenv("BURST_INTERVAL_SECONDS", "60")),
    )
    args = parser.parse_args()
    send_jobs(os.environ["QUEUE_URL"], args.count, args.delay, args.bursts, args.burst_interval)


if __name__ == "__main__":
    main()
