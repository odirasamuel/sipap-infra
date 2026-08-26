"""
Subscription Reminder Handler Lambda

Sends 24-hour pre-expiration reminders to users via WhatsApp.
Runs on an hourly schedule via EventBridge.

Features:
- Finds users whose subscriptions expire within 24 hours
- Sends WhatsApp reminder with renewal link
- Tracks reminder_sent_at to prevent duplicate reminders
- Batch processing with configurable batch size

Environment Variables:
    POSTGRES_SECRET_ARN: ARN of Secrets Manager secret with DB credentials
    TWILIO_SECRET_ARN: ARN of Secrets Manager secret with Twilio credentials
    BASE_URL: Base URL for renewal links (default: https://valo.ai)
    BATCH_SIZE: Number of users to process per invocation (default: 100)
"""

import base64
import json
import logging
import os
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import boto3
import psycopg2
from psycopg2.extras import RealDictCursor

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secrets_manager = boto3.client('secretsmanager')

# Environment variables
POSTGRES_SECRET_ARN = os.environ.get('POSTGRES_SECRET_ARN', '')
TWILIO_SECRET_ARN = os.environ.get('TWILIO_SECRET_ARN', '')
BASE_URL = os.environ.get('BASE_URL', 'https://valo.ai')
BATCH_SIZE = int(os.environ.get('BATCH_SIZE', '100'))

# Cache for secrets
_db_credentials = None
_twilio_credentials = None


def get_secret(secret_arn: str) -> dict:
    """Retrieve secret from Secrets Manager."""
    response = secrets_manager.get_secret_value(SecretId=secret_arn)
    return json.loads(response['SecretString'])


def get_db_connection():
    """Create a database connection using credentials from Secrets Manager."""
    global _db_credentials

    if _db_credentials is None:
        _db_credentials = get_secret(POSTGRES_SECRET_ARN)

    return psycopg2.connect(
        host=_db_credentials['host'],
        port=_db_credentials.get('port', 5432),
        database=_db_credentials['database'],
        user=_db_credentials['username'],
        password=_db_credentials['password'],
        connect_timeout=5,
    )


def get_twilio_credentials() -> dict:
    """Get Twilio credentials from Secrets Manager (cached)."""
    global _twilio_credentials

    if _twilio_credentials is None:
        _twilio_credentials = get_secret(TWILIO_SECRET_ARN)

    return _twilio_credentials


def get_users_expiring_soon(cursor) -> list[dict]:
    """
    Find users whose subscriptions expire within 24 hours
    and haven't received an expiration reminder yet.

    Returns:
        List of user dicts with id, phone_number, name, subscription_expires_at
    """
    cursor.execute(
        """
        SELECT
            id,
            phone_number,
            name,
            subscription_tier,
            subscription_expires_at
        FROM users
        WHERE
            subscription_status = 'active'
            AND is_active = true
            AND deleted_at IS NULL
            AND subscription_expires_at BETWEEN NOW() AND NOW() + INTERVAL '24 hours'
            AND (
                expiration_reminder_sent_at IS NULL
                OR expiration_reminder_sent_at < subscription_expires_at - INTERVAL '24 hours'
            )
        ORDER BY subscription_expires_at ASC
        LIMIT %s
        """,
        (BATCH_SIZE,)
    )
    return cursor.fetchall()


def send_whatsapp_message(phone_number: str, message: str) -> bool:
    """
    Send WhatsApp message via Twilio.

    Args:
        phone_number: User's phone number in E.164 format
        message: Message to send

    Returns:
        True if message was sent successfully
    """
    try:
        twilio_creds = get_twilio_credentials()
        account_sid = twilio_creds['account_sid']
        auth_token = twilio_creds['auth_token']
        from_number = twilio_creds.get('whatsapp_number', 'whatsapp:+15553836181')

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
                logger.info(f"WhatsApp reminder sent to {phone_number}")
                return True
            else:
                logger.error(f"Failed to send WhatsApp: {response.status}")
                return False

    except Exception as e:
        logger.exception(f"Failed to send WhatsApp message to {phone_number}: {e}")
        return False


def send_expiration_reminder(
    phone_number: str,
    name: str | None,
    expires_at: datetime
) -> bool:
    """
    Send WhatsApp expiration reminder.

    Args:
        phone_number: User's phone number
        name: User's name (optional)
        expires_at: When subscription expires

    Returns:
        True if reminder was sent successfully
    """
    try:
        # Calculate hours until expiration
        now = datetime.now(timezone.utc)
        hours_remaining = max(0, int((expires_at - now).total_seconds() / 3600))

        display_name = name or 'there'
        renew_url = f"{BASE_URL}/renew?phone={urllib.parse.quote(phone_number)}"

        message = (
            f"Hi {display_name}! Your Valo subscription expires in {hours_remaining} hours. "
            f"Renew now to keep getting AI-powered sports predictions: {renew_url}"
        )

        return send_whatsapp_message(phone_number, message)

    except Exception as e:
        logger.error(f"Failed to send expiration reminder to {phone_number}: {e}")
        return False


def update_reminder_timestamp(cursor, user_id: str) -> None:
    """
    Mark that we sent an expiration reminder.

    Args:
        cursor: Database cursor
        user_id: User's UUID
    """
    cursor.execute(
        "UPDATE users SET expiration_reminder_sent_at = NOW() WHERE id = %s",
        (user_id,)
    )


def handler(event: dict, context) -> dict:
    """
    Lambda handler for subscription expiration reminders.

    Args:
        event: EventBridge scheduled event (or manual invocation)
        context: Lambda context

    Returns:
        Summary of processing results
    """
    logger.info("Starting subscription expiration reminder job")

    conn = None
    try:
        conn = get_db_connection()

        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            users = get_users_expiring_soon(cursor)
            logger.info(f"Found {len(users)} users with subscriptions expiring in 24 hours")

            if not users:
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'No users need reminders',
                        'users_processed': 0,
                        'reminders_sent': 0,
                        'failures': 0
                    })
                }

            sent_count = 0
            failed_count = 0

            for user in users:
                try:
                    if send_expiration_reminder(
                        user['phone_number'],
                        user['name'],
                        user['subscription_expires_at']
                    ):
                        update_reminder_timestamp(cursor, str(user['id']))
                        sent_count += 1
                    else:
                        failed_count += 1
                except Exception as e:
                    logger.error(f"Error processing user {user['id']}: {e}")
                    failed_count += 1

            conn.commit()

            logger.info(f"Reminder job complete: {sent_count} sent, {failed_count} failed")

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Reminder job completed',
                    'users_processed': len(users),
                    'reminders_sent': sent_count,
                    'failures': failed_count
                })
            }

    except Exception as e:
        logger.exception(f"Error in reminder job: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
    finally:
        if conn:
            conn.close()
