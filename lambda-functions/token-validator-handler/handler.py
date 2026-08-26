"""
Token Validator Handler Lambda

Validates registration tokens from signup URLs.
Used by the web registration page to verify tokens before showing payment options.

Endpoint: GET /auth/validate-token?token={token}&phone={phone}

Response (success):
    {
        "valid": true,
        "phone_number": "+2348012345678",
        "expires_at": "2026-08-26T15:30:00Z"
    }

Response (error):
    {
        "valid": false,
        "error": "Token expired",
        "error_code": "TOKEN_EXPIRED"
    }

Environment Variables:
    POSTGRES_SECRET_ARN: ARN of Secrets Manager secret with DB credentials
"""

import json
import logging
import os
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

# Cache for secrets
_db_credentials = None


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


def validate_registration_token(token: str, phone_number: str) -> dict:
    """
    Validate a registration token.

    Args:
        token: Registration token from URL
        phone_number: Phone number to validate against

    Returns:
        Validation result with status and details
    """
    conn = None
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT
                    phone_number,
                    expires_at,
                    used_at,
                    created_at
                FROM user_registration_tokens
                WHERE token = %s
                LIMIT 1
                """,
                (token,)
            )

            token_record = cursor.fetchone()

            if not token_record:
                return {
                    'valid': False,
                    'error': 'Token not found',
                    'error_code': 'TOKEN_NOT_FOUND'
                }

            # Check phone number matches
            if token_record['phone_number'] != phone_number:
                return {
                    'valid': False,
                    'error': 'Phone number mismatch',
                    'error_code': 'PHONE_MISMATCH'
                }

            # Check if already used
            if token_record['used_at']:
                return {
                    'valid': False,
                    'error': 'Token already used',
                    'error_code': 'TOKEN_USED',
                    'used_at': token_record['used_at'].isoformat()
                }

            # Check if expired
            now = datetime.now(timezone.utc)
            # Handle timezone-naive datetime from DB
            expires_at = token_record['expires_at']
            if expires_at.tzinfo is None:
                expires_at = expires_at.replace(tzinfo=timezone.utc)

            if expires_at < now:
                return {
                    'valid': False,
                    'error': 'Token expired',
                    'error_code': 'TOKEN_EXPIRED',
                    'expired_at': expires_at.isoformat()
                }

            return {
                'valid': True,
                'phone_number': token_record['phone_number'],
                'expires_at': expires_at.isoformat(),
                'already_used': False
            }

    except Exception as e:
        logger.exception(f"Error validating token: {e}")
        return {
            'valid': False,
            'error': 'Internal error',
            'error_code': 'INTERNAL_ERROR'
        }
    finally:
        if conn:
            conn.close()


def get_user_status(phone_number: str) -> dict | None:
    """
    Get user subscription status.

    Args:
        phone_number: User's phone number

    Returns:
        User status dict or None if user doesn't exist
    """
    conn = None
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT
                    id,
                    phone_number,
                    name,
                    subscription_status,
                    subscription_tier,
                    subscription_expires_at,
                    subscription_grace_until,
                    is_active
                FROM users
                WHERE phone_number = %s AND deleted_at IS NULL
                LIMIT 1
                """,
                (phone_number,)
            )

            user = cursor.fetchone()
            if not user:
                return None

            now = datetime.now(timezone.utc)

            # Determine actual status
            expires_at = user['subscription_expires_at']
            grace_until = user['subscription_grace_until']

            if expires_at:
                if expires_at.tzinfo is None:
                    expires_at = expires_at.replace(tzinfo=timezone.utc)
            if grace_until:
                if grace_until.tzinfo is None:
                    grace_until = grace_until.replace(tzinfo=timezone.utc)

            if not user['is_active']:
                status = 'suspended'
            elif expires_at is None:
                status = 'trial'
            elif expires_at > now:
                status = 'active'
            elif grace_until and grace_until > now:
                status = 'grace_period'
            else:
                status = 'expired'

            return {
                'exists': True,
                'phone_number': user['phone_number'],
                'name': user['name'],
                'status': status,
                'tier': user['subscription_tier'],
                'expires_at': expires_at.isoformat() if expires_at else None,
                'grace_until': grace_until.isoformat() if grace_until else None
            }

    except Exception as e:
        logger.exception(f"Error getting user status: {e}")
        return None
    finally:
        if conn:
            conn.close()


def handler(event: dict, context) -> dict:
    """
    Lambda handler for token validation and user status.

    Supports two operations:
    - GET /auth/validate-token?token={token}&phone={phone} - Validate registration token
    - GET /auth/user-status?phone={phone} - Get user subscription status

    Args:
        event: API Gateway event
        context: Lambda context

    Returns:
        API Gateway response
    """
    # CORS headers
    cors_headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Content-Type': 'application/json'
    }

    try:
        # Handle CORS preflight
        http_method = event.get('httpMethod') or event.get('requestContext', {}).get('http', {}).get('method', '')
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': '',
            }

        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        path = event.get('path', '')

        # Route based on path
        if 'user-status' in path:
            # GET /auth/user-status?phone={phone}
            phone_number = query_params.get('phone', '').strip()

            if not phone_number:
                return {
                    'statusCode': 400,
                    'headers': cors_headers,
                    'body': json.dumps({'error': 'phone parameter is required'})
                }

            # Ensure phone starts with +
            if not phone_number.startswith('+'):
                phone_number = f'+{phone_number}'

            user_status = get_user_status(phone_number)

            if user_status is None:
                return {
                    'statusCode': 200,
                    'headers': cors_headers,
                    'body': json.dumps({
                        'exists': False,
                        'phone_number': phone_number
                    })
                }

            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': json.dumps(user_status)
            }

        else:
            # GET /auth/validate-token?token={token}&phone={phone}
            token = query_params.get('token', '').strip()
            phone_number = query_params.get('phone', '').strip()

            if not token:
                return {
                    'statusCode': 400,
                    'headers': cors_headers,
                    'body': json.dumps({'error': 'token parameter is required'})
                }

            if not phone_number:
                return {
                    'statusCode': 400,
                    'headers': cors_headers,
                    'body': json.dumps({'error': 'phone parameter is required'})
                }

            # Ensure phone starts with +
            if not phone_number.startswith('+'):
                phone_number = f'+{phone_number}'

            result = validate_registration_token(token, phone_number)

            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': json.dumps(result)
            }

    except Exception as e:
        logger.exception(f"Error in token validator: {e}")
        return {
            'statusCode': 500,
            'headers': cors_headers,
            'body': json.dumps({'error': 'Internal server error'})
        }
