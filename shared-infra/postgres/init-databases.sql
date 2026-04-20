-- =============================================================================
-- Shared PostgreSQL — Initial Database Setup
-- =============================================================================
-- This script runs automatically on first container start (empty volume).
-- Add one CREATE DATABASE per app that uses shared postgres.
-- =============================================================================

-- Daytona
CREATE DATABASE daytona;

-- Add more app databases below as needed:
-- CREATE DATABASE langfuse;
-- CREATE DATABASE myapp;
