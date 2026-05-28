-- Secure Database for Arduino Uno R3 Project
-- Projet Pont Léonard de Vinci - Base de données sécurisée

-- Create database with encryption support
CREATE DATABASE IF NOT EXISTS arduino_project CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE arduino_project;

-- Create dedicated database user with limited privileges
-- IMPORTANT: Replace 'password' with a strong password
CREATE USER IF NOT EXISTS 'arduino_user'@'localhost' IDENTIFIED BY 'ArduinoSecure@2026!';

-- Table for sensor data with security considerations
CREATE TABLE IF NOT EXISTS sensor_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    sensor_type VARCHAR(50) NOT NULL,
    sensor_value FLOAT NOT NULL,
    unit VARCHAR(20),
    status VARCHAR(20) DEFAULT 'active',
    hash_checksum VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_timestamp (timestamp),
    INDEX idx_sensor_type (sensor_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table for device configuration with encryption fields
CREATE TABLE IF NOT EXISTS device_config (
    id INT AUTO_INCREMENT PRIMARY KEY,
    device_name VARCHAR(100) NOT NULL,
    device_type VARCHAR(50),
    pin_number INT,
    baud_rate INT DEFAULT 9600,
    api_key VARCHAR(255) ENCRYPTED WITH KEY 'arduino_key',
    status VARCHAR(20) DEFAULT 'active',
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_device_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table for audit logs (security tracking)
CREATE TABLE IF NOT EXISTS audit_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_name VARCHAR(100),
    action VARCHAR(100),
    table_name VARCHAR(50),
    record_id INT,
    old_value TEXT,
    new_value TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    ip_address VARCHAR(45),
    INDEX idx_timestamp (timestamp),
    INDEX idx_user (user_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table for system logs with encryption
CREATE TABLE IF NOT EXISTS system_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    log_level VARCHAR(20),
    message TEXT ENCRYPTED WITH KEY 'arduino_key',
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    source VARCHAR(100),
    INDEX idx_level (log_level),
    INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table for user access control
CREATE TABLE IF NOT EXISTS user_access (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL,
    last_login DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Grant privileges to arduino_user (read-only by default)
GRANT SELECT ON arduino_project.sensor_data TO 'arduino_user'@'localhost';
GRANT SELECT ON arduino_project.device_config TO 'arduino_user'@'localhost';
GRANT INSERT ON arduino_project.sensor_data TO 'arduino_user'@'localhost';
GRANT SELECT ON arduino_project.system_logs TO 'arduino_user'@'localhost';

-- Create admin user for management
CREATE USER IF NOT EXISTS 'arduino_admin'@'localhost' IDENTIFIED BY 'AdminSecure@2026!';
GRANT ALL PRIVILEGES ON arduino_project.* TO 'arduino_admin'@'localhost';

-- Apply privilege changes
FLUSH PRIVILEGES;

-- Enable event for automatic log cleanup (keeps last 90 days)
CREATE EVENT IF NOT EXISTS cleanup_old_logs
ON SCHEDULE EVERY 1 DAY
DO
    DELETE FROM system_logs WHERE timestamp < DATE_SUB(NOW(), INTERVAL 90 DAY);

-- View for aggregated sensor data (secure access)
CREATE VIEW sensor_data_view AS
SELECT 
    sensor_type,
    AVG(sensor_value) as avg_value,
    MIN(sensor_value) as min_value,
    MAX(sensor_value) as max_value,
    COUNT(*) as count,
    DATE(timestamp) as date
FROM sensor_data
GROUP BY sensor_type, DATE(timestamp);

-- Enable query logging for audit purposes
SET GLOBAL log_queries_not_using_indexes = ON;
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;

-- Security notes:
-- 1. Replace default passwords with strong, unique passwords
-- 2. Use SSL/TLS for database connections
-- 3. Enable binary logging for backup and recovery
-- 4. Implement regular backups with encryption
-- 5. Use prepared statements in application code to prevent SQL injection
-- 6. Enable audit logging for compliance tracking
-- 7. Restrict database access by IP address
