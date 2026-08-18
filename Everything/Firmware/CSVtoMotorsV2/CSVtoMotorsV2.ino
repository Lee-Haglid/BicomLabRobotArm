#include <Servo.h>

// Haglid
// Servo simulink CSV interface V2 (HANDSHAKE, STORE-THEN-PLAY)
// Most recent update: Jan 29 2026
//
// Protocol (matched to MATLAB Option A):
//   PC -> "CLEAR"         (optional) clear buffer
//   PC -> "t_ms,a1,a2,a3" (repeat up to MAX_SAMPLES lines; Arduino replies "RDY" each line)
//   PC -> "END"           (Arduino replies "LOADED n", "OK", "RDY")
//   PC -> "PLAY"          (Arduino plays back; prints "RDY" each applied point; then "DONE", "RDY")
//
// Notes:
// - MAX_SAMPLES limits how many rows you can store (UNO RAM). Use MATLAB downsampling to <= MAX_SAMPLES.

Servo s1, s2, s3;

// Declare Servo Pins
const int servo1 = 9;
const int servo2 = 10;
const int servo3 = 11;
const int SERVO_OFFSET = 90;  // CSV zero maps to servo 90°

// Trajectory sample
struct Sample {
  uint32_t t_ms;
  uint8_t a1;
  uint8_t a2;
  uint8_t a3;
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
    if (c == '\r') continue; // ignore CR
    if (c == '\n') {         // LF ends line
      buf[pos] = '\0';
      pos = 0;
      return true;
    }
    if (pos < buflen - 1) buf[pos++] = c;
  }
  return false;
}

void setup() {
  Serial.begin(115200);

  // Attach with explicit pulse range to reduce startup jerk
  s1.attach(servo1, 1000, 2000);
  s2.attach(servo2, 1000, 2000);
  s3.attach(servo3, 1000, 2000);

  // Immediately command a known safe position
  s1.write(90);
  s2.write(90);
  s3.write(90);
  delay(300);


  Serial.println("READY: send lines 't_ms,a1,a2,a3' then 'END'. Send 'PLAY' to start.");
  Serial.println(RDY); // ready for first command
}

void loop() {
  static char line[64];

  // ---------------- LOAD MODE ----------------
  if (!playing) {
    if (!readLine(line, sizeof(line))) return;

    // Commands
    if (strcmp(line, "END") == 0) {
      loaded = (nSamples > 0);
      Serial.print("LOADED ");
      Serial.println(nSamples);
      Serial.println("OK");
      Serial.println(RDY);
      return;
    }

    if (strcmp(line, "PLAY") == 0) {
      if (loaded) {
        playing = true;
        tStart = millis();
        idx = 0;
        Serial.println("PLAYING");
        // During playback, RDY is printed per applied point
      } else {
        Serial.println("ERR: no data loaded");
        Serial.println(RDY);
      }
      return;
    }

    if (strcmp(line, "CLEAR") == 0) {
      nSamples = 0;
      loaded = false;
      playing = false;
      idx = 0;
      Serial.println("CLEARED");
      Serial.println(RDY);
      return;
    }

    // Parse sample: t_ms,a1,a2,a3
    uint32_t t;
    int a1, a2, a3;
    if (sscanf(line, "%lu,%d,%d,%d", &t, &a1, &a2, &a3) == 4) {
      if (nSamples < MAX_SAMPLES) {
        traj[nSamples].t_ms = t;
        traj[nSamples].a1 = (uint8_t)constrain(a1, -90, 90);
        traj[nSamples].a2 = (uint8_t)constrain(a2, -90, 90);
        traj[nSamples].a3 = (uint8_t)constrain(a3, -90, 90);
        nSamples++;

        // Handshake: ready for next line
        Serial.println(RDY);
      } else {
        Serial.println("ERR: MAX_SAMPLES reached");
        Serial.println(RDY); // keep handshake so MATLAB doesn't hang
      }
    } else {
      Serial.println("ERR: bad line");
      Serial.println(RDY);
    }

    return;
  }

  // ---------------- PLAYBACK MODE ----------------
  uint32_t now = millis() - tStart;

  // Apply all samples that are due
  while (idx < nSamples && now >= traj[idx].t_ms) {
    s1.write(constrain(traj[idx].a1 + SERVO_OFFSET, 0, 180));
    s2.write(constrain(traj[idx].a2 + SERVO_OFFSET, 0, 180));
    s3.write(constrain(traj[idx].a3 + SERVO_OFFSET, 0, 180));
    Serial.println(traj[idx].a2);


    idx++;

    // Handshake: point applied
    Serial.println(RDY);
  }

  if (idx >= nSamples) {
    playing = false;
    Serial.println("DONE");
    Serial.println(RDY); // ready for new load/play commands
  }
}
