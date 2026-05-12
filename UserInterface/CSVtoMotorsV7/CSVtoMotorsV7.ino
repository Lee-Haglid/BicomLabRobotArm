#include <Servo.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

Servo sBottom, sMid, sTop, sElbow, sWrist;

// Change these if your wiring is different
const int pinBottom = 9;
const int pinMid    = 10;
const int pinTop    = 11;
const int pinElbow  = 6;
const int pinWrist  = 5;

const int SERVO_OFFSET = 90;
const int BUF_SIZE = 24;

// How often Arduino updates interpolated servo targets
const uint32_t INTERP_UPDATE_MS = 5;

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

uint32_t playStartMillis = 0;
uint32_t firstSampleTms = 0;
uint32_t lastInterpUpdate = 0;

Sample currentSample;
Sample nextSample;
bool haveCurrent = false;
bool haveNext = false;

int currentBottom = 90;
int currentMid    = 90;
int currentTop    = 90;
int currentElbow  = 90;
int currentWrist  = 90;

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

  playStartMillis = 0;
  firstSampleTms = 0;
  lastInterpUpdate = 0;

  haveCurrent = false;
  haveNext = false;
}

bool enqueueSample(uint32_t t_ms, int bottom, int mid, int top, int elbow, int wrist) {
  if (qCount >= BUF_SIZE) return false;

  q[qTail].t_ms   = t_ms;
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

int lerpInt(int a, int b, float alpha) {
  return (int)round((1.0f - alpha) * a + alpha * b);
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

void writeInterpolatedPose(const Sample &a, const Sample &b, uint32_t nowRelMs) {
  uint32_t t0 = a.t_ms;
  uint32_t t1 = b.t_ms;

  float alpha;
  if (t1 <= t0) {
    alpha = 1.0f;
  } else {
    alpha = (float)(nowRelMs - t0) / (float)(t1 - t0);
    if (alpha < 0.0f) alpha = 0.0f;
    if (alpha > 1.0f) alpha = 1.0f;
  }

  int interpBottom = lerpInt((int)a.bottom, (int)b.bottom, alpha);
  int interpMid    = lerpInt((int)a.mid,    (int)b.mid,    alpha);
  int interpTop    = lerpInt((int)a.top,    (int)b.top,    alpha);
  int interpElbow  = lerpInt((int)a.elbow,  (int)b.elbow,  alpha);
  int interpWrist  = lerpInt((int)a.wrist,  (int)b.wrist,  alpha);

  writeServoPoseFromSigned(interpBottom, interpMid, interpTop, interpElbow, interpWrist);
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

void setup() {
  Serial.begin(115200);

  sBottom.attach(pinBottom, 1000, 2000);
  sMid.attach(pinMid, 1000, 2000);
  sTop.attach(pinTop, 1000, 2000);
  sElbow.attach(pinElbow, 1000, 2000);
  sWrist.attach(pinWrist, 1000, 2000);

  // No forced zero pose on startup
  delay(300);

  Serial.println(F("READY"));
  printAck();
}

void loop() {
  static char line[96];

  while (readLine(line, sizeof(line))) {
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
      if (enqueueSample(t_ms, bottom, mid, top, elbow, wrist)) {
        printAck();
      } else {
        Serial.println(F("ERR: BUF_FULL"));
        printAck();
      }
    } else {
      Serial.println(F("ERR: BAD_LINE"));
      printAck();
    }
  }

  if (!streamingActive) return;

  if (!playbackStarted && qCount > 0) {
    if (dequeueSample(currentSample)) {
      haveCurrent = true;

      if (peekSample(nextSample)) {
        haveNext = true;
      } else {
        haveNext = false;
      }

      firstSampleTms = currentSample.t_ms;
      playStartMillis = millis();
      lastInterpUpdate = 0;
      playbackStarted = true;

      Serial.println(F("PLAYING"));
      writeServoPoseFromSigned(currentSample.bottom, currentSample.mid, currentSample.top,
                               currentSample.elbow, currentSample.wrist);
      printPose();
      printAck();
    }
  }

  if (playbackStarted && haveCurrent) {
    uint32_t nowRel = (millis() - playStartMillis) + firstSampleTms;

    // Advance through any samples whose time has passed
    while (haveNext && nowRel >= nextSample.t_ms) {
      dequeueSample(currentSample);

      if (peekSample(nextSample)) {
        haveNext = true;
      } else {
        haveNext = false;
      }

      printAck();
    }

    // Interpolated updates between current and next
    if (haveNext) {
      if (nowRel - lastInterpUpdate >= INTERP_UPDATE_MS) {
        lastInterpUpdate = nowRel;
        writeInterpolatedPose(currentSample, nextSample, nowRel);
      }
    } else {
      // no next point, hold exact current pose
      writeServoPoseFromSigned(currentSample.bottom, currentSample.mid, currentSample.top,
                               currentSample.elbow, currentSample.wrist);
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