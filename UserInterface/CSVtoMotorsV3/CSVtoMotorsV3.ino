#include <Servo.h>

// Haglid
// Servo simulink CSV interface V2 (HANDSHAKE, STORE-THEN-PLAY)
// Most recent update: Jan 29 2026
//
// Protocol (matched to MATLAB Option A):
//   PC -> "CLEAR"         clear buffer
//   PC -> "t_ms,a1,a2,a3" repeat up to MAX_SAMPLES lines; Arduino replies "RDY" each line
//   PC -> "END"           Arduino replies "LOADED n", "OK", "RDY"
//   PC -> "PLAY"          Arduino plays back; prints "rpy: a b c" each applied point; then "DONE", "RDY"

#include <string.h>
#include <stdio.h>

Servo s1, s2, s3;

// Declare Servo Pins
const int servo1 = 9;
const int servo2 = 10;
const int servo3 = 11;
const int SERVO_OFFSET = 90;  // CSV zero maps to servo 90°

// Smaller trajectory sample for Uno RAM
struct Sample {
  uint16_t t_ms;  // enough for chunked playback as long as each chunk < 65.5 s
  int8_t a1;      // stores -90..90
  int8_t a2;
  int8_t a3;
};

// Keep memory small (UNO)
const int MAX_SAMPLES = 180;
Sample traj[MAX_SAMPLES];
int nSamples = 0;

bool loaded = false;
bool playing = false;

uint32_t tStart = 0;
int idx = 0;

// Handshake token
const char* RDY = "RDY";

// Read one newline-terminated line from Serial into buf
bool readLine(char* buf, size_t buflen) {
  static size_t pos = 0;

  while (Serial.available()) {
    char c = (char)Serial.read();

    if (c == '\r') continue;

    if (c == '\n') {
      buf[pos] = '\0';
      pos = 0;
      return true;
    }

    if (pos < buflen - 1) {
      buf[pos++] = c;
    }
  }
  return false;
}

void setup() {
  Serial.begin(115200);

  s1.attach(servo1, 1000, 2000);
  s2.attach(servo2, 1000, 2000);
  s3.attach(servo3, 1000, 2000);

  s1.write(90);
  s2.write(90);
  s3.write(90);
  delay(300);

  Serial.println(F("READY: send lines 't_ms,a1,a2,a3' then 'END'. Send 'PLAY' to start."));
  Serial.println(F("RDY"));
}

void loop() {
  static char line[64];

  // ---------------- LOAD MODE ----------------
  if (!playing) {
    if (!readLine(line, sizeof(line))) return;

    if (strcmp(line, "END") == 0) {
      loaded = (nSamples > 0);
      Serial.print(F("LOADED "));
      Serial.println(nSamples);
      Serial.println(F("OK"));
      Serial.println(F("RDY"));
      return;
    }

    if (strcmp(line, "PLAY") == 0) {
      if (loaded) {
        playing = true;
        tStart = millis();
        idx = 0;
        Serial.println(F("PLAYING"));
      } else {
        Serial.println(F("ERR: no data loaded"));
        Serial.println(F("RDY"));
      }
      return;
    }

    if (strcmp(line, "CLEAR") == 0) {
      nSamples = 0;
      loaded = false;
      playing = false;
      idx = 0;
      Serial.println(F("CLEARED"));
      Serial.println(F("RDY"));
      return;
    }

    // Parse sample: t_ms,a1,a2,a3
    unsigned long t;
    int a1, a2, a3;

    if (sscanf(line, "%lu,%d,%d,%d", &t, &a1, &a2, &a3) == 4) {
      if (nSamples < MAX_SAMPLES) {
        if (t > 65535UL) {
          Serial.println(F("ERR: t_ms too large"));
          Serial.println(F("RDY"));
          return;
        }

        traj[nSamples].t_ms = (uint16_t)t;
        traj[nSamples].a1 = (int8_t)constrain(a1, -90, 90);
        traj[nSamples].a2 = (int8_t)constrain(a2, -90, 90);
        traj[nSamples].a3 = (int8_t)constrain(a3, -90, 90);
        nSamples++;

        Serial.println(F("RDY"));
      } else {
        Serial.println(F("ERR: MAX_SAMPLES reached"));
        Serial.println(F("RDY"));
      }
    } else {
      Serial.println(F("ERR: bad line"));
      Serial.println(F("RDY"));
    }

    return;
  }

  // ---------------- PLAYBACK MODE ----------------
  uint32_t now = millis() - tStart;

  while (idx < nSamples && now >= traj[idx].t_ms) {
    int pos1 = constrain((int)traj[idx].a1 + SERVO_OFFSET, 0, 180);
    int pos2 = constrain((int)traj[idx].a2 + SERVO_OFFSET, 0, 180);
    int pos3 = constrain((int)traj[idx].a3 + SERVO_OFFSET, 0, 180);

    s1.write(pos1);
    s2.write(pos2);
    s3.write(pos3);

    Serial.print(F("rpy: "));
    Serial.print(pos1);
    Serial.print(' ');
    Serial.print(pos2);
    Serial.print(' ');
    Serial.println(pos3);

    idx++;
    Serial.println(F("RDY"));
  }

  if (idx >= nSamples) {
    playing = false;
    Serial.println(F("DONE"));
    Serial.println(F("RDY"));
  }
}