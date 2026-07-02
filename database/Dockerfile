# Database Migration Container
# Runs PostgreSQL migrations for SIPAP using Alembic
#
# Note: Using Debian-based image instead of Alpine to avoid Python version conflicts
# Debian allows us to use Python 3.12 with AWS CLI and psycopg2-binary

FROM postgres:15-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    jq \
    dos2unix \
    python3 \
    python3-pip \
    python3-dev \
    libpq-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 (standalone binary, doesn't interfere with Python)
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Install Python packages for Alembic
# Debian doesn't require --break-system-packages flag
RUN pip3 install --no-cache-dir \
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
