-- SIPAP Database Schema
-- PostgreSQL 15.4 (Aurora Serverless v2)

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    whatsapp_id VARCHAR(50) UNIQUE,
    subscription_status VARCHAR(20) DEFAULT 'trial',
    subscription_tier VARCHAR(20) DEFAULT 'basic',
    subscription_expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    stripe_customer_id VARCHAR(100),
    preferences JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_users_phone_number ON users(phone_number);
CREATE INDEX idx_users_subscription_status ON users(subscription_status);

-- Sports table
CREATE TABLE sports (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Leagues table
CREATE TABLE leagues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sport_id INTEGER REFERENCES sports(id),
    external_id VARCHAR(100),
    name VARCHAR(200) NOT NULL,
    country VARCHAR(100),
    tier INTEGER,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (sport_id, external_id)
);

CREATE INDEX idx_leagues_sport_id ON leagues(sport_id);

-- Teams table
CREATE TABLE teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sport_id INTEGER REFERENCES sports(id),
    league_id UUID REFERENCES leagues(id),
    external_id VARCHAR(100),
    name VARCHAR(200) NOT NULL,
    short_name VARCHAR(50),
    country VARCHAR(100),
    logo_url VARCHAR(500),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (sport_id, external_id)
);

CREATE INDEX idx_teams_sport_id ON teams(sport_id);

-- Matches table
CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sport_id INTEGER REFERENCES sports(id),
    league_id UUID REFERENCES leagues(id),
    external_id VARCHAR(100),
    home_team_id UUID REFERENCES teams(id),
    away_team_id UUID REFERENCES teams(id),
    scheduled_at TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'scheduled',
    home_score INTEGER,
    away_score INTEGER,
    venue VARCHAR(200),
    weather JSONB,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (sport_id, external_id)
);

CREATE INDEX idx_matches_scheduled_at ON matches(scheduled_at);
CREATE INDEX idx_matches_status ON matches(status);

-- Predictions table
CREATE TABLE predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID REFERENCES matches(id),
    user_id UUID REFERENCES users(id),
    market VARCHAR(50) NOT NULL,
    outcome VARCHAR(50) NOT NULL,
    probability DECIMAL(5,4) NOT NULL,
    confidence_score DECIMAL(5,4) NOT NULL,
    ensemble_method VARCHAR(50),
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP
);

CREATE INDEX idx_predictions_match_id ON predictions(match_id);
CREATE INDEX idx_predictions_confidence_score ON predictions(confidence_score DESC);

-- Prediction Evidence table
CREATE TABLE prediction_evidence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prediction_id UUID REFERENCES predictions(id),
    mcp_server VARCHAR(100) NOT NULL,
    evidence_type VARCHAR(50),
    evidence_data JSONB NOT NULL,
    weight DECIMAL(5,4),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_prediction_evidence_prediction_id ON prediction_evidence(prediction_id);

-- Agent Contributions table
CREATE TABLE agent_contributions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prediction_id UUID REFERENCES predictions(id),
    agent_name VARCHAR(100) NOT NULL,
    agent_probability DECIMAL(5,4) NOT NULL,
    agent_confidence DECIMAL(5,4) NOT NULL,
    reasoning JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_agent_contributions_prediction_id ON agent_contributions(prediction_id);

-- User Feedback table
CREATE TABLE user_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prediction_id UUID REFERENCES predictions(id),
    user_id UUID REFERENCES users(id),
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    feedback_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_feedback_prediction_id ON user_feedback(prediction_id);

-- Subscription Events table
CREATE TABLE subscription_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    event_type VARCHAR(50) NOT NULL,
    stripe_event_id VARCHAR(100),
    event_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_subscription_events_user_id ON subscription_events(user_id);
CREATE INDEX idx_subscription_events_created_at ON subscription_events(created_at);
