import json
import os
import random
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3

RUNNING = True


def process_message(body: str, delay: float, failure_rate: float = 0.0) -> None:
    payload = json.loads(body) if body.lstrip().startswith("{") else body
    print(f"Processing: {payload}", flush=True)
    if failure_rate and random.random() < failure_rate:
        raise RuntimeError("Intentional processing failure")
    time.sleep(delay)


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/health"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_error(404)

    def log_message(self, *_args):
        return


def consume(queue_url: str, sqs=None) -> None:
    sqs = sqs or boto3.client("sqs", region_name=os.getenv("AWS_REGION", "eu-central-1"))
    delay = float(os.getenv("PROCESSING_SECONDS", "5"))
    failure_rate = float(os.getenv("FAILURE_RATE", "0"))
    while RUNNING:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=20,
            AttributeNames=["ApproximateReceiveCount"],
        )
        for message in response.get("Messages", []):
            try:
                process_message(message["Body"], delay, failure_rate)
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=message["ReceiptHandle"])
            except Exception as exc:
                # No delete: SQS makes the message visible again, then eventually sends it to the DLQ.
                print(f"Processing failed: {exc}", flush=True)


def main() -> None:
    global RUNNING
    signal.signal(signal.SIGTERM, lambda *_: globals().__setitem__("RUNNING", False))
    server = ThreadingHTTPServer(("0.0.0.0", 8080), HealthHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        consume(os.environ["QUEUE_URL"])
    finally:
        RUNNING = False
        server.shutdown()


if __name__ == "__main__":
    main()
