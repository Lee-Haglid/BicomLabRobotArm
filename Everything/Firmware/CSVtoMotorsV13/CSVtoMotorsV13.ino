#include <Servo.h>
#include <SPI.h>
#include <Wire.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

Servo sBottom, sMid, sTop, sElbow, sWrist;

// Servo pins
const int pinBottom = 9;
const int pinMid    = 7;   // DO NOT use 10. Pin 10 is SPI SS.
const int pinTop    = 6;
const int pinElbow  = 3;
const int pinWrist  = 5;

// UNO hardware SPI
const int PUMP_SS_PIN = 10;

const int SERVO_OFFSET = 90;
const int BUF_SIZE = 24;
const uint32_t INTERP_UPDATE_MS = 5;
const uint32_t DEBUG_PRINT_MS = 100;

// IMU settings
#define MPU_ADDR 0x68

const float ACCEL_SCALE = 16384.0;
const float GYRO_SCALE  = 131.0;

const float COMP_ALPHA = 0.96;
const float ACCEL_LPF = 0.15;
const float GYRO_DEADBAND = 0.20;

bool imuLogging = false;
uint32_t imuStartMs = 0;
uint32_t lastImuMs = 0;
const uint32_t IMU_SAMPLE_MS = 20;

float gyroBiasX = 0;
float gyroBiasY = 0;
float gyroBiasZ = 0;

float roll = 0;
float pitch = 0;
float yaw = 0;

float axFilt = 0;
float ayFilt = 0;
float azFilt = 0;

uint32_t lastImuMicros = 0;

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
uint32_t lastDebugPrint = 0;

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

    if (c == '\r') {
      continue;
    }

    if (c == '\n') {
      buf[pos] = '\0';

      if (pos == 0) {
        return false;
      }

      pos = 0;
      return true;
    }

    if (pos < buflen - 1) {
      buf[pos++] = c;
    }
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
  lastDebugPrint = 0;
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

void sendHeartRateSPI(uint8_t bpm) {
  digitalWrite(PUMP_SS_PIN, LOW);
  SPI.transfer(0xA5);
  SPI.transfer(bpm);
  digitalWrite(PUMP_SS_PIN, HIGH);
}

// =========================
// IMU FUNCTIONS
// =========================

void imuWriteReg(uint8_t reg, uint8_t val) {
  Wire.beginTransmission((uint8_t)MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

int16_t imuRead16(uint8_t reg) {
  Wire.beginTransmission((uint8_t)MPU_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);

  Wire.requestFrom((uint8_t)MPU_ADDR, (uint8_t)2);

  if (Wire.available() < 2) {
    return 0;
  }

  uint8_t high = Wire.read();
  uint8_t low = Wire.read();

  return (int16_t)((high << 8) | low);
}

void calibrateIMUGyro() {
  long sumGX = 0;
  long sumGY = 0;
  long sumGZ = 0;

  Serial.println(F("IMU-CALIBRATING"));

  for (int i = 0; i < 1000; i++) {
    sumGX += imuRead16(0x43);
    sumGY += imuRead16(0x45);
    sumGZ += imuRead16(0x47);
    delay(2);
  }

  gyroBiasX = sumGX / 1000.0;
  gyroBiasY = sumGY / 1000.0;
  gyroBiasZ = sumGZ / 1000.0;

  Serial.println(F("IMU-CAL-DONE"));
}

void setupIMU() {
  Wire.begin();
  Wire.setClock(100000);

  imuWriteReg(0x6B, 0x00);
  delay(100);

  // Accel range +/-2g
  imuWriteReg(0x1C, 0x00);

  // Gyro range +/-250 deg/s
  imuWriteReg(0x1B, 0x00);

  calibrateIMUGyro();

  int16_t axRaw = imuRead16(0x3B);
  int16_t ayRaw = imuRead16(0x3D);
  int16_t azRaw = imuRead16(0x3F);

  axFilt = axRaw / ACCEL_SCALE;
  ayFilt = ayRaw / ACCEL_SCALE;
  azFilt = azRaw / ACCEL_SCALE;

  roll = atan2(ayFilt, azFilt) * 180.0 / PI;
  pitch = atan2(-axFilt, sqrt(ayFilt * ayFilt + azFilt * azFilt)) * 180.0 / PI;
  yaw = 0;

  lastImuMicros = micros();
}

void updateAndPrintIMU() {
  int16_t axRaw = imuRead16(0x3B);
  int16_t ayRaw = imuRead16(0x3D);
  int16_t azRaw = imuRead16(0x3F);

  int16_t gxRaw = imuRead16(0x43);
  int16_t gyRaw = imuRead16(0x45);
  int16_t gzRaw = imuRead16(0x47);

  uint32_t now = micros();
  float dt = (now - lastImuMicros) / 1000000.0;
  lastImuMicros = now;

  float ax = axRaw / ACCEL_SCALE;
  float ay = ayRaw / ACCEL_SCALE;
  float az = azRaw / ACCEL_SCALE;

  axFilt = axFilt + ACCEL_LPF * (ax - axFilt);
  ayFilt = ayFilt + ACCEL_LPF * (ay - ayFilt);
  azFilt = azFilt + ACCEL_LPF * (az - azFilt);

  float gx = (gxRaw - gyroBiasX) / GYRO_SCALE;
  float gy = (gyRaw - gyroBiasY) / GYRO_SCALE;
  float gz = (gzRaw - gyroBiasZ) / GYRO_SCALE;

  if (abs(gx) < GYRO_DEADBAND) gx = 0;
  if (abs(gy) < GYRO_DEADBAND) gy = 0;
  if (abs(gz) < GYRO_DEADBAND) gz = 0;

  float accelRoll = atan2(ayFilt, azFilt) * 180.0 / PI;
  float accelPitch = atan2(-axFilt, sqrt(ayFilt * ayFilt + azFilt * azFilt)) * 180.0 / PI;

  roll = COMP_ALPHA * (roll + gx * dt) + (1.0 - COMP_ALPHA) * accelRoll;
  pitch = COMP_ALPHA * (pitch + gy * dt) + (1.0 - COMP_ALPHA) * accelPitch;

  // No magnetometer, so yaw is gyro-only and will drift.
  yaw += gz * dt;

  uint32_t tMs = millis() - imuStartMs;

  Serial.print(F("IMU,"));
  Serial.print(tMs);
  Serial.print(',');
  Serial.print(roll, 2);
  Serial.print(',');
  Serial.print(pitch, 2);
  Serial.print(',');
  Serial.print(yaw, 2);
  Serial.print(',');
  Serial.print(gx, 3);
  Serial.print(',');
  Serial.print(gy, 3);
  Serial.print(',');
  Serial.print(gz, 3);
  Serial.print(',');
  Serial.print(axFilt, 4);
  Serial.print(',');
  Serial.print(ayFilt, 4);
  Serial.print(',');
  Serial.println(azFilt, 4);
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

  setupIMU();

  sendHeartRateSPI(heartRateBpm);

  Serial.println(F("READY"));
  printAck();
}

void loop() {
  static char line[96];

  while (readLine(line, sizeof(line))) {
    if (strlen(line) == 0) {
      continue;
    }

    if (strncmp(line, "HR ", 3) == 0) {
      int bpm = atoi(line + 3);
      bpm = constrain(bpm, 1, 240);
      heartRateBpm = (uint8_t)bpm;
      sendHeartRateSPI(heartRateBpm);
      Serial.print(F("HR-SET "));
      Serial.println(heartRateBpm);
      continue;
    }

    if (strcmp(line, "IMU_START") == 0) {
      imuLogging = true;
      imuStartMs = millis();
      lastImuMs = millis();
      lastImuMicros = micros();
      Serial.println(F("IMU-STARTED"));
      updateAndPrintIMU();
      continue;
    }

    if (strcmp(line, "IMU_STOP") == 0) {
      imuLogging = false;
      Serial.println(F("IMU-STOPPED"));
      continue;
    }

    if (strcmp(line, "START") == 0) {
      clearQueue();
      streamingActive = true;
      sendHeartRateSPI(heartRateBpm);
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
      Serial.print(F("ERR: BAD_LINE "));
      Serial.println(line);
      printAck();
    }
  }

  if (imuLogging && millis() - lastImuMs >= IMU_SAMPLE_MS) {
    lastImuMs = millis();
    updateAndPrintIMU();
  }

  if (!streamingActive) {
    return;
  }

  if (!playbackStarted && qCount >= 2) {
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
      lastDebugPrint = 0;
      playbackStarted = true;

      Serial.println(F("PLAYING"));

      writeServoPoseFromSigned(
        currentSample.bottom,
        currentSample.mid,
        currentSample.top,
        currentSample.elbow,
        currentSample.wrist
      );

      printPose();
      printAck();
    }
  }

  if (playbackStarted && haveCurrent) {
    uint32_t nowRel = (millis() - playStartMillis) + firstSampleTms;

    while (haveNext && nowRel >= nextSample.t_ms) {
      dequeueSample(currentSample);

      if (peekSample(nextSample)) {
        haveNext = true;
      } else {
        haveNext = false;
      }

      printAck();
    }

    if (!haveNext && qCount > 0) {
      if (peekSample(nextSample)) {
        haveNext = true;
      }
    }

    if (haveNext) {
      if (nowRel - lastInterpUpdate >= INTERP_UPDATE_MS) {
        lastInterpUpdate = nowRel;
        writeInterpolatedPose(currentSample, nextSample, nowRel);
      }
    } else {
      writeServoPoseFromSigned(
        currentSample.bottom,
        currentSample.mid,
        currentSample.top,
        currentSample.elbow,
        currentSample.wrist
      );
    }

    if (nowRel - lastDebugPrint >= DEBUG_PRINT_MS) {
      lastDebugPrint = nowRel;
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