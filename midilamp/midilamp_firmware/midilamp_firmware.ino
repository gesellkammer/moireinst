#include <Adafruit_MCP4725.h>
#include <Wire.h>

#define DELAYMS 10
#define HEARTBEAT_PERIOD 500
#define VCC 5
#define DAC_RESOLUTION 4096
#define V_TABLE_SIZE 8
#define MAXVALUE 1000
Adafruit_MCP4725 dac;

float linearize_light[] = {
  0,     // 0
  0.7,   // 1
  0.9,   // 2
  1.15,  // 3
  1.5,   // 4
  2.0,   // 5
  2.5,   // 6
  3,     // 7
  4,     // 8
  4      // guard
}; 

int lumtable[MAXVALUE];

int dac_out;
int dac_changed = 0;
int cmd_pointer = 0;
unsigned long now = 0;
unsigned long last_heartbeat = 0;
byte id[] = "LMP";
float fvalue = 0;

#define CMDSIZE 20
char cmd[CMDSIZE];

#define MSG_HEARTBEAT 72 // 'H' (72)

void populate_lumtable() {
  float x, y, y0, y1;
  int i0, i1;
  for(int i=0; i<MAXVALUE;i++) {
    x = i/float(MAXVALUE)*V_TABLE_SIZE;
    i0 = int(x);
    i1 = i0 + 1;
    y0 = linearize_light[i0];
    y1 = linearize_light[i1];
    y = (x - i0) * (y1 - y0) + y0;
    lumtable[i] = y/VCC * DAC_RESOLUTION;
  }
}

int get_dac(int lum) {
  // lum: 0-999
  lum = min(MAXVALUE-1, lum);
  return lumtable[lum];
}

void send_heartbeat() {
  Serial.print('H');
  Serial.print("LMP");
  Serial.write((byte)0);
}

void setup() {
  dac.begin(0x62);
  Serial.begin(115000);
  populate_lumtable();
  dac_out = get_dac(MAXVALUE);
  dac_changed = 1;
}

void loop() {
  int value;
  if(dac_changed) {
    dac.setVoltage(dac_out, false);
    dac_changed = 0;
  }
  
  while (Serial.available()) {
    char rcv = (char)Serial.read();
    if( rcv == 0 ) {
      cmd[cmd_pointer] = NULL;
      switch(cmd[0]) {
        case 'S': 
          value = atoi(&cmd[1]);
          if(value >= 0 && value <= MAXVALUE) {
            dac_out = get_dac(value);
            dac_changed = 1;
          }
          break;
      }  
      cmd_pointer = 0;
    } else {
      cmd[cmd_pointer] = rcv;
      cmd_pointer += 1;
      if( cmd_pointer >= CMDSIZE ) {
        cmd_pointer = 0;
        Serial.print("EBUFOVERFLOW");
        Serial.write((byte)0);
      }
    }
  }
  
  now = millis();
  if( now - last_heartbeat > HEARTBEAT_PERIOD ) {
    send_heartbeat();
    last_heartbeat = now;
  }
  
  delay(DELAYMS);
}
