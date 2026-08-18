#include <Servo.h>
#include <SPI.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

Servo sBottom, sMid, sTop, sElbow, sWrist;

// Keep the same pins as your current file
const int pinBottom = 9;
const int pinMid    = 10;
const int pinTop    = 6;
const int pinElbow  = 11;
const int pinWrist  = 5;

// UNO hardware SPI:
// SS   = 10
// MOSI = 11
// MISO = 12
// SCK  = 13
const int PUMP_SS_PIN = 10;

const int SERVO_OFFSET = 90;
const int BUF_SIZE = 24;

// Faster interpolation updates
const uint32_t INTERP_UPDATE_US = 500;
const uint32_t DEBUG_PRINT_MS   = 1000000;

// Clamp motion to +/-30 degrees
const int ANGLE_LIMIT = 30;

// Servo pulse range
const int SERVO_MIN_US    = 1000;
const int SERVO_MAX_US    = 2000;
const int SERVO_CENTER_US = 1500;

struct Sample {
  uint32_t t_ms;
  int8_t bottom;
  int8_t mid;
  int8_t top;
  int8_t elbow;
  int8_t wrist;
};

Sample q[BUF_SIZE];
int qHead = 0;
int qTail = 0;
int qCount = 0;

bool streamingActive = false;
bool endReceived = false;
bool playbackStarted = false;

uint32_t playStartMicros = 0;
uint32_t firstSampleTus = 0;
uint32_t lastInterpUpdateUs = 0;
uint32_t lastDebugPrintMs = 0;

Sample currentSample;
Sample nextSample;
bool haveCurrent = false;
bool haveNext = false;

int currentBottom = 90;
int currentMid    = 90;
int currentTop    = 90;
int currentElbow  = 90;
int currentWrist  = 90;

uint8_t heartRateBpm = 72;

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

int clampAngle(int x) {
  if (x > ANGLE_LIMIT) return ANGLE_LIMIT;
  if (x < -ANGLE_LIMIT) return -ANGLE_LIMIT;
  return x;
}

float clampAngleF(float x) {
  if (x > ANGLE_LIMIT) return (float)ANGLE_LIMIT;
  if (x < -ANGLE_LIMIT) return (float)(-ANGLE_LIMIT);
  return x;
}

void printAck() {
  Serial.print(F("ACK "));
  Serial.println(qCount);
}

void printPose() {
  Serial.print(F("rpyew: "));
  Serial.print(currentBottom);
  Serial.print(' ');
  Serial.print(currentMid);
  Serial.print(' ');
  Serial.print(currentTop);
  Serial.print(' ');
  Serial.print(currentElbow);
  Serial.print(' ');
  Serial.println(currentWrist);
}

void clearQueue() {
  qHead = 0;
  qTail = 0;
  qCount = 0;
  endReceived = false;
  playbackStarted = false;
  playStartMicros = 0;
  firstSampleTus = 0;
  lastInterpUpdateUs = 0;
  lastDebugPrintMs = 0;
  haveCurrent = false;
  haveNext = false;
}

bool enqueueSample(uint32_t t_ms, int bottom, int mid, int top, int elbow, int wrist) {
  if (qCount >= BUF_SIZE) return false;

  q[qTail].t_ms   = t_ms;
  q[qTail].bottom = (int8_t)clampAngle(bottom);
  q[qTail].mid    = (int8_t)clampAngle(mid);
  q[qTail].top    = (int8_t)clampAngle(top);
  q[qTail].elbow  = (int8_t)clampAngle(elbow);
  q[qTail].wrist  = (int8_t)clampAngle(wrist);

  qTail = (qTail + 1) % BUF_SIZE;
  qCount++;
  return true;
}

bool dequeueSample(Sample &s) {
  if (qCount <= 0) return false;
  s = q[qHead];
  qHead = (qHead + 1) % BUF_SIZE;
  qCount--;
  return true;
}

bool peekSample(Sample &s) {
  if (qCount <= 0) return false;
  s = q[qHead];
  return true;
}

int signedToServoDeg(int x) {
  x = clampAngle(x);
  return constrain(x + SERVO_OFFSET, 0, 180);
}

int signedToServoUs(float x) {
  x = clampAngleF(x);

  // map signed angle to pulse width
  float us = SERVO_CENTER_US + (x / 90.0f) * (SERVO_MAX_US - SERVO_CENTER_US);

  if (us < SERVO_MIN_US) us = SERVO_MIN_US;
  if (us > SERVO_MAX_US) us = SERVO_MAX_US;

  return (int)round(us);
}

// smoothstep interpolation
float smoothstep01(float a) {
  if (a <= 0.0f) return 0.0f;
  if (a >= 1.0f) return 1.0f;
  return a * a * (3.0f - 2.0f * a);
}

void writeServoPoseFromSigned(int bottom, int mid, int top, int elbow, int wrist) {
  bottom = clampAngle(bottom);
  mid    = clampAngle(mid);
  top    = clampAngle(top);
  elbow  = clampAngle(elbow);
  wrist  = clampAngle(wrist);

  currentBottom = signedToServoDeg(bottom);
  currentMid    = signedToServoDeg(mid);
  currentTop    = signedToServoDeg(top);
  currentElbow  = signedToServoDeg(elbow);
  currentWrist  = signedToServoDeg(wrist);

  sBottom.writeMicroseconds(signedToServoUs((float)bottom));
  sMid.writeMicroseconds(signedToServoUs((float)mid));
  sTop.writeMicroseconds(signedToServoUs((float)top));
  sElbow.writeMicroseconds(signedToServoUs((float)elbow));
  sWrist.writeMicroseconds(signedToServoUs((float)wrist));
}

void writeInterpolatedPose(const Sample &a, const Sample &b, uint32_t nowRelUs) {
  uint32_t t0_us = a.t_ms * 1000UL;
  uint32_t t1_us = b.t_ms * 1000UL;

  float alpha;
  if (t1_us <= t0_us) {
    alpha = 1.0f;
  } else {
    alpha = (float)(nowRelUs - t0_us) / (float)(t1_us - t0_us);
    if (alpha < 0.0f) alpha = 0.0f;
    if (alpha > 1.0f) alpha = 1.0f;
  }

  float s = smoothstep01(alpha);

  float interpBottom = (1.0f - s) * (float)a.bottom + s * (float)b.bottom;
  float interpMid    = (1.0f - s) * (float)a.mid    + s * (float)b.mid;
  float interpTop    = (1.0f - s) * (float)a.top    + s * (float)b.top;
  float interpElbow  = (1.0f - s) * (float)a.elbow  + s * (float)b.elbow;
  float interpWrist  = (1.0f - s) * (float)a.wrist  + s * (float)b.wrist;

  currentBottom = signedToServoDeg((int)round(interpBottom));
  currentMid    = signedToServoDeg((int)round(interpMid));
  currentTop    = signedToServoDeg((int)round(interpTop));
  currentElbow  = signedToServoDeg((int)round(interpElbow));
  currentWrist  = signedToServoDeg((int)round(interpWrist));

  sBottom.writeMicroseconds(signedToServoUs(interpBottom));
  sMid.writeMicroseconds(signedToServoUs(interpMid));
  sTop.writeMicroseconds(signedToServoUs(interpTop));
  sElbow.writeMicroseconds(signedToServoUs(interpElbow));
  sWrist.writeMicroseconds(signedToServoUs(interpWrist));
}

void writeZeroPose() {
  currentBottom = 90;
  currentMid    = 90;
  currentTop    = 90;
  currentElbow  = 90;
  currentWrist  = 90;

  sBottom.writeMicroseconds(SERVO_CENTER_US);
  sMid.writeMicroseconds(SERVO_CENTER_US);
  sTop.writeMicroseconds(SERVO_CENTER_US);
  sElbow.writeMicroseconds(SERVO_CENTER_US);
  sWrist.writeMicroseconds(SERVO_CENTER_US);
}

void sendHeartRateSPI(uint8_t bpm) {
  digitalWrite(PUMP_SS_PIN, LOW);
  SPI.transfer(0xA5);
  SPI.transfer(bpm);
  digitalWrite(PUMP_SS_PIN, HIGH);
}

void setup() {
  Serial.begin(115200);

  sBottom.attach(pinBottom, SERVO_MIN_US, SERVO_MAX_US);
  sMid.attach(pinMid, SERVO_MIN_US, SERVO_MAX_US);
  sTop.attach(pinTop, SERVO_MIN_US, SERVO_MAX_US);
  sElbow.attach(pinElbow, SERVO_MIN_US, SERVO_MAX_US);
  sWrist.attach(pinWrist, SERVO_MIN_US, SERVO_MAX_US);

  pinMode(PUMP_SS_PIN, OUTPUT);
  digitalWrite(PUMP_SS_PIN, HIGH);
  SPI.begin();

  delay(300);

  // Send HR once at startup
  sendHeartRateSPI(heartRateBpm);

  Serial.println(F("READY"));
  printAck();
}

void loop() {
  static char line[96];

  while (readLine(line, sizeof(line))) {
    if (strncmp(line, "HR ", 3) == 0) {
      int bpm = atoi(line + 3);
      bpm = constrain(bpm, 1, 240);
      heartRateBpm = (uint8_t)bpm;

      // Only send SPI when HR explicitly changes
      sendHeartRateSPI(heartRateBpm);

      Serial.print(F("HR-SET "));
      Serial.println(heartRateBpm);
      continue;
    }

    if (strcmp(line, "START") == 0) {
      clearQueue();
      streamingActive = true;
      Serial.println(F("READY"));
      printAck();
      continue;
    }

    if (strcmp(line, "END") == 0) {
      endReceived = true;
      Serial.println(F("END-ACK"));
      printAck();
      continue;
    }

    if (strcmp(line, "STOP") == 0) {
      clearQueue();
      streamingActive = false;
      Serial.println(F("STOPPED"));
      printAck();
      continue;
    }

    if (strcmp(line, "ZERO") == 0) {
      writeZeroPose();
      printPose();
      printAck();
      continue;
    }

    uint32_t t_ms;
    int bottom, mid, top, elbow, wrist;
    if (sscanf(line, "%lu,%d,%d,%d,%d,%d", &t_ms, &bottom, &mid, &top, &elbow, &wrist) == 6) {
      if (!enqueueSample(t_ms, bottom, mid, top, elbow, wrist)) {
        Serial.println(F("ERR: BUF_FULL"));
      }
    } else {
      Serial.println(F("ERR: BAD_LINE"));
      printAck();
    }
  }

  if (!streamingActive) return;

  // Start only when we have at least 2 points
  if (!playbackStarted && qCount >= 2) {
    if (dequeueSample(currentSample)) {
      haveCurrent = true;
      haveNext = peekSample(nextSample);

      firstSampleTus = currentSample.t_ms * 1000UL;
      playStartMicros = micros();
      lastInterpUpdateUs = 0;
      lastDebugPrintMs = 0;
      playbackStarted = true;

      Serial.println(F("PLAYING"));
      writeServoPoseFromSigned(currentSample.bottom, currentSample.mid, currentSample.top,
                               currentSample.elbow, currentSample.wrist);
    }
  }

  if (playbackStarted && haveCurrent) {
    uint32_t nowRelUs = (micros() - playStartMicros) + firstSampleTus;
    uint32_t nowRelMs = nowRelUs / 1000UL;

    while (haveNext && nowRelMs >= nextSample.t_ms) {
      dequeueSample(currentSample);
      haveNext = peekSample(nextSample);
    }

    if (!haveNext && qCount > 0) {
      haveNext = peekSample(nextSample);
    }

    if (haveNext) {
      if (nowRelUs - lastInterpUpdateUs >= INTERP_UPDATE_US) {
        lastInterpUpdateUs = nowRelUs;
        writeInterpolatedPose(currentSample, nextSample, nowRelUs);
      }
    } else {
      writeServoPoseFromSigned(currentSample.bottom, currentSample.mid, currentSample.top,
                               currentSample.elbow, currentSample.wrist);
    }

    uint32_t nowMsForDebug = millis();
    if (nowMsForDebug - lastDebugPrintMs >= DEBUG_PRINT_MS) {
      lastDebugPrintMs = nowMsForDebug;
      printPose();
    }
  }

  if (playbackStarted && endReceived && qCount == 0 && !haveNext) {
    streamingActive = false;
    playbackStarted = false;
    endReceived = false;
    haveCurrent = false;
    Serial.println(F("DONE"));
    printAck();
  }
}