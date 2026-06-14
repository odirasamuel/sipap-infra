# Database Migration Container
# Runs PostgreSQL migrations for SIPAP

FROM postgres:15-alpine

# Install AWS CLI for secrets access
RUN apk add --no-cache aws-cli jq bash dos2unix

# Copy SQL migration files
COPY schema.sql /migrations/schema.sql
COPY seed_data.sql /migrations/seed_data.sql

# Copy migration script and fix line endings
COPY run-migration.sh /run-migration.sh
RUN dos2unix /run-migration.sh && chmod +x /run-migration.sh

# Set working directory
WORKDIR /migrations

# Entry point
ENTRYPOINT ["/bin/bash", "/run-migration.sh"]
