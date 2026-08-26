"""
Payment Session Handler Lambda

Creates Flutterwave checkout sessions for subscription payments.

Endpoint: POST /payments/create-session
Request Body:
    {
        "phone_number": "+2348012345678",
        "tier": "basic",
        "weeks": 1,
        "country": "NG",
        "email": "user@example.com"  // optional
    }

Response:
    {
        "checkout_url": "https://checkout.flutterwave.com/...",
        "tx_ref": "VALO_1234567890_abc123"
    }

Environment Variables:
    FLUTTERWAVE_SECRET_ARN: ARN of Secrets Manager secret with Flutterwave credentials
    REDIRECT_URL: URL to redirect after payment completion
"""

import json
import logging
import os
import random
import string
import time
import urllib.request
import urllib.error

import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secrets_manager = boto3.client('secretsmanager')

# Environment variables
FLUTTERWAVE_SECRET_ARN = os.environ.get('FLUTTERWAVE_SECRET_ARN', '')
REDIRECT_URL = os.environ.get('REDIRECT_URL', 'https://ridhatech.com/payment-success')

# Subscription tiers (must match database)
SUBSCRIPTION_TIERS = {
    'basic': {
        'name': 'Pro',  # Display name (we renamed basic to Pro for users)
        'price_cents': 200,  # $2
    },
}

# Cache for secrets (reused across warm Lambda invocations)
_flutterwave_credentials = None


def get_flutterwave_credentials() -> dict:
    """Retrieve Flutterwave credentials from Secrets Manager (cached)."""
    global _flutterwave_credentials

    if _flutterwave_credentials is None:
        if not FLUTTERWAVE_SECRET_ARN:
            raise ValueError("FLUTTERWAVE_SECRET_ARN environment variable not set")

        response = secrets_manager.get_secret_value(SecretId=FLUTTERWAVE_SECRET_ARN)
        _flutterwave_credentials = json.loads(response['SecretString'])
        logger.info("Flutterwave credentials loaded from Secrets Manager")

    return _flutterwave_credentials


def generate_tx_ref() -> str:
    """Generate unique transaction reference."""
    timestamp = int(time.time() * 1000)
    random_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=7))
    return f"VALO_{timestamp}_{random_suffix}"


def create_flutterwave_session(
    phone_number: str,
    tier: str,
    weeks: int,
    customer_email: str | None = None,
    customer_name: str | None = None,
) -> dict:
    """
    Create Flutterwave Standard checkout session.

    Args:
        phone_number: Customer phone number in E.164 format
        tier: Subscription tier (basic)
        weeks: Number of weeks to subscribe
        customer_email: Customer email (optional but recommended)
        customer_name: Customer name (optional)

    Returns:
        dict with checkout_url and tx_ref

    Raises:
        ValueError: If tier is invalid
        RuntimeError: If Flutterwave API call fails
    """
    if tier not in SUBSCRIPTION_TIERS:
        raise ValueError(f"Invalid tier: {tier}. Must be one of: {list(SUBSCRIPTION_TIERS.keys())}")

    credentials = get_flutterwave_credentials()
    secret_key = credentials.get('secret_key')

    if not secret_key:
        raise ValueError("Flutterwave secret_key not found in credentials")

    tier_data = SUBSCRIPTION_TIERS[tier]
    total_cents = tier_data['price_cents'] * weeks
    amount_usd = total_cents / 100

    tx_ref = generate_tx_ref()

    # Build request payload
    payload = {
        'tx_ref': tx_ref,
        'amount': amount_usd,
        'currency': 'USD',
        'redirect_url': REDIRECT_URL,
        'customer': {
            'email': customer_email or f"{phone_number.replace('+', '')}@valo.user",
            'phonenumber': phone_number,
            'name': customer_name or 'Valo User',
        },
        'customizations': {
            'title': 'Valo Subscription',
            'description': f"{tier_data['name']} Plan - {weeks} {'Week' if weeks == 1 else 'Weeks'}",
            'logo': 'https://ridhatech.com/logo.png',
        },
        'meta': {
            'phone_number': phone_number,
            'tier': tier,
            'weeks': str(weeks),
            'provider': 'flutterwave',
        },
    }

    # Make API request to Flutterwave
    url = 'https://api.flutterwave.com/v3/payments'
    headers = {
        'Authorization': f'Bearer {secret_key}',
        'Content-Type': 'application/json',
    }

    request_data = json.dumps(payload).encode('utf-8')
    request = urllib.request.Request(url, data=request_data, headers=headers, method='POST')

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response_data = json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8') if e.fp else 'No error body'
        logger.error(f"Flutterwave API error: {e.code} - {error_body}")
        raise RuntimeError(f"Flutterwave API error: {e.code}")
    except urllib.error.URLError as e:
        logger.error(f"Flutterwave connection error: {e.reason}")
        raise RuntimeError(f"Failed to connect to Flutterwave: {e.reason}")

    if response_data.get('status') != 'success':
        error_message = response_data.get('message', 'Unknown error')
        logger.error(f"Flutterwave payment creation failed: {error_message}")
        raise RuntimeError(f"Flutterwave error: {error_message}")

    checkout_url = response_data.get('data', {}).get('link')
    if not checkout_url:
        logger.error(f"No checkout URL in response: {response_data}")
        raise RuntimeError("Flutterwave did not return a checkout URL")

    logger.info(f"Created Flutterwave session: tx_ref={tx_ref}, amount=${amount_usd}")

    return {
        'checkout_url': checkout_url,
        'tx_ref': tx_ref,
    }


def handler(event: dict, context) -> dict:
    """
    Lambda handler for creating payment sessions.

    Args:
        event: API Gateway event
        context: Lambda context

    Returns:
        API Gateway response with checkout URL or error
    """
    # CORS headers for browser requests
    cors_headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
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

        # Parse request body
        body = event.get('body', '{}')
        if event.get('isBase64Encoded', False):
            import base64
            body = base64.b64decode(body).decode('utf-8')

        try:
            request_data = json.loads(body) if body else {}
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in request body: {e}")
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'Invalid JSON in request body'}),
            }

        # Extract and validate parameters
        phone_number = request_data.get('phone_number', '').strip()
        tier = request_data.get('tier', 'basic').strip().lower()
        weeks = request_data.get('weeks', 1)
        customer_email = request_data.get('email', '').strip() or None
        customer_name = request_data.get('name', '').strip() or None

        # Validate phone number
        if not phone_number:
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'phone_number is required'}),
            }

        # Ensure phone number starts with +
        if not phone_number.startswith('+'):
            phone_number = f'+{phone_number}'

        # Validate weeks
        try:
            weeks = int(weeks)
            if weeks < 1 or weeks > 52:
                raise ValueError("weeks must be between 1 and 52")
        except (ValueError, TypeError):
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'weeks must be a number between 1 and 52'}),
            }

        # Validate tier
        if tier not in SUBSCRIPTION_TIERS:
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({
                    'error': f'Invalid tier. Must be one of: {list(SUBSCRIPTION_TIERS.keys())}',
                }),
            }

        # Create Flutterwave session
        result = create_flutterwave_session(
            phone_number=phone_number,
            tier=tier,
            weeks=weeks,
            customer_email=customer_email,
            customer_name=customer_name,
        )

        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps(result),
        }

    except ValueError as e:
        logger.error(f"Validation error: {e}")
        return {
            'statusCode': 400,
            'headers': cors_headers,
            'body': json.dumps({'error': str(e)}),
        }
    except RuntimeError as e:
        logger.error(f"Runtime error: {e}")
        return {
            'statusCode': 502,
            'headers': cors_headers,
            'body': json.dumps({'error': str(e)}),
        }
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'headers': cors_headers,
            'body': json.dumps({'error': 'Internal server error'}),
        }
