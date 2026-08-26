"""
Payment Webhook Handler Lambda

Handles payment webhooks from Stripe, Paystack, and Flutterwave.
Updates user subscriptions and sends WhatsApp confirmations.

Features:
- Idempotency protection via database constraints
- Payment attempt tracking for reconciliation
- Grace period calculation (24 hours)
- Notification retry queue for failed WhatsApp messages

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
    WHATSAPP_NOTIFICATION_QUEUE_URL: SQS queue URL for notification retries
"""

import hashlib
import hmac
import json
import logging
import os
import urllib.parse
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
sqs = boto3.client('sqs')

# Environment variables
POSTGRES_SECRET_ARN = os.environ.get('POSTGRES_SECRET_ARN', '')
STRIPE_WEBHOOK_SECRET = os.environ.get('STRIPE_WEBHOOK_SECRET', '')
PAYSTACK_SECRET_KEY = os.environ.get('PAYSTACK_SECRET_KEY', '')
FLUTTERWAVE_WEBHOOK_SECRET = os.environ.get('FLUTTERWAVE_WEBHOOK_SECRET', '')
TWILIO_SECRET_ARN = os.environ.get('TWILIO_SECRET_ARN', '')
WHATSAPP_NOTIFICATION_QUEUE_URL = os.environ.get('WHATSAPP_NOTIFICATION_QUEUE_URL', '')

# Grace period duration (24 hours after subscription expiration)
GRACE_PERIOD_HOURS = 24


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


# =============================================================================
# Signature Verification
# =============================================================================


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
        elements = dict(item.split('=') for item in signature.split(','))
        timestamp = elements.get('t', '')
        expected_sig = elements.get('v1', '')

        signed_payload = f"{timestamp}.{payload}"
        computed_sig = hmac.new(
            STRIPE_WEBHOOK_SECRET.encode('utf-8'),
            signed_payload.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()

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


# =============================================================================
# Payment Data Extraction
# =============================================================================


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


def parse_tx_ref(tx_ref: str) -> dict | None:
    """
    Parse payment data from tx_ref.

    Format: VALO_{phone_safe}_{tier}_{weeks}_{timestamp}_{random}
    Example: VALO_P2348012345678_basic_1_1787760291660_u2foxx1

    Returns dict with phone_number, tier, weeks or None if parsing fails.
    """
    try:
        if not tx_ref or not tx_ref.startswith('VALO_'):
            return None

        parts = tx_ref.split('_')
        if len(parts) < 5:
            # Old format: VALO_{timestamp}_{random} - can't extract data
            return None

        # New format: VALO_{phone_safe}_{tier}_{weeks}_{timestamp}_{random}
        phone_safe = parts[1]
        tier = parts[2]
        weeks = int(parts[3])

        # Decode phone: P -> +
        phone_number = phone_safe.replace('P', '+')

        return {
            'phone_number': phone_number,
            'tier': tier,
            'weeks': weeks,
        }
    except (ValueError, IndexError) as e:
        logger.warning(f"Failed to parse tx_ref '{tx_ref}': {e}")
        return None


def extract_flutterwave_payment_data(event: dict) -> PaymentData | None:
    """
    Extract payment data from Flutterwave webhook event.

    Flutterwave sends two different payload structures:

    1. CARD_TRANSACTION (test mode / some live transactions):
    {
        "id": 12345678,
        "txRef": "VALO_P2348012345678_basic_1_1787760291660_abc123",
        "flwRef": "FLW-MOCK-xxxxx",
        "amount": 2,
        "currency": "USD",
        "status": "successful",
        "customer": {"email": "..."},
        "event.type": "CARD_TRANSACTION"
    }

    2. charge.completed (standard webhook):
    {
        "event": "charge.completed",
        "data": {
            "tx_ref": "VALO_P2348012345678_basic_1_...",
            "flw_ref": "FLW-...",
            ...
        }
    }

    Payment data (phone, tier, weeks) is embedded in tx_ref since
    Flutterwave doesn't return the meta object in webhooks.
    """
    try:
        # Detect payload structure: root-level (CARD_TRANSACTION) or nested (charge.completed)
        if 'txRef' in event or 'event.type' in event:
            # Root-level structure (CARD_TRANSACTION)
            data = event
            customer = data.get('customer', {})
            reference = data.get('txRef', '') or data.get('flwRef', '')
        else:
            # Nested structure (charge.completed)
            data = event.get('data', {})
            customer = data.get('customer', {})
            reference = data.get('tx_ref', '') or data.get('flw_ref', '')

        # Extract payment data from tx_ref (primary method)
        tx_data = parse_tx_ref(reference)

        if tx_data:
            phone_number = tx_data['phone_number']
            tier = tx_data['tier']
            weeks = tx_data['weeks']
        else:
            # Fallback: try meta object (may not be present in webhooks)
            meta = data.get('meta', {})
            phone_number = meta.get('phone_number', '') or customer.get('phone_number', '')
            tier = meta.get('tier', 'basic')
            weeks_raw = meta.get('weeks', '1')
            weeks = int(weeks_raw) if isinstance(weeks_raw, str) else weeks_raw

        logger.info(f"Flutterwave payment extracted: phone={phone_number}, tier={tier}, weeks={weeks}, ref={reference}")

        return {
            'phone_number': phone_number,
            'tier': tier,
            'weeks': weeks,
            'provider': 'flutterwave',
            'amount_usd': data.get('amount', 0),
            'customer_email': customer.get('email'),
            'reference': reference,
        }
    except Exception as e:
        logger.error(f"Failed to extract Flutterwave payment data: {e}")
        return None


# =============================================================================
# Idempotency and Tracking
# =============================================================================


def check_already_processed(cursor, provider: str, reference: str) -> bool:
    """
    Check if this payment webhook was already processed.

    Args:
        cursor: Database cursor
        provider: Payment provider (stripe, paystack, flutterwave)
        reference: Payment reference/session ID

    Returns:
        True if already processed (duplicate webhook)
    """
    if not reference:
        return False

    cursor.execute(
        """
        SELECT id FROM subscription_events
        WHERE (stripe_session_id = %s OR paystack_reference = %s OR flutterwave_reference = %s)
        AND status = 'succeeded'
        LIMIT 1
        """,
        (reference, reference, reference)
    )
    return cursor.fetchone() is not None


def record_payment_attempt(
    cursor,
    payment_data: PaymentData,
    status: str,
    failure_reason: str | None = None,
    raw_payload: dict | None = None
) -> None:
    """
    Record payment attempt for tracking and reconciliation.

    Args:
        cursor: Database cursor
        payment_data: Extracted payment information
        status: Attempt status (pending, succeeded, failed)
        failure_reason: Reason for failure if applicable
        raw_payload: Raw webhook payload for debugging
    """
    processed_at = datetime.now(timezone.utc) if status != 'pending' else None

    cursor.execute(
        """
        INSERT INTO payment_attempts (
            phone_number, provider, provider_reference, amount_usd,
            tier, weeks, status, failure_reason, webhook_received_at,
            raw_webhook_payload, processed_at
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s)
        ON CONFLICT (provider, provider_reference) WHERE provider_reference IS NOT NULL
        DO UPDATE SET
            status = EXCLUDED.status,
            failure_reason = EXCLUDED.failure_reason,
            processed_at = EXCLUDED.processed_at,
            updated_at = NOW(),
            retry_count = payment_attempts.retry_count + 1
        """,
        (
            payment_data['phone_number'],
            payment_data['provider'],
            payment_data['reference'],
            payment_data['amount_usd'],
            payment_data['tier'],
            payment_data['weeks'],
            status,
            failure_reason,
            json.dumps(raw_payload) if raw_payload else None,
            processed_at,
        )
    )


def calculate_grace_period(expires_at: datetime) -> datetime:
    """
    Calculate grace period (24 hours after expiration).

    Args:
        expires_at: Subscription expiration timestamp

    Returns:
        Grace period end timestamp
    """
    return expires_at + timedelta(hours=GRACE_PERIOD_HOURS)


# =============================================================================
# User Creation and Subscription Update
# =============================================================================


def create_user_from_payment(
    cursor,
    phone_number: str,
    tier: str,
    customer_email: str | None = None
) -> dict | None:
    """
    Create a new user record from payment data.

    Called when payment succeeds but user doesn't exist yet.
    This handles the case where a new user completes payment
    before their record is created (direct payment without WhatsApp).

    Args:
        cursor: Database cursor
        phone_number: User's phone number in E.164 format
        tier: Subscription tier (basic, pro)
        customer_email: Customer email from payment provider

    Returns:
        Dict with user id and name, or None if creation fails
    """
    try:
        cursor.execute(
            """
            INSERT INTO users (
                phone_number,
                email,
                subscription_status,
                subscription_tier,
                is_active,
                created_at,
                updated_at
            ) VALUES (%s, %s, 'pending', %s, true, NOW(), NOW())
            ON CONFLICT (phone_number) DO NOTHING
            RETURNING id, name
            """,
            (phone_number, customer_email, tier)
        )

        result = cursor.fetchone()
        if result:
            logger.info(f"Created new user from payment: {phone_number}")
            return {'id': result['id'], 'name': result['name']}

        # User may have been created by concurrent request, try to fetch
        cursor.execute(
            "SELECT id, name FROM users WHERE phone_number = %s",
            (phone_number,)
        )
        return cursor.fetchone()

    except Exception as e:
        logger.error(f"Failed to create user from payment: {e}")
        return None


def mark_registration_token_used(cursor, phone_number: str) -> None:
    """
    Mark registration token as used after successful payment.

    Args:
        cursor: Database cursor
        phone_number: User's phone number
    """
    try:
        cursor.execute(
            """
            UPDATE user_registration_tokens
            SET used_at = NOW()
            WHERE phone_number = %s AND used_at IS NULL
            """,
            (phone_number,)
        )
    except Exception as e:
        # Non-critical, just log
        logger.warning(f"Failed to mark registration token as used: {e}")


def update_subscription(payment_data: PaymentData) -> bool:
    """
    Update user subscription in the database with grace period.

    AUTO-CREATES USER IF NOT EXISTS: If payment succeeds but user
    doesn't exist yet, creates the user record automatically.
    This handles new users who complete payment directly.

    Args:
        payment_data: Extracted payment information

    Returns:
        True if update was successful
    """
    conn = None
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            # Calculate expiration and grace period
            expires_at = datetime.now(timezone.utc) + timedelta(weeks=payment_data['weeks'])
            grace_until = calculate_grace_period(expires_at)

            # Update user subscription with grace period
            cursor.execute(
                """
                UPDATE users SET
                    subscription_status = 'active',
                    subscription_tier = %s,
                    subscription_expires_at = %s,
                    subscription_grace_until = %s,
                    updated_at = NOW()
                WHERE phone_number = %s
                RETURNING id, name
                """,
                (payment_data['tier'], expires_at, grace_until, payment_data['phone_number'])
            )

            user = cursor.fetchone()

            # AUTO-CREATE USER IF NOT EXISTS
            if not user:
                logger.info(f"User not found, creating from payment: {payment_data['phone_number']}")
                user = create_user_from_payment(
                    cursor,
                    payment_data['phone_number'],
                    payment_data['tier'],
                    payment_data['customer_email']
                )

                if not user:
                    logger.error(f"Failed to create user: {payment_data['phone_number']}")
                    return False

                # Update the newly created user's subscription
                cursor.execute(
                    """
                    UPDATE users SET
                        subscription_status = 'active',
                        subscription_tier = %s,
                        subscription_expires_at = %s,
                        subscription_grace_until = %s,
                        updated_at = NOW()
                    WHERE id = %s
                    RETURNING id, name
                    """,
                    (payment_data['tier'], expires_at, grace_until, user['id'])
                )
                user = cursor.fetchone()

            # Mark registration token as used (if exists)
            mark_registration_token_used(cursor, payment_data['phone_number'])

            # Record subscription event with all columns
            stripe_ref = payment_data['reference'] if payment_data['provider'] == 'stripe' else None
            paystack_ref = payment_data['reference'] if payment_data['provider'] == 'paystack' else None
            flutterwave_ref = payment_data['reference'] if payment_data['provider'] == 'flutterwave' else None

            cursor.execute(
                """
                INSERT INTO subscription_events (
                    user_id, event_type, provider, amount_usd,
                    stripe_session_id, paystack_reference, flutterwave_reference,
                    metadata, status
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    user['id'],
                    'payment_succeeded',
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
                    'succeeded',
                )
            )

        conn.commit()
        logger.info(
            f"Subscription updated for {payment_data['phone_number']}: "
            f"{payment_data['tier']} x {payment_data['weeks']} weeks "
            f"(expires: {expires_at}, grace until: {grace_until})"
        )
        return True

    except Exception as e:
        logger.exception(f"Failed to update subscription: {e}")
        if conn:
            conn.rollback()
        return False
    finally:
        if conn:
            conn.close()


# =============================================================================
# WhatsApp Notifications
# =============================================================================


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

        import urllib.request
        import base64

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
                logger.info(f"WhatsApp confirmation sent to {phone_number}")
                return True
            else:
                logger.error(f"Failed to send WhatsApp: {response.status}")
                return False

    except Exception as e:
        logger.exception(f"Failed to send WhatsApp confirmation: {e}")
        return False


def queue_whatsapp_notification(payment_data: PaymentData) -> None:
    """
    Queue WhatsApp notification for retry via SQS.

    Args:
        payment_data: Payment data with phone_number, tier, weeks
    """
    try:
        if not WHATSAPP_NOTIFICATION_QUEUE_URL:
            logger.warning("WHATSAPP_NOTIFICATION_QUEUE_URL not configured, cannot queue notification")
            return

        sqs.send_message(
            QueueUrl=WHATSAPP_NOTIFICATION_QUEUE_URL,
            MessageBody=json.dumps({
                'phone_number': payment_data['phone_number'],
                'tier': payment_data['tier'],
                'weeks': payment_data['weeks'],
                'retry_count': 0,
            })
        )
        logger.info(f"Queued WhatsApp notification for retry: {payment_data['phone_number']}")

    except Exception as e:
        logger.error(f"Failed to queue WhatsApp notification: {e}")


# =============================================================================
# Main Handler
# =============================================================================


def handler(event: dict, context) -> dict:
    """
    Lambda handler for payment webhooks with idempotency and tracking.

    Args:
        event: API Gateway event with webhook payload
        context: Lambda context

    Returns:
        API Gateway response
    """
    raw_body = None
    payment_data = None
    conn = None

    try:
        # Extract headers and body
        headers = event.get('headers', {})
        body = event.get('body', '')

        # Handle base64 encoding if needed
        if event.get('isBase64Encoded', False):
            import base64
            body = base64.b64decode(body).decode('utf-8')

        raw_body = body

        # Determine provider based on headers
        stripe_signature = headers.get('stripe-signature') or headers.get('Stripe-Signature', '')
        paystack_signature = headers.get('x-paystack-signature') or headers.get('X-Paystack-Signature', '')
        flutterwave_signature = headers.get('verif-hash') or headers.get('Verif-Hash', '')

        # =====================================================================
        # Provider Detection and Signature Verification
        # =====================================================================

        if stripe_signature:
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
            logger.info("Processing Flutterwave webhook")

            if not verify_flutterwave_signature(flutterwave_signature):
                logger.warning("Invalid Flutterwave signature")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Invalid signature'}),
                }

            webhook_event = json.loads(body)

            # Debug: Log the raw webhook structure
            logger.info(f"Flutterwave webhook payload keys: {list(webhook_event.keys())}")
            logger.info(f"Flutterwave event type: {webhook_event.get('event')} | event.type: {webhook_event.get('event.type')}")

            # Flutterwave uses 'event.type' field (not 'event')
            # Valid event types: CARD_TRANSACTION, charge.completed
            event_type = webhook_event.get('event') or webhook_event.get('event.type')
            valid_events = ['charge.completed', 'CARD_TRANSACTION']
            if event_type not in valid_events:
                logger.info(f"Ignoring Flutterwave event: {event_type}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'received': True}),
                }

            # Flutterwave sends data at root level (not nested in 'data')
            # Check status - can be 'successful' or 'success'
            status = webhook_event.get('status', '').lower()
            if status not in ['successful', 'success']:
                logger.info(f"Ignoring Flutterwave payment with status: {status}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'received': True, 'status': status}),
                }

            payment_data = extract_flutterwave_payment_data(webhook_event)

        else:
            logger.warning("Unknown webhook provider (no signature header)")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing signature header'}),
            }

        # =====================================================================
        # Validate Payment Data
        # =====================================================================

        if not payment_data or not payment_data['phone_number']:
            logger.error("Invalid payment data")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid payment data'}),
            }

        # =====================================================================
        # Idempotency Check
        # =====================================================================

        conn = get_db_connection()
        with conn.cursor() as cursor:
            # Check if already processed (idempotency)
            if check_already_processed(cursor, payment_data['provider'], payment_data['reference']):
                logger.info(f"Duplicate webhook ignored: {payment_data['reference']}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'received': True, 'duplicate': True}),
                }

            # Record payment attempt as pending
            record_payment_attempt(
                cursor, payment_data, 'pending',
                raw_payload=json.loads(raw_body) if raw_body else None
            )
            conn.commit()

        # =====================================================================
        # Process Subscription Update
        # =====================================================================

        if update_subscription(payment_data):
            # Update payment attempt to succeeded
            with conn.cursor() as cursor:
                record_payment_attempt(cursor, payment_data, 'succeeded')
                conn.commit()

            # Send WhatsApp confirmation (queue for retry if fails)
            whatsapp_sent = send_whatsapp_confirmation(
                payment_data['phone_number'],
                payment_data['tier'],
                payment_data['weeks'],
            )

            if not whatsapp_sent:
                # Queue for retry instead of silently failing
                queue_whatsapp_notification(payment_data)

            return {
                'statusCode': 200,
                'body': json.dumps({'received': True, 'subscription_updated': True}),
            }
        else:
            # Update payment attempt to failed
            with conn.cursor() as cursor:
                record_payment_attempt(
                    cursor, payment_data, 'failed',
                    failure_reason='Database update failed - user may not exist'
                )
                conn.commit()

            # Return 200 to prevent provider retries (we've recorded the attempt)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'received': True,
                    'error': 'Subscription update failed',
                    'requires_manual_review': True,
                }),
            }

    except Exception as e:
        logger.exception(f"Error processing webhook: {e}")

        # Try to record the failure for debugging
        if payment_data and conn:
            try:
                with conn.cursor() as cursor:
                    record_payment_attempt(
                        cursor, payment_data, 'failed',
                        failure_reason=str(e),
                        raw_payload=json.loads(raw_body) if raw_body else None
                    )
                    conn.commit()
            except Exception:
                pass  # Don't fail on failure tracking

        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'}),
        }

    finally:
        if conn:
            conn.close()
