#include <Wire.h>
#include <math.h>

#define MPU_ADDR 0x68

const float ACCEL_SCALE = 16384.0;
const float GYRO_SCALE = 131.0;

const float COMP_ALPHA = 0.96;
const float ACCEL_LPF = 0.15;
const float GYRO_DEADBAND = 0.20;

float gyroBiasX = 0;
float gyroBiasY = 0;
float gyroBiasZ = 0;

float roll = 0;
float pitch = 0;
float yaw = 0;

float axFilt = 0;
float ayFilt = 0;
float azFilt = 0;

unsigned long lastMicros;
unsigned long startMillis;

void writeReg(uint8_t reg, uint8_t val) {
  Wire.beginTransmission((uint8_t)MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

int16_t read16(uint8_t reg) {
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

void calibrateGyro() {
  long sumGX = 0;
  long sumGY = 0;
  long sumGZ = 0;

  Serial.println("Keep IMU still");

  for (int i = 0; i < 1500; i++) {
    sumGX += read16(0x43);
    sumGY += read16(0x45);
    sumGZ += read16(0x47);
    delay(2);
  }

  gyroBiasX = sumGX / 1500.0;
  gyroBiasY = sumGY / 1500.0;
  gyroBiasZ = sumGZ / 1500.0;

  Serial.println("Ready");
}

void setup() {
  Serial.begin(115200);

  Wire.begin();
  Wire.setClock(100000);

  delay(1000);

  writeReg(0x6B, 0x00);
  delay(100);

  writeReg(0x1C, 0x00);
  writeReg(0x1B, 0x00);

  calibrateGyro();

  int16_t axRaw = read16(0x3B);
  int16_t ayRaw = read16(0x3D);
  int16_t azRaw = read16(0x3F);

  axFilt = axRaw / ACCEL_SCALE;
  ayFilt = ayRaw / ACCEL_SCALE;
  azFilt = azRaw / ACCEL_SCALE;

  roll = atan2(ayFilt, azFilt) * 180.0 / PI;
  pitch = atan2(-axFilt, sqrt(ayFilt * ayFilt + azFilt * azFilt)) * 180.0 / PI;
  yaw = 0;

  lastMicros = micros();
  startMillis = millis();
}

void loop() {
  int16_t axRaw = read16(0x3B);
  int16_t ayRaw = read16(0x3D);
  int16_t azRaw = read16(0x3F);

  int16_t gxRaw = read16(0x43);
  int16_t gyRaw = read16(0x45);
  int16_t gzRaw = read16(0x47);

  unsigned long now = micros();
  float dt = (now - lastMicros) / 1000000.0;
  lastMicros = now;

  float t = (millis() - startMillis) / 1000.0;

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

  Serial.print(t, 3);
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

  delay(20);
}