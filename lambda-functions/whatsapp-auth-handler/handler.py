"""
WhatsApp Auth Handler Lambda

Authenticates incoming WhatsApp messages by checking user subscription status.
Routes messages based on authentication result:
- Active subscribers: Forward to SQS for processing
- New users: Return TwiML with signup link
- Expired users: Return TwiML with renewal link

Environment Variables:
    POSTGRES_SECRET_ARN: ARN of Secrets Manager secret with DB credentials
    SQS_QUEUE_URL: URL of the WhatsApp messages SQS FIFO queue
    BASE_URL: Base URL for signup/renewal pages (e.g., https://ridhatech.com)
"""

import json
import logging
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import TypedDict
from urllib.parse import parse_qs

import boto3
import psycopg2
from psycopg2.extras import RealDictCursor

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secrets_manager = boto3.client('secretsmanager')
sqs = boto3.client('sqs')

# Environment variables
POSTGRES_SECRET_ARN = os.environ.get('POSTGRES_SECRET_ARN', '')
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL', '')
BASE_URL = os.environ.get('BASE_URL', 'https://ridhatech.com')


class UserStatus(TypedDict):
    """User subscription status."""
    exists: bool
    is_active: bool
    subscription_status: str | None
    subscription_expires_at: datetime | None
    name: str | None


class TwilioPayload(TypedDict):
    """Parsed Twilio webhook payload."""
    from_number: str
    body: str
    message_sid: str
    account_sid: str


def get_db_credentials() -> dict:
    """Retrieve database credentials from Secrets Manager."""
    response = secrets_manager.get_secret_value(SecretId=POSTGRES_SECRET_ARN)
    return json.loads(response['SecretString'])


def get_db_connection():
    """Create a database connection using credentials from Secrets Manager."""
    credentials = get_db_credentials()
    return psycopg2.connect(
        host=credentials['host'],
        port=credentials.get('port', 5432),
        database=credentials['database'],
        user=credentials['username'],
        password=credentials['password'],
        connect_timeout=5,
    )


def parse_twilio_payload(body: str) -> TwilioPayload:
    """Parse Twilio webhook form-urlencoded payload."""
    params = parse_qs(body)
    return {
        'from_number': params.get('From', [''])[0],
        'body': params.get('Body', [''])[0],
        'message_sid': params.get('MessageSid', [''])[0],
        'account_sid': params.get('AccountSid', [''])[0],
    }


def check_user_status(phone_number: str) -> UserStatus:
    """
    Check user subscription status in the database.

    Args:
        phone_number: User's phone number in E.164 format

    Returns:
        UserStatus with subscription details
    """
    conn = None
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT
                    name,
                    subscription_status,
                    subscription_expires_at,
                    is_active
                FROM users
                WHERE phone_number = %s AND is_active = true
                LIMIT 1
                """,
                (phone_number,)
            )
            row = cursor.fetchone()

            if not row:
                return {
                    'exists': False,
                    'is_active': False,
                    'subscription_status': None,
                    'subscription_expires_at': None,
                    'name': None,
                }

            return {
                'exists': True,
                'is_active': row['is_active'],
                'subscription_status': row['subscription_status'],
                'subscription_expires_at': row['subscription_expires_at'],
                'name': row['name'],
            }
    finally:
        if conn:
            conn.close()


def create_registration_token(phone_number: str) -> str:
    """
    Create a one-time registration token for new user signup.

    Args:
        phone_number: User's phone number

    Returns:
        Generated token string
    """
    token = secrets.token_urlsafe(32)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)

    conn = None
    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO user_registration_tokens (phone_number, token, expires_at)
                VALUES (%s, %s, %s)
                ON CONFLICT (token) DO UPDATE SET
                    phone_number = EXCLUDED.phone_number,
                    expires_at = EXCLUDED.expires_at,
                    used_at = NULL
                """,
                (phone_number, token, expires_at)
            )
        conn.commit()
        return token
    finally:
        if conn:
            conn.close()


def forward_to_sqs(phone_number: str, raw_payload: str, request_id: str) -> None:
    """
    Forward authenticated message to SQS for processing.

    Args:
        phone_number: User's phone number (used as MessageGroupId)
        raw_payload: Original Twilio webhook payload
        request_id: API Gateway request ID (used for deduplication)
    """
    sqs.send_message(
        QueueUrl=SQS_QUEUE_URL,
        MessageBody=raw_payload,
        MessageGroupId=phone_number,
        MessageDeduplicationId=request_id,
    )
    logger.info(f"Forwarded message to SQS for {phone_number}")


def generate_twiml_response(message: str) -> str:
    """Generate TwiML XML response."""
    return f'<?xml version="1.0" encoding="UTF-8"?><Response><Message>{message}</Message></Response>'


def generate_empty_twiml() -> str:
    """Generate empty TwiML response (no reply to user)."""
    return '<?xml version="1.0" encoding="UTF-8"?><Response></Response>'


def handler(event: dict, context) -> dict:
    """
    Lambda handler for WhatsApp authentication.

    Args:
        event: API Gateway event with Twilio webhook payload
        context: Lambda context

    Returns:
        API Gateway response with TwiML
    """
    try:
        # Extract request details
        request_id = event.get('requestContext', {}).get('requestId', secrets.token_urlsafe(16))
        body = event.get('body', '')

        # Handle base64 encoding if needed
        if event.get('isBase64Encoded', False):
            import base64
            body = base64.b64decode(body).decode('utf-8')

        logger.info(f"Processing request {request_id}")

        # Parse Twilio payload
        payload = parse_twilio_payload(body)
        phone_number = payload['from_number']

        if not phone_number:
            logger.warning("No phone number in payload")
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'text/xml'},
                'body': generate_twiml_response("Sorry, we couldn't process your message. Please try again."),
            }

        logger.info(f"Checking subscription status for {phone_number}")

        # Check user subscription status
        user_status = check_user_status(phone_number)

        # Route based on status
        if not user_status['exists']:
            # New user - generate registration token and return signup link
            token = create_registration_token(phone_number)
            signup_url = f"{BASE_URL}/signup?token={token}&phone={phone_number}"

            logger.info(f"New user {phone_number} - sending signup link")
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'text/xml'},
                'body': generate_twiml_response(
                    f"Welcome to SIPAP! To get started with AI-powered sports predictions, "
                    f"please register here: {signup_url}"
                ),
            }

        # Check if subscription is expired
        now = datetime.now(timezone.utc)
        expires_at = user_status['subscription_expires_at']

        if expires_at and expires_at < now:
            # Expired subscription - send renewal link
            renew_url = f"{BASE_URL}/renew?phone={phone_number}"
            name = user_status['name'] or 'there'

            logger.info(f"Expired subscription for {phone_number} - sending renewal link")
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'text/xml'},
                'body': generate_twiml_response(
                    f"Hi {name}! Your SIPAP subscription has expired. "
                    f"Renew now to continue receiving AI sports predictions: {renew_url}"
                ),
            }

        if user_status['subscription_status'] != 'active':
            # User exists but no active subscription
            subscribe_url = f"{BASE_URL}/subscribe?phone={phone_number}"
            name = user_status['name'] or 'there'

            logger.info(f"Inactive subscription for {phone_number} - sending subscribe link")
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'text/xml'},
                'body': generate_twiml_response(
                    f"Hi {name}! You need an active subscription to use SIPAP. "
                    f"Subscribe here: {subscribe_url}"
                ),
            }

        # Active subscriber - forward to SQS for processing
        forward_to_sqs(phone_number, body, request_id)

        logger.info(f"Active subscriber {phone_number} - message forwarded to SQS")

        # Return empty TwiML - the orchestrator will send the actual response
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'text/xml'},
            'body': generate_empty_twiml(),
        }

    except Exception as e:
        logger.exception(f"Error processing WhatsApp message: {e}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'text/xml'},
            'body': generate_twiml_response(
                "Sorry, we're experiencing technical difficulties. Please try again later."
            ),
        }
