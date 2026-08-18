#include <SPI.h>

const int Motor = 4;

// If your relay turns ON when D4 is HIGH, keep these.
// If your relay is active LOW, swap these.
const int PUMP_ON  = HIGH;
const int PUMP_OFF = LOW;

volatile byte spiByte = 0;
volatile bool newByte = false;

byte heartRateBpm = 72;

int systole = 0;
int diastole = 0;

bool waitingForBpm = false;

void setup() {
  pinMode(Motor, OUTPUT);
  digitalWrite(Motor, PUMP_OFF);

  Serial.begin(9600);

  // UNO SPI s pins:
  // D10 = SS
  // D11 = MOSI
  // D12 = MISO
  // D13 = SCK
  pinMode(SS, INPUT);
  pinMode(MISO, OUTPUT);

  // Enable SPI s mode
  SPCR |= _BV(SPE);

  // Enable SPI interrupt
  SPI.attachInterrupt();

  updateTiming();

  Serial.println("Pump SPI s ready");
}

ISR(SPI_STC_vect) {
  spiByte = SPDR;
  newByte = true;
}

void loop() {
  handleSPI();

  if (heartRateBpm > 0) {
    digitalWrite(Motor, PUMP_ON);
    delayWithSPI(systole);

    digitalWrite(Motor, PUMP_OFF);
    delayWithSPI(diastole);
  } else {
    digitalWrite(Motor, PUMP_OFF);
    delayWithSPI(100);
  }
}

void delayWithSPI(int durationMs) {
  unsigned long startMs = millis();

  while (millis() - startMs < (unsigned long)durationMs) {
    handleSPI();
    delay(1);
  }
}

void handleSPI() {
  if (!newByte) return;

  noInterrupts();
  byte b = spiByte;
  newByte = false;
  interrupts();

  Serial.print("SPI byte received: ");
  Serial.println(b);

  // Ignore header if it appears
  if (b == 0xA5) {
    Serial.println("Header ignored");
    return;
  }

  // Treat any valid BPM byte directly as heart rate
  if (b >= 1 && b <= 240) {
    heartRateBpm = b;
    updateTiming();

    Serial.print("Received HR: ");
    Serial.println(heartRateBpm);
  }
}

void updateTiming() {
  float HR = (float)heartRateBpm;

  systole  = (int)((60.0 / HR) * 1000.0 * (3.0 / 8.0));
  diastole = (int)((60.0 / HR) * 1000.0 * (5.0 / 8.0));

  Serial.print("systole ms: ");
  Serial.println(systole);
  Serial.print("diastole ms: ");
  Serial.println(diastole);
}