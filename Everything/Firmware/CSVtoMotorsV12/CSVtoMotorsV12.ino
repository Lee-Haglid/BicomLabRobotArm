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

// store time internally as microseconds
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

bool enqueueSample(uint32_t t_us, int bottom, int mid, int top, int elbow, int wrist) {
  if (qCount >= BUF_SIZE) return false;

  q[qTail].t_us   = t_us;
  q[qTail].bottom = (int8_t)constrain(bottom, -90, 90);
  q[qTail].mid    = (int8_t)constrain(mid, -90, 90);
  q[qTail].top    = (int8_t)constrain(top, -90, 90);
  q[qTail].elbow  = (int8_t)constrain(elbow, -90, 90);
  q[qTail].wrist  = (int8_t)constrain(wrist, -90, 90);

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

int signedToServo(int x) {
  return constrain(x + SERVO_OFFSET, 0, 180);
}

void writeServoPoseFromSigned(int bottom, int mid, int top, int elbow, int wrist) {
  currentBottom = signedToServo(bottom);
  currentMid    = signedToServo(mid);
  currentTop    = signedToServo(top);
  currentElbow  = signedToServo(elbow);
  currentWrist  = signedToServo(wrist);

  sBottom.write(currentBottom);
  sMid.write(currentMid);
  sTop.write(currentTop);
  sElbow.write(currentElbow);
  sWrist.write(currentWrist);
}

void writeZeroPose() {
  currentBottom = 90;
  currentMid    = 90;
  currentTop    = 90;
  currentElbow  = 90;
  currentWrist  = 90;

  sBottom.write(90);
  sMid.write(90);
  sTop.write(90);
  sElbow.write(90);
  sWrist.write(90);
}

void sendHeartRateSPI(uint8_t bpm) {
  digitalWrite(PUMP_SS_PIN, LOW);
  SPI.transfer(0xA5);
  SPI.transfer(bpm);
  digitalWrite(PUMP_SS_PIN, HIGH);
}

void setup() {
  Serial.begin(115200);

  sBottom.attach(pinBottom, 1000, 2000);
  sMid.attach(pinMid, 1000, 2000);
  sTop.attach(pinTop, 1000, 2000);
  sElbow.attach(pinElbow, 1000, 2000);
  sWrist.attach(pinWrist, 1000, 2000);

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
    int bottom, mid, top, elbow, wrist;

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
    bottom = atoi(token);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    mid = atoi(token);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    top = atoi(token);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    elbow = atoi(token);

    token = strtok(NULL, ",");
    if (token == NULL) { Serial.println(F("ERR: BAD_LINE")); printAck(); continue; }
    wrist = atoi(token);

    if (enqueueSample(t_us, bottom, mid, top, elbow, wrist)) {
      printAck();
    } else {
      Serial.println(F("ERR: BUF_FULL"));
      printAck();
    }
  }

  if (!streamingActive) return;

  // start once at least 1 point is present
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