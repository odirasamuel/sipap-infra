"""
Payment Webhook Handler Lambda

Handles payment webhooks from Stripe, Paystack, and Flutterwave.
Updates user subscriptions and sends WhatsApp confirmations.

Supported Events:
- Stripe: checkout.session.completed
- Paystack: charge.success
- Flutterwave: charge.completed

Environment Variables:
    POSTGRES_SECRET_ARN: ARN of Secrets Manager secret with DB credentials
    STRIPE_WEBHOOK_SECRET: Stripe webhook signing secret
    PAYSTACK_SECRET_KEY: Paystack secret key for webhook verification
    FLUTTERWAVE_WEBHOOK_SECRET: Flutterwave webhook secret for verification
    TWILIO_SECRET_ARN: ARN of Secrets Manager secret with Twilio credentials
"""

import hashlib
import hmac
import json
import logging
import os
from datetime import datetime, timedelta, timezone
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
STRIPE_WEBHOOK_SECRET = os.environ.get('STRIPE_WEBHOOK_SECRET', '')
PAYSTACK_SECRET_KEY = os.environ.get('PAYSTACK_SECRET_KEY', '')
FLUTTERWAVE_WEBHOOK_SECRET = os.environ.get('FLUTTERWAVE_WEBHOOK_SECRET', '')
TWILIO_SECRET_ARN = os.environ.get('TWILIO_SECRET_ARN', '')


class PaymentData(TypedDict):
    """Extracted payment data."""
    phone_number: str
    tier: str
    weeks: int
    provider: str
    amount_usd: float
    customer_email: str | None
    reference: str


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


def verify_stripe_signature(payload: str, signature: str) -> bool:
    """
    Verify Stripe webhook signature.

    Args:
        payload: Raw request body
        signature: Stripe-Signature header value

    Returns:
        True if signature is valid
    """
    try:
        # Parse the signature header
        elements = dict(item.split('=') for item in signature.split(','))
        timestamp = elements.get('t', '')
        expected_sig = elements.get('v1', '')

        # Compute expected signature
        signed_payload = f"{timestamp}.{payload}"
        computed_sig = hmac.new(
            STRIPE_WEBHOOK_SECRET.encode('utf-8'),
            signed_payload.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()

        # Compare signatures
        return hmac.compare_digest(computed_sig, expected_sig)
    except Exception as e:
        logger.error(f"Stripe signature verification failed: {e}")
        return False


def verify_paystack_signature(payload: str, signature: str) -> bool:
    """
    Verify Paystack webhook signature using HMAC-SHA512.

    Args:
        payload: Raw request body
        signature: X-Paystack-Signature header value

    Returns:
        True if signature is valid
    """
    try:
        computed_sig = hmac.new(
            PAYSTACK_SECRET_KEY.encode('utf-8'),
            payload.encode('utf-8'),
            hashlib.sha512
        ).hexdigest()

        return hmac.compare_digest(computed_sig, signature)
    except Exception as e:
        logger.error(f"Paystack signature verification failed: {e}")
        return False


def verify_flutterwave_signature(signature: str) -> bool:
    """
    Verify Flutterwave webhook signature.

    Flutterwave uses a simple secret hash comparison.
    The 'verif-hash' header should match FLUTTERWAVE_WEBHOOK_SECRET.

    Args:
        signature: verif-hash header value

    Returns:
        True if signature matches
    """
    try:
        if not signature or not FLUTTERWAVE_WEBHOOK_SECRET:
            return False
        return hmac.compare_digest(signature, FLUTTERWAVE_WEBHOOK_SECRET)
    except Exception as e:
        logger.error(f"Flutterwave signature verification failed: {e}")
        return False


def extract_stripe_payment_data(event: dict) -> PaymentData | None:
    """Extract payment data from Stripe checkout.session.completed event."""
    try:
        session = event['data']['object']
        metadata = session.get('metadata', {})

        return {
            'phone_number': metadata.get('phone_number', ''),
            'tier': metadata.get('tier', 'basic'),
            'weeks': int(metadata.get('weeks', '1')),
            'provider': 'stripe',
            'amount_usd': session.get('amount_total', 0) / 100,
            'customer_email': session.get('customer_email'),
            'reference': session.get('id', ''),
        }
    except Exception as e:
        logger.error(f"Failed to extract Stripe payment data: {e}")
        return None


def extract_paystack_payment_data(event: dict) -> PaymentData | None:
    """Extract payment data from Paystack charge.success event."""
    try:
        data = event['data']
        metadata = data.get('metadata', {})

        return {
            'phone_number': metadata.get('phone_number', ''),
            'tier': metadata.get('tier', 'basic'),
            'weeks': int(metadata.get('weeks', 1)),
            'provider': 'paystack',
            'amount_usd': data.get('amount', 0) / 100,
            'customer_email': data.get('customer', {}).get('email'),
            'reference': data.get('reference', ''),
        }
    except Exception as e:
        logger.error(f"Failed to extract Paystack payment data: {e}")
        return None


def extract_flutterwave_payment_data(event: dict) -> PaymentData | None:
    """
    Extract payment data from Flutterwave charge.completed event.

    Flutterwave event structure:
    {
        "event": "charge.completed",
        "data": {
            "id": 12345678,
            "tx_ref": "SIPAP_1234567890_abc123",
            "flw_ref": "FLW-MOCK-xxxxx",
            "amount": 2,
            "currency": "USD",
            "status": "successful",
            "customer": {
                "email": "user@example.com",
                "phone_number": "+2348012345678",
                "name": "John Doe"
            },
            "meta": {
                "phone_number": "+2348012345678",
                "tier": "basic",
                "weeks": "1",
                "provider": "flutterwave"
            }
        }
    }
    """
    try:
        data = event.get('data', {})
        meta = data.get('meta', {})
        customer = data.get('customer', {})

        # Get phone number from meta or customer
        phone_number = meta.get('phone_number', '') or customer.get('phone_number', '')

        # Handle weeks as string or int
        weeks_raw = meta.get('weeks', '1')
        weeks = int(weeks_raw) if isinstance(weeks_raw, str) else weeks_raw

        return {
            'phone_number': phone_number,
            'tier': meta.get('tier', 'basic'),
            'weeks': weeks,
            'provider': 'flutterwave',
            'amount_usd': data.get('amount', 0),  # Flutterwave already in USD
            'customer_email': customer.get('email'),
            'reference': data.get('tx_ref', '') or data.get('flw_ref', ''),
        }
    except Exception as e:
        logger.error(f"Failed to extract Flutterwave payment data: {e}")
        return None


def update_subscription(payment_data: PaymentData) -> bool:
    """
    Update user subscription in the database.

    Args:
        payment_data: Extracted payment information

    Returns:
        True if update was successful
    """
    conn = None
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            # Calculate new expiration date
            expires_at = datetime.now(timezone.utc) + timedelta(weeks=payment_data['weeks'])

            # Update user subscription
            cursor.execute(
                """
                UPDATE users SET
                    subscription_status = 'active',
                    subscription_tier = %s,
                    subscription_expires_at = %s,
                    updated_at = NOW()
                WHERE phone_number = %s
                RETURNING id, name
                """,
                (payment_data['tier'], expires_at, payment_data['phone_number'])
            )

            user = cursor.fetchone()
            if not user:
                logger.error(f"User not found: {payment_data['phone_number']}")
                return False

            # Record subscription event
            # Use appropriate reference field based on provider
            stripe_ref = payment_data['reference'] if payment_data['provider'] == 'stripe' else None
            paystack_ref = payment_data['reference'] if payment_data['provider'] == 'paystack' else None
            flutterwave_ref = payment_data['reference'] if payment_data['provider'] == 'flutterwave' else None

            cursor.execute(
                """
                INSERT INTO subscription_events (
                    user_id, event_type, provider, amount_usd,
                    stripe_session_id, paystack_reference, flutterwave_reference, metadata
                ) VALUES (
                    %s, 'payment_succeeded', %s, %s, %s, %s, %s, %s
                )
                """,
                (
                    user['id'],
                    payment_data['provider'],
                    payment_data['amount_usd'],
                    stripe_ref,
                    paystack_ref,
                    flutterwave_ref,
                    json.dumps({
                        'tier': payment_data['tier'],
                        'weeks': payment_data['weeks'],
                        'customer_email': payment_data['customer_email'],
                    }),
                )
            )

        conn.commit()
        logger.info(f"Subscription updated for {payment_data['phone_number']}: {payment_data['tier']} x {payment_data['weeks']} weeks")
        return True

    except Exception as e:
        logger.exception(f"Failed to update subscription: {e}")
        if conn:
            conn.rollback()
        return False
    finally:
        if conn:
            conn.close()


def send_whatsapp_confirmation(phone_number: str, tier: str, weeks: int) -> bool:
    """
    Send WhatsApp confirmation message via Twilio.

    Args:
        phone_number: User's phone number in E.164 format
        tier: Subscription tier
        weeks: Number of weeks purchased

    Returns:
        True if message was sent successfully
    """
    try:
        if not TWILIO_SECRET_ARN:
            logger.warning("TWILIO_SECRET_ARN not configured, skipping WhatsApp notification")
            return True

        twilio_creds = get_secret(TWILIO_SECRET_ARN)
        account_sid = twilio_creds['account_sid']
        auth_token = twilio_creds['auth_token']
        from_number = twilio_creds.get('whatsapp_number', 'whatsapp:+15553836181')

        # Send via Twilio API
        import urllib.request
        import base64

        tier_name = 'Pro' if tier == 'pro' else 'Basic'
        message = (
            f"Payment confirmed! Your SIPAP {tier_name} subscription is now active for {weeks} week(s). "
            f"Send me a team name or match to get AI-powered predictions!"
        )

        url = f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json"

        data = {
            'From': from_number if from_number.startswith('whatsapp:') else f'whatsapp:{from_number}',
            'To': f'whatsapp:{phone_number}' if not phone_number.startswith('whatsapp:') else phone_number,
            'Body': message,
        }

        # URL encode the data
        encoded_data = '&'.join(f"{k}={urllib.parse.quote(str(v))}" for k, v in data.items()).encode('utf-8')

        request = urllib.request.Request(url, data=encoded_data, method='POST')
        auth_string = base64.b64encode(f"{account_sid}:{auth_token}".encode('utf-8')).decode('utf-8')
        request.add_header('Authorization', f'Basic {auth_string}')
        request.add_header('Content-Type', 'application/x-www-form-urlencoded')

        with urllib.request.urlopen(request, timeout=10) as response:
            if response.status == 201:
                logger.info(f"WhatsApp confirmation sent to {phone_number}")
                return True
            else:
                logger.error(f"Failed to send WhatsApp: {response.status}")
                return False

    except Exception as e:
        logger.exception(f"Failed to send WhatsApp confirmation: {e}")
        return False


def handler(event: dict, context) -> dict:
    """
    Lambda handler for payment webhooks.

    Args:
        event: API Gateway event with webhook payload
        context: Lambda context

    Returns:
        API Gateway response
    """
    try:
        # Extract headers and body
        headers = event.get('headers', {})
        body = event.get('body', '')

        # Handle base64 encoding if needed
        if event.get('isBase64Encoded', False):
            import base64
            body = base64.b64decode(body).decode('utf-8')

        # Determine provider based on headers
        stripe_signature = headers.get('stripe-signature') or headers.get('Stripe-Signature', '')
        paystack_signature = headers.get('x-paystack-signature') or headers.get('X-Paystack-Signature', '')
        flutterwave_signature = headers.get('verif-hash') or headers.get('Verif-Hash', '')

        payment_data = None

        if stripe_signature:
            # Stripe webhook
            logger.info("Processing Stripe webhook")

            if not verify_stripe_signature(body, stripe_signature):
                logger.warning("Invalid Stripe signature")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Invalid signature'}),
                }

            webhook_event = json.loads(body)

            if webhook_event.get('type') != 'checkout.session.completed':
                logger.info(f"Ignoring Stripe event: {webhook_event.get('type')}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'received': True}),
                }

            payment_data = extract_stripe_payment_data(webhook_event)

        elif paystack_signature:
            # Paystack webhook
            logger.info("Processing Paystack webhook")

            if not verify_paystack_signature(body, paystack_signature):
                logger.warning("Invalid Paystack signature")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Invalid signature'}),
                }

            webhook_event = json.loads(body)

            if webhook_event.get('event') != 'charge.success':
                logger.info(f"Ignoring Paystack event: {webhook_event.get('event')}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'received': True}),
                }

            payment_data = extract_paystack_payment_data(webhook_event)

        elif flutterwave_signature:
            # Flutterwave webhook
            logger.info("Processing Flutterwave webhook")

            if not verify_flutterwave_signature(flutterwave_signature):
                logger.warning("Invalid Flutterwave signature")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Invalid signature'}),
                }

            webhook_event = json.loads(body)

            # Check for charge.completed event with successful status
            if webhook_event.get('event') != 'charge.completed':
                logger.info(f"Ignoring Flutterwave event: {webhook_event.get('event')}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'received': True}),
                }

            # Verify payment was successful
            event_data = webhook_event.get('data', {})
            if event_data.get('status') != 'successful':
                logger.info(f"Ignoring Flutterwave payment with status: {event_data.get('status')}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'received': True, 'status': event_data.get('status')}),
                }

            payment_data = extract_flutterwave_payment_data(webhook_event)

        else:
            logger.warning("Unknown webhook provider (no signature header)")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing signature header'}),
            }

        if not payment_data or not payment_data['phone_number']:
            logger.error("Invalid payment data")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid payment data'}),
            }

        # Update subscription
        if update_subscription(payment_data):
            # Send WhatsApp confirmation
            send_whatsapp_confirmation(
                payment_data['phone_number'],
                payment_data['tier'],
                payment_data['weeks'],
            )

            return {
                'statusCode': 200,
                'body': json.dumps({'received': True, 'subscription_updated': True}),
            }
        else:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Failed to update subscription'}),
            }

    except Exception as e:
        logger.exception(f"Error processing webhook: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'}),
        }


# Import for URL encoding (needed for Twilio API call)
import urllib.parse
