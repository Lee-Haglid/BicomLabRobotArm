#include <Servo.h>
#include <SPI.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
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

// Clamp motion to +/-30 degrees
const int ANGLE_LIMIT = 30;

// Servo pulse range
const int SERVO_MIN_US    = 1000;
const int SERVO_MAX_US    = 2000;
const int SERVO_CENTER_US = 1500;

// Input timestamps are SECONDS in the CSV text, but stored as MICROSECONDS internally
struct Sample {
  uint32_t t_us;
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

Sample currentSample;
bool haveCurrent = false;

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
  haveCurrent = false;
}

bool enqueueSample(uint32_t t_us, float bottom, float mid, float top, float elbow, float wrist) {
  if (qCount >= BUF_SIZE) return false;

  q[qTail].t_us   = t_us;
  q[qTail].bottom = (int8_t)clampAngle((int)round(bottom));
  q[qTail].mid    = (int8_t)clampAngle((int)round(mid));
  q[qTail].top    = (int8_t)clampAngle((int)round(top));
  q[qTail].elbow  = (int8_t)clampAngle((int)round(elbow));
  q[qTail].wrist  = (int8_t)clampAngle((int)round(wrist));

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

  float us = SERVO_CENTER_US + (x / 90.0f) * (SERVO_MAX_US - SERVO_CENTER_US);

  if (us < SERVO_MIN_US) us = SERVO_MIN_US;
  if (us > SERVO_MAX_US) us = SERVO_MAX_US;

  return (int)round(us);
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

  sendHeartRateSPI(heartRateBpm);

  Serial.println(F("READY"));
  printAck();
}

void loop() {
  static char line[128];

  while (readLine(line, sizeof(line))) {
    if (strncmp(line, "HR ", 3) == 0) {
      int bpm = atoi(line + 3);
      bpm = constrain(bpm, 1, 240);
      heartRateBpm = (uint8_t)bpm;
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

    // INPUT FORMAT: t_sec,bottom,mid,top,elbow,wrist
    char* token;
    double t_sec;
    uint32_t t_us;
    float bottom, mid, top, elbow, wrist;

    token = strtok(line, ",");
    if (token == NULL) {
      Serial.println(F("ERR: BAD_LINE"));
      printAck();
      continue;
    }
    t_sec = atof(token);
    t_us = (uint32_t)round(t_sec * 1000000.0);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    bottom = (float)atof(token);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    mid = (float)atof(token);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    top = (float)atof(token);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    elbow = (float)atof(token);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    wrist = (float)atof(token);

    if (!enqueueSample(t_us, bottom, mid, top, elbow, wrist)) {
      Serial.println(F("ERR: BUF_FULL"));
    } else {
      printAck();
    }
  }

  if (!streamingActive) return;

  if (!playbackStarted && qCount > 0) {
    if (dequeueSample(currentSample)) {
      haveCurrent = true;
      firstSampleTus = currentSample.t_us;
      playStartMicros = micros();
      playbackStarted = true;

      Serial.println(F("PLAYING"));
      writeServoPoseFromSigned(currentSample.bottom, currentSample.mid, currentSample.top,
                               currentSample.elbow, currentSample.wrist);
      printAck();
    }
  }

  if (playbackStarted && haveCurrent) {
    uint32_t nowRelUs = (micros() - playStartMicros) + firstSampleTus;

    Sample nextSample;
    while (peekSample(nextSample) && nowRelUs >= nextSample.t_us) {
      dequeueSample(currentSample);
      writeServoPoseFromSigned(currentSample.bottom, currentSample.mid, currentSample.top,
                               currentSample.elbow, currentSample.wrist);
      printAck();
    }
  }

  if (playbackStarted && endReceived && qCount == 0) {
    streamingActive = false;
    playbackStarted = false;
    endReceived = false;
    haveCurrent = false;
    Serial.println(F("DONE"));
    printAck();
  }
}