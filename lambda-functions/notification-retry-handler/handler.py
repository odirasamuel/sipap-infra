"""
Notification Retry Handler Lambda

Processes failed WhatsApp notification messages from the retry queue.
Attempts to resend payment confirmation messages via Twilio.

Message Format (from payment webhook handler):
{
    "phone_number": "+2348012345678",
    "tier": "basic",
    "weeks": 1,
    "retry_count": 0
}

Retry Strategy:
- Queue has 5 minute delay before first delivery
- Max 3 retries before moving to DLQ
- SQS handles visibility timeout and redelivery

Environment Variables:
    TWILIO_SECRET_ARN: ARN of Secrets Manager secret with Twilio credentials
"""

import base64
import json
import logging
import os
import urllib.parse
import urllib.request

import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secrets_manager = boto3.client('secretsmanager')

# Environment variables
TWILIO_SECRET_ARN = os.environ.get('TWILIO_SECRET_ARN', '')

# Cache for Twilio credentials (reused across invocations)
_twilio_creds_cache: dict | None = None


def get_twilio_credentials() -> dict:
    """
    Retrieve Twilio credentials from Secrets Manager with caching.

    Returns:
        Dict with account_sid, auth_token, whatsapp_number
    """
    global _twilio_creds_cache

    if _twilio_creds_cache is not None:
        return _twilio_creds_cache

    if not TWILIO_SECRET_ARN:
        raise ValueError("TWILIO_SECRET_ARN environment variable not set")

    response = secrets_manager.get_secret_value(SecretId=TWILIO_SECRET_ARN)
    _twilio_creds_cache = json.loads(response['SecretString'])
    return _twilio_creds_cache


def send_whatsapp_confirmation(phone_number: str, tier: str, weeks: int) -> bool:
    """
    Send WhatsApp confirmation message via Twilio.

    Args:
        phone_number: User's phone number in E.164 format
        tier: Subscription tier (basic, pro)
        weeks: Number of weeks purchased

    Returns:
        True if message was sent successfully
    """
    try:
        twilio_creds = get_twilio_credentials()

        account_sid = twilio_creds['account_sid']
        auth_token = twilio_creds['auth_token']
        from_number = twilio_creds.get('whatsapp_number', 'whatsapp:+15553836181')

        tier_name = 'Pro' if tier == 'pro' else 'Basic'
        message = (
            f"Payment confirmed! Your Valo {tier_name} subscription is now active for {weeks} week(s). "
            f"Send me a team name or match to get AI-powered predictions!"
        )

        url = f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json"

        data = {
            'From': from_number if from_number.startswith('whatsapp:') else f'whatsapp:{from_number}',
            'To': f'whatsapp:{phone_number}' if not phone_number.startswith('whatsapp:') else phone_number,
            'Body': message,
        }

        encoded_data = '&'.join(f"{k}={urllib.parse.quote(str(v))}" for k, v in data.items()).encode('utf-8')

        request = urllib.request.Request(url, data=encoded_data, method='POST')
        auth_string = base64.b64encode(f"{account_sid}:{auth_token}".encode('utf-8')).decode('utf-8')
        request.add_header('Authorization', f'Basic {auth_string}')
        request.add_header('Content-Type', 'application/x-www-form-urlencoded')

        with urllib.request.urlopen(request, timeout=10) as response:
            if response.status == 201:
                logger.info(f"WhatsApp confirmation sent successfully to {phone_number}")
                return True
            else:
                logger.error(f"Failed to send WhatsApp: HTTP {response.status}")
                return False

    except urllib.error.HTTPError as e:
        logger.error(f"Twilio API error: {e.code} - {e.reason}")
        # Read error body for debugging
        try:
            error_body = e.read().decode('utf-8')
            logger.error(f"Twilio error details: {error_body}")
        except Exception:
            pass
        return False

    except Exception as e:
        logger.exception(f"Failed to send WhatsApp confirmation: {e}")
        return False


def handler(event: dict, context) -> dict:
    """
    Lambda handler for notification retry queue.

    Processes SQS messages containing failed WhatsApp notifications.
    Messages that fail here will be retried by SQS (up to maxReceiveCount).
    After max retries, messages go to the dead letter queue.

    Args:
        event: SQS event with Records array
        context: Lambda context

    Returns:
        Processing result
    """
    records = event.get('Records', [])
    success_count = 0
    failure_count = 0

    for record in records:
        try:
            # Parse message body
            body = json.loads(record['body'])
            phone_number = body.get('phone_number', '')
            tier = body.get('tier', 'basic')
            weeks = body.get('weeks', 1)
            retry_count = body.get('retry_count', 0)

            logger.info(
                f"Processing notification retry for {phone_number}, "
                f"tier={tier}, weeks={weeks}, attempt={retry_count + 1}"
            )

            # Validate required fields
            if not phone_number:
                logger.error("Missing phone_number in message body")
                failure_count += 1
                continue

            # Attempt to send notification
            if send_whatsapp_confirmation(phone_number, tier, weeks):
                logger.info(f"Notification sent successfully to {phone_number}")
                success_count += 1
            else:
                logger.warning(f"Notification failed for {phone_number}, will be retried by SQS")
                failure_count += 1
                # Raise to trigger SQS retry
                raise RuntimeError(f"Failed to send notification to {phone_number}")

        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in message body: {e}")
            failure_count += 1
            # Don't raise - bad message format should go to DLQ
            continue

        except Exception as e:
            logger.exception(f"Error processing record: {e}")
            failure_count += 1
            # Re-raise to trigger SQS retry
            raise

    logger.info(f"Processed {len(records)} records: {success_count} success, {failure_count} failures")

    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(records),
            'success': success_count,
            'failures': failure_count,
        })
    }
