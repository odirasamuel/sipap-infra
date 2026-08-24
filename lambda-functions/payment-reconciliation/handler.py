"""
Payment Reconciliation Lambda

Runs on schedule (e.g., every 6 hours) to detect and fix orphaned payments.
An orphaned payment is one where:
- We received the webhook and recorded a payment_attempt
- But the subscription was never activated (payment_attempt stuck in 'pending')

This Lambda:
1. Finds pending payment_attempts older than 1 hour
2. Queries the payment provider API to verify actual status
3. If confirmed successful, activates the subscription
4. If confirmed failed, marks the attempt as failed

DISABLED by default - Enable only after payment provider is live.

Environment Variables:
    POSTGRES_SECRET_ARN: ARN of Secrets Manager secret with DB credentials
    FLUTTERWAVE_SECRET_KEY_ARN: ARN of Secrets Manager secret with Flutterwave key
    RECONCILIATION_ENABLED: Set to 'true' to enable reconciliation
"""

import json
import logging
import os
import urllib.request
from datetime import datetime, timedelta, timezone

import boto3
import psycopg2
from psycopg2.extras import RealDictCursor

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secrets_manager = boto3.client('secretsmanager')
sns = boto3.client('sns')

# Environment variables
POSTGRES_SECRET_ARN = os.environ.get('POSTGRES_SECRET_ARN', '')
FLUTTERWAVE_SECRET_KEY_ARN = os.environ.get('FLUTTERWAVE_SECRET_KEY_ARN', '')
RECONCILIATION_ENABLED = os.environ.get('RECONCILIATION_ENABLED', 'false').lower() == 'true'
ALERT_TOPIC_ARN = os.environ.get('ALERT_TOPIC_ARN', '')

# Cache for secrets (reused across invocations)
_secrets_cache: dict = {}

# Grace period duration (24 hours after subscription expiration)
GRACE_PERIOD_HOURS = 24


def get_secret(secret_arn: str) -> dict:
    """Retrieve secret from Secrets Manager with caching."""
    if secret_arn in _secrets_cache:
        return _secrets_cache[secret_arn]

    response = secrets_manager.get_secret_value(SecretId=secret_arn)
    secret = json.loads(response['SecretString'])
    _secrets_cache[secret_arn] = secret
    return secret


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


def verify_flutterwave_payment(reference: str) -> str:
    """
    Verify payment status with Flutterwave API.

    Args:
        reference: Transaction reference (tx_ref)

    Returns:
        'succeeded', 'failed', 'pending', or 'unknown'
    """
    try:
        if not FLUTTERWAVE_SECRET_KEY_ARN:
            logger.warning("FLUTTERWAVE_SECRET_KEY_ARN not configured")
            return 'unknown'

        secret = get_secret(FLUTTERWAVE_SECRET_KEY_ARN)
        secret_key = secret.get('secret_key', '')

        if not secret_key:
            logger.warning("Flutterwave secret_key not found in secret")
            return 'unknown'

        url = f"https://api.flutterwave.com/v3/transactions/verify_by_reference?tx_ref={reference}"

        request = urllib.request.Request(url)
        request.add_header('Authorization', f'Bearer {secret_key}')
        request.add_header('Content-Type', 'application/json')

        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.loads(response.read().decode('utf-8'))

            if data.get('status') == 'success':
                payment_status = data.get('data', {}).get('status', '')
                if payment_status == 'successful':
                    return 'succeeded'
                elif payment_status == 'failed':
                    return 'failed'
                return 'pending'

            return 'unknown'

    except urllib.error.HTTPError as e:
        logger.error(f"Flutterwave API error: {e.code} - {e.reason}")
        return 'unknown'
    except Exception as e:
        logger.error(f"Error verifying Flutterwave payment: {e}")
        return 'unknown'


def verify_payment_with_provider(provider: str, reference: str) -> str:
    """
    Query payment provider API to verify actual payment status.

    Args:
        provider: Payment provider (stripe, paystack, flutterwave)
        reference: Payment reference/session ID

    Returns:
        'succeeded', 'failed', 'pending', or 'unknown'
    """
    if provider == 'flutterwave':
        return verify_flutterwave_payment(reference)
    # Add other providers as needed (stripe, paystack)
    # For now, return unknown for unsupported providers
    return 'unknown'


def activate_subscription(cursor, payment: dict) -> bool:
    """
    Activate subscription for a reconciled payment.

    Args:
        cursor: Database cursor
        payment: Payment attempt record

    Returns:
        True if activation was successful
    """
    try:
        # Calculate expiration and grace period
        expires_at = datetime.now(timezone.utc) + timedelta(weeks=payment['weeks'])
        grace_until = expires_at + timedelta(hours=GRACE_PERIOD_HOURS)

        # Update user subscription
        cursor.execute(
            """
            UPDATE users SET
                subscription_status = 'active',
                subscription_tier = %s,
                subscription_expires_at = %s,
                subscription_grace_until = %s,
                updated_at = NOW()
            WHERE phone_number = %s
            RETURNING id
            """,
            (payment['tier'], expires_at, grace_until, payment['phone_number'])
        )

        result = cursor.fetchone()
        if not result:
            logger.error(f"User not found for reconciliation: {payment['phone_number']}")
            return False

        user_id = result['id']

        # Record subscription event
        cursor.execute(
            """
            INSERT INTO subscription_events (
                user_id, event_type, provider, amount_usd,
                flutterwave_reference, metadata, status
            ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (
                user_id,
                'payment_reconciled',
                payment['provider'],
                payment['amount_usd'],
                payment['provider_reference'] if payment['provider'] == 'flutterwave' else None,
                json.dumps({
                    'tier': payment['tier'],
                    'weeks': payment['weeks'],
                    'reconciled_at': datetime.now(timezone.utc).isoformat(),
                }),
                'succeeded',
            )
        )

        # Update payment attempt to succeeded
        cursor.execute(
            """
            UPDATE payment_attempts SET
                status = 'succeeded',
                processed_at = NOW(),
                updated_at = NOW()
            WHERE id = %s
            """,
            (payment['id'],)
        )

        logger.info(f"Reconciled payment for {payment['phone_number']}: {payment['provider_reference']}")
        return True

    except Exception as e:
        logger.error(f"Error activating subscription for reconciliation: {e}")
        return False


def send_alert(message: str) -> None:
    """Send alert via SNS (if configured)."""
    if not ALERT_TOPIC_ARN:
        logger.info(f"Alert (no topic configured): {message}")
        return

    try:
        sns.publish(
            TopicArn=ALERT_TOPIC_ARN,
            Subject="Valo Payment Reconciliation Alert",
            Message=message,
        )
        logger.info(f"Alert sent: {message}")
    except Exception as e:
        logger.error(f"Failed to send alert: {e}")


def handler(event: dict, context) -> dict:
    """
    Lambda handler for payment reconciliation.

    Finds and reconciles orphaned payments (pending > 1 hour).

    Args:
        event: CloudWatch Events / EventBridge event
        context: Lambda context

    Returns:
        Reconciliation results
    """
    # Check if reconciliation is enabled
    if not RECONCILIATION_ENABLED:
        logger.info("Payment reconciliation is DISABLED")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Reconciliation disabled',
                'enabled': False,
            })
        }

    logger.info("Starting payment reconciliation")

    conn = None
    try:
        conn = get_db_connection()

        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            # Find pending payments older than 1 hour (should have completed by now)
            # But not older than 24 hours (too old to reconcile safely)
            cursor.execute(
                """
                SELECT * FROM payment_attempts
                WHERE status = 'pending'
                AND created_at < NOW() - INTERVAL '1 hour'
                AND created_at > NOW() - INTERVAL '24 hours'
                ORDER BY created_at ASC
                LIMIT 50
                """
            )

            pending_payments = cursor.fetchall()
            logger.info(f"Found {len(pending_payments)} pending payments to reconcile")

            reconciled = 0
            failed = 0
            skipped = 0

            for payment in pending_payments:
                try:
                    # Query provider for actual status
                    actual_status = verify_payment_with_provider(
                        payment['provider'],
                        payment['provider_reference']
                    )

                    if actual_status == 'succeeded':
                        # Payment succeeded but we missed it - activate subscription
                        if activate_subscription(cursor, payment):
                            reconciled += 1
                            logger.info(f"Reconciled: {payment['provider_reference']}")
                        else:
                            failed += 1

                    elif actual_status == 'failed':
                        # Mark as failed
                        cursor.execute(
                            """
                            UPDATE payment_attempts SET
                                status = 'failed',
                                failure_reason = 'Provider confirmed failure during reconciliation',
                                updated_at = NOW()
                            WHERE id = %s
                            """,
                            (payment['id'],)
                        )
                        failed += 1
                        logger.info(f"Marked as failed: {payment['provider_reference']}")

                    else:
                        # Still pending or unknown - skip for now
                        skipped += 1
                        logger.info(f"Skipped (status={actual_status}): {payment['provider_reference']}")

                except Exception as e:
                    logger.error(f"Error reconciling payment {payment['id']}: {e}")
                    skipped += 1

            conn.commit()

            # Send alert if significant reconciliation occurred
            if reconciled > 0:
                send_alert(f"Reconciled {reconciled} orphaned payments")

            logger.info(
                f"Reconciliation complete: "
                f"{reconciled} reconciled, {failed} failed, {skipped} skipped"
            )

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'checked': len(pending_payments),
                    'reconciled': reconciled,
                    'failed': failed,
                    'skipped': skipped,
                })
            }

    except Exception as e:
        logger.exception(f"Error during reconciliation: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

    finally:
        if conn:
            conn.close()
