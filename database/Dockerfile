# Database Migration Container
# Runs PostgreSQL migrations for SIPAP using Alembic

FROM postgres:15-alpine

# Install system dependencies
RUN apk add --no-cache \
    aws-cli \
    jq \
    bash \
    dos2unix \
    python3 \
    py3-pip \
    postgresql-dev \
    gcc \
    musl-dev \
    python3-dev

# Install Python packages for Alembic
# Note: --break-system-packages is safe in Docker containers (PEP 668)
RUN pip3 install --no-cache-dir --break-system-packages \
    alembic==1.13.1 \
    psycopg2-binary==2.9.9 \
    SQLAlchemy==2.0.25

# Create migrations directory structure
WORKDIR /migrations

# Copy Alembic configuration
COPY alembic.ini /migrations/alembic.ini
COPY alembic/ /migrations/alembic/

# Copy legacy SQL files (for reference and baseline migration)
COPY schema.sql /migrations/schema.sql
COPY seed_data.sql /migrations/seed_data.sql

# Copy migration script and fix line endings
COPY run-migration.sh /run-migration.sh
RUN dos2unix /run-migration.sh && chmod +x /run-migration.sh

# Entry point
ENTRYPOINT ["/bin/bash", "/run-migration.sh"]
