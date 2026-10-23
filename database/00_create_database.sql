-- ============================================================
-- File: database/00_create_database.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Create the target MySQL database for the build.
--
-- Notes:
--   - {{TARGET_DB}} is replaced by the Python build script
--     before execution.
--   - The build script is responsible for checking whether the
--     database already exists and whether recreation is allowed.
-- ============================================================

CREATE DATABASE `{{TARGET_DB}}`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;