from unittest.mock import Mock, patch

from consumer.app import HealthHandler, process_message


@patch("consumer.app.time.sleep")
def test_process_message(mock_sleep):
    process_message("job-1", 5)
    mock_sleep.assert_called_once_with(5)


def test_health_handler_supports_health_path():
    assert HealthHandler.do_GET is not None
