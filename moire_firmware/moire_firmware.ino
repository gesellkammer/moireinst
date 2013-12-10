#include "TimerOne.h"
#include "EEPROM.h"


// - - - - - - - - - - - - - - - - - - 
//      CONFIG
// - - - - - - - - - - - - - - - - - - 

#define DEBUG 0
#define BAUDRATE 256000    // this does not matter in the leonardo
#define SAMPLERATE 1200    // 2600 -> ksmps=16   1300 -> ksmps=32 (@44100Hz)   1800 -> ksmps=24
#define CTRLRATE 18
#define HEARTBEATRATE 1

#define PIN_FADER1 A5
#define PIN_FADER2 A3
#define PIN_PEDAL1 A4
#define PIN_BUTTON1 8
#define PIN_BUTTON2 2
#define PIN_LED2 9
#define PIN_LED1 3
#define PIN_LIGHT1 13
#define PIN_DIP1 4
#define PIN_DIP2 7

#define PEDAL_MARGIN 4
#define FADER_MARGIN 2
#define TOUCHED_THRESH 40
#define LONG_PRESS_MILLIS 1500
#define BLINK_MILLIS 50

#define DEBUG_CTRLRATE 1
#define DEBUG_DATARATE 10

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
#define HEARTBEAT 200

#define EEPROM_EMPTY16 65535  // Uninitialized slot
#define ADDR0 0

#define SERIALPRINT2(A, B) Serial.print(A); Serial.print(" "); Serial.println(B);
#define SERIALPRINT3(A, B, C) Serial.print(A); Serial.print(" "); Serial.print(B); Serial.print(" "); Serial.println(C); 
#define SERIALPRINT5(A, B, C, D, E) Serial.print(A); Serial.print(" "); Serial.print(B); Serial.print(" "); Serial.print(C); Serial.print(" "); Serial.print(D); Serial.print(" "); Serial.println(E);
#define SERIALPRINT6(A, B, C, D, E, F) Serial.print(A); Serial.print(" "); Serial.print(B); Serial.print(" "); Serial.print(C); Serial.print(" "); Serial.print(D); Serial.print(" "); Serial.print(E); Serial.print(" "); Serial.println(F);

// Define various ADC prescaler
const unsigned char PS_16 = (1 << ADPS2);
const unsigned char PS_32 = (1 << ADPS2) | (1 << ADPS0);
const unsigned char PS_64 = (1 << ADPS2) | (1 << ADPS1);
const unsigned char PS_128 = (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0);

int fadertable[] = {0, 22, 43, 92, 184, 276, 490, 826, 1023};

const int fadertable_size = sizeof(fadertable) / sizeof(int);

unsigned int pedal1_last = 200, 
  pedal1_min  = 200, 
  pedal1_max  = 900, 
  fader1_last = 200, 
  fader1_min  = 200, 
  fader1_max  = 900;

float pedal1_scale=0, 
      fader1_scale=0;

unsigned long 
  last_loop  = 0,
  last_blink = 0,
  last_heartbeat = 0;

bool calibrating = false;

int 
  drive_light_with_pedal1 = 1,
  but2_state = 0,
  but1_state = 0;

byte ctrlbuf[9];
const int ctrlbuf_size = sizeof(ctrlbuf) / sizeof(byte);

#if !DEBUG
const int ctrl_period_ms = (1000/CTRLRATE);
#else
const int ctrl_period_ms = (1000/DEBUG_CTRLRATE);
#endif

const int heartbeat_period_ms = 1000/HEARTBEATRATE;

// ------------- HELPERS ---------------------

unsigned long int freq2timer(float freq) {
  float period = 1/freq;
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
  /*
  if( calibrating ) {
    return;
  }
  */

#if !DEBUG
  Serial.write(DATABLOCK);    
  value = analogRead(A0);
  Serial.write(value >> 7);
  Serial.write(value & 0b1111111);
  value = analogRead(A1);
  Serial.write(value >> 7);
  Serial.write(value & 0b1111111);
#else
  value = analogRead(A0);
  Serial.print("A0: ");
  Serial.print(value);
  value = analogRead(A1);
  Serial.print(" A1: ");
  Serial.println(value);
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
  noInterrupts();
    eeprom_write_uint(addr, pedal1_min);
    eeprom_write_uint(addr+2, pedal1_max);
    pedal1_scale = 1023.0 / (pedal1_max - pedal1_min);
    eeprom_write_uint(addr+4, fader1_min);
    eeprom_write_uint(addr+6, fader1_max);
    // eeprom_write_uint(addr+8, but2_state);
  interrupts();
  fader1_scale = 1023.0 / (fader1_max - fader1_min);
}

void load_state() {
  int addr = ADDR0;
  pedal1_min = eeprom_read_uint(addr, 200, 0, 1023);
  pedal1_max = eeprom_read_uint(addr+2, 900, 0, 1023);
  fader1_min = eeprom_read_uint(addr+4, 200, 0, 1023);
  fader1_max = eeprom_read_uint(addr+6, 900, 0, 1023);
  //but2_state = eeprom_read_uint(addr+8, 0, 0, 1);
  //digitalWrite(PIN_LED2, but2_state);
  pedal1_scale = 1023.0 /(pedal1_max - pedal1_min);
  fader1_scale = 1023.0 /(fader1_max - fader1_min);
}

void ledblink(int pin, int numblinks, int period_ms, int dur_ms) {
  int state = digitalRead(pin);
  for(int i=0; i<numblinks; i++) {
    digitalWrite(pin, !state);
    delay(dur_ms);
    digitalWrite(pin, state);
    delay(period_ms - dur_ms);
  }
}

// -----------------------------------------------
//                   SETUP

void setup() {

  pinMode(PIN_LED1, OUTPUT);
  pinMode(PIN_LIGHT1, OUTPUT);
  pinMode(PIN_BUTTON1, INPUT_PULLUP);
  pinMode(PIN_DIP1, INPUT_PULLUP);
  pinMode(PIN_DIP2, INPUT_PULLUP);
  pinMode(PIN_BUTTON2, INPUT_PULLUP);
  pinMode(PIN_LED2, OUTPUT);
  digitalWrite(PIN_LIGHT1, HIGH);
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

  // signal turn on
  ledblink(PIN_LED1, 10, 100, 50);
  
  Timer1.initialize(update_period_microsec);
  Timer1.attachInterrupt( read_sample );    
}

void loop() {
  int fader1, fader2, pedal1;
  int static but1_last = 0;
  int static but2_last = 0;
  int pedal1_warp;
  bool send_control;
  unsigned long static but1_press_t0;
  int static fader1_precalib, pedal1_precalib;
  float f;
  unsigned long now = millis();

  /*
  if( now - last_loop < ctrl_period_ms ) {
    return;
  }
  */

  noInterrupts();
  pedal1 = analogRead(PIN_PEDAL1);
  fader1 = analogRead(PIN_FADER1);
  fader2 = analogRead(PIN_FADER2);
  interrupts();
  
  fader1 = 1023 - fader1; 
  fader1 = int(fader1*0.66 + fader1_last*0.34);

  fader2 = 1023 - fader_linearize(fader2) * 1023;

  pedal1 >>= 2; // drop 2 bits of resolution
  pedal1 <<= 2;
  
  // BUTTONS
  int but1 = 1 - digitalRead(PIN_BUTTON1);
  int but2 = 1 - digitalRead(PIN_BUTTON2);

  // DIP switches
  drive_light_with_pedal1 = 1 - digitalRead(PIN_DIP1);
  pedal1_warp = 1 - digitalRead(PIN_DIP2);

  if( but2 == 0 && but2_last) {
    but2_state = 1 - but2_state;
    digitalWrite(PIN_LED2, but2_state);
  }

  if( but1 == 1 && !but1_last ) {
    // started pressing, calculate duration of press
    but1_press_t0 = now;
  } else if( but1 == 0 && but1_last) {
    // stopped pressing
    if( calibrating ) {
      save_state();
      calibrating = false;
      digitalWrite(PIN_LED1, but1_state);
    } else if ( but1_state ) {
      // STATE: NOT calibrating, BUT1 is ON
      but1_state = 0;
      digitalWrite(PIN_LED1, LOW);
    } else if ( now-but1_press_t0>=LONG_PRESS_MILLIS ) {
      // STATE: NOT calibrating, BUT1 is OFF, pressed long
      calibrating = true;
      fader1_precalib = fader1;
      pedal1_precalib = pedal1;
    } else {
      // STATE: NOT calibrating, BUT1 is OFF, pressed short
      but1_state = 1;
      digitalWrite(PIN_LED1, HIGH);
    }
  }
  but1_last = but1;
  but2_last = but2;
  
  // NORMALIZATION
  if ( !calibrating ) {
    #if DEBUG
      SERIALPRINT5("fader1:", fader1, fader1_min, fader1_max, fader1_scale);
    #endif
    
    pedal1 = constrain(pedal1, pedal1_min, pedal1_max);
    
    if( pedal1_warp ) {
      f = ((pedal1 - pedal1_min)/float(pedal1_max - pedal1_min)) * 3.14159265 + 3.14159265;
      f = (1+cos(f))/2.0;

      pedal1 = f * 1023;   
    } else {
      pedal1 = (pedal1-pedal1_min) * pedal1_scale;
    }
    
    if( drive_light_with_pedal1 ) {
      analogWrite(PIN_LIGHT1, pedal1/4);
    }
  } 
  else { // CALIBRATING
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

    // bling the led when calibrating
    if( (now - last_blink > BLINK_MILLIS) || (now < last_blink) ) {
      digitalWrite(PIN_LED1, !digitalRead(PIN_LED1));
      last_blink = now;
    }
    
#if DEBUG
    SERIALPRINT3("CALIBRATING --> Fader1 min-max:", fader1_min, fader1_max);
    SERIALPRINT3("                Pedal1 min-max:", pedal1_min, pedal1_max);
#endif
  }

  fader1_last = fader1;
  pedal1_last = pedal1;
  
#if !DEBUG
  ctrlbuf[0] = CONTROLBLOCK;
  ctrlbuf[1] = pedal1 >> 7;
  ctrlbuf[2] = pedal1 & 0b1111111;
  ctrlbuf[3] = fader1 >> 7;
  ctrlbuf[4] = fader1 & 0b1111111;
  ctrlbuf[5] = fader2 >> 7;
  ctrlbuf[6] = fader2 & 0b1111111;
  ctrlbuf[7] = but1_state;
  ctrlbuf[8] = but2_state;
  noInterrupts();  // <--- A control block cant be interrupted by a data block
    Serial.write(ctrlbuf, ctrlbuf_size);
  interrupts();    
#else
  // DEBUG
  if( !calibrating ) {
    noInterrupts();
    SERIALPRINT6("Fader Pedal Fader2 but1raw but2raw", fader1, pedal1, fader2, but1, but2)
    interrupts();
  }
#endif
  if( now - last_heartbeat > heartbeat_period_ms || now < last_heartbeat ) {
    noInterrupts();
      Serial.write(HEARTBEAT);
    interrupts();
    last_heartbeat = now;
  }
  delay(ctrl_period_ms);
}
