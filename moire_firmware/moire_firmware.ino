#include "TimerOne.h"
#include "EEPROM.h"


// - - - - - - - - - - - - - - - - - - 
//      CONFIG
// - - - - - - - - - - - - - - - - - - 

#define DEBUG 0
#define BAUDRATE 256000    // this does not matter in the leonardo
#define SAMPLERATE 1200    // 2600 -> ksmps=16   1300 -> ksmps=32 (@44100Hz)   1800 -> ksmps=24
#define FASTADC 0
#define DEBUG_DATARATE 1
#define PIN_FADER1 A5
#define PIN_PEDAL1 A4
#define PIN_BUTTON1 2
#define PIN_LED1 3
#define PIN_DEBUG 13
#define CTRLRATE 16
#define PEDAL_MARGIN 4
#define FADER_MARGIN 2
#define TOUCHED_THRESH 40
byte enabled_pins[] = {A0, A1};

//  ----------------- END CONFIG ----------------------

// defines for setting and clearing register bits
#ifndef cbi
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#endif
#ifndef sbi
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))
#endif

#define DATABLOCK 128
#define CONTROLBLOCK 140
#define EEPROM_EMPTY16 65535  // Uninitialized slot
#define ADDR0 0

#define SERIALPRINT3(A, B, C) Serial.print(A); Serial.print(" "); Serial.print(B); Serial.print(" "); Serial.println(C);

// Define various ADC prescaler
const unsigned char PS_16 = (1 << ADPS2);
const unsigned char PS_32 = (1 << ADPS2) | (1 << ADPS0);
const unsigned char PS_64 = (1 << ADPS2) | (1 << ADPS1);
const unsigned char PS_128 = (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0);

// int fadertable[] = { 27, 51, 99, 166, 355, 551, 980, 980 };      // log slider : measured every 10mm
int fadertable[] = { 0, 11, 28, 43, 65, 98, 180, 399, 646, 882, 1022, 1022};
const int fadertable_size = sizeof(fadertable) / sizeof(int);

const int numpins = sizeof(enabled_pins) / sizeof(byte);

unsigned int pedal1_last = 200, 
  pedal1_min  = 200, 
  pedal1_max  = 900, 
  fader1_last = 200, 
  fader1_min  = 200, 
  fader1_max  = 900;

float pedal1_scale, fader1_scale;

unsigned long but1_pressedtime = 0;
unsigned long last_loop = 0;
bool calibrating = false;

#if !DEBUG
const int ctrl_period_ms = (1000/CTRLRATE);
#else
const int ctrl_period_ms = (1000/20);
#endif

// ------------- HELPERS ---------------------

unsigned long int freq2timer(int freq) {
  float period = 1.0/freq;
  unsigned long int microseconds = period * 1000 * 1000;
  return microseconds;
}

float fader_linearize(int x) {
  int x1, 
    x0 = fadertable[0],
    maxindex = fadertable_size - 1;
  if( x <= x0) {
    return 0.0;
  }
  else if( x >= fadertable[maxindex]) {
    return 1.0;
  };
  float f;
  for (int i=0; i < maxindex; i++) {
    x1 = fadertable[i+1];
    if( x >= x0 && x <= x1 ) {
      f = (x-x0) / float((x1-x0));
      f = (i + f)/float(maxindex);
      return f;
    }
    x0 = x1;
  }
}

// ------------------ INTERRUPT ----------------------

void read_sample() {
  int value, pin;
  if( calibrating ) {
    return;
  }
#if !DEBUG
  Serial.write(DATABLOCK + numpins);    
  value = analogRead(A0);
  Serial.write(value >> 7);
  Serial.write(value & 0b1111111);
  value = analogRead(A1);
  Serial.write(value >> 7);
  Serial.write(value & 0b1111111);
#else
  for(int i=0; i < numpins; i++) {
    pin = enabled_pins[i];
    value = analogRead(pin);
    Serial.print("A");
    Serial.print(i);
    Serial.print(": ");
    Serial.println(value);
  }    
#endif
}

// ----------------- EEPROM ----------------------
unsigned eeprom_write_uint(unsigned addr, unsigned value) {
  EEPROM.write(ADDR0 + addr, value >> 8);
  EEPROM.write(ADDR0 + addr+1, value & 0b11111111);   
}

unsigned eeprom_read_uint(unsigned addr, unsigned setdefault, unsigned minimum=0, unsigned maximum=65534) {
  int hi = EEPROM.read(ADDR0 + addr);
  int lo = EEPROM.read(ADDR0 + addr + 1);
  unsigned value = (hi << 8) + lo;
  if(value == EEPROM_EMPTY16 || (value < minimum) || (value > maximum)) {
    value = setdefault;
    eeprom_write_uint(addr, value);
  }
  return value;
}

void save_state() {
  int addr = ADDR0;
  eeprom_write_uint(addr, pedal1_min);
  eeprom_write_uint(addr+2, pedal1_max);
  pedal1_scale = 1023.0 / (pedal1_max - pedal1_min);
  eeprom_write_uint(addr+4, fader1_min);
  eeprom_write_uint(addr+6, fader1_max);
  fader1_scale = 1023.0 / (fader1_max - fader1_min);
}

void load_state() {
  int addr = ADDR0;
  pedal1_min = eeprom_read_uint(addr, 200, 0, 1023);
  pedal1_max = eeprom_read_uint(addr+2, 900, 0, 1023);
  fader1_min = eeprom_read_uint(addr+4, 200, 0, 1023);
  fader1_max = eeprom_read_uint(addr+6, 900, 0, 1023);
  pedal1_scale = 1023.0 /(pedal1_max - pedal1_min);
  fader1_scale = 1023.0 /(fader1_max - fader1_min);
}

// -----------------------------------------------
//                   SETUP

void setup() {
  pinMode(PIN_LED1, OUTPUT);
  pinMode(PIN_BUTTON1, INPUT_PULLUP);
  load_state();
  
  Serial.begin(BAUDRATE);
  while(!Serial) {};
#if !DEBUG
  long int update_period_microsec = freq2timer(SAMPLERATE);
#else
  long int update_period_microsec = freq2timer(DEBUG_DATARATE);
#endif
  
  ADCSRA &= ~PS_128;  // remove bits set by Arduino library  
  // you can choose a prescaler from above.
  // PS_16, PS_32, PS_64 or PS_128
  ADCSRA |= PS_32;    // set our own prescaler to 64 
  
  Timer1.initialize(update_period_microsec);
  Timer1.attachInterrupt( read_sample );

  pinMode(PIN_DEBUG, OUTPUT);    
#if !DEBUG
  digitalWrite(PIN_DEBUG, HIGH);
#else
  digitalWrite(PIN_DEBUG, LOW);
#endif
}

void loop() {
  int fader1, pedal1, but1=0;
  int static but1_last;
  int static fader1_precalib, pedal1_precalib;
    
  /*
  unsigned long now = millis();
  if( now - last_loop < ctrl_period_ms ) {
    return;
  }
  */

#if DEBUG
  int static led_debug_status = 0;
  led_debug_status = 1-led_debug_status;
  digitalWrite(PIN_DEBUG, led_debug_status);
#endif

  //last_loop = now;
  noInterrupts();
  pedal1 = analogRead(PIN_PEDAL1);
  fader1 = analogRead(PIN_FADER1);
  interrupts();
  
  fader1 = fader_linearize(fader1) * 1023;
  //fader1 = (fader1 + fader1_last) / 2;
  fader1 = int(fader1*0.66 + fader1_last*0.34);
  fader1_last = fader1;
  //pedal1 = int(pedal1*0.8 + pedal1_last*0.2);
  pedal1 >>= 2; // drop 2 bits of resolution
  pedal1 <<= 2;
  pedal1_last = pedal1;
  
  but1 = 1 - digitalRead(PIN_BUTTON1);
  
  if( but1 == 0 && but1_last) {
    if( !calibrating) {
      calibrating = true;
      fader1_precalib = fader1;
      pedal1_precalib = pedal1;
      digitalWrite(PIN_LED1, HIGH); // this turns ON the LED
#if DEBUG
      Serial.println("CALIBRATING!");    
#endif
    } else {
      digitalWrite(PIN_LED1, LOW);
      save_state();
      calibrating = false;
#if DEBUG
      Serial.println("Stopped calibrating");
#endif
    }
  } 
  but1_last = but1;
  
  // NORMALIZATION
  if ( !calibrating ) {
    fader1 = constrain(fader1, fader1_min, fader1_max);
    pedal1 = constrain(pedal1, pedal1_min, pedal1_max);
    fader1 = (fader1 - fader1_min) * fader1_scale;
    pedal1 = (pedal1 - pedal1_min) * pedal1_scale;
#if DEBUG
    SERIALPRINT3("Fader1 MIN MAX", fader1_min, fader1_max);
    SERIALPRINT3("Pedal1 MIN MAX", pedal1_min, pedal1_max);
#endif
  } 
  else { // CALIBRATION
    // Has it moved yet? No -> adjust extremes
    if ( fader1_precalib < 0) {
      if( fader1 < fader1_min) {
        fader1_min = fader1 + FADER_MARGIN;
      } else if ( fader1 > fader1_max) {
        fader1_max = fader1 - FADER_MARGIN;
      }
    } else if ( abs(fader1 - fader1_precalib) > TOUCHED_THRESH ) {
      fader1_min = min(fader1, fader1_precalib);
      fader1_max = max(fader1, fader1_precalib);
      fader1_precalib = -1023;  // this indicates that it was moved
    }
    
    if( pedal1_precalib < 0) {
      if( pedal1 < pedal1_min) {
        pedal1_min = pedal1 + PEDAL_MARGIN;
      } else if ( pedal1 > pedal1_max) {
        pedal1_max = pedal1 - PEDAL_MARGIN;
      }            
    } else if ( abs(pedal1 - pedal1_precalib) > TOUCHED_THRESH) {   
      pedal1_min = min(pedal1, pedal1_precalib);
      pedal1_max = max(pedal1, pedal1_precalib);
      pedal1_precalib = -1023;
    } 
    
#if DEBUG
    SERIALPRINT3("CALIBRATING --> Fader1 min-max:", fader1_min, fader1_max);
    SERIALPRINT3("                Pedal1 min-max:", pedal1_min, pedal1_max);
#endif
  }
  
  noInterrupts();  // <--- A control block cannot be interrupted by a data block
#if !DEBUG
  // PROTOCOL: 1 byte | fader1:uint16 | pedal1:utin16
  Serial.write(CONTROLBLOCK);
  Serial.write(fader1 >> 7);
  Serial.write(fader1 & 0b1111111);
  Serial.write(pedal1 >> 7);
  Serial.write(pedal1 & 0b1111111);
#else
  // DEBUG
  if( !calibrating ) {
    Serial.print("fader1: ");
    Serial.println(fader1);
    Serial.print("pedal1: ");
    Serial.println(pedal1);
  }
#endif
  interrupts(); 
  delay(ctrl_period_ms);
  
}
