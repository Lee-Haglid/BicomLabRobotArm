#include <Arduino.h>
#include <SCServo.h>

SMS_STS st;

#define SERVO_RX 16
#define SERVO_TX 17

const int OLD_ID = 1;
const int NEW_ID = 5;

void setup() {

  Serial.begin(115200);

  Serial2.begin(1000000, SERIAL_8N1, SERVO_RX, SERVO_TX);

  st.pSerial = &Serial2;

  delay(1000);

  Serial.println("Changing servo ID...");

  int result = st.unLockEprom(OLD_ID);

  Serial.print("Unlock result: ");
  Serial.println(result);

  delay(100);

  result = st.writeByte(OLD_ID, SMS_STS_ID, NEW_ID);

  Serial.print("Write result: ");
  Serial.println(result);

  delay(100);

  st.LockEprom(NEW_ID);

  Serial.println("Done.");
}

void loop() {

}