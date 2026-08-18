#include <Servo.h>

// Haglid
// Servo simulink CSV interface V1 (HANDSHAKE)
// Most recent update: Jan 29 2026

Servo s1, s2, s3;

// Declare Servo Pins
const int servo1 = 9;
const int servo2 = 10;
const int servo3 = 11;

// Trajectory
struct Sample {
  uint32_t t_ms;
  uint8_t a1;
  uint8_t a2;
  uint8_t a3;
};

// Keep memory small
const int MAX_SAMPLES = 180;
Sample traj[MAX_SAMPLES];
int nSamples = 0;

bool loaded = false;
bool playing = false;

uint32_t tStart = 0;
int idx = 0;

// Handshake token
const char* RDY = "RDY";

// Read line from serial
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
    if (pos < buflen - 1) buf[pos++] = c;
  }
  return false;
}

void resetPlayback() {
  playing = false;
  idx = 0;
  loaded = (nSamples > 0);
}

void setup() {
  Serial.begin(115200);

  s1.attach(servo1);
  s2.attach(servo2);
  s3.attach(servo3);

  Serial.println("READY: send lines 't_ms,a1,a2,a3' then 'END'. Send 'PLAY' to start.");
  Serial.println(RDY); // Handshake: ready to receive first command
}

void loop() {
  static char line[64];

  // ---- LOAD MODE ----
  if (!playing) {
    if (readLine(line, sizeof(line))) {

      // Commands
      if (strcmp(line, "END") == 0) {
        loaded = (nSamples > 0);
        Serial.print("LOADED ");
        Serial.println(nSamples);
        Serial.println("OK");
        Serial.println(RDY); // Handshake: ready for next command
        return;
      }

      if (strcmp(line, "PLAY") == 0) {
        if (loaded) {
          playing = true;
          tStart = millis();
          idx = 0;
          Serial.println("PLAYING");
          // NOTE: do NOT print RDY here; during playback we handshake per applied point.
        } else {
          Serial.println("ERR: no data loaded");
          Serial.println(RDY); // Handshake: ready for next command
        }
        return;
      }

      if (strcmp(line, "CLEAR") == 0) {
        nSamples = 0;
        loaded = false;
        Serial.println("CLEARED");
        Serial.println(RDY); // Handshake: ready for next command
        return;
      }

      // Parse sample: t_ms,a1,a2,a3
      uint32_t t;
      int a1, a2, a3;
      if (sscanf(line, "%lu,%d,%d,%d", &t, &a1, &a2, &a3) == 4) {
        if (nSamples < MAX_SAMPLES) {
          traj[nSamples].t_ms = t;
          traj[nSamples].a1 = (uint8_t)constrain(a1, 0, 180);
          traj[nSamples].a2 = (uint8_t)constrain(a2, 0, 180);
          traj[nSamples].a3 = (uint8_t)constrain(a3, 0, 180);
          nSamples++;

          // Handshake: acknowledge each received line so MATLAB can send the next one
          Serial.println(RDY);

          // Optional: ack every N lines to reduce chatter (keep if you want extra debug)
          // if (nSamples % 50 == 0) Serial.println("ACK");
        } else {
          Serial.println("ERR: MAX_SAMPLES reached");
          Serial.println(RDY); // Handshake anyway so MATLAB doesn't hang
        }
      } else {
        Serial.println("ERR: bad line");
        Serial.println(RDY); // Handshake anyway so MATLAB doesn't hang
      }
    }
    return;
  }

  // ---- PLAYBACK MODE ----
  uint32_t now = millis() - tStart;

  // Push all samples that are due
  while (idx < nSamples && now >= traj[idx].t_ms) {
    s1.write(traj[idx].a1);
    s2.write(traj[idx].a2);
    s3.write(traj[idx].a3);

    idx++;

    // Handshake: signal that a point was applied (lets MATLAB pace if you stream during playback)
    Serial.println(RDY);
  }

  if (idx >= nSamples) {
    playing = false;
    Serial.println("DONE");
    Serial.println(RDY); // ready for new load/play commands
  }
}
