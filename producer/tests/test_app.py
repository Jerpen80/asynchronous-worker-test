from unittest.mock import Mock, patch

from producer.app import send_jobs


@patch("producer.app.time.sleep")
def test_send_jobs_batches_ten_messages(mock_sleep):
    sqs = Mock()
    sqs.send_message_batch.side_effect = [
        {"Successful": [{"Id": str(i)} for i in range(10)]},
        {"Successful": [{"Id": "10"}]},
    ]
    assert send_jobs("queue", 11, 0.1, sqs=sqs) == 11
    assert sqs.send_message_batch.call_count == 2
    assert mock_sleep.call_count == 2


@patch("producer.app.time.sleep")
def test_send_jobs_repeats_bursts_and_waits_between_them(mock_sleep):
    sqs = Mock()
    sqs.send_message_batch.return_value = {"Successful": [{"Id": "0"}]}

    assert send_jobs("queue", 1, 0, burst_count=3, burst_interval=30, sqs=sqs) == 3
    assert sqs.send_message_batch.call_count == 3
    assert mock_sleep.call_count == 2
    mock_sleep.assert_called_with(30)
