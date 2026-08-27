"""
Account Handler Lambda

Retrieves user account information and subscription history.

Endpoint: GET /account?phone={phone_number}

Returns:
    - User profile (name, email, phone, subscription status)
    - Subscription details (tier, expiration, provider)
    - Payment history (recent subscription events)

Environment Variables:
    POSTGRES_SECRET_ARN: ARN of Secrets Manager secret with DB credentials
"""

import json
import logging
import os
from datetime import datetime, timezone
from typing import TypedDict

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


class UserAccount(TypedDict):
    """User account data returned to frontend."""
    name: str
    email: str
    phone_number: str
    subscription_status: str
    subscription_tier: str
    subscription_expires_at: str
    provider: str


class SubscriptionEvent(TypedDict):
    """Subscription event for payment history."""
    event_type: str
    amount_usd: float
    created_at: str


def get_secret(secret_arn: str) -> dict:
    """Retrieve secret from Secrets Manager."""
    response = secrets_manager.get_secret_value(SecretId=secret_arn)
    return json.loads(response['SecretString'])


def get_db_connection():
    """Create a database connection using credentials from Secrets Manager."""
    credentials = get_secret(POSTGRES_SECRET_ARN)
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
    Normalize phone number to E.164 format.

    Args:
        phone: Phone number (may have spaces, dashes, etc.)

    Returns:
        Normalized phone number starting with +
    """
    # Remove all non-digit characters except +
    cleaned = ''.join(c for c in phone if c.isdigit() or c == '+')

    # Ensure it starts with +
    if not cleaned.startswith('+'):
        cleaned = '+' + cleaned

    return cleaned


def get_user_account(phone_number: str) -> dict | None:
    """
    Retrieve user account information from database.

    Args:
        phone_number: User's phone number in E.164 format

    Returns:
        Dict with user info and payment history, or None if not found
    """
    conn = None
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            # Get user info
            cursor.execute(
                """
                SELECT
                    id,
                    name,
                    email,
                    phone_number,
                    subscription_status,
                    subscription_tier,
                    subscription_expires_at,
                    subscription_grace_until,
                    created_at
                FROM users
                WHERE phone_number = %s AND is_active = true
                """,
                (phone_number,)
            )

            user_row = cursor.fetchone()

            if not user_row:
                return None

            # Determine effective subscription status
            # If expired but within grace period, still show as active
            subscription_status = user_row['subscription_status']
            expires_at = user_row['subscription_expires_at']
            grace_until = user_row['subscription_grace_until']

            now = datetime.now(timezone.utc)

            if expires_at and subscription_status == 'active':
                # Make expires_at timezone-aware if it isn't
                if expires_at.tzinfo is None:
                    expires_at = expires_at.replace(tzinfo=timezone.utc)

                if expires_at < now:
                    # Check grace period
                    if grace_until:
                        if grace_until.tzinfo is None:
                            grace_until = grace_until.replace(tzinfo=timezone.utc)

                        if grace_until < now:
                            subscription_status = 'expired'
                        # else: still in grace period, keep as active
                    else:
                        subscription_status = 'expired'

            # Determine provider from most recent payment
            cursor.execute(
                """
                SELECT provider
                FROM subscription_events
                WHERE user_id = %s AND event_type = 'payment_succeeded'
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (user_row['id'],)
            )
            provider_row = cursor.fetchone()
            provider = provider_row['provider'] if provider_row else 'flutterwave'

            # Get payment history (last 10 events)
            cursor.execute(
                """
                SELECT
                    event_type,
                    amount_usd,
                    created_at
                FROM subscription_events
                WHERE user_id = %s
                ORDER BY created_at DESC
                LIMIT 10
                """,
                (user_row['id'],)
            )

            history_rows = cursor.fetchall()

            # Format user data
            user: UserAccount = {
                'name': user_row['name'] or 'Valo User',
                'email': user_row['email'] or '',
                'phone_number': user_row['phone_number'],
                'subscription_status': subscription_status,
                'subscription_tier': user_row['subscription_tier'] or 'basic',
                'subscription_expires_at': (
                    user_row['subscription_expires_at'].isoformat()
                    if user_row['subscription_expires_at']
                    else ''
                ),
                'provider': provider,
            }

            # Format payment history
            history: list[SubscriptionEvent] = [
                {
                    'event_type': row['event_type'],
                    'amount_usd': float(row['amount_usd']) if row['amount_usd'] else 0,
                    'created_at': row['created_at'].isoformat() if row['created_at'] else '',
                }
                for row in history_rows
            ]

            return {
                'user': user,
                'history': history,
            }

    except Exception as e:
        logger.exception(f"Failed to get user account: {e}")
        return None
    finally:
        if conn:
            conn.close()


def handler(event: dict, context) -> dict:
    """
    Lambda handler for account lookup.

    Args:
        event: API Gateway event with query parameters
        context: Lambda context

    Returns:
        API Gateway response with user data or error
    """
    # CORS headers
    cors_headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'GET,OPTIONS',
        'Content-Type': 'application/json',
    }

    try:
        # Handle OPTIONS preflight
        http_method = event.get('httpMethod') or event.get('requestContext', {}).get('http', {}).get('method', '')
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': '',
            }

        # Get phone number from query parameters
        query_params = event.get('queryStringParameters') or {}
        phone_raw = query_params.get('phone', '')

        if not phone_raw:
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'Phone number is required'}),
            }

        # Normalize phone number
        phone_number = normalize_phone_number(phone_raw)

        if len(phone_number) < 10:
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'Invalid phone number format'}),
            }

        logger.info(f"Looking up account for: {phone_number}")

        # Get user account
        result = get_user_account(phone_number)

        if not result:
            return {
                'statusCode': 404,
                'headers': cors_headers,
                'body': json.dumps({'error': 'User not found'}),
            }

        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps(result),
        }

    except Exception as e:
        logger.exception(f"Error in account handler: {e}")
        return {
            'statusCode': 500,
            'headers': cors_headers,
            'body': json.dumps({'error': 'Internal server error'}),
        }
