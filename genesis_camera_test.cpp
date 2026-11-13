#include <Arduino.h>

// Pin definitions (Connect through a 3.3V-to-5V level shifter if not 5V tolerant)
const int PIN_D0 = 2; // Genesis Port 2 Pin 1 (Up)
const int PIN_D1 = 3; // Genesis Port 2 Pin 2 (Down)
const int PIN_D2 = 4; // Genesis Port 2 Pin 3 (Left)
const int PIN_D3 = 5; // Genesis Port 2 Pin 4 (Right)
const int PIN_TL = 6; // Genesis Port 2 Pin 6 (Button B - Frame Ready Flag)
const int PIN_TH = 7; // Genesis Port 2 Pin 7 (Select - Clock from Genesis)

// 128x128 pixels at 4bpp = 16x16 tiles = 256 tiles * 32 bytes = 8,192 bytes
const int TOTAL_BYTES = 8192;

void setup() {
  pinMode(PIN_D0, OUTPUT);
  pinMode(PIN_D1, OUTPUT);
  pinMode(PIN_D2, OUTPUT);
  pinMode(PIN_D3, OUTPUT);
  pinMode(PIN_TL, OUTPUT);
  pinMode(PIN_TH, INPUT);

  digitalWrite(PIN_TL, HIGH); // Idle HIGH (not ready)
}

void writeNibble(uint8_t nibble) {
  digitalWrite(PIN_D0, (nibble >> 0) & 1);
  digitalWrite(PIN_D1, (nibble >> 1) & 1);
  digitalWrite(PIN_D2, (nibble >> 2) & 1);
  digitalWrite(PIN_D3, (nibble >> 3) & 1);
}

void loop() {
  // 1. Signal to Genesis that a frame is ready by pulling TL LOW
  digitalWrite(PIN_TL, LOW);

  // 2. Stream 8,192 bytes (16,384 nibbles) synced to TH transitions
  for (int i = 0; i < TOTAL_BYTES; i++) {
    // Generate a moving test pattern (0..15 color indices)
    uint8_t color1 = ((i / 32) + (millis() / 200)) & 0x0F;
    uint8_t color2 = (color1 + 1) & 0x0F;

    // Wait for Genesis to pull TH LOW for Upper Nibble
    while (digitalRead(PIN_TH) == HIGH) {}
    writeNibble(color1);

    // Wait for Genesis to pull TH HIGH for Lower Nibble
    while (digitalRead(PIN_TH) == LOW) {}
    writeNibble(color2);
  }

  // 3. Frame complete: return TL HIGH and pause briefly
  digitalWrite(PIN_TL, HIGH);
  delay(50);
}
