#include <Arduino.h>
#include <SCServo.h>
#include <SD.h>
#include <SPI.h>
#include <Wire.h>
#include <math.h>

SMS_STS st;

#define SERVO_SERIAL Serial1

const int PUMP_CS_PIN = 10;

const int ID_BOTTOM = 3;
const int ID_MID    = 2;
const int ID_TOP    = 1;
const int ID_ELBOW  = 4;
const int ID_WRIST  = 5;

const int STS_MIN_POS = 0;
const int STS_MAX_POS = 4096;
const int STS_SPEED = 3500;
const int STS_ACCEL = 400;

// Motor angle offsets in degrees.
// Positive values add to the commanded angle before converting to STS position.
const float OFFSET_BOTTOM = -30.0f;
const float OFFSET_MID    = -30.0f;
const float OFFSET_TOP    = -20.0f;
const float OFFSET_ELBOW  = 3.0f;
const float OFFSET_WRIST  = 0.0f;

const char *CSV_FILE = "traj.csv";
const uint32_t INTERP_UPDATE_US = 5000;

File trajFile;
File uploadFile;
bool uploadingFile = false;

struct Sample {
  uint32_t t_ms;
  float bottom;
  float mid;
  float top;
  float elbow;
  float wrist;
};

Sample currentSample, nextSample;

bool haveCurrent = false;
bool haveNext = false;
bool playing = false;

uint32_t playStartUs = 0;
uint32_t firstSampleMs = 0;
uint32_t lastInterpUs = 0;

uint8_t heartRateBpm = 72;

// IMU
#define MPU_ADDR 0x68

const float ACCEL_SCALE = 16384.0;
const float GYRO_SCALE = 131.0;
const float COMP_ALPHA = 0.96;
const float ACCEL_LPF = 0.15;
const float GYRO_DEADBAND = 0.20;

bool imuLogging = false;
uint32_t imuStartMs = 0;
uint32_t lastImuMs = 0;
uint32_t lastImuMicros = 0;
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

float signedDegToSTSPos(float deg) {
  deg = constrain(deg, -180.0f, 180.0f);
  float absoluteDeg = deg + 180.0f;
  float pos = (absoluteDeg * 4096.0f / 360.0f);
  return constrain(pos, STS_MIN_POS, STS_MAX_POS);
}

float lerpInt(float a, float b, float alpha) {
  return (1.0f - alpha) * a + alpha * b;
}

void writeServoPoseFromSigned(float bottom, float mid, float top, float elbow, float wrist) {

  bottom = constrain(bottom + OFFSET_BOTTOM, -180, 180);
  mid    = constrain(mid    + OFFSET_MID,    -180, 180);
  top    = constrain(top    + OFFSET_TOP,    -180, 180);
  elbow  = constrain(elbow  + OFFSET_ELBOW,  -180, 180);
  wrist  = constrain(wrist  + OFFSET_WRIST,  -180, 180);

  float bottomPos = signedDegToSTSPos(bottom);
  float midPos    = signedDegToSTSPos(mid);
  float topPos    = signedDegToSTSPos(top);
  float elbowPos  = signedDegToSTSPos(elbow);
  float wristPos  = signedDegToSTSPos(wrist);

  static uint32_t lastPrintMs = 0;

  if (millis() - lastPrintMs >= 100) {

    lastPrintMs = millis();

    Serial.print("POS ");
    Serial.print(bottomPos);
    Serial.print(" ");
    Serial.print(midPos);
    Serial.print(" ");
    Serial.print(topPos);
    Serial.print(" ");
    Serial.print(elbowPos);
    Serial.print(" ");
    Serial.println(wristPos);
  }

  st.WritePosEx(ID_BOTTOM, bottomPos, STS_SPEED, STS_ACCEL);
  st.WritePosEx(ID_MID,    midPos,    STS_SPEED, STS_ACCEL);
  st.WritePosEx(ID_TOP,    topPos,    STS_SPEED, STS_ACCEL);
  st.WritePosEx(ID_ELBOW,  elbowPos,  STS_SPEED, STS_ACCEL);
  st.WritePosEx(ID_WRIST,  wristPos,  STS_SPEED, STS_ACCEL);
}

void writeZeroPose() {
  writeServoPoseFromSigned(0, 0, 0, 0, 0);
}

void writeInterpolatedPose(const Sample &a, const Sample &b, uint32_t nowRelMs) {
  float alpha;

  if (b.t_ms <= a.t_ms) {
    alpha = 1.0f;
  } else {
    alpha = (float)(nowRelMs - a.t_ms) / (float)(b.t_ms - a.t_ms);
    alpha = constrain(alpha, 0.0f, 1.0f);
  }

  writeServoPoseFromSigned(
    lerpInt(a.bottom, b.bottom, alpha),
    lerpInt(a.mid,    b.mid,    alpha),
    lerpInt(a.top,    b.top,    alpha),
    lerpInt(a.elbow,  b.elbow,  alpha),
    lerpInt(a.wrist,  b.wrist,  alpha)
  );
}

bool readNextSample(File &f, Sample &s) {
  static char line[128];

  while (f.available()) {
    int len = f.readBytesUntil('\n', line, sizeof(line) - 1);
    line[len] = '\0';

    if (len <= 1) continue;

    if (strstr(line, "time") || strstr(line, "Time")) {
      continue;
    }

    uint32_t t;
    float b, m, top, e, w;

    int matched = sscanf(line, "%lu,%f,%f,%f,%f,%f", &t, &b, &m, &top, &e, &w);

    if (matched == 6) {
      s.t_ms = t;
      s.bottom = constrain(b, -180, 180);
      s.mid = constrain(m, -180, 180);
      s.top = constrain(top, -180, 180);
      s.elbow = constrain(e, -180, 180);
      s.wrist = constrain(w, -180, 180);
      return true;
    }
  }

  return false;
}

void sendHeartRateSPI(uint8_t bpm) {
  SPI.beginTransaction(SPISettings(100000, MSBFIRST, SPI_MODE0));

  digitalWrite(PUMP_CS_PIN, LOW);
  delayMicroseconds(10);

  SPI.transfer(0xA5);
  delayMicroseconds(10);
  SPI.transfer(bpm);

  delayMicroseconds(10);
  digitalWrite(PUMP_CS_PIN, HIGH);

  SPI.endTransaction();
}

void startPlayback() {
  if (trajFile) trajFile.close();

  trajFile = SD.open(CSV_FILE, FILE_READ);

  if (!trajFile) {
    Serial.println("ERR: Could not open traj.csv");
    return;
  }

  haveCurrent = readNextSample(trajFile, currentSample);
  haveNext = readNextSample(trajFile, nextSample);

  if (!haveCurrent) {
    Serial.println("ERR: No samples in file");
    trajFile.close();
    return;
  }

  firstSampleMs = currentSample.t_ms;
  playStartUs = micros();
  lastInterpUs = 0;
  playing = true;

  writeServoPoseFromSigned(
    currentSample.bottom,
    currentSample.mid,
    currentSample.top,
    currentSample.elbow,
    currentSample.wrist
  );

  Serial.println("PLAYING");
}

void stopPlayback() {
  playing = false;

  if (trajFile) trajFile.close();

  Serial.println("STOPPED");
}

void updatePlayback() {
  if (!playing) return;

  uint32_t elapsedMs = (micros() - playStartUs) / 1000;
  uint32_t nowRelMs = firstSampleMs + elapsedMs;

  while (haveNext && nowRelMs >= nextSample.t_ms) {
    currentSample = nextSample;
    haveNext = readNextSample(trajFile, nextSample);
  }

  if (micros() - lastInterpUs >= INTERP_UPDATE_US) {
    lastInterpUs = micros();

    if (haveNext) {
      writeInterpolatedPose(currentSample, nextSample, nowRelMs);
    } else {
      writeServoPoseFromSigned(
        currentSample.bottom,
        currentSample.mid,
        currentSample.top,
        currentSample.elbow,
        currentSample.wrist
      );

      playing = false;
      if (trajFile) trajFile.close();
      Serial.println("DONE");
    }
  }
}

// IMU FUNCTIONS

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

  if (Wire.available() < 2) return 0;

  uint8_t high = Wire.read();
  uint8_t low = Wire.read();

  return (int16_t)((high << 8) | low);
}

void calibrateIMUGyro() {
  long sumGX = 0;
  long sumGY = 0;
  long sumGZ = 0;

  for (int i = 0; i < 1000; i++) {
    sumGX += imuRead16(0x43);
    sumGY += imuRead16(0x45);
    sumGZ += imuRead16(0x47);
    delay(2);
  }

  gyroBiasX = sumGX / 1000.0;
  gyroBiasY = sumGY / 1000.0;
  gyroBiasZ = sumGZ / 1000.0;
}

void setupIMU() {
  Wire.begin();
  Wire.setClock(100000);

  imuWriteReg(0x6B, 0x00);
  delay(100);

  imuWriteReg(0x1C, 0x00);
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
  yaw += gz * dt;

  uint32_t tMs = millis() - imuStartMs;

  Serial.print("IMU,");
  Serial.print(tMs);
  Serial.print(",");
  Serial.print(roll, 2);
  Serial.print(",");
  Serial.print(pitch, 2);
  Serial.print(",");
  Serial.print(yaw, 2);
  Serial.print(",");
  Serial.print(gx, 3);
  Serial.print(",");
  Serial.print(gy, 3);
  Serial.print(",");
  Serial.print(gz, 3);
  Serial.print(",");
  Serial.print(axFilt, 4);
  Serial.print(",");
  Serial.print(ayFilt, 4);
  Serial.print(",");
  Serial.println(azFilt, 4);
}

void handleUSBCommands() {
  if (!Serial.available()) return;

  String cmd = Serial.readStringUntil('\n');
  cmd.trim();

  if (uploadingFile) {
    if (cmd == "UPLOAD_END") {
      uploadFile.close();
      uploadingFile = false;
      Serial.println("UPLOAD-DONE");
      return;
    }

    uploadFile.println(cmd);
    Serial.println("UPLOAD-ACK");
    return;
  }

  if (cmd.startsWith("UPLOAD_BEGIN")) {
    if (trajFile) trajFile.close();

    SD.remove(CSV_FILE);

    uploadFile = SD.open(CSV_FILE, FILE_WRITE);

    if (!uploadFile) {
      Serial.println("ERR: UPLOAD OPEN FAILED");
      return;
    }

    uploadingFile = true;
    Serial.println("UPLOAD-READY");
    return;
  }

  if (cmd == "START") {
    startPlayback();
  } else if (cmd == "STOP") {
    stopPlayback();
  } else if (cmd == "ZERO") {
    writeZeroPose();
    Serial.println("ZEROED");
  } else if (cmd.startsWith("HR ")) {
    int bpm = cmd.substring(3).toInt();
    bpm = constrain(bpm, 1, 240);
    heartRateBpm = bpm;
    sendHeartRateSPI(heartRateBpm);

    Serial.print("HR-SET ");
    Serial.println(heartRateBpm);
  } else if (cmd == "IMU_START") {
    imuLogging = true;
    imuStartMs = millis();
    lastImuMs = millis();
    lastImuMicros = micros();
    Serial.println("IMU-STARTED");
  } else if (cmd == "IMU_STOP") {
    imuLogging = false;
    Serial.println("IMU-STOPPED");
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  SERVO_SERIAL.begin(1000000);
  st.pSerial = &SERVO_SERIAL;

  pinMode(PUMP_CS_PIN, OUTPUT);
  digitalWrite(PUMP_CS_PIN, HIGH);

  SPI.begin();

  if (!SD.begin(BUILTIN_SDCARD)) {
    Serial.println("ERR: SD init failed");
  } else {
    Serial.println("SD ready");
  }

  setupIMU();

  writeZeroPose();
  sendHeartRateSPI(heartRateBpm);

  Serial.println("READY");
}

void loop() {
  handleUSBCommands();

  if (imuLogging && millis() - lastImuMs >= IMU_SAMPLE_MS) {
    lastImuMs = millis();
    updateAndPrintIMU();
  }

  updatePlayback();
}