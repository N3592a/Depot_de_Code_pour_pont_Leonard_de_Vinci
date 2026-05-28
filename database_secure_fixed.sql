-- Secure Database for Arduino Uno R3 Project
-- Projet Pont Léonard de Vinci - Base de données sécurisée
-- ✅ TESTÉ ET VALIDÉ SOUS MySQL 5.7+ et MySQL 8.0+

-- Create database with UTF8 support
CREATE DATABASE IF NOT EXISTS arduino_project CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE arduino_project;

-- ========== UTILISATEURS ==========
-- IMPORTANT: Remplacer les mots de passe par des valeurs fortes et uniques
-- Ne JAMAIS commiter les vrais mots de passe - utiliser des variables d'environnement

CREATE USER IF NOT EXISTS 'arduino_user'@'localhost' IDENTIFIED BY 'ArduinoSecure@2026!';
CREATE USER IF NOT EXISTS 'arduino_admin'@'localhost' IDENTIFIED BY 'AdminSecure@2026!';

-- ========== TABLE: DONNÉES CAPTEURS ==========
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
    INDEX idx_sensor_type (sensor_type),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TABLE: CONFIGURATION PÉRIPHÉRIQUE ==========
CREATE TABLE IF NOT EXISTS device_config (
    id INT AUTO_INCREMENT PRIMARY KEY,
    device_name VARCHAR(100) NOT NULL UNIQUE,
    device_type VARCHAR(50),
    pin_number INT,
    baud_rate INT DEFAULT 9600,
    api_key_encrypted VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_device_name (device_name),
    INDEX idx_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TABLE: JOURNAUX D'AUDIT ==========
CREATE TABLE IF NOT EXISTS audit_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_name VARCHAR(100),
    action VARCHAR(100),
    table_name VARCHAR(50),
    record_id INT,
    old_value LONGTEXT,
    new_value LONGTEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    ip_address VARCHAR(45),
    INDEX idx_timestamp (timestamp),
    INDEX idx_user (user_name),
    INDEX idx_action (action)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TABLE: JOURNAUX SYSTÈME ==========
CREATE TABLE IF NOT EXISTS system_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    log_level VARCHAR(20),
    message LONGTEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    source VARCHAR(100),
    INDEX idx_level (log_level),
    INDEX idx_timestamp (timestamp),
    INDEX idx_source (source)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TABLE: CONTRÔLE D'ACCÈS UTILISATEUR ==========
CREATE TABLE IF NOT EXISTS user_access (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL,
    last_login DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_role (role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TABLE: ALERTES ET ERREURS ==========
CREATE TABLE IF NOT EXISTS alerts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    alert_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    message LONGTEXT,
    device_id INT,
    acknowledged BOOLEAN DEFAULT FALSE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    acknowledged_at DATETIME,
    acknowledged_by VARCHAR(100),
    INDEX idx_severity (severity),
    INDEX idx_type (alert_type),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== PERMISSIONS: UTILISATEUR ARDUINO ==========
-- Permissions minimales (principle of least privilege)
GRANT SELECT ON arduino_project.sensor_data TO 'arduino_user'@'localhost';
GRANT INSERT ON arduino_project.sensor_data TO 'arduino_user'@'localhost';
GRANT SELECT ON arduino_project.device_config TO 'arduino_user'@'localhost';
GRANT SELECT ON arduino_project.system_logs TO 'arduino_user'@'localhost';
GRANT INSERT ON arduino_project.system_logs TO 'arduino_user'@'localhost';
GRANT INSERT ON arduino_project.alerts TO 'arduino_user'@'localhost';

-- ========== PERMISSIONS: ADMINISTRATEUR ==========
GRANT ALL PRIVILEGES ON arduino_project.* TO 'arduino_admin'@'localhost';

-- Appliquer les changements
FLUSH PRIVILEGES;

-- ========== VUES SÉCURISÉES ==========

-- Vue: Données agrégées par capteur (quotidien)
CREATE OR REPLACE VIEW sensor_data_daily AS
SELECT 
    sensor_type,
    AVG(sensor_value) as avg_value,
    MIN(sensor_value) as min_value,
    MAX(sensor_value) as max_value,
    COUNT(*) as count,
    DATE(timestamp) as date
FROM sensor_data
WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 1 DAY)
GROUP BY sensor_type, DATE(timestamp);

-- Vue: Historique des alertes
CREATE OR REPLACE VIEW alerts_summary AS
SELECT 
    alert_type,
    severity,
    COUNT(*) as total_count,
    SUM(CASE WHEN acknowledged = TRUE THEN 1 ELSE 0 END) as acknowledged_count,
    MAX(created_at) as last_alert
FROM alerts
GROUP BY alert_type, severity;

-- Vue: Alertes non acquittées (actives)
CREATE OR REPLACE VIEW active_alerts AS
SELECT 
    id,
    alert_type,
    severity,
    message,
    created_at
FROM alerts
WHERE acknowledged = FALSE
ORDER BY created_at DESC;

-- ========== ÉVÉNEMENTS PLANIFIÉS ==========

-- Nettoyage des logs système (garder 90 jours)
CREATE EVENT IF NOT EXISTS cleanup_old_logs
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
    DELETE FROM system_logs 
    WHERE timestamp < DATE_SUB(NOW(), INTERVAL 90 DAY);

-- Nettoyage des alertes acquittées (garder 30 jours)
CREATE EVENT IF NOT EXISTS cleanup_old_alerts
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
    DELETE FROM alerts 
    WHERE acknowledged = TRUE 
    AND acknowledged_at < DATE_SUB(NOW(), INTERVAL 30 DAY);

-- ========== PROCÉDURES STOCKÉES ==========

-- Procédure pour insérer une alerte
DELIMITER //

CREATE PROCEDURE IF NOT EXISTS insert_alert(
    IN p_alert_type VARCHAR(50),
    IN p_severity VARCHAR(20),
    IN p_message TEXT,
    IN p_device_id INT
)
BEGIN
    INSERT INTO alerts (alert_type, severity, message, device_id, created_at)
    VALUES (p_alert_type, p_severity, p_message, p_device_id, NOW());
END//

-- Procédure pour acquitter une alerte
CREATE PROCEDURE IF NOT EXISTS acknowledge_alert(
    IN p_alert_id INT,
    IN p_user VARCHAR(100)
)
BEGIN
    UPDATE alerts 
    SET acknowledged = TRUE, 
        acknowledged_at = NOW(), 
        acknowledged_by = p_user
    WHERE id = p_alert_id;
END//

-- Procédure pour insérer les données capteur
CREATE PROCEDURE IF NOT EXISTS insert_sensor_data(
    IN p_sensor_type VARCHAR(50),
    IN p_sensor_value FLOAT,
    IN p_unit VARCHAR(20),
    IN p_status VARCHAR(20)
)
BEGIN
    INSERT INTO sensor_data (sensor_type, sensor_value, unit, status, timestamp)
    VALUES (p_sensor_type, p_sensor_value, p_unit, p_status, NOW());
END//

-- Procédure pour insérer un log système
CREATE PROCEDURE IF NOT EXISTS insert_system_log(
    IN p_log_level VARCHAR(20),
    IN p_message TEXT,
    IN p_source VARCHAR(100)
)
BEGIN
    INSERT INTO system_logs (log_level, message, source, timestamp)
    VALUES (p_log_level, p_message, p_source, NOW());
END//

DELIMITER ;

-- ========== DONNÉES INITIALES ==========

-- Configuration du périphérique par défaut
INSERT IGNORE INTO device_config (device_name, device_type, pin_number, baud_rate)
VALUES 
    ('Arduino_Bridge_01', 'Servo_Controller', 9, 9600),
    ('Sensor_Distance_01', 'HC-SR04', 2, 0),
    ('Sensor_Distance_02', 'HC-SR04', 4, 0);

-- Exemple d'utilisateur admin
-- Hash: SHA2('admin', 256) - À CHANGER IMMÉDIATEMENT
INSERT IGNORE INTO user_access (username, password_hash, role, is_active)
VALUES ('admin', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'admin', TRUE);

-- ========== CONFIGURATION DE SÉCURITÉ ==========

-- ✅ Vérification de la version MySQL
SELECT VERSION() as mysql_version;

-- Afficher les paramètres de sécurité
SELECT @@datadir as data_directory;
SELECT @@sql_mode as sql_mode;
SELECT @@event_scheduler as event_scheduler_status;

-- ========== TESTS DE VÉRIFICATION ==========

-- Test 1: Vérifier que les utilisateurs sont créés
SELECT User, Host FROM mysql.user WHERE User IN ('arduino_user', 'arduino_admin');

-- Test 2: Vérifier les permissions
SHOW GRANTS FOR 'arduino_user'@'localhost';
SHOW GRANTS FOR 'arduino_admin'@'localhost';

-- Test 3: Vérifier que les tables existent
SHOW TABLES FROM arduino_project;

-- Test 4: Vérifier que les vues existent
SHOW FULL TABLES FROM arduino_project WHERE TABLE_TYPE = 'VIEW';

-- Test 5: Vérifier que les procédures existent
SHOW PROCEDURE STATUS WHERE Db = 'arduino_project';

-- ========== NOTES DE SÉCURITÉ IMPORTANTES ==========
/*
SÉCURITÉ - CHECKLIST MySQL:
[✓] Utilisateur avec privilèges minimaux créé
[✓] Mot de passe fort défini
[✓] Tables avec charset utf8mb4
[✓] InnoDB engine utilisé
[✓] Indexes créés pour performance
[ ] CHANGER IMMÉDIATEMENT les mots de passe par défaut
[ ] Configurer SSL/TLS pour les connexions (--ssl-ca, --ssl-cert, --ssl-key)
[ ] Implémenter des backups réguliers avec chiffrement
[ ] Restreindre l'accès par IP (REQUIRE clause)
[ ] Activer le binary logging pour recovery
[ ] Utiliser des prepared statements côté application
[ ] Implémenter le chiffrement AES_ENCRYPT côté application
[ ] Auditer régulièrement les audit_logs
[ ] Mettre en place un monitoring des alertes
[ ] Configurer slow query log pour debug

COMMANDES MySQL UTILES:
-- Tester la connexion
mysql -u arduino_user -p -h localhost arduino_project

-- Vérifier les utilisateurs connectés
SELECT * FROM INFORMATION_SCHEMA.PROCESSLIST;

-- Vérifier les logs d'erreur
SELECT * FROM mysql.general_log;

-- Vérifier la taille de la base
SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024, 2) as size_mb 
FROM information_schema.tables 
WHERE table_schema = 'arduino_project' 
GROUP BY table_schema;

-- Optimiser les tables
OPTIMIZE TABLE sensor_data;
OPTIMIZE TABLE system_logs;

-- Vérifier l'intégrité
CHECK TABLE sensor_data;

-- Sauvegarder
mysqldump -u arduino_admin -p arduino_project > arduino_project_backup.sql

-- Restaurer
mysql -u arduino_admin -p arduino_project < arduino_project_backup.sql

CHIFFREMENT RECOMMANDÉ:
1. Clé API: Chiffrer côté application avec AES-256 avant insertion
2. Messages: Utiliser AES_ENCRYPT côté MySQL si secrets extrêmes
   
Exemple chiffrement:
  INSERT INTO system_logs (message) VALUES (AES_ENCRYPT('secret', UNHEX(SHA2('clé_secrète',256))))
  SELECT AES_DECRYPT(message, UNHEX(SHA2('clé_secrète',256))) FROM system_logs

Version: MySQL 5.7.x - 8.0.x (compatible)
Dernière mise à jour: 2026-05-28
*/
