"""Alembic Environment Configuration for SIPAP

This file is executed when running Alembic migrations. It sets up the
database connection and migration context.

Environment Variables Required:
    DB_HOST: Database hostname
    DB_PORT: Database port (default: 5432)
    DB_NAME: Database name
    DB_USER: Database username
    DB_PASSWORD: Database password (retrieved from AWS Secrets Manager)
"""

from logging.config import fileConfig
import os

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context

# Alembic Config object
config = context.config

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Metadata object (not used for schema introspection, but required by Alembic)
# We're using SQL-based migrations, not model-based
target_metadata = None


def get_database_url() -> str:
    """Construct database URL from environment variables.

    Returns:
        PostgreSQL connection string

    Raises:
        ValueError: If required environment variables are missing
    """
    db_host = os.getenv('DB_HOST')
    db_port = os.getenv('DB_PORT', '5432')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')

    if not all([db_host, db_name, db_user, db_password]):
        raise ValueError(
            "Missing required environment variables. "
            "Required: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD"
        )

    return f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.

    This configures the context with just a URL and not an Engine,
    though an Engine is acceptable here as well. By skipping the Engine
    creation we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.
    """
    url = get_database_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode.

    In this scenario we need to create an Engine and associate a
    connection with the context.
    """
    # Override sqlalchemy.url with our database URL from environment
    configuration = config.get_section(config.config_ini_section)
    configuration['sqlalchemy.url'] = get_database_url()

    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,  # Don't pool connections in migration container
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


# Run migrations in online mode (connected to database)
if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
