import logging
import json

# Configure logging with INFO level to capture important events and general information
logging.basicConfig(level=logging.INFO)

def handler(event, context):
    try:
        # Log the received event as a JSON string for better readability in the logs
        logging.info(f"Received event: {json.dumps(event)}")

        # Add your event processing logic here
        logging.info("Processing event...")  # Log that event processing has started

        # Example of processing logic: check if 'key1' exists in the event data
        if 'key1' in event:
            # Log the value of 'key1' if it exists in the event
            logging.info(f"Event contains key1 with value: {event['key1']}")

        # Return a success message after the event is processed
        return "Event processed successfully"

    except Exception as e:
        # Log any errors that occur during event processing
        logging.error(f"Error occurred: {e}")
        # Rethrow the exception to ensure proper error handling and visibility
        raise

# Simulate event reception (for local testing)
if __name__ == "__main__":
    # Example test event to simulate how the function handles real events
    test_event = {"key1": "value1"}
    handler(test_event, None)  # Call the handler function with the test event
