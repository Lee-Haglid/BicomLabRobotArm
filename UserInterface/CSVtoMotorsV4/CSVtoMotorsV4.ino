#include <Servo.h>
#include <string.h>
#include <stdio.h>

Servo s1, s2, s3;

const int servo1 = 9;
const int servo2 = 10;
const int servo3 = 11;
const int SERVO_OFFSET = 90;

const int BUF_SIZE = 24;

struct Sample {
  uint32_t t_ms;
  int8_t a1;
  int8_t a2;
  int8_t a3;
};

Sample buf[BUF_SIZE];
volatile int head = 0;
volatile int tail = 0;
volatile int count = 0;

bool started = false;
bool endReceived = false;
bool playingAnnounced = false;
uint32_t tStart = 0;

bool readLine(char* out, size_t maxLen) {
  static size_t pos = 0;
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      out[pos] = '\0';
      pos = 0;
      return true;
    }
    if (pos < maxLen - 1) out[pos++] = c;
  }
  return false;
}

void printBufCount() {
  Serial.print(F("BUF "));
  Serial.println(count);
}

bool pushSample(uint32_t t, int a1, int a2, int a3) {
  if (count >= BUF_SIZE) return false;
  buf[tail].t_ms = t;
  buf[tail].a1 = (int8_t)constrain(a1, -90, 90);
  buf[tail].a2 = (int8_t)constrain(a2, -90, 90);
  buf[tail].a3 = (int8_t)constrain(a3, -90, 90);
  tail = (tail + 1) % BUF_SIZE;
  count++;
  return true;
}

bool peekSample(Sample &s) {
  if (count <= 0) return false;
  s = buf[head];
  return true;
}

bool popSample(Sample &s) {
  if (count <= 0) return false;
  s = buf[head];
  head = (head + 1) % BUF_SIZE;
  count--;
  return true;
}

void resetStream() {
  head = 0;
  tail = 0;
  count = 0;
  started = false;
  endReceived = false;
  playingAnnounced = false;
  tStart = 0;
}

void setup() {
  Serial.begin(115200);

  s1.attach(servo1, 1000, 2000);
  s2.attach(servo2, 1000, 2000);
  s3.attach(servo3, 1000, 2000);

  s1.write(90);
  s2.write(90);
  s3.write(90);
  delay(300);

  Serial.println(F("READY"));
  printBufCount();
}

void loop() {
  static char line[64];

  while (readLine(line, sizeof(line))) {
    if (strcmp(line, "START") == 0) {
      resetStream();
      Serial.println(F("READY"));
      printBufCount();
      continue;
    }

    if (strcmp(line, "END") == 0) {
      endReceived = true;
      Serial.println(F("END-ACK"));
      printBufCount();
      continue;
    }

    if (strcmp(line, "STOP") == 0) {
      resetStream();
      Serial.println(F("STOPPED"));
      printBufCount();
      continue;
    }

    if (strcmp(line, "ZERO") == 0) {
      s1.write(90);
      s2.write(90);
      s3.write(90);
      Serial.println(F("rpy: 90 90 90"));
      printBufCount();
      continue;
    }

    uint32_t t;
    int a1, a2, a3;
    if (sscanf(line, "%lu,%d,%d,%d", &t, &a1, &a2, &a3) == 4) {
      if (pushSample(t, a1, a2, a3)) {
        printBufCount();
      } else {
        Serial.println(F("ERR: BUF_FULL"));
        printBufCount();
      }
    } else {
      Serial.println(F("ERR: BAD_LINE"));
      printBufCount();
    }
  }

  if (count > 0) {
    Sample s;
    if (peekSample(s)) {
      if (!started) {
        tStart = millis();
        started = true;
      }

      uint32_t now = millis() - tStart;
      if (now >= s.t_ms) {
        popSample(s);

        int pos1 = constrain((int)s.a1 + SERVO_OFFSET, 0, 180);
        int pos2 = constrain((int)s.a2 + SERVO_OFFSET, 0, 180);
        int pos3 = constrain((int)s.a3 + SERVO_OFFSET, 0, 180);

        s1.write(pos1);
        s2.write(pos2);
        s3.write(pos3);

        if (!playingAnnounced) {
          Serial.println(F("PLAYING"));
          playingAnnounced = true;
        }

        Serial.print(F("rpy: "));
        Serial.print(pos1);
        Serial.print(' ');
        Serial.print(pos2);
        Serial.print(' ');
        Serial.println(pos3);

        printBufCount();
      }
    }
  }

  if (endReceived && count == 0 && started) {
    Serial.println(F("DONE"));
    resetStream();
    printBufCount();
  }
}