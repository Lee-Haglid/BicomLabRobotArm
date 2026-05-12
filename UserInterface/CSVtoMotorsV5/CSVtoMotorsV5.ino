#include <Servo.h>

// Haglid
// 5-joint servo CSV interface
// Simple store-then-play version
//
// Protocol:
//   PC -> "CLEAR"
//   PC -> "t_ms,bottom,mid,top,elbow,wrist"
//   PC -> "END"
//   PC -> "PLAY"
//
// Arduino replies:
//   "RDY" after each accepted line
//   "LOADED n", "OK", "RDY" after END
//   "PLAYING" when playback starts
//   "DONE", "RDY" when playback finishes

Servo sBottom, sMid, sTop, sElbow, sWrist;

// change these if your wiring is different
const int pinBottom = 9;
const int pinMid    = 10;
const int pinTop    = 11;
const int pinElbow  = 6;
const int pinWrist  = 5;

const int SERVO_OFFSET = 90;

struct Sample {
  uint16_t t_ms;
  int8_t bottom;
  int8_t mid;
  int8_t top;
  int8_t elbow;
  int8_t wrist;
};

const int MAX_SAMPLES = 120;   // keep small enough for Uno RAM
Sample traj[MAX_SAMPLES];
int nSamples = 0;

bool loaded = false;
bool playing = false;

uint32_t tStart = 0;
int idx = 0;

const char* RDY = "RDY";

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

void writeZeroPose() {
  sBottom.write(90);
  sMid.write(90);
  sTop.write(90);
  sElbow.write(90);
  sWrist.write(90);
}

void setup() {
  Serial.begin(115200);

  sBottom.attach(pinBottom, 1000, 2000);
  sMid.attach(pinMid, 1000, 2000);
  sTop.attach(pinTop, 1000, 2000);
  sElbow.attach(pinElbow, 1000, 2000);
  sWrist.attach(pinWrist, 1000, 2000);

  writeZeroPose();
  delay(300);

  Serial.println("READY: send lines 't_ms,bottom,mid,top,elbow,wrist' then 'END'. Send 'PLAY' to start.");
  Serial.println(RDY);
}

void loop() {
  static char line[96];

  // ---------------- LOAD MODE ----------------
  if (!playing) {
    if (!readLine(line, sizeof(line))) return;

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

    if (strcmp(line, "ZERO") == 0) {
      writeZeroPose();
      Serial.println("rpyew: 90 90 90 90 90");
      Serial.println(RDY);
      return;
    }

    uint32_t t;
    int bottom, mid, top, elbow, wrist;

    if (sscanf(line, "%lu,%d,%d,%d,%d,%d", &t, &bottom, &mid, &top, &elbow, &wrist) == 6) {
      if (nSamples < MAX_SAMPLES) {
        if (t > 65535UL) {
          Serial.println("ERR: t_ms too large");
          Serial.println(RDY);
          return;
        }

        traj[nSamples].t_ms   = (uint16_t)t;
        traj[nSamples].bottom = (int8_t)constrain(bottom, -90, 90);
        traj[nSamples].mid    = (int8_t)constrain(mid, -90, 90);
        traj[nSamples].top    = (int8_t)constrain(top, -90, 90);
        traj[nSamples].elbow  = (int8_t)constrain(elbow, -90, 90);
        traj[nSamples].wrist  = (int8_t)constrain(wrist, -90, 90);

        nSamples++;
        Serial.println(RDY);
      } else {
        Serial.println("ERR: MAX_SAMPLES reached");
        Serial.println(RDY);
      }
    } else {
      Serial.println("ERR: bad line");
      Serial.println(RDY);
    }

    return;
  }

  // ---------------- PLAYBACK MODE ----------------
  uint32_t now = millis() - tStart;

  while (idx < nSamples && now >= traj[idx].t_ms) {
    int posBottom = constrain((int)traj[idx].bottom + SERVO_OFFSET, 0, 180);
    int posMid    = constrain((int)traj[idx].mid    + SERVO_OFFSET, 0, 180);
    int posTop    = constrain((int)traj[idx].top    + SERVO_OFFSET, 0, 180);
    int posElbow  = constrain((int)traj[idx].elbow  + SERVO_OFFSET, 0, 180);
    int posWrist  = constrain((int)traj[idx].wrist  + SERVO_OFFSET, 0, 180);

    sBottom.write(posBottom);
    sMid.write(posMid);
    sTop.write(posTop);
    sElbow.write(posElbow);
    sWrist.write(posWrist);

    Serial.print("rpyew: ");
    Serial.print(posBottom);
    Serial.print(" ");
    Serial.print(posMid);
    Serial.print(" ");
    Serial.print(posTop);
    Serial.print(" ");
    Serial.print(posElbow);
    Serial.print(" ");
    Serial.println(posWrist);

    idx++;
    Serial.println(RDY);
  }

  if (idx >= nSamples) {
    playing = false;
    Serial.println("DONE");
    Serial.println(RDY);
  }
}