"""
WhatsApp Auth Handler Lambda

Authenticates incoming WhatsApp messages by checking user subscription status.
Routes messages based on authentication result:
- Active subscribers: Forward to SQS for processing
- Grace period users: Forward to SQS but send renewal reminder (once per day)
- New users: Return TwiML with signup link
- Expired users (past grace): Return TwiML with renewal link

Features:
- 24-hour grace period after subscription expiration
- Daily renewal reminders during grace period
- Soft cutoff to avoid abrupt service interruption

Environment Variables:
    POSTGRES_SECRET_ARN: ARN of Secrets Manager secret with DB credentials
    SQS_QUEUE_URL: URL of the WhatsApp messages SQS FIFO queue
    BASE_URL: Base URL for signup/renewal pages (e.g., https://valo.ai)
    TWILIO_SECRET_ARN: ARN for Twilio credentials (optional, for grace period reminders)
"""

import json
import logging
import os
import secrets
import urllib.parse
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
BASE_URL = os.environ.get('BASE_URL', 'https://valo.ai')
TWILIO_SECRET_ARN = os.environ.get('TWILIO_SECRET_ARN', '')


class UserStatus(TypedDict):
    """User subscription status including grace period."""
    exists: bool
    is_active: bool
    subscription_status: str | None
    subscription_expires_at: datetime | None
    subscription_grace_until: datetime | None
    name: str | None
    in_grace_period: bool


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


def normalize_phone_number(phone: str) -> str:
    """
    Normalize phone number by stripping whatsapp: prefix.

    Twilio sends: whatsapp:+2348012345678
    Database stores: +2348012345678
    """
    if phone.startswith('whatsapp:'):
        return phone[9:]  # Remove 'whatsapp:' prefix
    return phone


def parse_twilio_payload(body: str) -> TwilioPayload:
    """Parse Twilio webhook form-urlencoded payload."""
    params = parse_qs(body)
    raw_from = params.get('From', [''])[0]
    return {
        'from_number': normalize_phone_number(raw_from),
        'body': params.get('Body', [''])[0],
        'message_sid': params.get('MessageSid', [''])[0],
        'account_sid': params.get('AccountSid', [''])[0],
    }


def check_user_status(phone_number: str) -> UserStatus:
    """
    Check user subscription status including grace period.

    Args:
        phone_number: User's phone number in E.164 format

    Returns:
        UserStatus with subscription details and grace period info
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
                    subscription_grace_until,
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
                    'subscription_grace_until': None,
                    'name': None,
                    'in_grace_period': False,
                }

            now = datetime.now(timezone.utc)
            expires_at = row['subscription_expires_at']
            grace_until = row['subscription_grace_until']

            # Determine if user is in grace period
            # Grace period = subscription expired but grace_until is still in the future
            in_grace_period = False
            if expires_at and expires_at < now:
                if grace_until and grace_until > now:
                    in_grace_period = True

            return {
                'exists': True,
                'is_active': row['is_active'],
                'subscription_status': row['subscription_status'],
                'subscription_expires_at': expires_at,
                'subscription_grace_until': grace_until,
                'name': row['name'],
                'in_grace_period': in_grace_period,
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


def send_grace_period_reminder(phone_number: str, grace_until: datetime) -> None:
    """
    Send a reminder that subscription is in grace period (once per day max).

    This is a non-blocking operation - if it fails, the message is still processed.

    Args:
        phone_number: User's phone number
        grace_until: Grace period expiration timestamp
    """
    conn = None
    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            # Check if reminder already sent today
            cursor.execute(
                """
                SELECT renewal_reminder_sent_at FROM users
                WHERE phone_number = %s
                AND renewal_reminder_sent_at > NOW() - INTERVAL '24 hours'
                """,
                (phone_number,)
            )

            if cursor.fetchone():
                logger.info(f"Grace period reminder already sent today to {phone_number}")
                return

            # Update reminder timestamp
            cursor.execute(
                "UPDATE users SET renewal_reminder_sent_at = NOW() WHERE phone_number = %s",
                (phone_number,)
            )
            conn.commit()

        # Calculate hours remaining
        hours_remaining = max(0, int((grace_until - datetime.now(timezone.utc)).total_seconds() / 3600))

        # Send reminder via Twilio (non-blocking)
        send_whatsapp_message(
            phone_number,
            f"Your Valo subscription expired. You have {hours_remaining} hours of grace period remaining. "
            f"Renew now to avoid interruption: {BASE_URL}/renew?phone={phone_number}"
        )

        logger.info(f"Sent grace period reminder to {phone_number} ({hours_remaining}h remaining)")

    except Exception as e:
        # Log but don't fail - message processing should continue
        logger.error(f"Failed to send grace period reminder to {phone_number}: {e}")
    finally:
        if conn:
            conn.close()


def send_whatsapp_message(phone_number: str, message: str) -> bool:
    """
    Send a WhatsApp message via Twilio.

    Args:
        phone_number: Recipient's phone number
        message: Message text

    Returns:
        True if sent successfully
    """
    try:
        if not TWILIO_SECRET_ARN:
            logger.warning("TWILIO_SECRET_ARN not configured")
            return False

        response = secrets_manager.get_secret_value(SecretId=TWILIO_SECRET_ARN)
        twilio_creds = json.loads(response['SecretString'])

        account_sid = twilio_creds['account_sid']
        auth_token = twilio_creds['auth_token']
        from_number = twilio_creds.get('whatsapp_number', 'whatsapp:+15553836181')

        import urllib.request
        import base64

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
            return response.status == 201

    except Exception as e:
        logger.error(f"Failed to send WhatsApp message: {e}")
        return False


def generate_twiml_response(message: str) -> str:
    """Generate TwiML XML response."""
    return f'<?xml version="1.0" encoding="UTF-8"?><Response><Message>{message}</Message></Response>'


def generate_empty_twiml() -> str:
    """Generate empty TwiML response (no reply to user)."""
    return '<?xml version="1.0" encoding="UTF-8"?><Response></Response>'


def handler(event: dict, context) -> dict:
    """
    Lambda handler for WhatsApp authentication with grace period support.

    Decision flow:
    1. New user -> signup link
    2. Expired AND past grace period -> renewal link (blocked)
    3. In grace period -> allow but send reminder
    4. No active subscription -> subscribe link
    5. Active subscriber -> forward to SQS

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
        now = datetime.now(timezone.utc)

        # =================================================================
        # Decision 1: New user - generate registration token and signup link
        # =================================================================
        if not user_status['exists']:
            token = create_registration_token(phone_number)
            signup_url = f"{BASE_URL}/signup?token={token}&phone={phone_number}"

            logger.info(f"New user {phone_number} - sending signup link")

            # Send message via Twilio API (same as orchestrator)
            send_whatsapp_message(
                phone_number,
                f"Welcome to Valo! To get started with AI-powered sports predictions, "
                f"please register here: {signup_url}"
            )

            # Return empty TwiML - message already sent via API
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'text/xml'},
                'body': generate_empty_twiml(),
            }

        name = user_status['name'] or 'there'
        expires_at = user_status['subscription_expires_at']

        # =================================================================
        # Decision 2: Expired AND past grace period - blocked
        # =================================================================
        if expires_at and expires_at < now and not user_status['in_grace_period']:
            renew_url = f"{BASE_URL}/renew?phone={phone_number}"

            logger.info(f"Expired subscription (past grace) for {phone_number}")

            # Send message via Twilio API (same as orchestrator)
            send_whatsapp_message(
                phone_number,
                f"Hi {name}! Your Valo subscription has expired. "
                f"Renew now to continue receiving AI sports predictions: {renew_url}"
            )

            # Return empty TwiML - message already sent via API
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'text/xml'},
                'body': generate_empty_twiml(),
            }

        # =================================================================
        # Decision 3: In grace period - allow but remind
        # =================================================================
        if user_status['in_grace_period']:
            logger.info(f"User {phone_number} in grace period - allowing with reminder")

            # Forward message to queue for processing
            forward_to_sqs(phone_number, body, request_id)

            # Send non-blocking grace period reminder (once per day)
            if user_status['subscription_grace_until']:
                send_grace_period_reminder(phone_number, user_status['subscription_grace_until'])

            # Return empty TwiML - orchestrator will send the actual response
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'text/xml'},
                'body': generate_empty_twiml(),
            }

        # =================================================================
        # Decision 4: User exists but no active subscription
        # =================================================================
        if user_status['subscription_status'] != 'active':
            subscribe_url = f"{BASE_URL}/subscribe?phone={phone_number}"

            logger.info(f"Inactive subscription for {phone_number}")

            # Send message via Twilio API (same as orchestrator)
            send_whatsapp_message(
                phone_number,
                f"Hi {name}! You need an active subscription to use Valo. "
                f"Subscribe here: {subscribe_url}"
            )

            # Return empty TwiML - message already sent via API
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'text/xml'},
                'body': generate_empty_twiml(),
            }

        # =================================================================
        # Decision 5: Active subscriber - forward to SQS for processing
        # =================================================================
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
