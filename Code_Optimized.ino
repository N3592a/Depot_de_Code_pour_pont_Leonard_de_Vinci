#include <Servo.h>

// ========== BROCHES ==========
const int trigPin1 = 2;
const int echoPin1 = 3;
const int trigPin2 = 4;
const int echoPin2 = 5;
const int ledPin = 6;
const int servoPin = 9;

// ========== SEUILS ET TIMINGS ==========
const float SEUIL_DETECTION = 25.0;
const float SEUIL_PRESENCE = 15.0;
const unsigned long TIMEOUT_OUVERTURE = 30000;  // 30 secondes
const unsigned long DEBOUNCE_DELAY = 150;       // Anti-rebond: 150ms
const unsigned long SECURITE_RECOVERY_TIME = 60000; // 1 minute avant retry
const unsigned long LOOP_DELAY = 250;           // Délai de boucle optimisé

// ========== ÉTATS ==========
enum EtatPont { FERME, OUVERT_ATTENTE_PASSAGE, EN_PASSAGE, SECURITE, RECUPERATION };
EtatPont etat = FERME;
EtatPont etatPrecedent = FERME;

// ========== TIMING ==========
unsigned long tEtat = 0;              // Temps d'entrée dans l'état
unsigned long lastStateChange = 0;    // Anti-rebond
unsigned long tSecuriteStart = 0;     // Début de la période SECURITE

// ========== SERVO ==========
Servo pontServo;

// ========== LOGGING ==========
enum LogLevel { LOG_INFO, LOG_WARN, LOG_ERROR, LOG_DEBUG };

void logMessage(LogLevel level, const char* msg) {
  Serial.print("[");
  Serial.print(millis());
  Serial.print("] [");
  
  switch(level) {
    case LOG_DEBUG:
      Serial.print("DEBUG");
      break;
    case LOG_INFO:
      Serial.print("INFO");
      break;
    case LOG_WARN:
      Serial.print("WARN");
      break;
    case LOG_ERROR:
      Serial.print("ERROR");
      break;
  }
  
  Serial.print("] ");
  Serial.println(msg);
}

// ========== CAPTEURS ==========
float mesurerDistanceCM(int trigPin, int echoPin) {
  const int N = 5;  // Plus de mesures pour meilleure précision
  float val = 0;
  int validMeasures = 0;

  for (int i = 0; i < N; i++) {
    digitalWrite(trigPin, LOW);
    delayMicroseconds(2);
    digitalWrite(trigPin, HIGH);
    delayMicroseconds(10);
    digitalWrite(trigPin, LOW);

    long duration = pulseIn(echoPin, HIGH, 25000);
    
    // Vérifier que la mesure est valide (plage 2cm à 400cm)
    if (duration > 0) {
      float d = (duration * 0.034) / 2.0;
      if (d >= 2.0 && d <= 400.0) {
        val += d;
        validMeasures++;
      }
    }
    
    delay(15);
  }

  // Retourner la moyenne si au moins 2 mesures valides
  return (validMeasures >= 2) ? (val / validMeasures) : 999.0;
}

// ========== COMMANDES PONT ==========
void ouvrirPont() {
  int angle = constrain(90, 0, 180);
  pontServo.write(angle);
  logMessage(LOG_INFO, ">> PONT OUVERT");
}

void fermerPont() {
  int angle = constrain(0, 0, 180);
  pontServo.write(angle);
  logMessage(LOG_INFO, ">> PONT FERMÉ");
}

// ========== SÉCURITÉ ==========
void alerteSecurite(const char* raison) {
  Serial.print("!!! ALERTE SECURITE: ");
  Serial.println(raison);
  
  fermerPont();
  digitalWrite(ledPin, HIGH);
  
  etat = SECURITE;
  tSecuriteStart = millis();
  
  logMessage(LOG_ERROR, raison);
}

void tentativeRecuperation() {
  unsigned long tempsSecurite = millis() - tSecuriteStart;
  
  if (tempsSecurite > SECURITE_RECOVERY_TIME) {
    logMessage(LOG_WARN, "Tentative de récupération après erreur...");
    
    // Réinitialiser
    fermerPont();
    digitalWrite(ledPin, LOW);
    etat = RECUPERATION;
    etatPrecedent = FERME;
    tEtat = millis();
    lastStateChange = millis();
    
    delay(500); // Laisser stabiliser
    
    // Si OK, revenir à FERME
    etat = FERME;
    logMessage(LOG_INFO, "Système réinitialisé avec succès");
  }
}

// ========== TRANSITION D'ÉTAT AVEC DEBOUNCING ==========
void changeEtat(EtatPont nouvelEtat) {
  unsigned long tempsEcoule = millis() - lastStateChange;
  
  if (tempsEcoule >= DEBOUNCE_DELAY && nouvelEtat != etat) {
    etatPrecedent = etat;
    etat = nouvelEtat;
    tEtat = millis();
    lastStateChange = millis();
  }
}

// ========== SETUP ==========
void setup() {
  // Configuration des pins
  pinMode(trigPin1, OUTPUT);
  pinMode(echoPin1, INPUT);
  pinMode(trigPin2, OUTPUT);
  pinMode(echoPin2, INPUT);
  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);

  // Configuration du servo
  pontServo.attach(servoPin);
  
  // Configuration série
  Serial.begin(9600);
  delay(1000);

  // Initialisation
  fermerPont();
  tEtat = millis();
  lastStateChange = millis();
  
  logMessage(LOG_INFO, "=== SYSTEME PONT INITIALISE ===");
  logMessage(LOG_DEBUG, "Broches configurées");
  logMessage(LOG_DEBUG, "Servo attaché");
  logMessage(LOG_INFO, "Prêt à fonctionner");
}

// ========== LOOP ==========
void loop() {
  // Gestion de la récupération après erreur
  if (etat == SECURITE) {
    tentativeRecuperation();
    delay(LOOP_DELAY);
    return;
  }

  if (etat == RECUPERATION) {
    delay(LOOP_DELAY);
    return;
  }

  // Mesure des capteurs
  float d1 = mesurerDistanceCM(trigPin1, echoPin1);
  float d2 = mesurerDistanceCM(trigPin2, echoPin2);

  // Détection capteur hors service
  if (d1 == 999.0 || d2 == 999.0) {
    alerteSecurite("ERREUR CAPTEUR - Mesure invalide");
    delay(LOOP_DELAY);
    return;
  }

  // Debug: afficher les distances toutes les 2 secondes
  static unsigned long lastDebug = 0;
  if (millis() - lastDebug > 2000) {
    Serial.print("D1=");
    Serial.print(d1);
    Serial.print("cm D2=");
    Serial.print(d2);
    Serial.print("cm ETAT=");
    Serial.println(etat);
    lastDebug = millis();
  }

  // Vérifier le timeout global
  if (etat != FERME && (millis() - tEtat) > TIMEOUT_OUVERTURE) {
    logMessage(LOG_WARN, "TIMEOUT - Fermeture sécuritaire");
    fermerPont();
    digitalWrite(ledPin, LOW);
    changeEtat(FERME);
    delay(LOOP_DELAY);
    return;
  }

  // Machine à états
  switch (etat) {
    case FERME:
      if (d1 < SEUIL_DETECTION) {
        logMessage(LOG_INFO, ">> Arrivée détectée");
        ouvrirPont();
        digitalWrite(ledPin, HIGH);
        changeEtat(OUVERT_ATTENTE_PASSAGE);
      }
      break;

    case OUVERT_ATTENTE_PASSAGE:
      if (d2 < SEUIL_PRESENCE) {
        logMessage(LOG_INFO, ">> Passage détecté");
        changeEtat(EN_PASSAGE);
      }
      break;

    case EN_PASSAGE:
      if (d2 > SEUIL_PRESENCE) {
        logMessage(LOG_INFO, ">> Départ détecté");
        fermerPont();
        digitalWrite(ledPin, LOW);
        changeEtat(FERME);
      }
      break;

    default:
      break;
  }

  delay(LOOP_DELAY);
}
